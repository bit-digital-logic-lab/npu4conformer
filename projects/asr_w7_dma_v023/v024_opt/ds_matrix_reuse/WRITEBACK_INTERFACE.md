# WRITEBACK INTERFACE — independent patch for the storage/writeback owner

This note is deliberately separate from the engine integration.  It describes
what the 2x1 W-reuse schedule needs from `block_storage_stream_v2` and what is
actually changed.  The full unified diff is
`patches/writeback_interface_v1.patch`.

## 1. Unchanged writeback contract

The C48 writeback ports and behavior are the v023 contract:

```
cseg_valid / cseg_ready / cseg_address[31:0] / cseg_epoch /
cseg_layer,matrix,row,col / cseg_beats[15:0]
cval_valid / cval_ready / cval_data[191:0] / cval_last
cwr_pending[7:0] / cwr_idle / cwr_done / cwr_error / cwr_code[7:0]
wr_req_valid/ready, wr_req_address[31:0], wr_req_beats[15:0]
wr_valid/ready, wr_data[127:0], wr_strobe[15:0], wr_done, wr_error
```

- one `cseg` per 16 C48 values (96 B = 6 x 128-bit beats);
- one `cval` per 4-value group;
- packer, WSTRB, 4 KiB split, posted AW/B credit and `write_bytes =
  popcount(WSTRB)` are unchanged;
- `cwr_idle` still means all segment commands posted, all beats sent, all B
  responses received.

No new writeback tag, FIFO or BRAM is introduced by this task.

## 2. Interface additions (stage side only)

```
input wire [1:0] stage_release_a, stage_release_w;  // new
input wire rd_a_stage, rd_w_stage;                  // replaces rd_stage
output wire dbg_wr_en, dbg_wr_kind[1:0], dbg_wr_stage; // test/debug
```

- `stage_release[s]` is kept as the legacy combined release.  The new engine
  ties it to 0 and drives `stage_release_a/w` separately.
- A/W readiness and captured headers already existed as separate bits; the
  engine now consumes them independently.
- The bank instance changes from `operand_banks_dual_v1` to
  `operand_banks_dual_reuse`; only the final A/W read mux select is split.
  The memory arrays are byte-identical in shape to v023.

## 3. Abort/drain fix (writeback logic)

v023 dropped `wq_cnt` only for a sticky write error:

```verilog
if(wr_err_sticky&&wq_cnt!=0)begin wq_cnt<=0;wq_rd<=wq_wr;end
```

A compute abort (C48 overflow, stage fault, watchdog) can arrive after a
`cseg` was accepted but before it is posted to the DMA.  The queue then never
drains and `cwr_idle` / `drain_done` never assert.  The patch changes it to:

```verilog
if((wr_err_sticky||abort)&&wq_cnt!=0)begin wq_cnt<=0;wq_rd<=wq_wr;end
```

The already-accepted `w_cur` segment is still padded with zero-strobe beats by
the existing abort path, so the DMA beat count is satisfied.  This is the only
writeback-engine behavior change in the patch.

Evidence: the C48-overflow case `ovf_m64n32k32_c1_r1` exits with
`code=08`, `done=1`, `cwr_pending=0`, `b_outstanding=0`, `w_busy=0`.
Before the fix it hung in `WAITDRAIN` with `cwr_pending=1`.

## 4. Pair-schedule obligation in v1

The pair schedule computes br0 then br1 and emits one result payload.  To keep
the v023 per-tile result/writeback meaning, v1 enforces:

- br0’s 64 `cseg` commands are posted and drained (`cwr_idle`) before br1’s
  final-K write stream starts;
- therefore the writeback module never sees interleaved br0/br1 segments in
  this version;
- `result0` and `result1` are separate results, each with its own
  `result_cache_address = target_high + slot*6144`.

If a later version wants to overlap the two tiles’ writebacks, the writeback
interface needs a tile/slot tag per `cseg` (or a separate virtual channel), and
`cwr_idle` must become per-tile.  That is **not** implemented or claimed here.
