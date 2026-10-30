# REPORT — ds_vector: vector throughput / hierarchy / approx integration (v023)

**Task directory:** `/home/yang/Desktop/项目/v023_repair/ds_vector`
**Baseline:** frozen `work/rtl/ddr_vector_engine.sv`, `work/rtl/asr_fp32_alu.sv`
**Scope:** logic simulation only. No synthesis, Vivado, STA, board, VNC or push.
The frozen ZIP/work tree and all other workers' directories were read-only; all new
RTL, TB, fixtures, scripts, logs and reports are under this task directory.

## 0. Response to primary acceptance (2026-10-29)

`../primary_acceptance/REPORT.md` correctly refused early PASS. This task re-ran the
affected vector cases after that report:

1. **Tail packets (fixed).** The four reported failures
   (`add_tail5`, `add_tail7`, `a48_tail3`, `f32_to_i16_tail7`) were reproduced. Root
   cause was the four-lane operand/valid alignment on the final partial beat of very
   short banks in the Icarus simulation. Those banks (<= 8 elements) now use the exact
   sequential core; the four cases and all 67 exact fixtures pass byte-for-byte against
   the frozen baseline. This is a functional fix, not a redefinition of pass.
2. **FMA counterexample (not ours to wave through).** The primary probe
   `0x3f800001 * 0x3fc00000 = 3fc00001` instead of `3fc00002` is a real single-rounding
   failure in the epilogue path. `ds_vector` does **not** implement or substitute FMA:
   op 17 only reaches the vendor `asr_fma_ip` port, and the test build aborts with
   "FMA not covered" (`logs/fma_not_covered.log`). The epilogue blocker remains open
   and must not be accepted from a vector PASS.
3. **Approx tier mismatch (claim withdrawn).** The delivered `approx_div_sqrt` is one
   fixed 4-stage structure; `TIER/LATENCY/II` are not structural. This report claims
   only the measured configuration and error/throughput, not 2/4/7-cycle tiers, not
   300/600 MHz. The primary's 0.1080% DIV / 0.0006% SQRT measurements agree with our
   1.10e-3 / 5.24e-6 vector-level results.
4. **Early PASS not reused.** Every number in this report comes from the post-fix
   reruns in `logs/regression_run.log`, `logs/axi_run.log`, `logs/approx_run.log`
   (`rc=0`), with source SHA in `result.json`. `ds_layout`, `ds_matrix`, `ds_graph`
   and `ds_integration` are not claimed complete; whole-model/CASE0000 acceptance is
   explicitly out of scope for this vector task.

## 1. Deliverables

| File | Purpose |
|---|---|
| `candidate/rtl/ddr_vector_engine_pipe.sv` | Pipelined candidate engine, same top-level port list |
| `candidate/rtl/asr_fp32_lane_fixed.sv` | 3-cycle fixed-latency FP32 lane, II=1 |
| `candidate/rtl/vector_desc_check_pipe.sv` | V1/V2/V3 descriptor validator |
| `candidate/rtl/ddr_vector_axi_pipe.sv` | Candidate wrapper for the two frozen `axi_dma_v019` cores |
| `candidate/rtl/ddr_vector_engine_approx.sv` | Wrapper enabling the gemini_approx core |
| `candidate/rtl/gemini_approx/*` | Single delivered 4-stage `approx_div_sqrt` + reciprocal/rsqrt LUTs (copied from gemini_approx, SHA preserved) |
| `baseline/` | Frozen baseline copies used as same-load reference |
| `tb/tb_vector_generic.sv` | Baseline/candidate same-load TB, normal/tail/error/backpressure/snapshot/busy-start |
| `tb/tb_vector_axi_generic.sv` | Same TB through the two real AXI DMA wrappers |
| `scripts/gen_fixtures.py` | Deterministic independent fixtures |
| `scripts/run_regression.py` | Exact baseline-vs-candidate regression |
| `scripts/run_axi.py` | AXI same-load regression |
| `scripts/run_approx.py` | Integrated approximate DIV/SQRT error/throughput test |
| `result.json` | Merged exact/approx/AXI/FMA result + SHA manifest |
| `INTERFACE.md` | Integration contract (engine + `approx_div_sqrt`) |
| `FINDINGS.md` | Measured findings and honest limitations |
| `progress.json` | Stage status |
| `logs/` | Per-test logs, rc and compile logs |
| `SHA256SUMS.txt` | Source SHA of all RTL/TB/scripts |

