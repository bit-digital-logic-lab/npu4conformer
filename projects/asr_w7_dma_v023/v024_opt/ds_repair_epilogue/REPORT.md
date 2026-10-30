# REPORT — ds_repair_epilogue

Date: 2026-10-30  
Tree: `/home/yang/Desktop/项目/v024_opt/ds_repair_epilogue`  
Model: `opencode-go/deepseek-v4.1-flash`  
Scope: **module-level Icarus Verilog logic simulation only.** No synthesis,
Vivado/STA, board, VNC or push. No frequency, whole-model time, WER/CER or
bandwidth claim. The source worker tree
`v024_opt/ds_epilogue_channels` and the review tree
`v024_opt/ds_adversarial_review` were treated as read-only; their files were
copied into this tree and run here.

---

## 0. Result

`run_all.sh` exits **0** with fresh artifacts:

| Check | Result |
|---|---|
| Strict formal gate on new SHA | **28/28 cases PASS**, rc=0 |
| Multi-phase real beats | **1088** A16 + 544 packed + 1088 FP32, 0 errors |
| Boundary lengths | 1,2,3,5,9,17,31,32,33,127,129,255,256,257,259,511,512 PASS |
| Original worker 10-case regression with new RTL | **10/10 PASS** |
| Negative control (column-0 mutation) | rejected, **26/28 cases with real value mismatches** |
| Old SHA, original advisory AR-006/AR-007 | **rc=1 / rc=1** (reproduced) |
| Old SHA, corrected-ready AR-006/AR-007 | rc=0 / rc=0 (32/32 and 72/72 beats) |
| New SHA, corrected-ready AR-006/AR-007 | rc=0 / rc=0 (32/32 and 72/72 beats) |
| Old SHA, new strict gate | **rc=1**, only `cfg_pending_beat` fails |
| New SHA, new strict gate | **rc=0**, 0 failures |

`result.json` is written from these fresh logs, not from an old PASS file.
Exit codes and sub-item results agree: any mismatch, stability error,
missing/extra beat, count error, watchdog or compile error makes the gate and
`run_all.sh` non-zero.

**Important honest finding:** AR-006 and AR-007 *as published* are not RTL
deadlocks. The advisory testbench freezes `a16_ready`/`fp32x4_ready` after the
last `send_beat` and never drives them during its `cfg`/`param`/drain wait
loops. A consumer that never re-asserts `ready` cannot drain any pipelined RTL.
With the same advisory TB and only a clocked `ready` driver added (no RTL
change), the **old** SHA completes 32/32 and 72/72 beats cleanly. The new SHA
also passes. This is why the formal gate keeps independent random/long-window
backpressure *live* instead of deleting the check.

The old SHA does have a real, contract-derived failure that the new SHA fixes:
`cfg_ready` and legacy/active-bank parameter writes hand-shake while an input
beat is presented but not yet accepted, re-parameterizing that beat and
withdrawing `spill_valid` without a handshake. That is the `cfg_pending_beat`
case below.

---

## 1. AR-006 / AR-007 reproduction and root cause

Frozen old input (matches `FINDINGS.md`):

```
epilogue_stream_engine_v024.sv  4fff5c3f21b3924c421e4a91a82db40550b1d782b18348cad6bff125c9fcb305
epilogue_lane.sv                c633576dd01da04ec2686096f9e90acdfc7ca4987925c8bb7d053df204cf3885
epilogue_i48_to_f32.sv          4c862453f53b26e18b832c5fd919da7f8f444b70f9a4affb060deb91a37f5a13
```

Reproduction used a **byte-identical copy** of the review harness in
`ref_probe/` (`run_epilogue.sh` and `tb_epilogue.sv` SHAs are in
`logs/evidence/ref_copy_sha.txt`; the review tree was not edited):

```bash
bash ref_probe/scripts/run_epilogue.sh adv_old <old rtl files>
```

Observed (logs `ref_probe/logs/epi/adv_old/`):

| Probe | Old SHA | New SHA |
|---|---|---|
| `probe_both_bp` (`+mode=3 +bp=1`) | rc=1, `a16=22 fp=25`, tags 22..31 missing, watchdog | rc=1, same frozen-ready artefact |
| `probe_multiphase_a16bp` (`+mode=0 +bp=2`) | rc=1, `WATCHDOG a16=54 fp=57` | rc=0, 72/72 (last frozen value happened to be ready) |

