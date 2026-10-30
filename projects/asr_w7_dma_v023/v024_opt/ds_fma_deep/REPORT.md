# REPORT — ds_fma_deep (V0.24): 7-stage 129-bit-accumulator FP32 FMA

**Date:** 2026-10-30
**Working directory:** `/home/yang/Desktop/项目/v024_opt/ds_fma_deep`
**Execution model:** `opencode-go/deepseek-v4.1-flash` (only model used)
**Scope:** local RTL logic simulation only. No synthesis, Vivado/STA, board,
VNC or push. No ns / Fmax / whole-model-seconds claim.

**Overall result:** `overall_pass = true` (see `result.json`,
`process_exit_rc = 0`). All numeric suites are **0 mismatches** against the
independent Fraction-based reference; the candidate is also bit-identical to
the trusted 4-stage RTL on the same vectors.

---

## 1. Provenance and what was not changed

Base = the trusted **`v023_repair/gemini_fma_round2/candidate/fp32_fma_pipe.sv`**
(4 register stages, 129-bit accumulator), SHA-256
`1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12`,
frozen read-only as `reference/baseline_4stage_fp32_fma_pipe.sv`.

The old 3-stage / 76-bit file was **not** used (per `REVIEW_DECISIONS.md` item 4).

Arithmetic semantics are preserved exactly:

- true single-rounding IEEE-754 binary32 FMA `RNE(a*b + c)`;
- FTZ for subnormal inputs and outputs;
- canonical qNaN `0x7fc00000`;
- `inf*0 -> NaN`, `inf + (-inf) -> NaN`;
- exact non-zero cancellation -> `+0`;
- `a*b` FTZ-zero with finite non-zero `c` -> bit-exact `c` bypass;
- overflow -> Inf, underflow -> signed zero;
- tag / last / flush / valid-ready backpressure unchanged.

The only behavioural change is **pipeline latency: 4 -> 7 cycles**, with
throughput still **II = 1**.

---

## 2. Retiming: register-boundary operations (7 stages)

| Stage | Combinational work before the register | Registered payload (main) |
|---|---|---|
| **S1** | unpack, FTZ, NaN/Inf/zero classification, `inf*0` / `inf-inf` detect, **24x24 mantissa multiply**, exponent add | flags, `prod[47:0]`, `exp_p/exp_c`, `c_norm`, tag/last |
| **S2** | 1-bit product normalize, **dominant-operand select** (48-bit compare + 10-bit exponent compare), shift amount clamp, effective sign/sub | `d_val`, `s_val`, `shift`, `exp_base`, `d_sign`, `eff_sub` |
| **S3** | **128-bit right alignment shifter** + shifted-out sticky OR tree | `s_acc[127:0]`, `sticky`, `d_val`, `exp_base`, flags |
| **S4** | **129-bit add/sub** with sticky-borrow injection | `sum_acc[128:0]`, `sticky`, `exp_base`, `d_sign`, flags |
| **S5** | **grouped/tree LZC** of `sum_acc` -> `msb[7:0]`; zero/cancellation decision | `sum_acc`, `msb`, `sticky`, zero flag/sign, flags |
| **S6** | **normalization shift**, 24-bit mantissa, round-bit select, sticky-mask OR, result exponent | `mant24`, `round_bit`, `sticky`, `exp_res`, `d_sign`, flags |
| **S7** | **RNE round-up**, overflow/underflow FTZ, special/zero/bypass mux | final result, tag, last |

Key structural points:

1. **No stage contains multiply + align + 129-bit add.** They are S1, S3, S4.
2. **The 129-bit LZC is grouped/tree, not a 129-deep priority chain.**
   `sum_acc` is split into 9 x 16-bit groups (group 8 = bit 128 only):
   - per-group non-zero: 16-bit OR trees;
   - group select: 9-entry priority (small);
   - within-group: `lzc16` = high-byte/low-byte split + 3-level `lzc8` tree;
   - `msb = gsel*16 + (15 - lzc16)`.
   This is verified exhaustively in `tests/tb_lzc_tree.sv` (8 x 65,535 group
   words + 20,000 random 129-bit patterns + dense patterns -> 0 errors).
