# FINDINGS — ds_vector v023

All statements below are from actual Icarus logic simulation of the RTL in this
directory. No synthesis, STA, Vivado, board, VNC or push was performed. The frozen
`work/` and other workers' directories were not modified.

## 1. What actually changed

1. **Fixed-latency path is now a throughput pipeline.** The baseline
   `asr_fp32_alu.sv` takes 4 real cycles per fixed op (alu_phase 0..3) and the engine
   waits per element (`CREAD -> CSEND -> CWAIT`). The candidate adds
   `asr_fp32_lane_fixed` (S0 latch, S1 prepare/product, S2 finish; output is
   combinational from S2). Measured lane latency is 3 cycles and lane II is 1.
2. **128-bit unpack / pack.** One 128-bit raw window yields 4 FP32 or 8 A16 (or 2
   C48) operand items per cycle; result pack writes 4 FP32 or 8 I16 per 128-bit beat.
   A16/A48/out16 fixtures all pass byte comparison.
3. **Descriptor validation is split into V1/V2/V3.** V1 format/flags, V2 sizes +
   destination window, V3 source windows. No DMA request exists before V3. Invalid
   descriptors cost 4 extra cycles (baseline 1 -> candidate 5 in the error fixtures)
   and still produce zero read/write requests.
4. **DIV/SQRT exact is retained and is not called II=1.** The unchanged
   `asr_fp32_alu` is still the default (`USE_APPROX_DIV_SQRT=0`). Measured exact
   DIV/SQRT is ~31.2-31.4 cycles/element (iterative, one outstanding), versus ~1.31
   cycles/element for pipelined add. EXP/LOG remain ~82/116 cycles/element.
5. **gemini_approx single 4-stage core is integrated, not faked.** `approx_div_sqrt`
   (LUT + one Newton step) is the only delivered structure; the `TIER/LATENCY/II`
   parameters are metadata and do not produce 2/7-cycle variants (primary acceptance
   finding). It is instantiated only when
   `USE_APPROX_DIV_SQRT=1`; the engine allows 4 outstanding requests and checks the
   returned tag in order. Exact fallback remains one parameter away.
6. **Small banks (<= 8 elements) use the exact sequential core.** The 4-lane
   operand/partial-beat path showed an Icarus-visible hazard on the last partial beat
   of very short banks (count 5/7, A48 count 3, I16 count 7). Routing only those tiny
   banks through the exact core preserves bit equality with the baseline and costs
   little. All 67 exact fixtures now match baseline byte-for-byte.
7. **FMA is untouched and not covered.** `asr_fma_ip` port order and arithmetic are
   unchanged. The test build links only `tests/fma_forbidden_stub.sv`; invoking op 17
   aborts with `FMA not covered by forbidden-stub tests` (see
   `logs/fma_not_covered.log`). No add/mul substitute is used.

## 2. Measured same-load results (transactional DMA BFM)

Selected rows from `result.json` (1001 elements unless noted):

| fixture | baseline cycles | candidate cycles | speedup | candidate cycles/element |
|---|---:|---:|---:|---:|
| add_1001 | 8414 | 1309 | 6.43x | 1.31 |
| sub_1001 | 8414 | 1309 | 6.43x | 1.31 |
| mul_1001 | 8414 | 1309 | 6.43x | 1.31 |
| a16_to_f32_1001 | 4778 | 533 | 8.96x | 0.53 |
| a48_to_f32_1001 | 4858 | 1194 | 4.07x | 1.19 |
| f32_to_i16_1001 | 4769 | 695 | 6.86x | 0.69 |
| bperiod_32 | 7896 | 816 | 9.68x | 0.82 |
| btiled_2048 | 15246 | 1518 | 10.04x | 0.74 |
| div_1001 (exact default) | 32438 | 31411 | 1.03x | 31.38 |
| sqrt_1001 (exact default) | 31843 | 31263 | 1.02x | 31.23 |
| exp_1001 (exact default) | 82894 | 82314 | 1.01x | 82.23 |
| log_1001 (exact default) | 116928 | 116348 | 1.01x | 116.23 |