Root cause, proven by a minimal stimulus-only change in `exp/tb_exp.sv`:
the advisory `send_beat` only randomizes ready while a beat is being sent; once
the last beat is accepted it stops, and `do_cfg`/`do_pw`/`drain_outputs` wait
with ready frozen at whatever the last random value was. If that value is 0,
the remaining in-flight beats cannot leave. Any correct AXI-Stream sink has the
same behaviour.

Same advisory TB, only a continuous `ready` driver added to every wait loop, no
RTL change (logs `logs/evidence/corrected_*`):

| | AR-006 (`mode=3 bp=1`) | AR-007 (`mode=0 bp=2`) |
|---|---|---|
| old SHA | rc=0, 32/32 A16 + 32/32 FP32 | rc=0, 72/72 A16 + 72/72 FP32 |
| new SHA | rc=0, 32/32 + 32/32 | rc=0, 72/72 + 72/72 |

Conclusion: the published AR-006 advisory (`both ready held 0 forever`) is
**unsatisfiable by any valid RTL**; it is retained only as root-cause evidence.
The formal gate does not weaken the intent: it applies independent random,
coprime long-window and bounded full-stall (64 cycles, then released)
backpressure to all four consumers and requires exact completion.

---

## 2. RTL repair (new SHA)

Only `rtl/epilogue_stream_engine_v024.sv` changed; the other six files are
byte-identical to the candidate.

1. **Per-consumer A16 pending/ack.** A16 is a dedicated `a16_pend_*` register,
   loaded from the lane beat and cleared only by its own handshake (or
   abort/reset). It no longer borrows the packer source beat, so packed
   backpressure cannot withdraw/hold A16.
2. **Independent packer source.** `src_*` is released when the packer captures
   the beat (empty half register or completed 128-bit word), not when A16 acks.
   An empty half can absorb a beat while the 128-bit output is backpressured;
   only the word-completing/flushing beat waits for the p128 slot.
3. **FP32 per-lane pending unchanged.** The four lockstep lanes each hold one
   post-ReLU FP32 beat; `fp32x4_valid` clears only on the fp32x4 handshake.
4. **Valid stability by construction.** All four output valids are held until
   their own handshake; only `abort`/reset clears them. This satisfies the
   "do not withdraw valid because the other channel's ready changed" rule.
5. **Config/param race fix.** `cfg_ready = engine_idle && !cval_valid`; legacy
   and **active-bank** parameter writes also require `!cval_valid`. A presented
   but unaccepted input beat is therefore consumed before its parameters can
   change. Inactive-bank ping-pong preload remains allowed during streaming.

Preserved unchanged: per-column scale/bias alignment through the i2f stages,
two-bank table + bc sideband, A16/packed/FP32/spill semantics, abort flush,
config drain, scalar fallback, telemetry and port list. The original worker's
10-case regression (including per-column bank0->bank1, active-bank write
rejection, abort with FP32 pending, spill + FP32 random backpressure, partial
table fallback, bias-only legacy preload and addr-2 rejection) passes with the
new engine.

---

## 3. Old-SHA failure / new-SHA pass evidence

### 3.1 Original advisory (unsatisfiable frozen-ready form)

`logs/evidence/summary.json`:

```
old  AR-006 rc=1, AR-007 rc=1
new  AR-006 rc=1, AR-007 rc=0
```

The new SHA still fails AR-006 in the *original* form because both consumers
are held unready forever at the end; no correct design can drain that. This is
reported deliberately rather than “fixed” by dropping data.

### 3.2 Contract-derived real failure: `cfg_pending_beat`

New strict case (also in the formal gate): a beat is presented with
`cfg_spill_c48=1` and `spill_ready=0`; an early `cfg`/new-epoch request is
asserted for 20 cycles. Required behaviour: `cfg_ready` stays 0, `spill_valid`
stays high and stable, the beat is accepted, then config fires.

| SHA | Result |
|---|---|
| old `4fff5c3f…` | rc=1: 20× `FAIL cfg_ready with pending input beat`, 20× `FAIL spill valid withdrawn without handshake`, `FAIL STABLE spill tag=0` |
| new `f4857c19…` | rc=0: `a16=65/65 pack=33/33 fp=65/65 spill=1/1`, then the scalar epoch completes |