## 2. Architecture and numerical order

### 2.1 Fixed-latency path

Baseline: one element through `CREAD -> CSEND -> CWAIT`, with `asr_fp32_alu` spending
four real cycles in `alu_phase` 0..3. The candidate preserves the exact arithmetic
functions (`fp_add_prepare/fp_add_finish/fp_mul/int48_float/float_int32/pack_rne`,
FTZ/RNE) but splits them into a lane pipeline:

```
S0 latch -> S1 prepare / partial product / quick conversion -> S2 finish -> output
```

- lane latency **3 cycles**, lane **II=1**;
- four lanes in parallel, one 128-bit beat/cycle when not stalled;
- measured `add_1001`: **251 issue beats / 271 compute cycles = 1.08 cycles/beat**
  (~4 elements/beat); total 1309 cycles including DMA/load/store;
- A48 uses 2 C48/beat: 501 beats / 521 cycles;
- output pack writes 4 FP32 or 8 I16 per 128-bit beat.

A16 input is stored as 8 packed 16-bit values per word and sign-extended on read; C48
input is stored as 2×48-bit per word. A16/C48/QDQ positions and the F32_I16 clip are
unchanged. Scalar/tiled/repeating-B addressing is preserved.

### 2.2 Iterative ops are not called II=1

`DIV/SQRT/EXP/LOG` stay on the unchanged exact `asr_fp32_alu` by default. Measured
exact costs are ~31.2-31.4 cycles/element for DIV/SQRT, ~82 for EXP and ~116 for LOG.
They are reported separately and are never included in the II=1 claim.

### 2.3 Descriptor validation

The baseline single-cycle predicate (multiple 64-bit multiplies, `overlap()`,
`readable()`) is split into:

- **V1** magic/reserved/count/op/flag/period checks;
- **V2** size products + destination alignment/window/A-window;
- **V3** source B/C windows and final verdict.

No read/write request is emitted before V3. Invalid descriptors cost 4 extra cycles
(1 -> 5 in the error cases) and emit zero DMA requests, matching the baseline ACL
behavior. Valid descriptor latency shifts by 4 cycles; this is documented in
`INTERFACE.md`.

### 2.4 Approximate DIV/SQRT

`gemini_approx` delivered `approx_div_sqrt` (one fixed 4-stage structure: 128-entry LUT
+ one Newton step). Its `TIER/LATENCY/II` parameters are metadata only; the primary
acceptance rerun confirmed they do not build 2/4/7-cycle tiers, so this report makes
no three-tier claim. It is instantiated only when
`USE_APPROX_DIV_SQRT=1`; the default remains exact. The engine keeps up to four
requests outstanding, checks `tag_out` in order, and sets `flags[4]` on approximate
results. `flags[0..2]` use the same abort policy as the exact ALU (`error_code=04`).

## 3. Verification (actual RTL, same load)

### 3.1 Exact baseline vs candidate

`result.json` / `logs/regression_run.log` (`rc=0`): **67 exact fixtures + 7 stress
modes, all PASS**. Cases include:

- ADD/SUB/MUL, A16 input, C48 input, I16 output, scalar A/B, B period 1..256,
  btiled 1024/2048;
- tails 1,2,3,5,7,9,127,255,257,1001;
- 20 invalid descriptors (magic/reserved/count/op/window/alignment/overlap/A16+A48/
  A48+ascalar/out16 op/period/btiled);
- read error, write error, busy start, descriptor snapshot, four backpressure modes;
- frozen `work` gold: add_scalar, mul_vector, i16_to_float, round_i16, i48_to_float
  are byte-exact.

Selected measured cycles:

