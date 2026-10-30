# REPORT — ds_matrix_reuse v1

Date: 2026-10-30  
Task: `/home/yang/Desktop/项目/v024_opt/ds_matrix_reuse`  
Scope: **logic simulation only**.  No synthesis, Vivado, DRC/STA, board, VNC,
network deployment or push.  No frequency or whole-model seconds claim.
All source outside this directory (`v023_repair/`, `work/`, ZIP, other
workers) was read-only.

## 1. Executive result

The v023 `SLOTS=2` C cache is **two resident C48 accumulators**, not a
ready-made 2x1 W-reuse super-tile.  The v023 schedule still computes one output
tile at a time and reloads W per row tile.  Making the 2x1 schedule work
required three interface changes in addition to the loop change:

1. independent A and W compute read-stage selects (`rd_a_stage`,
   `rd_w_stage`);
2. independent A/W stage-ready checks in the engine;
3. per-kind stage release (`stage_release_a`, `stage_release_w`) so A can be
   refilled while W stays pinned.

The candidate keeps the v023 C cache, A bank and W bank arrays unchanged
(no new BRAM/LUTRAM array), adds only control/telemetry flops, and implements
`cfg_w_reuse`:

- `0`: v023 single-tile schedule;
- `1`: pair `(br, br+1)` across all K when at least two row blocks remain;
  W is loaded once per `(bk,bc)`; an odd last row block uses the single-tile
  tail path.

Measured on the same fixtures/BFM/gold:

| case | reuse | cycles | AXI/transactional read B | W read B | write B |
|---|---:|---:|---:|---:|---:|
| M64 N32 K96 C0 | 0 | 4550 | 18,432 | 6,144 | 12,288 |
| M64 N32 K96 C0 | 1 | **4367** | **15,360** | **3,072** | 12,288 |
| M64 N32 K96 C1 | 1 | 5154 | 27,648 | 3,072 | 12,288 |
| v023 reference M64 N32 K96 C0 | n/a | 4552 | — | 6,144 | 12,288 |
| v023 reference M64 N32 K96 C1 | n/a | 5329 | — | 6,144 | 12,288 |

The gain is a read-traffic/schedule effect, not a PE-frequency claim.  The
two-slot result is emitted one tile at a time; result0 waits `cwr_idle` before
br1’s final-K write stream starts, so the v1 pair is not a free two-tile
overlap.

## 2. Audit answer (details in `REVIEW.md`)

- The two C slots are 2 x 256 groups x 192 bit = 2 x 6,144 B.  Group index is
  9 bit `{slot, group[7:0]}`; slot0/slot1 never alias.
- The cache has **one** 192-bit read port and **one** write port.  Only one
  tile is read/written by the compute path in a cycle.
- The result payload is **one** 49,152-bit register, so two results cannot be
  emitted simultaneously.
- v023 ties A and W to one `rd_stage` (`operand_banks_dual_v2.sv:58-59`), checks
  `stage_a_ready[s] && stage_w_ready[s]` together
  (`block_engine_prefetch_v2.sv:258`), and releases both kinds with one
  `stage_release` (`block_storage_stream_v2.sv:412-415`).  A loop-only change
  would therefore either read W from the wrong stage or free the pinned W.
- Therefore the “zero extra BRAM” part of the claim is supportable; the
  “only modify `block_engine_prefetch_v2`” part is not.

The direct evidence for the port/staging claim is the TB hazard monitor:
during every RUN cycle, the storage’s actual DMA write stage/kind is compared
with `rd_a_stage`/`rd_w_stage`.  All normal/backpressure/fault runs report
`haz_a=0`, `haz_w=0`.  `c_raw_bypass_cycles=0` in all normal runs, and the
directed `tb_cache_slots` proves same-group bypass and cross-slot non-alias.

## 3. What was implemented

| module | role |
|---|---|
| `candidate/rtl/block_engine_reuse_v1.sv` | new pair/single engine; optional W reuse; same A16/W7/C48 numeric/error contract |
| `candidate/rtl/block_storage_stream_reuse_v1.sv` | v023 storage + independent A/W read stages + per-kind release + abort queue drop |
| `candidate/rtl/operand_banks_dual_reuse.sv` | same A/W arrays, separate A/W read-stage muxes |
| `candidate/rtl/matrix_reuse_cluster_v1.sv` | engine + storage + read DMA + write DMA; AXI read/write masters separate |
| `candidate/rtl/c_cache_banked4_pipe.sv` etc. | unmodified v023 copies |

Pair schedule per `bk` (`wst` alternates per `bk`):

1. wait A0 = A(br,bk), W = W(bk,bc), both headers/faults checked;
2. issue A1 = A(br+1,bk) into A stage 1; run br0 on A0 + W;
3. release A stage 0; wait A1;
4. issue A0(next) into A stage 0 and W(next) into W stage `wst^1`;
   run br1 on A1 + W;
