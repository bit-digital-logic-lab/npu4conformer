# FINDINGS — ds_adversarial_review

Severity: **S1** contract/numeric failure, **S2** boundary/latency/flush hazard
that can silently lose or duplicate data, **S3** declared-contract ambiguity or
coverage limit.

Method: independent gold written from the published contract (`gold/*.py`, no
RTL or worker golden imported), real Icarus RTL simulation, `-j1`, shell
`timeout` + in-TB watchdog. A candidate is frozen by SHA-256 before the run
(`reports/frozen_shas.json`). Mutants live in `mutants/`; no worker tree was
edited.

---

## AR-001 — FMA accepts a transfer while `flush=1` (S2, still present)

**Frozen input:** `ds_fma_deep/candidate/fp32_fma_pipe.sv`
SHA-256 `b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82`
(also the v023 baseline `1ed8801a…`).

**Test:** `tb/tb_fma.sv +mode=4`: hold `flush=1` for four cycles with
`in_valid=1`, sample `in_ready`.
**Observed:** `FLUSH_HANDSHAKES=4`. The same edge takes the flush branch in all
stages, so an upstream that keeps issuing loses an element it believes was
accepted.
**Expected:** `in_ready=0` while `flush=1` (or a documented drain handshake).
**Reproduce:** `bash scripts/run_fma.sh probe <fma>.sv` (mode 4 is advisory).
**Status:** **fixed** by `ds_repair_fmaflush/rtl/fp32_fma_pipe.sv`
SHA-256 `3c1114bc40078fd357bb968e8daecc53e68ad4da25a6ae586ce658b4d2a5e0c5`.
Re-run with the same harness: mode4 `PASS` (0 handshakes during flush), and
stream 8734 / flush / reset / II all pass. The integration must pick this SHA,
not `b062284a…`, if the flush contract is required.

---

## AR-002 — FMA zero+zero / inf×subnormal contract is not strict IEEE (S3)

At the v023 baseline, 59 of 8,734 strict-IEEE probes differ: exact
`(+0)+(-0)` returns `-0` (sign taken from `c`), and `inf * subnormal` returns
`inf` because `inf*0` detection uses raw bits while arithmetic is FTZ.
This matches the v023 reference and is therefore the *declared project
contract*, not a regression. Do not call the core "strict IEEE" without this
caveat; any strict residual-add consumer can see a signed-zero difference.

---

## AR-004 — per-column scale/bias were not pipelined with C48 data (S1, fixed)

**Frozen (failing) input:** `ds_epilogue_channels` engine
`a70758bb5e558a4e…`, lane `52465ee6a3a64594…`, i2f `637a7b327d35760b…`.
**Observed:** `tb_epilogue +mode=0` → 61 a16/FP32 mismatches, `stat_table_hits`
still 256 and `stat_col_align_err=0`. Example: tag 1 (columns 4..7) used the
table entries of columns 12..15 — a **+2-beat** shift, equal to the i2f stage
latency. `epilogue_lane` fed the engine's combinational `lane_scale/lane_bias`
straight to `epilogue_fma_stage`; the data went through two i2f registers, so the
scale sampled at the FMA input belonged to a later beat.
**Fix observed:** the worker changed `epilogue_i48_to_f32` to carry
`in_scale/in_bias` through S1/S2 with the data; a later SHA passes.
**Evidence:** `reports/findings/AR-004_mode0_misaligned_scales.log`.
**Lesson:** this is the exact "perchannel column tag" hazard; keep the alignment
test in the gate.

---

## AR-005 — vector 4-lane tail: old failure and the naive-fix negative control

**Old v023 (`ds_closeout_numeric/rtl/ddr_vector_engine_pipe.sv`)**: fixed-op
(ADD, op0) totals **9..16** fail with 20..48 byte mismatches; totals 1..8 pass
only because the engine falls back to the scalar `CITER` path, and >=17 passes.
This is the untested 4-lane boundary.
**Candidate `ds_vector_fma/rtl/ddr_vector_engine_pipe.sv`
`dad7cac00ecbe5a7…`**: passes every tested total for op17 FMA, op0 ADD and
op15 F32_I16/out16: 1..17, 127, 255, 256, 257, 1001 (plus B-delay 25). See
`logs/vec/vec_cand_early/rc.txt`.
**Negative control:** `mutants/vector/ddr_vector_engine_naive_gate.sv` only
deletes the `bank_elems>8` condition from the v023 engine. It fails totals
**5..8** (`va/vb` mismatch), proving the gate must not be removed without the
real mask/pack fix. This is the explicit "不准只删条件" check.

