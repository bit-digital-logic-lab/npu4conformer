# REPORT — gemini_approx_round2: Approximate Arithmetic Boundary & Protocol Rectification

**Task**: `gemini_approx_round2`  
**Date**: 2026-10-29  
**Execution Constraints**: Logic simulation only (Icarus Verilog 14), read-only external worker repositories, no synthesis, no Vivado STA, no board testing, no VNC, no git push. Watchdog enforced on every simulation, compile `-j1`, no overall timeout.  
**Deliverables**: `REPORT.md`, `INTERFACE.md`, `result.json`, `progress.json`, `run_all.sh`, and candidate RTL in `candidate/rtl/` and `rtl/`.

---

## 1. Executive Summary & Response to ds_numeric_adversarial Audit

The independent numeric adversarial acceptance audit (`v023_repair/ds_numeric_adversarial/REPORT.md`, `FINDINGS.md`) reported that while the structural refactoring of `gemini_approx_repair` was successful (fake tiers pruned, single Tier 1 with Latency=5 and II=1 enforced, composite multiplier cone pipelined), three numerical boundary defects and one integration contract ambiguity remained:

1. **APPROX-1 (F7 in FINDINGS.md)**: DIV factor-2 boundary error on $1.0 / 0x41fffad2$ ($1.0 / 31.9998$), resulting in 99.88% relative error ($0.062468$ instead of $0.031252$).
2. **APPROX-2 (F8 in FINDINGS.md)**: RSQRT factor-2 boundary error on $RSQRT(0x7f7fffff)$ (max finite float), resulting in 99.99985% relative error ($1.0842e-19$ instead of $5.4210e-20$).
3. **APPROX-3 (F9 in FINDINGS.md)**: $RSQRT(-0)$ and negative subnormals returned $+inf$ (`0x7f800000`) instead of IEEE-754 $-inf$ (`0xff800000`).
4. **FLUSH Integration Ambiguity**: The `flush` port in `gemini_approx_repair/candidate/rtl/approx_div_sqrt.sv` was declared as `input wire flush,` without a default value, posing integration compilation risks for callers omitting `.flush(...)` (e.g. `ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv:160`).

### Remediation Actions Taken in Round 2
- **Fixed APPROX-1**: Diagnosed that Newton-Raphson approximation for reciprocal is concave from below ($Y_1 \le 1/X_B$) and dips slightly below 0.5 ($0.49948$) when $X_A \approx 1.0$ and $X_B \approx 2.0$. In Q46 fixed point, both bits 46 and 45 become 0. Implemented dedicated Stage 4 normalization branch for $div\_num\_prod < 0.5$, taking mantissa from bits `[43:21]` and decrementing exponent by 2.
- **Fixed APPROX-2**: Diagnosed that for max finite float ($X_A \to 4.0$), $Y_1 \approx 0.5$ dips slightly below 0.5, causing $rsqrt\_y\_norm = Y_1 \ll 1$ to equal $0x7ffff4 < 1.0$ with bit 23 equal to 0. Implemented Stage 4 normalization branch when $rsqrt\_y\_norm[23] == 0$, shifting mantissa left by 1 and setting exponent to $125 - k$.
- **Fixed APPROX-3**: Updated Stage 0 special case logic to assign `special_val_s0 = a_sign ? FP32_NEG_INF : FP32_POS_INF` on zero operands, preserving exact IEEE-754 signed infinity for both $-0$ and negative subnormals.
- **Enforced Flush Integration Contract**: Declared `input flush = 1'b0,` in the module port list, ensuring seamless backward-compatibility with modules instantiating `approx_div_sqrt` without `.flush(...)` (such as `ds_vector`), while fully supporting 1-cycle pipeline flushing when connected.
- **Black-Box Retest against 15,168 Adversarial Vectors**: Fully re-evaluated the module using `ds_numeric_adversarial`'s 15,168 vectors under BP=0 and BP=1, achieving **100% PASS with 0 special mismatches, 0 worst cases >10%, 0 tag errors, and 0 stability errors**.

---

## 2. Model Context Clarification (512-dim Conformer/Transformer ASR)

As verified in `v023_repair/ds_numeric_adversarial/model_audit.json`:
- The target system is a **512-dimension Conformer/Transformer ASR encoder-decoder** (12 encoder layers, 6 decoder layers, 79 LayerNormalization instances with non-trivial scale and beta parameters), **not a KWT-1 keyword transformer**.
- Previous claims regarding 64 features, 99 keywords, or synthetic variance ranges $[10^{-6}, 100]$ are formally rejected as obsolete competition assumptions.
- This module serves as a generic, high-throughput IEEE-754 approximate DIV/SQRT/RSQRT unit applicable across any layer dimension without architectural assumptions about keyword counts or tensor geometries.

---

## 3. Pipeline Architecture & Register Allocation

The pipeline enforces a strict 5-cycle latency and II=1 throughput with balanced arithmetic distribution:

