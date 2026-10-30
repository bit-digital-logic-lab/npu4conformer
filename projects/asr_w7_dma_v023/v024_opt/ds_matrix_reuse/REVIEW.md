# REVIEW — is the v023 `SLOTS=2` really a 2x1 W-reuse super-tile?

Date: 2026-10-30  
Scope: read-only audit of `v023_repair/ds_matrix` plus the new candidate in
this directory.  Logic simulation only; no synthesis/STA/board/frequency.

## 1. Short answer

The v023 storage **can hold two C tiles at once** (2 x 256 C48 groups =
2 x 6144 B), but the v023 **schedule does not keep two tiles across K**, and
changing only the loop in `block_engine_prefetch_v2.sv` is **not sufficient**
to reuse W.  The claim in `REVIEW_INPUT.txt` item 3 (“只需修改
`block_engine_prefetch_v2` 的块调度循环 ... 不增加 1 bit BRAM”) is therefore
only half true:

- true: no new C/A/W memory array is needed;
- false: the existing ports, stage-ready contract and release contract cannot
  express “A stage 0 + pinned W stage 1” at the same time.

The candidate here implements the missing control/port changes and measures
the result.  It does **not** add a third storage slot and does **not** claim
that both slots are readable/writable in the same cycle.

## 2. What v023 actually provides

| item | v023 fact | evidence |
|---|---|---|
| C cache | 4 banks x 512 x 48 = 98,304 bit; group 0..255 = slot 0, 256..511 = slot 1 | `c_cache_banked4_pipe.sv:32-43` |
| C ports | one synchronous read port + one synchronous write port; same-cycle read/write allowed for different groups; same-group write-first bypass | `c_cache_banked4_pipe.sv:25-47` |
| C tags | two tag sets, `valid_cache[0:1]`, `tag_done[0:1]` | `block_engine_prefetch_v2.sv:120-123` |
| engine loop | after a result, `bc` advances first, then `br`; each tile loads all K by itself | `block_engine_prefetch_v2.sv:511-516` |
| C lookup | one `slot` at a time; the second slot is allocated only for the next tile | `block_engine_prefetch_v2.sv:336-342` |
| A/W banks | 2 A stages (2 x 2048 B) and 2 W stages (2 x 1024 B) | `operand_banks_dual_v2.sv:34-56` |
| A/W read port | **one** `rd_stage` selects both A and W | `operand_banks_dual_v2.sv:58-59` |
| stage ready | `stage_a_ready[s]` and `stage_w_ready[s]` are independent bits, but `cur_stage_ok` requires **both** in the same index | `block_engine_prefetch_v2.sv:258` |
| stage release | one 2-bit `stage_release` frees **both** A and W of a stage | `block_storage_stream_v2.sv:412-415` |
| result | one 49,152-bit `result_payload`; one result at a time | `block_engine_prefetch_v2.sv:107`, `500-516` |
| measured W repeat | K96 C1: 6 W transfers / 6144 B, 3072 B unique -> 3072 B repeat | `ds_matrix/REPORT.md:168` |

So the two slots are **two accumulators**, not two simultaneous read ports,
two result payloads, or two writeback streams.

## 3. Why “just change the loop” fails

Three independent blockers were found:

1. **Read-stage coupling.**  `operand_banks_dual_v2` exposes
   `rd_stage` and uses it for both `a_values` and `w_values`
   (`operand_banks_dual_v2.sv:58-59`).  A reuse schedule needs A stage 0 and
   W stage 1 in the same cycle.  With the v023 port this reads A and W from
   the same stage, i.e. it cannot pin W while replacing A.
2. **Stage-ready coupling.**  The engine treats a stage as usable only if
   `stage_a_ready[s] && stage_w_ready[s]` (`:258`).  The storage can mark A and
   W ready independently (`block_storage_stream_v2.sv:165-166`), but the engine
   throws that away.  Refilling A into a stage that does not hold the current W
   would make `cur_stage_ok` false even though the data path is valid.
3. **Release coupling.**  `stage_release[s]` clears both `stg_have[s][0]` and
   `stg_have[s][1]` (`block_storage_stream_v2.sv:412-415`).  A schedule that
   frees A after `br0` while keeping W for `br1` cannot use this contract;
   it would also free the pinned W.  A naive loop change would either corrupt
   the second row tile or deadlock waiting for a W that was released.

A fourth, scheduling-level blocker: the v023 outer loop finishes one output
tile (all K, result, C writeback) before the next tile.  Keeping two C tiles
across K requires a different loop (`bk` outer, pair inner) and two live tags,
not just a new address calculation.

## 4. What this candidate changes

| concern | change |
|---|---|
| A/W read select | `operand_banks_dual_reuse`: separate `rd_a_stage` / `rd_w_stage`; the two 2:1 muxes are independent, the memory arrays are unchanged |
| stage readiness | engine checks A and W headers independently; `a_hdr_ok`, `w_hdr_ok` use separate stage indices |
| stage release | `stage_release_a[1:0]` / `stage_release_w[1:0]`; legacy `stage_release` still ORs both |
| C tiles | pair start installs slot0=br, slot1=br+1; both stay resident for every `bk` |
| W reuse | one W load per `(bk,bc)`; W stage `wst` alternates per `bk`, W(next) is prefetched into `wst^1` |
| result | one payload; result0 is emitted before br1 final-K, result1 after; no two-tile simultaneous result |

The C cache, A banks and W banks are bit-for-bit the v023 arrays
(`scripts/check_capacity.py` compares the declarations against the read-only
v023 files).

## 5. Pair schedule and the exact stage ownership