3. **Sticky is collected where it belongs:** alignment sticky in S3, rounding
   sticky mask in S6, both OR-reduced (balanced trees in synthesis).
4. **RNE and packing are alone in S7**, so the round/overflow mux does not
   share a stage with the normalization shifter.

### Longest structural risks (no timing numbers claimed)

- **S6** is the widest single stage in this split: one 129-bit normalization
  shifter, a one-hot mask decoder + 129-bit AND + OR reduction for rounding
  sticky, and the 10-bit result-exponent add. The mantissa shift and the
  sticky path are parallel, but this is the stage most likely to need further
  coarse/fine shift splitting if a future STA run demands it.
- **S3** is next: 128-bit alignment shifter in parallel with the shifted-out
  sticky mask/OR tree, then the 129-bit operand is registered.
- **S4** is a 129-bit add/sub with carry; **S1** is the 24x24 multiply
  (DSP-friendly).

This report deliberately does **not** convert these structural depths into ns,
MHz or a 300 MHz claim. Only local logic simulation was run.

---

## 3. Verification methodology (independent gold, frozen metadata)

- **Golden:** `v023_repair/ds_numeric_adversarial/ref/refmodel.py`, SHA-256
  `38eb7ed944f05d6ac45ff68b69fbaa4b0b5b895f0eef46fa33e138395ceb64e2`.
  It is a Fraction/integer implementation, independent of the DUT and of
  gemini's own `reference/fma_reference.py`; the latter was **not** used.
  `scripts/run_regression.py` aborts if this SHA, or a frozen vector SHA,
  changes.
- **Vectors (frozen):**
  - `fma_adversarial_8734.vec` = the independent
    `ds_numeric_adversarial/vectors/fma.vec`, SHA
    `5a995d68158bf82714fc79110156d3b6af21c3fb09b2d3f67f51c5ef4961cdd7`;
  - `fma_random_gemini_20000.vec`, SHA
    `bc6ff4e57d0d1601aef34dfe46b4c1bacb673de82fb9aa6382be7dcd351485f5`;
  - `fma_random_local_20000.vec`, regenerated deterministically (seed
    `0x5EED2026`) by `scripts/gen_random_vectors.py`.
- **Same BFM:** `tests/tb_fma.sv` and `tests/tb_asr_fma_ip.sv` are byte copies
  of the v023 independent testbenches (same input file format, same handshake,
  same drain rule). The flush test is copied and only its fixed wait counts are
  adapted to the new latency; the protocol/checks are unchanged.
- **Drain boundary:** each vector suite runs to `out_count == in_count` (the
  last beat is accepted and drained) before the TB exits; the runner also
  requires equal counts and 0 tag/last/stability errors.
- **Backpressure:** BP=0 (always ready) and BP=1 (LFSR 50% random ready). Under
  BP=1 the elastic pipeline drains every beat and never reports a result
  earlier than 7 cycles.
- **Watchdogs:** every simulation has a SystemVerilog cycle watchdog
  (`+MAX_CYCLES`, `$finish(2)`) and a Python wall-clock watchdog (600 s). The
  runner treats a printed `WATCHDOG` or a count mismatch as failure and exits
  non-zero. (Icarus `vvp` returns 0 even for `$finish(2)`, so the runner does
  not rely on the process code alone.)
- **Cross-check, not golden:** the candidate is additionally compared bit for
  bit with the trusted 4-stage RTL on 8,734 + 20,000 vectors; this is an
  equivalence check, not the acceptance reference.

---

## 4. Results (all re-simulated in this run)