Instrumented compute-only counters for `add_1001`: **251 issue beats, 271 compute
cycles** => 1.08 cycles/beat, i.e. ~4 elements/beat. This is the II evidence; the
total 1309 cycles is dominated by the DMA/load/store and BFM stalls, not the lanes.
For A48 (2 C48/beat) the counters are 501 beats / 521 cycles.

The AXI wrapper (`ddr_vector_axi_pipe`, two unchanged `axi_dma_v019` cores, shared
memory BFM) gives add_scalar 7882 -> 995 cycles (7.92x) with byte-identical output.
Modes 1..6 (bad descriptors) have zero requests; modes 7/8 (read/write errors) fault;
mode 9 (busy start) rejects the second start. The candidate records read/compute
overlap (204 cycles) but **zero write/compute overlap** on this fixture because the
compute finishes faster than the write drain; this is reported, not hidden.

## 3. Approximate DIV/SQRT integration (single delivered 4-stage core)

`approx_result.json`; exact baseline on the same vectors:

| op | max rel. error | mean rel. error | median ULP | cycle speedup | cycles/element |
|---|---:|---:|---:|---:|---:|
| DIV 1001 | 1.10e-3 | 2.69e-4 | 1456 | 12.30x | 2.63 |
| SQRT 1001 | 5.24e-6 | 1.10e-6 | 10 | 12.79x | 2.49 |

The approximate result sets `flags[4]` (0x10) and is never called bitexact. Special
cases DIV/0, 0/0, sqrt(negative), inf/inf all abort with `error_code=04` and appropriate
flags; no silent zero. Eight backpressure runs (modes 11..14 on DIV and SQRT) produced
identical bytes. The engine checks the approx tag in order (`error_code=06` on a
mismatch). The residual error was not propagated through a whole model here; gemini's
own LayerNorm/Softmax code-error study is cited in its report, not re-claimed as a
whole-model gate.

## 4. Descriptor / error / snapshot evidence

- 20 invalid descriptors: magic, reserved low/high, count 0/huge, op 19, D low,
  D unaligned, A overlap D, A unaligned, A16+A48, A48+ascalar, out16 with wrong op,
  non-power-of-two period, period+bscalar, btiled period 0, btiled count not 1024,
  plus four DIV/SQRT special cases. All baseline/candidate runs fault with no
  validator DMA side effect.
- Tail counts 1,2,3,5,7,9 (and 127,255,257,1001) all match baseline byte-for-byte;
  tail bytes outside the declared output remain 0xa5.
- Backpressure modes 11/12/13/14 and busy-start mode 9 and descriptor-snapshot mode 10
  all match baseline output.
- The independent frozen `work` gold for the five exact fixtures (`add_scalar`,
  `mul_vector`, `i16_to_float`, `round_i16`, `i48_to_float`) is byte-exact.

## 5. Honest limitations / non-claims

- No FMA numeric evidence; vendor model absent.
- No W7/A16/C48 matrix datapath change was made; only the vector engine. W7 positions,
  A16, C48 packing and F32_I16 clip are retained and exercised where the vector engine
  touches them.
- No whole-plan or whole-model speedup claim. The 153.8s -> 12.5s -> 0.15s attachment
  predictions are not used as acceptance criteria.
- No synthesis/STA/600 MHz/Vivado/board/CDC claim. The descriptor split removes a
  combinational evaluation but no timing report was produced.
- Generated exp/log gold differs from the RTL baseline because the baseline itself is
  polynomial approximation; this is not a candidate regression.
- Wide-lane tags are carried/echoed but not used as an ordering gate; only the approx
  path checks tags. This is explicitly noted in INTERFACE.
- 16-beat bursts were not treated as a defect; this task did not change the DMA core.