5. release A stage 1 and W stage `wst`; flip `wst`.

At no point does a DMA write target the A/W bank currently read by the array.
C slot0 is br and slot1 is br+1 for the whole K loop; old C is loaded once per
tile (`c_load_blocks == number of tiles`, not `tiles x K`).

## 4. Test matrix (real RTL, fresh fixtures, independent gold)

All cases use `scripts/gold_reuse.py`, which is a hand-written integer model
(not RTL-derived, not an old JSON PASS).  Every engine run compares:
result payload per block, the entire C memory, result count/coordinates,
`c_collect_groups`, `write_blocks`, BFM read/write commands and beats, expected
A/W/C block counts, `cwr_pending=0`, `b_outstanding=0`, `w_busy=0`, storage
drain, and `haz_a/haz_w=0`.

| case | M | N | K | old C | reuse | cycles | read B | W B | write B | result |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| m32n32k32_c0_r0 | 32 | 32 | 32 | 0 | 0 | 1,194 | 3,072 | 1,024 | 6,144 | PASS |
| m32n32k32_c0_r1 | 32 | 32 | 32 | 0 | 1 | 1,194 | 3,072 | 1,024 | 6,144 | PASS |
| m32n64k32_c0_r1 | 32 | 64 | 32 | 0 | 1 | 2,387 | 6,144 | 2,048 | 12,288 | PASS |
| m32n32k32_c1_r0 | 32 | 32 | 32 | 1 | 0 | 1,585 | 9,216 | 1,024 | 6,144 | PASS |
| m64n32k96_c0_r1 | 64 | 32 | 96 | 0 | 1 | 4,367 | 15,360 | 3,072 | 12,288 | PASS |
| m64n32k96_c0_r0 | 64 | 32 | 96 | 0 | 0 | 4,550 | 18,432 | 6,144 | 12,288 | PASS |
| m64n32k96_c1_r1 | 64 | 32 | 96 | 1 | 1 | 5,154 | 27,648 | 3,072 | 12,288 | PASS |
| m64n64k96_c0_r1 | 64 | 64 | 96 | 0 | 1 | 8,735 | 30,720 | 6,144 | 24,576 | PASS |
| m96n32k96_c0_r1 | 96 | 32 | 96 | 0 | 1 | 6,645 | 24,576 | 6,144 | 18,432 | PASS |
| m96n64k64_c1_r1 | 96 | 64 | 64 | 1 | 1 | 12,388 | 69,632 | 8,192 | 36,864 | PASS |
| m64n32k1_c0_r1 | 64 | 32 | 1 | 0 | 1 | 1,964 | 5,120 | 1,024 | 12,288 | PASS |
| m64n32k32_c0_r1 | 64 | 32 | 32 | 0 | 1 | 2,202 | 5,120 | 1,024 | 12,288 | PASS |
| m64n32k33_c0_r1 | 64 | 32 | 33 | 0 | 1 | 3,047 | 10,240 | 2,048 | 12,288 | PASS |
| m64n32k65_c0_r1 | 64 | 32 | 65 | 0 | 1 | 4,128 | 15,360 | 3,072 | 12,288 | PASS |
| backpressure C1 | 64 | 32 | 96 | 1 | 1 | 28,142 | 27,648 | 3,072 | 12,288 | PASS |

`read B` is the exact transactional BFM payload (`rd_beats x 16`); `W B` is
the W portion of that read and is an explicit counter/expected-value check,
not a bandwidth model.  K=1, K=32, K=96, K=33 and K=65 cover one-K-tile,
full-K-tile and non-multiple tail cases.  M96 exercises pair + odd tail.
N64 exercises two column blocks.

### 4.1 Faults / old-C overflow / parity / drain

| case | expected | measured | cycles | drain |
|---|---:|---:|---:|---|
| C48 old-C overflow (`c_mode=max`) | code 8 | **08** | 1,122 | `done=1,cwr_pending=0,b_out=0,w_busy=0` |
| bad W parity | code 9 | **09** | 203 | same |
| injected read error | code 9 | **09** | 137 | same |
| injected write error | code 10 | **0a** | 2,514 | same |

The overflow test exposed a real v023 storage bug: `abort` dropped the current
write segment but not segment commands already accepted into `wq_cnt`, so
`cwr_idle`/`drain_done` could never assert.  The fix is in
`patches/writeback_interface_v1.patch` (abort also drops the unposted queue).
This is a writeback/drain fix, not a matrix arithmetic change.

## 5. Actual AXI W bytes (AXI128 BFM)

