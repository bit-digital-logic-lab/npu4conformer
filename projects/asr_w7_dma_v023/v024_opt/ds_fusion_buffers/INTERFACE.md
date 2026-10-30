# INTERFACE — ds_fusion_buffers

Status: **module/cluster-level logic candidate, local Icarus simulation only**.
No synthesis, Vivado/STA, board, VNC or push. No whole-model or frequency claim.

Upstream reference (read-only, frozen):
`/home/yang/Desktop/项目/v023_repair/ds_closeout_fusion` and
`/home/yang/Desktop/项目/v023_repair/primary_stream_fix`.
This directory only adds a ping-pong A16 buffer, a dual-bank fused top, and new
tests. `candidate/matrix` and `candidate/primary` are byte-identical copies of
the frozen upstream candidates; `rtl/matrix_stream_fusion_top.sv` and the
single-bank `rtl/fusion_a16_blockbuf.sv` are kept as the single-buffer reference.

---

## 1. Dual-bank fused top `matrix_stream_fusion_top_dual`

File: `rtl/matrix_stream_fusion_top_dual.sv`.

### 1.1 Parameters

Same as the upstream fused top:

```systemverilog
SLOTS=2, MAX_DIM=4096, PIPE_STAGES=4, ACCUM_MODE=0, CPA_PIPE=1,
MAX_OUT=8, FIFO_BEATS=128, ARENA_BASE=0x03000000, ARENA_END=0x08000000,
WR_OUT=8, BRIDGE_FIFO=16, A16_WORDS=128
```

### 1.2 Ports

All matrix / epilogue / AXI ports are identical to
`matrix_stream_fusion_top` (see the frozen upstream `INTERFACE.md`), plus three
telemetry outputs:

```systemverilog
output wire [31:0] stat_overlap_cycles;      // writer_busy && engine_busy
output wire [31:0] stat_bank_stall_cycles;   // tile full, waiting for the other bank
output wire [15:0] stat_bank_occ_max;        // max simultaneously non-empty banks (<=2)
```

`cfg_scale` / `cfg_bias` remain **broadcast** values; `param_wr_addr` 0/1 only.
Per-channel and FP32 spill are not implemented in this version; see §4.

### 1.3 Completion / error semantics

- `done = done_engine && !fault && !writer_busy && !(|bank_busy) &&
  !writer_launch && (tiles_acked == ceil(M/32)*ceil(N/32))`.
- The writer `done` is still qualified by `axi_dma_v020_multi_v2` `b_out==0`;
  the top therefore cannot assert `done` before the last AXI B response.
- `fault = engine_fault || frame_err || bank_dup_err || bank_seq_err ||
  fifo_overflow || writer_fault`. `error_code` priority: engine → framer
  `0x51/0x52/0x53` → bank `0x61/0x62/0x63` → FIFO `0x54` → writer `0x71/0x72`.
- No abort/drain input. Reset is the only complete cleanup; the upstream
  engine/storage still do not expose an abort/drain port.

### 1.4 Bank / overlap contract

- Two independent 128×128-bit (2 KiB) banks = **4 KiB total**.
- `fill_bank` is written only by the epilogue packed stream; `drain_bank` is read
  only by the single A16 writer/DMA.
- A bank is never rewritten while `DRAINING`, and never drained before the
  tile-last packed word (`a16_packed_last`) has been written.
- The matrix `result_valid` is consumed when the completed bank is full **and**
  the other bank is empty. This lets tile t+1 compute while tile t's A16 write
  is still in flight. If the writer is still busy when tile t+1 becomes full,
  the engine waits (reported by `stat_bank_stall_cycles`); the pending tile is
  never dropped or cleared by software.
- The single writer serialises the two banks: at most one AXI write DMA is in
  flight. The dual buffer overlaps **compute with writeout**, not two writes.

### 1.5 A16 output contract

Unchanged from upstream: 32×32 signed int16, row-major, 2048 B per tile,
tile base `cfg_a16_base + (block_row*ceil(N/32)+block_col)*2048`; partial M/N
still emits a full 32×32 tile with zero in the unused region.

### 1.6 Cost (actual, not zero)

- On-chip storage: **+2048 B** for the second bank (2 × 2 KiB total).
- Ports: the top-level AXI port list is unchanged. Internally each bank is a
  simple 1-write/1-read array, so the implementation is two 128×128-bit banks
  (two BRAM-style arrays) instead of one; the added logic is a 1-bit bank index,
  write/read bank muxes, and per-bank empty/full/draining state.
- DDR traffic: **no extra byte**. Fused path still reads A/W and writes A16 only;
  C48 DDR write/read stay structurally zero. The second bank only holds data
  longer on chip.
- No extra AXI master, no extra clock, no CDC.

---

## 2. Dual bank buffer `fusion_a16_blockbuf_dual`

File: `rtl/fusion_a16_blockbuf_dual.sv`.