| fixture | baseline | candidate | speedup | candidate cyc/elem |
|---|---:|---:|---:|---:|
| add/sub/mul 1001 | 8414 | 1309 | 6.43x | 1.31 |
| A16→F32 1001 | 4778 | 533 | 8.96x | 0.53 |
| C48→F32 1001 | 4858 | 1194 | 4.07x | 1.19 |
| F32→I16 1001 | 4769 | 695 | 6.86x | 0.69 |
| B period 32 | 7896 | 816 | 9.68x | 0.82 |
| btiled 2048 | 15246 | 1518 | 10.04x | 0.74 |
| DIV exact | 32438 | 31411 | 1.03x | 31.38 |
| SQRT exact | 31843 | 31263 | 1.02x | 31.23 |

The only independent-gold mismatches are `exp_1001`/`log_1001`, where the frozen
baseline itself is a polynomial approximation (not a candidate regression). All
baseline-vs-candidate comparisons match.

### 3.2 AXI wrapper

`axi_result.json` / `logs/axi_run.log` (`rc=0`): 14/14 cases pass (10 modes + 4
additional frozen work fixtures) with the two frozen `axi_dma_v019` cores and the
shared-memory AXI BFM. add_scalar 7882 -> 995 cycles (7.92x), byte-identical output;
mul_vector 8528 -> 1763, i16_to_float 4805 -> 658, round_i16 4820 -> 923,
i48_to_float 4942 -> 1543. Modes 1..6 fault with zero requests; modes 7/8 fault
after drain; mode 9 rejects the busy start. Candidate read/compute overlap = 204;
**write/compute overlap = 0** on this fixture (compute drains faster than the write
side) — reported as measured, not hidden.

### 3.3 Approximate integration

`approx_result.json` / `logs/approx_run.log` (`rc=0`): 4 normal cases + 4 special cases
+ 8 backpressure cases PASS.

| op (1001) | max rel. err | mean rel. err | median ULP | speedup | cyc/elem |
|---|---:|---:|---:|---:|---:|
| DIV | 1.10e-3 | 2.69e-4 | 1456 | 12.30x | 2.63 |
| SQRT | 5.24e-6 | 1.10e-6 | 10 | 12.79x | 2.49 |

DIV/0, 0/0, sqrt(negative), inf/inf all fault (`error_code=04`) with flags
0x02/0x01; no silent zero. Eight backpressure runs produce identical bytes. This is a
vector-level error measurement, **not** a whole-model accuracy gate; gemini's own
LayerNorm/Softmax quantization study is separate and not re-claimed here.

### 3.4 FMA not covered

`logs/fma_not_covered.log`: op 17 aborts at
`FMA not covered by forbidden-stub tests` (`rc=1`, expected). The vendor
`asr_fma_ip` ports/order are untouched; no add/mul substitute is used.

## 4. Reproduction

```
cd /home/yang/Desktop/项目/v023_repair/ds_vector
python3 scripts/gen_fixtures.py          # deterministic fixtures
python3 scripts/run_regression.py       # exact baseline vs candidate + work gold
python3 scripts/run_axi.py              # two real axi_dma_v019 wrappers
python3 scripts/run_approx.py           # gemini_approx single 4-stage integration
```

Compilation is serial (one `iverilog` process at a time; Icarus has no `-j`). Logs with
command line, rc, stdout/stderr are in `logs/`. `result.json` merges the exact/approx/
AXI/FMA evidence and the SHA manifest.

## 5. Honest limitations

- No FMA numeric evidence (vendor sim model absent).
- No whole-model/whole-plan latency or accuracy claim; the 153.8s → 12.5s → 0.15s
  attachment predictions are not acceptance criteria.
- No synthesis/STA/600 MHz/CDC/Vivado/board claim. The descriptor split and lane
  pipeline are logic-only; no timing report was produced.
- Wide-lane tag tokens are carried/echoed but not used as an ordering gate; only the
  approximate tag is checked.
- Write/compute overlap is zero on the fast candidate add_scalar run; read/compute
  overlap is nonzero.
- Independent exp/log gold differs from the RTL baseline because the baseline is
  approximate; this is not claimed as a candidate bug.
- W7 matrix arithmetic, A16/C48 positions and QDQ boundaries were not changed by this
  task; only the vector engine was modified.
