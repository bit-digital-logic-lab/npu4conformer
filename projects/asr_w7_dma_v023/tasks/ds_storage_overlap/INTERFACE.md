# INTERFACE — ds_storage_overlap V1

This document is the integration contract for the candidate modules in
`candidate/rtl/`.  The original files under `work/` are read-only; the
unmodified numeric primitives copied into `candidate/rtl/` are listed in
`result.json` with SHA-256 values.

## 1. Modules and role

| module | role |
|---|---|
| `block_storage_stream_v1` | A/W double-stage prefetch loader + independent posted C48 write stream.  Transactional DMA terminal; **not** an AXI burst engine. |
| `operand_banks_dual_v1` | Two complete A16/W7 stage banks, DMA-friendly 128b write port, 16-row/16-column skewed read ports. |
| `block_engine_prefetch_v1` | K-order-preserving engine.  Reuses `array16_direct_v020`, `pe_direct_v020`, `c_cache_banked4`, `block_address_v020` unchanged. |
| `axi_dma_v019` (copied) | Only used by the layer-2 integration test; ds_ddr owns the production AXI DMA. |

## 2. `block_storage_stream_v1`

### 2.1 Parameters

| parameter | default | meaning |
|---|---|---|
| `ARENA_BASE/END` | `0x03000000/0x08000000` | matrix scratch range |
| `PARAM_BASE/END` | `0x10000000/0x40000000` | read-only weight range |
| `LD_Q` | 8 | load-command queue depth |
| `WR_Q` | 8 | C segment-command queue depth |
| `WR_OUT` | 8 | maximum posted write commands awaiting BRESP |

### 2.2 Load command (A/W prefetch or C stream)

```
ld_valid / ld_ready
ld_kind[1:0]       0=A, 1=W, 2=C
ld_stage           0/1 (A/W only)
ld_address[31:0]   block base address (must equal the address derived from cfg)
ld_epoch[31:0], ld_layer[15:0], ld_matrix[15:0],
ld_block_row[15:0], ld_block_col[15:0],
ld_allowed_ops[15:0], ld_completed_ops[15:0],
ld_encoding[1:0], ld_block_valid, ld_in_operation
```

A command is consumed when `ld_valid && ld_ready` at a rising edge.  Fields are
sampled at that edge.  For A/W the command is accepted only when the selected
stage/kind is free; the engine must pulse `stage_release[stage]` after it has
finished reading that stage.  For C only one load command may be outstanding
(`c_cmd_busy`).

The storage recomputes the expected address and checks epoch, layer, matrix id,
block row/col, allowed ops, block-valid, in-operation, 64B alignment, arena and
parameter bounds.  A mismatch never issues a DMA transaction; it is reported
through the stage fault / C header error path.

### 2.3 A/W stage response

```
stage_a_ready[1:0], stage_w_ready[1:0]   data for that stage/kind is complete
stage_a_fault[1:0], stage_w_fault[1:0]   request/ACL/DMA/parity fault
stage_a_bvalid/stage_w_bvalid, stage_a_inop/stage_w_inop
stage_a_epoch/stage_w_epoch, stage_a_layer/stage_w_layer,
stage_a_matrix/stage_w_matrix, stage_a_row/stage_w_row,
stage_a_col/stage_w_col, stage_a_allowed/stage_w_allowed,
stage_a_completed/stage_w_completed, stage_a_encoding/stage_w_encoding
stage_release[1:0]                       pulse to free a stage
```

The metadata vectors are two 32-bit/16-bit halves packed as
`{stage1, stage0}` for 32-bit fields and `{stage1, stage0}` for 16-bit fields;
`stage_*_encoding` is `{stage1, stage0}` two-bit halves.

`stage_a_ready` means the complete 32x32 A block is in the stage A bank;
`stage_w_ready` means the complete W block is in the stage W bank.  A stage is
usable when both are ready and neither fault bit is set.  W bytes are checked
for even parity (bit7) at load time, preserving the V020 B_DATA rule.

### 2.4 Compute-side bank read

```
rd_stage, rd_row_half, rd_col_half
a_k[79:0]    16 x 5-bit k addresses (row 0..15)
w_k[79:0]    16 x 5-bit k addresses (column 0..15)
a_values[255:0]  16 x 16-bit A values
w_values[111:0]  16 x 7-bit W values
```