The full strict gate on the old SHA fails **only** this case; the other 27
cases pass, which is why we do not claim a hidden old deadlock. On the new SHA
all 28 pass.

---

## 4. Strict formal gate matrix (new SHA, 28/28 PASS)

Independent TB: `tb/tb_epilogue_strict.sv`. It drives each of
`a16_ready`, `a16_packed_ready`, `fp32x4_ready`, `spill_ready` continuously and
independently (random, coprime long windows, or a bounded 64-cycle full stall
that is then released). It checks every cycle that `valid && !ready` keeps
valid/payload/tag/last; scores A16/FP32 by tag; scores packed against a
pair/zero-pad queue; scores spill against the accepted input beat; and requires
exact counts, no extra beats, no column-alignment errors, and a drain of the
last beat of every channel.

| Case group | Coverage | Observed |
|---|---|---|
| `multi_bp1..4` | bank0 512 → bank1 512 → scalar 64, per-column tables, inactive-bank preload, active-bank write reject, config at block boundary | 1088 A16 / 544 packed / 1088 FP32, `hits=4096`, `rej=4` |
| `multi_odd_bp2`, `multi_odd_bp4` | odd phase lengths 511/257/63 and 127/129/63 | 831 and 319 A16, packed ceil, 0 errors |
| `spill_bp1`, `spill_bp2` | 512 beats with C48 spill + FP32 + independent backpressure | 512 A16 / 256 packed / 512 FP32 / 512 spill |
| `abort_bp1`, `abort_bp2` | 6 beats, one-cycle abort, 20-cycle no-output window, new scalar epoch 64 beats | 64/64 A16, 32/32 packed, 64/64 FP32 post-abort |
| `cfg_pending_beat` | early config over a pending spill-stalled beat | see §3.2 |
| `boundary_n*` | 1,2,3,5,17,31,32,127,255,256,257,511,512 | exact counts, odd tails zero-padded |
| `boundary_bp3_n*` | 9,33,129,259 with independent A16/FP32 random backpressure | exact counts |

Backpressure profiles are deterministic from `+bp`/`+seed`; logs are under
`logs/gate_new/`. Compilation is one serial `iverilog` invocation per build; each
simulation has both a shell `timeout 300` and the in-TB `MAXCYC` watchdog.

---

## 5. Independent gold and vectors

* `gold/epilogue_gold.py`, `gold/fma_gold.py` are the independent
  published-contract model from `ds_adversarial_review/gold` (SHA in
  `SHA256SUMS.txt`); they do not import RTL or any worker golden.
* `gold/gen_vectors.py` generates deterministic vectors: 512 bank0 + 512 bank1
  + 64 scalar = **1088 beats**, 32 distinct per-column scale/bias entries per
  bank, four lanes per beat, tags unique per phase.
* Expected A16/FP32 come only from the gold; expected packed is built by the
  TB from consecutive A16 pairs with explicit zero-pad for odd/single tails;
  spill is checked against the accepted C48 input.
* The large multi-phase runs therefore complete **1088 real beats**, not a
  toy handful. Boundary runs independently cover 1..512.

---

## 6. Negative control

`scripts/negative_control.sh` copies the new RTL, forces every lane's
scale/bias lookup to column 0, and runs the full gate. The gate exits non-zero
and 26/28 cases report real value mismatches (e.g. `FAIL a16 tag=0 lane=3
got=7ace exp=7fff`, `FAIL fp tag=0 lane=3 got=46f59b80 exp=4711d49c`). The
control script exits 0 only when the broken RTL is rejected for that reason;
`logs/negctl/status.json` records `{"rejected":true,"value_mismatch":true}`.
The two cases that still pass at n=1/n=2 are single-column-aligned cases where
column 0 is the correct column; the gate as a whole is non-zero.

---

## 7. Original worker regression (feature preservation)

`scripts/run_regress.sh` copies the worker's 10-case suite into `regress/`,
substitutes this tree's RTL, and runs it unmodified. Result:
`REGRESS PASS cases=10 failed=[] rc=0` (`regress/RUN_RESULT.json`). This covers
scalar, per-column bank0->bank1, cross-row/short tail, config wait, abort
recovery, abort with FP32 pending, spill+FP32 random backpressure, long
periodic stalls, partial table fallback, bias-only legacy preload and
unsupported addr-2 rejection.

