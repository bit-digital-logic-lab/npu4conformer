# INTERFACE — V0.23 matrix P2 unified candidate

This is the integration contract for `candidate/rtl/`.  It describes logic
interfaces only; there is no synthesis, STA, CDC proof, board DDR timing or
whole-model claim.  The original `work/` tree is read-only.

## 1. Modules

| module | role |
|---|---|
| `block_engine_prefetch_v2` | K-order-preserving matrix engine; A/W double-stage prefetch, configurable PE depth, II=1 C collect, streamed final C48. |
| `block_storage_stream_v2` | transactional A/W/C load engine + posted C48 write stream; ACL/header/ownership checks; no AXI burst logic. |
| `operand_banks_dual_v2` | two complete A16/W7 stage banks; 128b DMA write port; 16-row/16-column skewed read ports. |
| `c_cache_banked4_pipe` | two logical 32x32 INT48 blocks, true-dual-port BRAM: synchronous read port + synchronous write port, same-address bypass. |
| `array16_w7_c48_cfg` / `pe_w7_c48_cfg` | ds_pe_pipeline 16x16 array / PE with `PIPE_STAGES=3..6`, `drain_done`, `array_drain_cycles`. |
| `axi_dma_v020_multi_v2` | ds_ddr multi-AR + read FIFO + posted write DMA, with PA-003/PA-004/PA-014 fixes. |
| `matrix_p2_cluster_v2` | integration wrapper: engine + storage + one read DMA + one write DMA; AXI read/write masters exposed separately. |
| `block_address_v020`, `pe_direct_v020`, `array16_direct_v020`, `c_cache_banked4`, `axi_dma_v019` | unmodified reference/baseline copies used by tests. |

## 2. `block_engine_prefetch_v2`

### 2.1 Parameters

| parameter | default | meaning |
|---|---:|---|
| `SLOTS` | 2 | C cache blocks; must be 2 |
| `MAX_DIM` | 4096 | max M/N/K |
| `PIPE_STAGES` | 4 | 3..6; passed to `array16_w7_c48_cfg` |
| `ACCUM_MODE` | 0 | 0 native CARRY (recommended), 1 CSA |
| `CPA_PIPE` | 1 | CSA final CPA register |

### 2.2 Config / result

The config/result ports are the same shape as `block_engine_banked_v020`:
`cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,cfg_m,cfg_n,cfg_k,cfg_layer,
cfg_a_id,cfg_b_id,cfg_c_id,cfg_target_high,cfg_allowed_ops,cfg_requested_op,
cfg_positions,cfg_clip,cfg_c_valid,cfg_c_completed`; `busy/done/fault/error_code`;
result `result_valid/result_ready/result_cache_address/result_epoch/
result_target_low/result_layer/result_matrix/result_block_row/result_block_col/
result_op_tag/result_data[49151:0]/...`.

New telemetry: `c_collect_groups,c_collect_cycles,c_raw_bypass_cycles,
pe_drain_cycles,array_drain_cycles,array_drain_done`.

`K` is always accumulated `bk=0..nbk-1` in ascending order.  The four C48 lanes
per group and the lane order are unchanged.

### 2.3 RUN timing contract

`RUN` lasts until all of:

```
run_cycle >= k_local + 14
array_drain_done == 1
```

where `k_local = min(32, cfg_k - bk*32)`.  `array_drain_done` is the real
ds_pe_pipeline quiet-counter output.  There is no `run_cycle==65` constant.
`flush = reset || state==FAIL`; leaving RUN does not flush.  New quadrants use
`clear_sum` in CLEAR, after the pipe is empty.

Nominal `RUN_END` for K=32 (cycles from run_cycle=0) is 65/66/67/68 for
PIPE_STAGES=3/4/5/6; the measured exit is one cycle later due to the quiet
counter sampling boundary (67/68/69/70 RUN cycles counted).  This is
deliberately conservative.

### 2.4 Operand load / stage contract

The engine drives `ld_*` commands to `block_storage_stream_v2`:

```
ld_valid/ld_ready, ld_kind[1:0] (0=A,1=W,2=C), ld_stage,
ld_address,ld_epoch,ld_layer,ld_matrix,ld_block_row,ld_block_col,
ld_allowed_ops,ld_completed_ops,ld_encoding,ld_block_valid,ld_in_operation
```