This is an asynchronous distributed-RAM read, same cycle, matching
`operand_banks_v020` timing.  The engine drives
`a_k[r] = run_cycle - r`, `w_k[c] = run_cycle - c`, with out-of-range k clamped
to 0 and `av/wv` deasserted by the engine.

### 2.5 C stream load (existing partial C)

```
c_hdr_valid / c_hdr_ready
c_hdr_exists, c_hdr_bvalid, c_hdr_inop, c_hdr_error, c_hdr_code[7:0]
c_hdr_epoch/layer/matrix/row/col/allowed/completed/encoding
c_ld_valid / c_ld_ready, c_ld_data[127:0], c_ld_index[15:0], c_ld_last,
c_ld_done, c_ld_error, c_ld_code[7:0]
```

Header is presented before any data beat.  `c_hdr_ready` acknowledges it.
`c_hdr_exists=0` means no data follows; the storage retires the command with
`c_ld_done`.  Data beats are 128b raw C48 byte-stream beats in ascending index
order.  The storage never starts a new C load while `c_cmd_busy`.

### 2.6 C48 streamed output (posted write)

```
cseg_valid / cseg_ready
cseg_address[31:0]   absolute C block address + row segment offset
cseg_epoch/layer/matrix/row/col, cseg_beats[15:0] (6 for a 96-byte segment)
cval_valid / cval_ready
cval_data[191:0]     four C48 values (lane0 = lowest C index)
cval_last            set on the fourth group of a 16-value segment
cwr_pending[7:0], cwr_idle, cwr_done, cwr_error, cwr_code[7:0]
```

A segment is 16 C48 values = 96 bytes = 6 x 128b beats.  The engine issues one
`cseg` command at the first of the four groups and then four `cval` groups.
The storage packs 48-bit values into a byte shifter and posts 128b beats as
soon as 16 bytes exist.  `cval_ready=0` is real backpressure: the engine must
hold `collected_values` and the cache write until the packer accepts the group.
`cwr_idle` means all segment commands have been posted, all beats sent and all
BRESP completions received.  `cwr_error` is sticky after an error/abort and
requires reset (or a new task reset) before re-use.

The engine waits for `cwr_idle` before reporting the block result, which is the
slot ownership rule: a cache slot is not reused while its posted writes are
still in flight.

### 2.7 DMA transaction ports

Read side (one outstanding):

```
rd_req_valid / rd_req_ready, rd_req_address[31:0], rd_req_beats[15:0]
rd_valid / rd_ready, rd_data[127:0], rd_index[15:0]
rd_done, rd_error
```

The sink asserts `rd_ready`; beats must be returned in `rd_index=0,1,...`
order.  `rd_done` is asserted after the last accepted beat; `rd_error` is valid
with `rd_done`.  The storage drains an accepted read transaction before it
reports a stage/C error (ACL failures do not issue a transaction).

Write side (posted, up to `WR_OUT` commands):

```
wr_req_valid / wr_req_ready, wr_req_address[31:0], wr_req_beats[15:0]
wr_valid / wr_ready, wr_data[127:0], wr_strobe[15:0]
wr_done, wr_error
```

`wr_req_valid` is asserted only when the storage has a segment command and a
write credit.  `wr_valid` may be deasserted between beats while the packer is
filling; `wr_ready` is the sink's backpressure.  `wr_done` is one pulse per
accepted command after its BRESP; `wr_error` marks a failed BRESP.  On abort or
write error, the storage drops never-posted segment commands and pads the
already-accepted command with zero-strobe beats so the DMA beat count is still
satisfied before the error exit.

### 2.8 Status

```
idle, drain_done
read_blocks, write_segments, read_bytes, write_bytes, error_count
read_wait_cycles, write_wait_cycles
ov_same_cycle              read and write beat handshakes in the same cycle
rd_active_wr_active_cycles read engine active while a write command is active
rd_active, wr_active       for engine overlap counters
dbg_rstate, dbg_wwait      debug only
```

## 3. `block_engine_prefetch_v1`

### 3.1 Control/result ports

Same configuration/result shape as `block_engine_banked_v020`:

```
clk, reset, start
cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch
cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id
cfg_target_high,cfg_allowed_ops,cfg_requested_op,cfg_positions,cfg_clip
cfg_c_valid,cfg_c_completed
busy,done,fault,error_code
task_cycles,compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses
prefetch_hits,prefetch_wait_cycles
overlap_compute_read_cycles,overlap_compute_write_cycles
result_valid/result_ready, result_cache_address, result_epoch,
result_target_low, result_layer, result_matrix, result_block_row,
result_block_col, result_op_tag, result_data[49151:0],
result_block_valid, result_in_operation, result_allowed_ops,
result_completed_ops
```