```systemverilog
fusion_a16_blockbuf_dual #(.WORDS(128), .BANKS(2)) u_buf (
  .clk, .rst_n, .flush, .start,
  .wr_valid, .wr_ready, .wr_data[127:0], .wr_tag[6:0], .wr_last,
  .addr_mode, .cfg_words[7:0], .fill_bank, .fill_start,
  .drain_bank, .drain_start, .rd_valid, .rd_ready, .rd_data[127:0], .rd_last,
  .bank_full[1:0], .bank_empty[1:0], .bank_busy[1:0], .drain_done_pulse[1:0],
  .stat_words_written, .stat_words_read,
  .err_duplicate, .err_sequence, .err_code[7:0]
);
```

States: `EMPTY -> FILLING -> FULL -> DRAINING -> EMPTY`.

- `ADDR_TAG` (0): write address = `wr_tag[6:0]` (fused row-major reorder).
- `ADDR_LINEAR` (1): write address = per-bank linear counter (baseline/odd-tail).
- `wr_last` must coincide with `cfg_words` words; otherwise `err_sequence=1`
  (code `0x62`) and the bank is closed so a test cannot deadlock.
- Duplicate write address: `err_duplicate=1` (code `0x61`).
- Fill or drain in the wrong state: `err_sequence=1` (code `0x63`).

---

## 3. FIFO credit / non-pausable source

`rtl/fusion_c48_fifo.sv` is unchanged: `DEPTH=16`, `in_ready=(count<DEPTH-1)`,
`occupancy<=15`, `credit=DEPTH-1-occupancy`, 1 skid slot.

`tb/tb_fifo_credit.sv` adds the non-pausable-source contract:
- producer is credit-gated using a deliberately **stale registered credit**;
- producer never retracts an asserted valid;
- a 512-beat stream with a 320-cycle consumer stall must deliver every beat,
  including the tail `last`, in order;
- occupancy must reach 15 and never exceed 15; overflow must stay 0.

This is the proof that a future C-cache readout without `cval_ready` can use
credit gating plus one reserved slot for the 1-cycle BRAM read, without writing
C48 to DDR.

---

## 4. Optional per-channel / FP32 interface (published, NOT implemented)

The frozen epilogue has only two broadcast words. The following optional
interface is published so the integrated top can adopt it later; this task
does **not** claim it works and does not route it in the dual top.

```systemverilog
// optional per-channel parameter preload (2 banks x 32 x 32-bit)
input  wire         pch_wr_valid;
output wire         pch_wr_ready;
input  wire [5:0]   pch_wr_addr;   // [5]=bank, [4:0]=column 0..31
input  wire [31:0]  pch_wr_data;
input  wire [5:0]   pch_scale_sel; // bank used by the current block column
input  wire [5:0]   pch_bias_sel;

// optional FP32 spill (4 x FP32 per beat = 128 bit)
input  wire         cfg_spill_fp32;
output wire         fp32_valid;
input  wire         fp32_ready;
output wire [127:0] fp32_data;
output wire [15:0]  fp32_tag;
output wire         fp32_last;
```

Contract for a future integration:
- 32 scale + 32 bias words per bank (256 B per bank, 512 B for two banks),
  indexed by the column inside the 32×32 block; block column `bc` selects the
  bank.
- Parameter writes accepted only when the epilogue is drained and no descriptor
  is pending (same rule as the current broadcast preload).
- `cfg_spill_fp32=1` bypasses the F32→I16 quantizer and emits 4×FP32 per beat
  in lane order; the A16 stream is not produced in that mode.
- Not tested/implemented here: no RTL, no vectors, no claim.

---

## 5. Filelists

- `filelist_fused_dual.f`: 25 files / 25 unique modules — frozen matrix (12),
  frozen primary (8), `fusion_c48_fifo`, `fusion_c48_framer`,
  `fusion_a16_blockbuf_dual`, `fusion_a16_writer`,
  `matrix_stream_fusion_top_dual`.
- `filelist_fused_single.f`: same but single-bank `fusion_a16_blockbuf` and
  upstream `matrix_stream_fusion_top` (control reference).
- `filelist_unfused.f`: 28 files / 28 modules — real C48-store/reload baseline.

Do not compile `axi128_ddr_bfm_v4.sv` and `axi128_ddr_bfm_v5.sv` together: both
define module `axi128_ddr_bfm`; v5 only adds `cfg_b_extra`.

---

## 6. Testbench / BFM

- `tb/axi128_ddr_bfm_v5.sv`: v4 model plus `cfg_b_extra`, which adds an explicit
  delay to every B response. With `cfg_b_extra=0` the behaviour is the v4 model.
- `tb/tb_fusion_dual.sv`: dual top, 2 AXI ports, same fixture/BFM/gold as the
  upstream fusion TB; logs `b_count`, `aw_count`, `last_b`, `dma_done`,
  `done`, `stat_overlap_cycles`, `stat_bank_occ_max`.
- `tb/tb_fusion_single_ref.sv`: same workload on the single-bank upstream top
  with the same v5 BFM, used only as a control.
- `tb/tb_unfused_baseline.sv`: frozen real unfused top (C48 DDR write + readback)
  with the same v5 BFM. `cfg_b_extra>1` was found not to complete in this
  simulation environment; the accepted baseline comparison uses `cfg_b_extra=0`
  (v4-equivalent), and is reported as such.
- `tb/tb_fifo_credit.sv`: credit-gated non-pausable source / tail proof.
- Upstream `tb_fifo_unit`, `tb_oddtail_writer`, `tb_epilogue_contract` are reused.