Storage returns `stage_a_ready/stage_w_ready/stage_*_fault/stage_*_bvalid/...`
and the engine pulses `stage_release[stage]` when it stops reading a stage.
A stage is usable only when both A and W are ready and neither fault is set.
The engine issues A(bk+1)/W(bk+1) into the other stage before RUN; storage
fills it during RUN/COLLECT.  A `stage_release` from the engine is the only
action that frees a stage.

### 2.5 C48 stream

```
cseg_valid/cseg_ready, cseg_address[31:0], cseg_epoch, cseg_layer/matrix/row/col,
cseg_beats[15:0] (=6)
cval_valid/cval_ready, cval_data[191:0] (4 C48, lane0 lowest), cval_last
cwr_pending[7:0], cwr_idle, cwr_done, cwr_error, cwr_code
```

The engine sends one `cseg` per 16 C48 values (96 B = 6 x 128b beats), then one
`cval` per 4-value group.  `cval_ready=0` holds the group and the cache write;
the next BRAM read is not issued.  `done` waits for `cwr_idle` and the storage
error drain.

The first group of each segment spends one cycle accepting `cseg`; the three
following groups sustain II=1.  Measured 1.59 cycles/group for K=96 (including
segment commands), versus 2.0 in the V1 C_READ/COLLECT pair.

### 2.6 Error codes

| code | meaning |
|---|---|
| 1 | cfg/address extent invalid |
| 2 | header identity/ACL mismatch |
| 3 | C exists/valid/completed inconsistency |
| 4 | C load DMA error |
| 5 | C load framing/index error |
| 7 | illegal state |
| 8 | C48 C-accumulation overflow (baseline rule retained) |
| 9 | A/W stage fault (ACL/DMA/parity) |
| 10 | C write error/backpressure fault |

## 3. `block_storage_stream_v2`

Parameters: `ARENA_BASE=0x03000000`, `ARENA_END=0x08000000`,
`PARAM_BASE=0x10000000`, `PARAM_END=0x40000000`, `LD_Q=8`, `WR_Q=8`, `WR_OUT=8`.

### 3.1 Load (A/W prefetch or C stream)

Same `ld_*` fields as §2.4.  `ld_ready` is asserted only when the selected
stage/kind is free (A/W) or no C command is outstanding (C).  The storage
recomputes the expected address from cfg and checks epoch/layer/matrix/block
row/col/allowed/in-operation/encoding, 64B alignment, arena/param bounds and
the 64-bit end (`ld_no_wrap`).  A mismatch never issues a DMA transaction.

A/W stage response is `stage_a_ready[1:0]`, `stage_w_ready[1:0]`, faults, and
captured header fields packed `{stage1,stage0}`.  A stage is free only after
`stage_release[stage]`.  W bytes are checked for even parity at load time.

### 3.2 C partial load

`c_hdr_valid/c_hdr_ready`, `c_hdr_exists`, `c_hdr_*` metadata; then
`c_ld_valid/c_ld_ready`, `c_ld_data[127:0]`, `c_ld_index`, `c_ld_last`,
`c_ld_done`, `c_ld_error/c_ld_code`.  The storage never starts a new C load
while `c_cmd_busy`.

### 3.3 C48 posted write

The `cseg/cval/cwr_*` ports are the same as §2.5.  The packer emits a 128b
beat whenever >=16 bytes are present; `wr_strobe` is the real byte mask.
`write_bytes` counts `popcount(WSTRB)`, including zero for a padding beat.
`cwr_idle` means all segment commands posted, all beats sent, all BRESP
received.  `cwr_error` is sticky and needs reset/new task before reuse.

### 3.4 Independent DMA transaction ports

Read side:

```
rd_req_valid/rd_req_ready, rd_req_address[31:0], rd_req_beats[15:0]
rd_valid/rd_ready, rd_data[127:0], rd_index[15:0]
rd_done, rd_error
```

Write side:

```
wr_req_valid/wr_req_ready, wr_req_address[31:0], wr_req_beats[15:0]
wr_valid/wr_ready, wr_data[127:0], wr_strobe[15:0]
wr_done, wr_error
```

Beats must be returned in ascending `rd_index` order.  The read engine drains
an accepted transaction before reporting a fault.  The write side is posted:
up to `WR_OUT` commands may be outstanding; on abort/error, unposted segment
commands are dropped and an accepted command is padded with zero-strobe beats
so the DMA beat count is still satisfied.

The storage also rejects a `cseg` whose 64-bit end or 32-bit address would
overflow (`cseg_end[63:32]!=0` or `cseg_address>0xFFFFFFF0`).