---

## 8. Reproduction

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_repair_epilogue
bash run_all.sh
echo $?        # 0 only if every check below passes
```

`run_all.sh` runs, in order:

1. `python3 gold/gen_vectors.py vectors` — deterministic 1088-beat vectors;
2. `bash scripts/run_gate.sh gate_new rtl/*.sv` — 28 strict cases, fresh logs;
3. `bash scripts/negative_control.sh` — broken RTL must be rejected;
4. `bash scripts/run_regress.sh` — worker 10/10 with new RTL;
5. `bash scripts/evidence.sh` — original advisory old/new, corrected-ready
   old/new, and the strict gate on the old SHA;
6. `python3 scripts/finalize.py` — fresh `result.json` + `SHA256SUMS.txt`.

Single-case example:

```bash
iverilog -g2012 -o /tmp/epi_sim tb/tb_epilogue_strict.sv rtl/*.sv
vvp /tmp/epi_sim +dir=vectors +mode=0 +bp=2 +seed=102 +n0=512 +n1=512 +ns=64
```

Observed `run_all.sh` wall time on this host: about 67 s; no parallel compile
or parallel simulation is used.

---

## 9. Frozen SHAs

New (this tree):

```
epilogue_stream_engine_v024.sv  f4857c19686948289f74de969806e8baff99114596d37a56506d9322d3872b84
epilogue_lane.sv                c633576dd01da04ec2686096f9e90acdfc7ca4987925c8bb7d053df204cf3885
epilogue_i48_to_f32.sv          4c862453f53b26e18b832c5fd919da7f8f444b70f9a4affb060deb91a37f5a13
epilogue_fma_stage.sv           34b55dc340b33ee570c540453662404579a77b2f8e2b166dbb2563ab3740c00b
epilogue_relu.sv                0e008b394489fcdd2f453aeebee5288f1b812d715c5e8840d47f19bcb3142c4d
epilogue_f32_to_i16.sv          c51d3327a7fcfbe7e584f1efa275413644147669c9d216ea7f5fbf31b864af6b
fp32_fma_pipe.sv                1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12
```

Old candidate engine: `4fff5c3f21b3924c421e4a91a82db40550b1d782b18348cad6bff125c9fcb305`.
Full per-file old/new hashes and every gold/TB/vector/script hash are in
`result.json` and `SHA256SUMS.txt`.

---

## 10. Tested / not tested

**Tested (module level):** per-column scale/bias alignment; 2 banks x 32
columns with bc sideband; inactive-bank preload; active-bank write rejection;
config held while beats drain; config asserted over a pending input beat;
abort/recover and table clear; A16/packed/FP32/spill independent random,
long-window and bounded full-stall backpressure; valid/payload stability;
exact beat counts and tag completeness; odd/even boundaries 1..512; 1088-beat
multi-phase drain; negative control.

**Not tested / not claimed:**

* No synthesis, Vivado/STA, timing, CDC, board, VNC or push.
* No frequency, whole-model seconds, WER/CER or DRAM bandwidth.
* No AXI/BFM/B-response inside this module; the last output handshake is the
  completion boundary.
* No residual add, LayerNorm or reassociation.
* No unified-graph integration; `ds_fusion_buffers` is not edited. The
  `pch_*` optional spelling still needs the documented adapter.
* The frozen-ready form of AR-006/AR-007 is not a valid acceptance test; it is
  retained only to document the root cause.

---

## 11. Caveats

1. The old SHA did **not** show a functional deadlock under any correct
   stimulus found here (160 randomized fuzz runs plus the full strict gate and
   the worker's 10 cases). We therefore do not rewrite history: AR-006/007 were
   harness artefacts. The new fork is a structural hardening (per-consumer
   pending/ack, stable valid) plus a real config/valid-stability fix.
2. The new fork adds one register stage to the A16 path and makes `cfg_ready`
   wait for a pending input beat. No timing/frequency claim is made.
3. The strict gate is intentionally monotonic: it never forces a channel ready
   at the end to “help” a run; only the bounded 64-cycle full-stall test has an
   expiry, and the driver resumes afterwards. Every reported beat left through
   a real `valid && ready` handshake.