```
[Inputs: a, b, op, tag] 
       │
   [Stage 0] : Classification, FTZ, Signed Inf (APPROX-3), Seed LUTs
       │
    ═══════ REGISTER R0 (val, op, tag, spec, xa, xb, seed, sign, exp, k, b) ═══════
       │
   [Stage 1] : DIV: xb * seed (24x16 -> 40b) & d1=2.0-p1 (40b sub)
               RSQRT: seed * seed (16x16 -> 32b)
       │
    ═══════ REGISTER R1 (val, op, tag, spec, res_div, rsqrt_sq, xa, xb, seed...) ═══════
       │
   [Stage 2] : DIV: seed * d1 (16x25 -> 41b) refined reciprocal
               RSQRT First Multiplier: xa * sq (25x32 -> 57b) & d1=3.0-p1 (58b sub)
       │
    ═══════ REGISTER R2 (val, op, tag, spec, div_y1, rsqrt_d1, seed, xa_orig...) ═══════
       │
   [Stage 3] : DIV: Pass refined reciprocal
               RSQRT Second Multiplier: seed * d1 (16x58 -> 74b signed)
       │
    ═══════ REGISTER R3 (val, op, tag, spec, refined_y, xa_orig, sign, exp...) ═══════
       │
   [Stage 4] : Multi-Case Normalization (APPROX-1, APPROX-2)
               DIV/SQRT: Numerator multiply xa * refined_y (24x24 -> 48b)
               RSQRT: Normalization shift
               Exponent adjust, IEEE-754 pack, FTZ & overflow flags
       │
    ═══════ OUTPUT REGISTERS (out_valid, result, flags, tag_out) ═══════
```

### Multiplier Budget per Stage
- **Stage 0**: 0 multipliers.
- **Stage 1**: 1 multiplier ($24 \times 16$ for DIV or $16 \times 16$ for RSQRT).
- **Stage 2**: 1 multiplier ($16 \times 25$ for DIV or $25 \times 32$ for RSQRT).
- **Stage 3**: 1 multiplier (0 for DIV, $16 \times 58$ signed for RSQRT).
- **Stage 4**: 1 multiplier ($24 \times 24$ for DIV/SQRT, 0 for RSQRT).

---

## 4. Verification Evidence & Test Results

All verification steps were executed sequentially via `run_all.sh` using Icarus Verilog (`iverilog -g2012`), monitored by cycle and wall-clock watchdogs.

### 4.1 Phase 1: Parameter Assertion & Illegal Config Rejection
Executed `tests/test_parameter_assertions.py`:
- `TIER=1, LATENCY=5, II=1`: Compiled and elaborated with rc=0 (PASS).
- `TIER=0`: Elaborator emitted `illegal_tier_parameter_only_tier_1_supported` (rc=1, PASS).
- `TIER=2`: Elaborator emitted `illegal_tier_parameter_only_tier_1_supported` (rc=1, PASS).
- `TIER=3`: Elaborator emitted error (rc=1, PASS).
- `LATENCY=4, 7`: Elaborator emitted `illegal_latency_parameter_must_be_5` (rc=1, PASS).
- `II=2`: Elaborator emitted `illegal_ii_parameter_must_be_1` (rc=1, PASS).

### 4.2 Phase 2: Hardware Protocol, Latency, II, Backpressure & Flush
Executed `tests/tb_protocol_perf.sv`:
- **Measured Latency**:
  - `DIV (op=0)`: 5 clock cycles.
  - `SQRT (op=1)`: 5 clock cycles.
  - `RSQRT (op=2)`: 5 clock cycles.
- **Initiation Interval**: 32 back-to-back requests issued consecutively produced 32 consecutive responses (cycle gap = 1, II=1).
- **Random Backpressure**: 64 transactions completed in-order with 100% tag integrity and zero stalls.
- **Flush Functionality**: 3 in-flight requests cleanly flushed in 1 cycle with 0 phantom completions; subsequent request resumed with exact 5-cycle latency.

### 4.3 Phase 3: Comprehensive Testsuite (4,131 Vectors)
Executed `tests/test_approx_suite.py`:
- Total vectors: 4,131.
- Backpressure consistency (full speed vs 25% stall): 4,131 / 4,131 (100.0%).
- Tag integrity: 4,131 / 4,131 (100.0%).
- Special cases handled: 31 / 31 verified.
- Relative errors:
  - DIV: Max 0.1080%, Mean 0.02236%.
  - SQRT: Max 0.0006%, Mean 0.00012%.
  - RSQRT: Max 0.0006%, Mean 0.00012%.