---

## AR-006 — epilogue deadlocks when A16 and FP32 are backpressured together (S1, open)

**Frozen input:** `ds_epilogue_channels` engine `4fff5c3f21b3924c…`, lane
`c633576dd01da04e…`, i2f `4c862453f53b26e1…`, fma `1ed8801a…`.
**Test:** 32 per-channel beats (bank0, distinct scale/bias per column),
`a16_ready` and `fp32x4_ready` independently randomized.
**Observed:** only **22 A16 / 25 FP32** beats leave; tags 22..31 never appear;
the TB watchdog fires. With either channel always ready (or no backpressure)
32/32 pass.
**Expected:** four independent consumers; stalling one must not stall/lose the
other.
**Reproduce:** `bash scripts/run_epilogue.sh <tag> <files>`; advisory probe
`probe_both_bp` (mode 3, `+bp=1`).
**Still open** in `ds_repair_epilogue/rtl/epilogue_stream_engine_v024.sv`
SHA-256 `f4857c19686948289f74de969806e8baff99114596d37a56506d9322d3872b84`
(22 A16 / 25 FP32 of 32).
**Severity rationale:** a real model with a slow A16 consumer and a ready FP32
tap can hang the whole epilogue.

---

## AR-007 — epilogue multi-phase stall with A16 backpressure only (S2, open)

**Test:** `tb_epilogue +mode=0 +bp=2` (bank0 → bank1 → scalar, only
`a16_ready` randomized; `fp32x4_ready=1`).
**Observed:** 54 A16 / 57 FP32 of 72, then watchdog. Single-phase `mode3 +bp=2`
passes, so the interaction is with the config transition (or the packed fork).
**Reproduce:** advisory probe `probe_multiphase_a16bp` in `run_epilogue.sh`.
**Fixed** in `ds_repair_epilogue` engine `f4857c19…`: 72/72 A16+FP32, PASS.

---

## AR-008 — storage coalescer: native pass, generic fallback page-rule/stall (S1/S2)

**Frozen input:** `ds_storage_write/rtl/block_storage_stream_v3.sv`
`b92cb2a73726156e…`.
**Native (aligned and block-crossing-4KiB)**: 64 cseg → **24 posted requests**,
384 beats, max 16 beats, 6144 B reconstructed byte-exactly with exactly one
write per byte; at `C_BASE=0x03000C00` the block crosses two 4 KiB pages and the
coalescer splits correctly (`pagesplit=2`). This meets the merge contract.
**Generic fallback (S1):** a single 96 B segment at `0x03000FE0` is posted as one
6-beat request `0x03000FE0..0x0300103F`, which **crosses the 4 KiB boundary**.
AXI4 forbids a burst crossing 4 KiB; the native path splits, the generic path
does not. Reproduce: `+generic +ngen=1 +genoff=00000fe0` (advisory in
`run_write.sh`).
**Generic back-to-back (S2):** two non-native segments at `0x…1110` and
`0x…1190`; the second never completes and `cseg_ready` goes **X** (watchdog).
Single generic segment passes. Reproduce: `+generic +ngen=2 +genoff=00001110`.
**Note:** the worker's own `tb_storage_coalesce.sv` currently does not elaborate
here (`rd_req_ready` is both a TB reg and a BFM output), so its PASS cannot be
taken as evidence for these two generic cases.

---

## Acceptance snapshot (frozen SHAs)

| item | frozen SHA | independent result |
|---|---|---|
| FMA 7-stage deep | `b062284a…` | numeric 8734 PASS, II=1 PASS, reset PASS, flush-epoch PASS; AR-001 open |
| vector tail/op17 | `dad7cac0…` | op17/op0/op15 tails PASS; drain PASS; old 9..16 negative reproduced |
| epilogue per-column | `4fff5c3f…`/`c633576d…` | no-bp functional PASS; AR-006/007 open |
| storage coalescer | `b92cb2a7…` | native/pagecross PASS; AR-008 generic open |
| fusion dual done-B | (worker result) | see REPORT; must be re-run with long B before integration |