For a pair `(br, br+1)` and each `bk`, with `wst` starting at 0 and flipping
after every `bk`:

| step | array reads | DMA writes allowed in the same window | why safe |
|---|---|---|---|
| 1 | wait A0=stage0, W=stage`wst` | none | headers/faults checked |
| 2 | br0: A stage0, W stage`wst` | A1(br+1,bk) -> A stage1 | stage1 != stage0 |
| 3 | after br0: release A stage0 | — | A0 no longer read |
| 4 | wait A1 ready | — | A stage1 header `(br+1,bk)` |
| 5 | br1: A stage1, W stage`wst` | A0(br,bk+1) -> A stage0; W(bk+1) -> W stage`wst^1` | stage0 != stage1 for A; `wst^1` != `wst` for W |
| 6 | after br1: release A stage1, W stage`wst` | — | W pinned only while both row tiles use it |
| 7 | next `bk`: `wst ^= 1` | — | W(next) already in the new `wst` |

The testbench monitors the storage’s real DMA write stage/kind against the
engine’s `rd_a_stage`/`rd_w_stage` during every RUN cycle.  All normal and
backpressure runs report `haz_a=0`, `haz_w=0`.  This is direct evidence for
the port/staging claim; it is not inferred from the loop code.

## 6. C tile lifetime and RAW

- Slot bit is part of the 9-bit cache group: `{slot, group[7:0]}`.  Slot0 and
  slot1 therefore never alias, even for the same 8-bit group index.
- Each `bk` performs read-modify-write of all 256 groups of each tile.  The
  read of group g+1 and write of group g happen in the same cycle (II=1).
  The read of the next group and the write of the current group are different
  addresses in the normal schedule, so `c_raw_bypass_cycles` is 0 in every
  regression.
- The same-address bypass is still present for a future schedule that reads
  and writes the same group.  `tb_cache_slots` proves:
  - slot0 group 5 and slot1 group 5 are independent;
  - same 9-bit group write/read gives write-first data and `raw=1`;
  - cross-slot same low-8-bit group gives the old slot1 data and `raw=0`;
  - byte mask writes only the selected 48-bit bank.
- Cross-K is safe because the last group of `bk` and the first group of
  `bk+1` are different groups; the C tile is not re-loaded from DDR between K
  blocks.  `c_load_blocks` equals the number of tiles, not tiles x K, in every
  old-C regression.

## 7. Two slots are not “all data available”

At any cycle the pair schedule uses:

- one 192-bit cache read and one 192-bit cache write (possibly different
  slots/groups, but only one of each);
- one 49,152-bit result payload;
- one `cseg/cval` writeback stream (the two tiles are deliberately not
  interleaved in v1);
- one A read stage and one W read stage.

Consequences:

- The two C tiles are resident but computed sequentially.
- `result0` waits for `cwr_idle` before br1’s final-K write stream starts.
  This is a measured serialization, not a free overlap; it keeps the v023
  per-tile writeback/result contract.
- The result payload is not duplicated, so the two results cannot be emitted
  in the same cycle.

## 8. Traffic arithmetic

Let `NBR=ceil(M/32)`, `NBC=ceil(N/32)`, `NBK=ceil(K/32)`, `NBLK=NBR*NBC`.

| stream | v023 single-tile | this pair schedule |
|---|---:|---:|
| A blocks | `NBLK*NBK` | `NBLK*NBK` (no A reuse; A0/A1 both loaded) |
| W blocks | `NBLK*NBK` | `ceil(NBR/2)*NBK*NBC` |
| C blocks (C=1) | `NBLK` | `NBLK` |
| C write bytes | `NBLK*6144` | `NBLK*6144` (unchanged) |

For `M=64,N=32,K=96`: A 6, W 3 vs 6, C 0/2, read bytes 15,360 vs 18,432
(C=0) and 27,648 vs 30,720 (C=1).  The measured AXI read bytes in the cluster
test match these numbers; AXI W bytes stay 12,288 because W reuse changes only
the read side.

## 9. A real abort/drain bug found by the overflow test

The first overflow run hung in `WAITDRAIN` with `cwr_pending=1`.  Root cause in
v023 `block_storage_stream_v2`: on `abort`, the write engine padded the current
`w_cur` segment but did **not** drop segment commands already accepted into
`wq_cnt`; only a sticky write error did that (`:450`).  If a compute fault
(e.g. C48 overflow) happens just after a `cseg` was accepted, `wq_cnt` never
returns to 0, `cwr_idle` never asserts, and `drain_done` never asserts.

Fix in this candidate: `(wr_err_sticky||abort)` drops the unposted write queue
(`patches/writeback_interface_v1.patch`).  The overflow test now exits with
`code=8`, `done=1`, `cwr_pending=0`, `b_outstanding=0`, `w_busy=0`.
This is a storage/writeback fix, not a matrix arithmetic change; it is offered
as an independent patch for the writeback owner.

## 10. Limits

- No synthesis/STA/CDC; no frequency or whole-model seconds claim.
- The AXI128 BFM is a protocol/stall model, not a board DDR/PHY.
- The pair schedule’s performance gain is workload-dependent: it saves W read
  bytes and shows a modest cycle reduction in these fixtures, but it also
  serializes result0 on `cwr_idle` and adds A1/A0 prefetch scheduling.
- The result payload remains one 49,152-bit register.  A future design that
  needs both results at once would need a second payload or a readback path;
  this candidate does not claim one.
- `cache_hits` is intentionally 0: every tile is computed once per task, so
  the pair schedule installs fresh tags instead of searching a previous tile.