The engine keeps `bk=0..nbk-1` ascending.  During RUN/COLLECT of stage S it has
already issued A(bk+1)/W(bk+1) into stage S^1.  At the last K tile, COLLECT
streams the four C48 lanes to `cseg`/`cval`; there is no whole-block C collect
buffer and no eviction-before-write phase.  `done` waits for `cwr_idle` and for
the storage error drain.

`cfg_c_valid=1` causes a C header/data load for each output block (existing
partial sum).  `cfg_c_valid=0` forces a fresh zero partial sum.

Error codes used by V1:

| code | meaning |
|---|---|
| 1 | cfg/address extents invalid |
| 2 | header identity/ACL mismatch |
| 3 | C exists/valid/completed inconsistency |
| 4 | C load DMA error |
| 5 | C load framing/index error |
| 7 | illegal state |
| 8 | C48 accumulation overflow |
| 9 | A/W stage fault (ACL/DMA/parity) |
| 10 | C write error/backpressure fault |

## 4. Upper-layer adaptation from `queued_v020_monitored`

The old wrapper has one shared `axi_dma_v019` owner arbiter between the plan
fetch queue and `block_storage_dma_wide4`.  V1 deliberately separates storage
read and write transactions, so the integration must change as follows:

1. Replace the old `req/header/data/out` storage interface with the
   `ld_*` / `stage_*` / `rd_*` bank port / `cseg+cval` / `cwr_*` interface.
   `block_engine_prefetch_v1` already drives it; the wrapper no longer needs to
   connect `req_*`, `header_*`, `data_*`, `out_*`.
2. Provide a **read transaction arbiter** between the immutable plan/queue
   fetch DMA and the storage `rd_*` port.  The queue fetch is low rate; grant
   it between storage block loads, or give it a second read master.
3. Provide a **separate write transaction master** (or a combined master with
   an explicit read/write owner arbiter).  If one physical AXI master is used,
   read/write independence is lost at the pin and must be reported as such; the
   storage still posts writes independently.
4. Keep the old `axi_dma_v019` cores if desired (proven by
   `tb_storage_axi.sv`), or plug ds_ddr's multi-outstanding DMA.  The contract
   is per-transaction address/beats, in-order beats, `done`/`error` after the
   last accepted beat (read) or after BRESP (write), and up to `WR_OUT`
   outstanding write commands.
5. The wrapper's `storage_idle` completion condition becomes
   `drain_done` plus `cwr_idle`; the engine's `done` already includes this.
6. `stage_release` is driven by the engine; no wrapper action.  The wrapper
   must not reuse a stage while `stage_a_ready/stage_w_ready` are low.
7. Plan/queue memory and the matrix arena remain disjoint; the storage address
   checks retain the old arena/parameter ACL.

## 4.8 AXI burst and clock-domain boundary

This candidate does **not** change AXI burst length or the DMA's outstanding
count.  ds_ddr owns the HP-facing master; the current guidance is 128b x
16-beat bursts (16-beat is not a defect) and enough outstanding requests to
hide memory latency.  The candidate's contribution is independent read/write
transaction queues, stage ownership and posted C writes; it can sit behind
either the frozen `axi_dma_v019` (one outstanding per direction) or ds_ddr's
multi-outstanding DMA.

All V1 control is single-clock.  PS AXI is nominally <=333 MHz; a 600 MHz
local compute domain would need CDC/async FIFO between the DMA/HP domain and
the compute domain.  No CDC is implemented or verified in this task.  The FSM
state is registered, but the combinational ready/credit paths (`ld_ready`,
`cval_ready`, `wr_valid`, `cwr_pending`, `stage_*_fault`) are not STA-cleaned;
register them at the clock-domain boundary for a 600 MHz target.

## 5. What is intentionally unchanged

- `array16_direct_v020` / `pe_direct_v020`: A16 * W7(S/J/M), positions nibble,
  clip saturation, 3-stage product pipeline, INT48 accumulation.
- `c_cache_banked4`: four-lane C48 read/modify/write group.
- W7 weight bytes (bit7 even parity), A16 layout, C48 layout, block bytes
  (2048/1024/6144) and block addressing.
- No FP32 FTZ/RNE/FMA or QDQ code is modified; those paths are not exercised by
  this task's tests and remain "not tested here".