### 4.4 Phase 4: Independent `ds_numeric_adversarial` 15,168-Vector Black-Box Verification
Executed `scripts/run_numeric_adversarial_15168.py` against the exact read-only adversarial test suite:
- **Total Vectors**: 15,168 (DIV 7,144, SQRT 4,012, RSQRT 4,012).
- **Special Mismatches**: **0** (was 3 in audit; RSQRT $-0$ and negative subnormal signed infinity fixed).
- **Factor-2 Boundary Worst Cases (>10%)**: **0** (was 2 in audit; DIV $1/31.9998$ and RSQRT max finite fixed).
- **Max Relative Errors**:
  - DIV: **0.11147%** (0.001115, within expected ~0.11% NR bound; down from 99.88%).
  - SQRT: **5.78e-6** (0.000578%).
  - RSQRT: **5.72e-6** (0.000572%; down from 99.99985%).
- **Mean Relative Errors**:
  - DIV: **0.02287%** (0.000229).
  - SQRT: **1.14e-6** (0.000114%).
  - RSQRT: **1.09e-6** (0.000109%).
- **Measured Latency**: Exactly 5 cycles across all 15,168 vectors (min=5, median=5, max=5).
- **Measured II**: Exactly 1 cycle across all 15,167 consecutive issues (min=1, max=1).
- **Stability Errors under BP=1 (50% stall)**: **0**.
- **Flush Test (`tb_approx_flush.sv`)**: **0 errors**.
- **Unconnected Flush Port (HAS_FLUSH=0)**: **PASS**, 0 errors across 15,168 vectors.
- **Overall Adversarial Verdict**: **ALL PASS (exit code 0)**.

### 4.5 Phase 5: Co-Simulation with `ds_vector` Candidate Engine
Compiled and executed `ddr_vector_engine_approx` with `tb_vector_generic.sv` on `ds_vector` fixtures:
- `div_1001`: Completed with `V023_VECTOR_PASS mode=0 cycles=2888 count=1001 fault=0 err=00 flags=10`.
- `sqrt_1001`: Completed with `V023_VECTOR_PASS mode=0 cycles=2739 count=1001 fault=0 err=00 flags=10`.
- Compatibility: Confirmed zero modifications to `ds_vector` files.

---

## 5. Deliverables & SHA-256 Checksums

| Path | SHA-256 Checksum | Description |
|---|---|---|
| `candidate/rtl/approx_div_sqrt.sv` | `444fa2a42f47a7cde2ad736ead3177225319c6af3bb1c2ab27309233bee7a864` | Repaired candidate core with 3-way DIV/RSQRT normalization & default flush |
| `candidate/rtl/approx_recip_lut.sv` | `b5d1ee5cbaca06a55ce6da67fc6c0fbbd88869c6e6aa5508f1c909c03bb4f41a` | 128-entry reciprocal seed ROM |
| `candidate/rtl/approx_rsqrt_lut.sv` | `cf0d0d03ec839b138acad933fe4561975e0690180ea1099721df3e33ec07e153` | 256-entry inverse square root seed ROM |
| `rtl/approx_div_sqrt.sv` | `444fa2a42f47a7cde2ad736ead3177225319c6af3bb1c2ab27309233bee7a864` | Mirrored top-level RTL core |
| `rtl/approx_recip_lut.sv` | `b5d1ee5cbaca06a55ce6da67fc6c0fbbd88869c6e6aa5508f1c909c03bb4f41a` | Mirrored reciprocal ROM |
| `rtl/approx_rsqrt_lut.sv` | `cf0d0d03ec839b138acad933fe4561975e0690180ea1099721df3e33ec07e153` | Mirrored inverse square root ROM |
| `scripts/run_numeric_adversarial_15168.py` | `d679431cc238ef5960735550d720277e33ad57cf0d164725a5fc8a5d4a16792a` | Standalone adversarial 15,168-vector runner |
| `run_all.sh` | `d7b5ef72beb3083aac0d221d95e238971d00d7065f4b129454cc93c83f7f6150` | One-click 5-phase verification script |
| `INTERFACE.md` | (present) | Binding interface and integration contract |
| `result.json` | (present) | Machine-readable verification summary |
| `progress.json` | (present) | Stage-by-stage execution log |

---

## 6. Known Limitations & Honest Boundaries

1. **Approximate Semantics**: The module implements approximate mathematics with single-iteration Newton-Raphson. Results are bounded within ~0.11% for DIV and ~5.78e-6 for SQRT/RSQRT. It is not bit-exact with IEEE-754 binary32 division.
2. **Subnormal FTZ**: All subnormal inputs and outputs are flushed to zero (FTZ) with `FLAG_UNDERFLOW` (`0x08`) asserted.
3. **External FMA Scope**: Fused Multiply-Add (FMA, op 17) remains an external vendor IP and is not handled by this approximate unit.
4. **Physical Implementation Scope**: Logic simulation only was performed (Icarus Verilog). No physical synthesis, Vivado STA, or board implementation was conducted in accordance with project constraints.
5. **ASR Model Verification Boundary**: Vector-level mathematical accuracy and quantization stability are verified; end-to-end speech recognition CER/WER must be evaluated during full-system graph execution.