The cluster test uses real AXI AR/R and AW/W/B masters and the shared AXI128
BFM.  `AXI_W_bytes` is the summed actual `WSTRB` count; `AW = B` and
`aw_cnt/b_cnt/wr_active` are all zero after `done + 10` cycles.

| case | reuse | cycles | AXI W bytes | W beats | W bursts | AXI read bytes | AW/B drained |
|---|---:|---:|---:|---:|---:|---:|---|
| M64 N32 K96 C0 | 0 | 7,612 | 12,288 | 768 | 130 | 18,432 | 130/130 |
| M64 N32 K96 C0 | 1 | 7,236 | 12,288 | 768 | 130 | **15,360** | 130/130 |
| M64 N32 K96 C1 | 1 | 8,435 | 12,288 | 768 | 130 | 27,648 | 130/130 |
| M64 N64 K96 C0 | 1 | 14,591 | 24,576 | 1,536 | 260 | 30,720 | 260/260 |
| M96 N32 K96 C0 | 1 | 11,083 | 18,432 | 1,152 | 195 | 24,576 | 195/195 |
| M96 N64 K64 C1 | 1 | 22,172 | 36,864 | 2,304 | 390 | 69,632 | 390/390 |

W bursts are larger than `64 x NBLK` because a 96 B C segment can cross a
4 KiB boundary and is split by the DMA; the byte/beat counts are exact.
W reuse changes only the read side, so the W write bytes are unchanged.

## 6. Reference RTL (not same-source golden)

The read-only v023 `tb_engine_p2` + v023 candidate RTL were rebuilt and run on
the same fixtures and gold:

| case | v023 cycles | v023 result |
|---|---:|---|
| M64 N32 K96 C0 | 4,552 | PASS |
| M64 N32 K96 C1 | 5,329 | PASS |

This is an independent RTL reference against the same integer gold, not a
reuse of an old PASS.  The new candidate also passes the same gold.

## 7. Capacity inventory (logical, not synthesis)

`scripts/check_capacity.py` verifies the declarations against the read-only v023
files and writes `logs/capacity.json`:

| array | shape | bits | bytes | style |
|---|---|---:|---:|---|
| C cache | 4 x 512 x 48 | 98,304 | 12,288 | block RAM (`ram_style=block`) |
| A banks | 2 x 16 x 8 x 128 | 32,768 | 4,096 | distributed RAM |
| W banks | 2 x 16 x 64 x 8 | 16,384 | 2,048 | distributed RAM |
| result payload | 1 x 49,152 | 49,152 | 6,144 | registers |

C cache per slot: 49,152 bit / 6,144 B; two slots: 12,288 B.

The candidate adds **no new memory array**.  It does add control/telemetry
flops (`unit`, `use_pair`, `wst`, `curs`, `cload_u`, result-hold fields,
`fresh_c[2]`, counters) and a second read-mux select.  This is **not** a zero
extra FF/LUT claim, and the table is not a Vivado/synthesis resource report.

## 8. Reproduction and evidence

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_matrix_reuse
bash scripts/run_all.sh          # 47 commands, rc=0; Verilator -j 1; timeouts
python3 scripts/collect_metrics.py
python3 scripts/check_capacity.py
python3 scripts/check_freeze.py
```

- `logs/commands.log` — 47 commands / 0 nonzero.
- `logs/metrics.txt`, `logs/metrics.json` — per-run rc/verdict/cycles/bytes.
- `logs/run_*.log` — full per-case logs (watchdogs inside TB + external timeout).
- `logs/capacity.log`, `logs/capacity.json` — array inventory.
- `REFERENCE_FREEZE.json`, `logs/check_freeze.log` — frozen gold/RTL/fixture
  SHA; `check_freeze.py` PASS.
- `filelist.txt`, `SHA256SUMS.txt` — unique deliverable/evidence list.

## 9. Unfinished / limits

- No synthesis, STA, CDC, DRC, board DDR/PHY, VNC or push.  No frequency,
  LUT/FF count or whole-model runtime is claimed.
- The AXI128 BFM is a protocol/stall model; its latencies/BP are not board
  measurements.  The Zynq PS hard DDR controller is not bypassed.
- The pair schedule is single-clock; `rd_a_stage/rd_w_stage`, per-kind release
  and `cval_ready`/`cwr_pending` paths are not STA-cleaned.
- v1 does not interleave the two tiles’ C writeback streams and does not emit
  two results in one cycle.  A future overlap needs a per-tile writeback tag or
  a second result path; not implemented.
- `cache_hits=0` by design: each tile is computed once per task; cache reuse
  across tasks is not modeled.
- M96 tail uses the single-tile path; W reuse applies only to complete pairs.
- The abort queue-drop fix is in the storage/writeback patch and should be
  merged by the writeback owner; this task does not modify other workers’
  directories.
- All results are for review by the main agent; an agent exit 0 is not an
  acceptance claim.