## 4. `c_cache_banked4_pipe`

```
rd_valid/rd_ready, rd_group[8:0], rd_data[191:0]   // synchronous, 1-cycle
wr_valid/wr_ready, wr_group[8:0], wr_mask[3:0], wr_data[191:0]
raw_bypass_pulse
```

512 groups x 192 bits, four 48-bit banks.  Group 0..255 is slot 0, 256..511 is
slot 1.  A read and a write can address different groups in the same cycle.
If `wr_group==rd_group`, the read output is bypassed with the write data
(write-first); `raw_bypass_pulse` reports it.  No RAM reset/whole-block clear;
ownership/epoch stays in the engine.

## 5. `axi_dma_v020_multi_v2`

Same ports as ds_ddr `axi_dma_v020_multi`, plus the fixes:

- `MAX_OUT` power-of-two, `MAX_BURST<=16`, `FIFO_BEATS>=MAX_OUT*MAX_BURST`
  are checked at elaboration.
- internal `next_addr` is 40-bit; `m_axi_araddr/awaddr` use all 40 bits.  A read
  at `0xFFFFFFF0`, 2 beats produces `0xFFFFFFF0` then `0x100000000`, never 0.
- `write_bytes += popcount(write_strobe)`.
- a B with no outstanding AW sets error and does not underflow `b_out`.
- `m_axi_wvalid` remains gated by upstream `write_valid`.

The DMA is still a per-transaction engine: one request context at a time, but
the read side can have up to `MAX_OUT` AR in flight and the write side up to
`MAX_OUT` AW/B.  It does not change the storage's per-C K order.

## 6. `matrix_p2_cluster_v2`

This is the integration wrapper used by the AXI test.  It has:

- config/result/engine telemetry from §2.2;
- separate `rd_m_axi_*` (AR/R) and `wr_m_axi_*` (AW/W/B) masters;
- `rd_ar_outstanding_max,rd_read_bytes,rd_read_bursts,wr_b_outstanding_max,
  wr_write_bytes,wr_write_bursts,rd_read_fifo_high`.

The cluster uses one `axi_dma_v020_multi_v2` per direction.  The unused
direction of each DMA is tied off; this keeps a read-only and a write-only AXI
master and avoids a shared request arbiter.  A real board integration still
needs the HP-port/SmartConnect topology from `soc_full`; this wrapper does not
claim a direct MIG bypass.

## 7. Upper-layer adaptation from `queued_v020_monitored` / plan cluster

1. Replace the old `req/header/data/out` storage ports with the
   `ld_* / stage_* / cseg+cval / cwr_*` contract and the separate `rd_*` /
   `wr_*` transaction ports.
2. Use `matrix_p2_cluster_v2` if a read-only + write-only master pair is
   acceptable; otherwise instantiate the storage + two DMA cores directly.
3. If a single physical AXI master is used, read/write independence is lost at
   the pin.  The storage still posts writes independently, but the pin-level
   arbitration must be reported separately.
4. The wrapper's `storage_idle` completion condition becomes `drain_done` plus
   `cwr_idle`; the engine's `done` already includes both.
5. `stage_release` is driven by the engine.  The wrapper must not reuse a stage
   while `stage_a_ready/stage_w_ready` are low.
6. Keep the matrix arena, parameter region and plan/queue region disjoint.

## 8. Clocking / timing boundary

All RTL in this candidate is single-clock.  The FSM state is registered, but
the combinational ready/credit paths (`ld_ready`, `cval_ready`, `wr_valid`,
`cwr_pending`, `stage_*_fault`, `commit_now`, DMA `can_ar/can_aw`) are not
STA-cleaned.  For a 300/600 MHz local compute domain, add boundary registers
and a CDC/async FIFO between the AXI/HP domain and the compute domain, then run
STA.  This task does not implement or verify CDC and does not claim any
frequency.

## 9. What is intentionally unchanged

- A16 signed two's complement, W7 `{S,J[1:0],M[3:0]}`, positions nibble,
  `clip` saturation, 32-bit intermediate truncation, INT48 natural wrap.
- A/W/C48 block layouts (2048/1024/6144 B), K accumulation order, lane order.
- FP32 FTZ/RNE/FMA and all QDQ boundaries; they are outside this integer path
  and were not modified or exercised here.
- V020 C-accumulation overflow fault code 8 is retained.