| Suite | Object | Vectors | BP | Mismatches | Latency / notes | Pass |
|---|---|---:|---:|---:|---|:---:|
| `fma_adv_8734_bp0` | `epilogue_fma_stage` | 8,734 | 0 | 0 | 7 cycles, span 8,734 (II=1) | yes |
| `fma_adv_8734_bp1` | `epilogue_fma_stage` | 8,734 | 1 | 0 | elastic, all drained | yes |
| `fma_random_local_20000_bp0` | `epilogue_fma_stage` | 20,000 | 0 | 0 | 7 cycles, span 20,000 (II=1) | yes |
| `fma_random_local_20000_bp1` | `epilogue_fma_stage` | 20,000 | 1 | 0 | elastic, all drained | yes |
| `fma_random_gemini_20000_bp0` | `epilogue_fma_stage` | 20,000 | 0 | 0 | frozen external vector cross-check | yes |
| `asr_ip_adv_8734` | `asr_fma_ip` AXIS | 8,734 | n/a | 0 | wrapper latency adapts to 7 | yes |
| `asr_ip_random_20000` | `asr_fma_ip` AXIS | 20,000 | n/a | 0 | wrapper latency adapts to 7 | yes |
| `equiv_adv_8734` | vs trusted 4-stage RTL | 8,734 | 0 | 0 | bit-identical data | yes |
| `equiv_random_local_20000` | vs trusted 4-stage RTL | 20,000 | 0 | 0 | bit-identical data | yes |
| `flush_latency_adapted` | lane / i48 / fma / i16 | directed | n/a | 0 flush errors | lane latency now 12 | yes |
| `latency_ii_bypass` | `epilogue_fma_stage` | 40 interleaved + flush/stall | 0 | 0 errors | mode0 bypass latency 7, II=1 | yes |
| `unit_directed` | `fp32_fma_pipe` | 13 directed | n/a | 0 fails | probe/cancel/tie/zero/inf/flush/BP | yes |
| `lzc_tree_exhaustive` | grouped/tree LZC | 574k patterns | n/a | 0 errors | exhaustive + random 129-bit | yes |

Mode-0 bypass is exercised inside the 8,734 adversarial set (1,000 mode-0
vectors) and in the explicit interleaved latency test; the bypass payload is
delayed by exactly the same 7 cycles as the FMA result and keeps tag/last.

### Latency adaptation delivered to consumers

- `fp32_fma_pipe`: **7 cycles, II=1**.
- `epilogue_fma_stage` / `asr_fma_ip`: 7 cycles (same ports).
- `epilogue_lane`: 2 + 7 + 1 + 2 = **12 cycles**.
- `epilogue_stream_engine_v023` elaborates unchanged; it has no fixed-latency
  assumption. Consumers must use valid/ready and must not count 4 cycles.

---

## 5. Deliverables and reproducibility

- Unique file list: **`FILELIST.txt`** (also embedded in `result.json`).
- Integration payload: `candidate/*.sv` only. `tests/`, `scripts/`, `logs/`,
  `sim/`, `vectors/`, `reference/` are verification artefacts.
- Candidate source SHA-256 is recorded in `result.json` under
  `candidate_source_sha256`; the candidate `fp32_fma_pipe.sv` in this run is
  `b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82`.
- Re-run (sequential, `-j1` compiles, per-sim watchdogs):

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_fma_deep
./run_all_tests.sh
```

Exit code is 0 only when every suite passes; `result.json` carries
`process_exit_rc`, per-suite `rc`, SHAs, what was tested and what was not.

---

## 6. Not tested / limitations

- No synthesis, STA, Vivado, board run, VNC or push; **no frequency or ns
  claim**, and no 300 MHz claim.
- No whole-model ASR inference, WER/CER, or full graph integration.
- Vector `op17` II=1 integration and per-channel/epilogue parameter tables are
  owned by `ds_vector_fma` / `ds_epilogue_channels` / `ds_fusion_buffers`;
  this task only publishes the latency-variable contract in `INTERFACE.md`.
- The 4-lane FMA area cost (four 129-bit accumulators) is not paid or claimed
  here; this task delivers one deep single-lane pipe.
- Icarus `$finish(n)` does not propagate a non-zero process code, so all
  failure detection is based on parsed counters plus the Python watchdog; the
  runner still exits non-zero on any failure.