Integration on `ds_unified_graph` is **not** claimed from these module passes.

---

## AR-009 — matrix W reuse is real in AXI bytes, not just a control bit (accept)

**Candidate:** `ds_matrix_reuse/candidate/rtl` cluster, `PIPE_STAGES=4`.
**Independent run** (same fixture, same BFM, only `cfg_w_reuse` differs):

| run | rd_bytes | AXI W bytes | cycles | verdict |
|---|---:|---:|---:|---|
| M64 N32 K96 reuse=0 | 18,432 | 12,288 | 7,612 | PASS |
| M64 N32 K96 reuse=1 | 15,360 | 12,288 | 7,236 | PASS |

The read drop is exactly 3,072 B = half of the 6,144 B W traffic; the A16/C
output bytes do not change. This is a real schedule change, not a counter.
**Caveat:** the pair schedule uses the existing two C slots plus a second A
stage; it is not "zero extra storage" (the INTERFACE accounts for the second A
bank and the two resident C tiles). Do not quote "zero BRAM" without the
capacity ledger.

---

## AR-010 — double-buffer A16 done-B boundary holds (accept, module/cluster)

**Candidate:** `ds_fusion_buffers/rtl/matrix_stream_fusion_top_dual.sv` (worker
SHA `ff13ca00…` in its result) and `rtl/fusion_a16_writer.sv`.
**Independent writer unit** (`tb/tb_doneb.sv`): with B delays 0/5/30 and an odd
8-byte tail, `done` is strictly after `dma_done`, `last_w < last_b`, and the tail
strobe is `0x00ff`. Negative control
`mutants/fusion/fusion_a16_writer_early_done.sv` (done on last W) fails, so the
test detects early completion.
**Independent dual-top runs** (real RTL + worker's v5 BFM, read-only):
- `main` (1 tile) `bextra=120`: `last_w=2106`, `last_b=2238`, `done=2240`,
  `wr_bursts=8`, `bmax=8`, PASS.
- `n64` (2 tiles) `bextra=3000`: `last_w=4825`, `last_b=7855`, `done=7857`,
  `wr_bursts=16`, `bmax=8`, PASS; `task_cycles=2934` vs `cycles=7857` shows the
  compute/write overlap is real under a long B delay.
This is not a whole-model claim; it is the fused cluster boundary.

---

## AR-011 — graph prefetch accounting and epoch invalidation (accept, module)

**Real-sim evidence** (`ds_graph_prefetch/logs/gp_*.log`, `lu_*.log`):
- exclusive union: `383+44+8+23339 = 23774` = total cycles; non-engine 435 =
  **1.83%**, so the rejected 59.8% attribution is an arithmetic error.
- lookahead on 23660 vs off 23774 → **114 cycles (0.48%)**, hits=6, misses=1.
- normal run `epoch=2, valid=0`; fault/isolation/abort runs `epoch=3/4,
  valid=0, aborts>0`; SEQ plans `has_seq=1, fetches=0`.
This accepts the *accounting correction* and the optional, default-off
lookahead/epoch contract. It does not claim a large speedup, and it is not an
end-to-end graph acceptance.

---

## AR-012 — ds_unified_graph integration was not deliverable at the review deadline (reject)

At the review cutoff:
- the worker's fused small-graph run printed `rc=0` (241 s), but the dumped A16
  window at the documented `0x04007800` matched the frozen `v024_ref.json` only
  **9/512** words; the worker's own judge reported `fused A16 mismatch 503/512`.
- the legacy fallback run was terminated (`rc=143`) and produced no PASS.
- `safety_normal` hit `rc=124` (90 s timeout) with `WAIT cyc=20000 busy=1
  rd=0 wr=0 b=0`.
- no `ds_unified_graph/result.json` or stage delivery was published.

Therefore the module PASSes above are **not** stitched into an integration PASS.
This is a process/technical block for the owner, not a claim that every module
is wrong. Re-run the same graph once a frozen unified SHA and `result.json`
exist; only then can the integration item be accepted.
