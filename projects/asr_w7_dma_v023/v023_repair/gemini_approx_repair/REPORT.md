# REPORT — gemini_approx_repair: Approximate Math Pipeline & Architectural Rectification

**Task**: `gemini_approx_repair`  
**Date**: 2026-10-29  
**Execution Constraints**: Logic simulation only (Icarus Verilog), read-only external repositories, zero-modification to `ds_vector` and other worker workspaces, independent exact mathematical baseline, no unconditional PASS, active watchdog on all simulations.  
**Deliverables**: `REPORT.md`, `INTERFACE.md`, `result.json`, `progress.json`, `run_all.sh`, and candidate RTL under `candidate/rtl/` and `rtl/`.

---

## 1. Executive Summary & Response to Primary Acceptance Audit

The primary acceptance report (`v023_repair/primary_acceptance/REPORT.md`) blocked the previous `gemini_approx` delivery with the following specific findings:
1. **Defective Parameterization & Fake Tiers**:
   - `LATENCY` and `II` parameters in `approx_div_sqrt.sv` were decorative and completely unreferenced in the hardware logic.
   - The reported 3 tiers (2, 4, and 7 cycles) were fictitious: `TIER=0` did not alter pipeline depth, and `TIER=2` contained zero second-iteration Newton-Raphson hardware, executing the exact same 4-cycle logic as `TIER=1`.
2. **Timing Bottleneck in RSQRT Composite Multiplier Cone**:
   - Stage 2 chained two full multiplications and a 58-bit subtraction in a single combinational path ($X_A \times Y_0^2 \to 3.0 - P \to \text{seed} \times D_1$), creating an unacceptable critical path.
3. **Unsubstantiated Frequency Claims**:
   - Fabricated claims of 300/600 MHz and `<2.4ns` operation were asserted without STA verification.
4. **Unconditional PASS in Test Harness**:
   - The previous test script printed `ALL VERIFICATION CHECKS PASSED` unconditionally without strict assertion gating or non-zero exit codes.

### Remediation Actions Executed
- **Pruned Fake Tiers**: Eliminated the superficial 3-tier façade. Retained a single, production-grade, high-throughput pipeline (Tier 1) with strictly verified **Latency = 5 cycles** and **Initiation Interval II = 1 cycle**.
- **Enforced Strict Parameter Assertion**: Added compile-time elaboration checks and simulation-time `$fatal` assertions. Any attempt to instantiate unsupported tiers (`TIER=0, 2`) or mismatching timing (`LATENCY!=5, II!=1`) fails deterministically.
- **Pipelined the Composite Multiplier Cone**: Split the RSQRT Newton-Raphson iteration across two distinct registered pipeline stages (Stage 2 and Stage 3). Every stage now contains at most one multiplier.
- **Added Pipeline Flush Control**: Implemented synchronous `flush` input with backward-compatible default value (`1'b0`).
- **Eliminated Unverified Frequency Promises**: Replaced speculative nanosecond timing with concrete, measurable register-boundary operation allocations.
- **Implemented Strict Test Gating**: Refactored `test_approx_suite.py` and testbenches to enforce non-zero exit codes (`sys.exit(1)`) on any discrepancy, tolerance failure, or simulation error.

---

## 2. Refactored Pipeline Architecture & Register Boundaries

Rather than guessing clock frequencies or path delays without STA, the architecture is explicitly defined by its **register boundaries** and **arithmetic operations per stage**:

```
[Inputs: a, b, op, tag] 
       │
   [Stage 0] : Classification, Subnormal FTZ, Seed LUT Lookups (128x16 ROMs)
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
   [Stage 4] : DIV/SQRT: Numerator multiply xa * refined_y (24x24 -> 48b)
               RSQRT: Normalize shift (refined_y << 1)
               Exponent adjust, IEEE-754 pack, FTZ & overflow flags
       │
    ═══════ OUTPUT REGISTERS (out_valid, result, flags, tag_out) ═══════
```

### Detailed Operation Breakdown by Clock Stage

| Stage | Input Registers | Operations Executed in Combinational Cone | Max Multiplier in Cone | Output Clocked Registers |
| :---: | :---: | :--- | :---: | :---: |
| **0** | Top Ports | Decode `op`; FTZ detection; classification of NaN/Inf/Zero/neg-sqrt; address generation; small ROM lookup (`approx_recip_lut` 7-bit, `approx_rsqrt_lut` 8-bit). | **None** (0 mults) | `val_r0`, `op_r0`, `tag_r0`, `spec_r0`, `sval_r0`, `sflg_r0`, `sign_r0`, `exp_r0`, `k_r0`, `b_r0`, `xa_r0`, `xb_r0`, `seed_r0` |
| **1** | `R0` | DIV: $X_B \times Y_0$ ($24 \times 16 \to 40$b) and $D_1 = 2.0 - X_B Y_0$;<br>RSQRT: $Y_0 \times Y_0$ ($16 \times 16 \to 32$b). | **One** ($24 \times 16$ or $16 \times 16$) | `val_r1`, `op_r1`, `tag_r1`, `spec_r1`, `sval_r1`, `sflg_r1`, `res_div_r1` (25b), `rsqrt_sq_r1` (32b), `xa_r1`, `xb_r1`, `seed_r1` |
| **2** | `R1` | DIV: $Y_1 = Y_0 \times D_1$ ($16 \times 25 \to 41$b);<br>RSQRT: $X_A \times Y_0^2$ ($25 \times 32 \to 57$b) and $D_1 = 3.0 - X_A Y_0^2$ (58b sub). | **One** ($16 \times 25$ or $25 \times 32$) | `val_r2`, `op_r2`, `tag_r2`, `spec_r2`, `sval_r2`, `sflg_r2`, `div_y1_r2` (24b), `rsqrt_d1_r2` (58b signed), `xa_orig_r2`, `seed_r2` |
| **3** | `R2` | DIV: Register pass-through of $Y_1$;<br>RSQRT: $Y_1 = \frac{1}{2} Y_0 \times D_1$ ($16 \times 58 \to 74$b signed). | **One** ($16 \times 58$ signed for RSQRT; 0 for DIV) | `val_r3`, `op_r3`, `tag_r3`, `spec_r3`, `sval_r3`, `sflg_r3`, `refined_y_r3` (24b), `xa_orig_r3`, `sign_r3`, `exp_r3`, `k_r3`, `b_r3` |
| **4** | `R3` | DIV: $X_A \times Y_1$ ($24 \times 24 \to 48$b);<br>SQRT: $X_A \times (2 Y_1)$ ($24 \times 24 \to 48$b);<br>RSQRT: Mantissa directly from $2 Y_1$;<br>Normalization 1-bit shift, exponent subtraction, overflow/underflow check, IEEE-754 packaging. | **One** ($24 \times 24$ for DIV/SQRT; 0 for RSQRT) | `out_valid`, `result` (32b), `flags` (8b), `tag_out` (16b) |

**Key Architectural Rectification**:
In the previous implementation, the RSQRT path executed the $X_A \times Y_0^2$ multiplication, the 58-bit subtraction, AND the $Y_0 \times D_1$ multiplication all in Stage 2. In this refactored RTL, those operations are split across Stage 2 and Stage 3 with a dedicated register stage (`rsqrt_d1_r2`). Consequently, every single stage contains at most one DSP multiplication.

---

## 3. Strict Parameter Enforcement & Rejection Verification

The parameter assertions in `approx_div_sqrt.sv` prevent erroneous system integration:

```systemverilog
generate
    if (TIER != 1) begin : gen_assert_tier
        illegal_tier_parameter_only_tier_1_supported _assert();
    end
    if (LATENCY != 5) begin : gen_assert_latency
        illegal_latency_parameter_must_be_5 _assert();
    end
    if (II != 1) begin : gen_assert_ii
        illegal_ii_parameter_must_be_1 _assert();
    end
endgenerate
```

Verification in `tests/test_parameter_assertions.py`:
- `TIER=0`: Elaborator emits `Unknown module type: illegal_tier_parameter_only_tier_1_supported` (Exit Code 1, PASSED).
- `TIER=2`: Elaborator emits `Unknown module type: illegal_tier_parameter_only_tier_1_supported` (Exit Code 1, PASSED).
- `TIER=3`: Elaborator emits error (Exit Code 1, PASSED).
- `LATENCY=4`: Elaborator emits `Unknown module type: illegal_latency_parameter_must_be_5` (Exit Code 1, PASSED).
- `LATENCY=7`: Elaborator emits `Unknown module type: illegal_latency_parameter_must_be_5` (Exit Code 1, PASSED).
- `II=2`: Elaborator emits `Unknown module type: illegal_ii_parameter_must_be_1` (Exit Code 1, PASSED).
- `TIER=1, LATENCY=5, II=1`: Compiles and elaborates with zero warnings or errors (Exit Code 0, PASSED).

---

## 4. Hardware Simulation Results: Latency, II, Backpressure & Flush

Testbench `tests/tb_protocol_perf.sv` was executed using Icarus Verilog (`iverilog -g2012`), protected by a 1,000,000 ns diagnostic watchdog:

1. **Measured Latency**:
   - `DIV (op=0)`: Handshake to output assertion = **5 clock cycles** (hardware cycle counter assertion verified).
   - `SQRT (op=1)`: Handshake to output assertion = **5 clock cycles** (hardware cycle counter assertion verified).
   - `RSQRT (op=2)`: Handshake to output assertion = **5 clock cycles** (hardware cycle counter assertion verified).
2. **Initiation Interval (II)**:
   - 32 continuous requests were driven back-to-back without bubbles (`in_valid=1` for 32 consecutive clock cycles).
   - All 32 responses were received in 32 consecutive clock cycles (`out_valid=1` every cycle with cycle gap = 1).
   - **Measured Initiation Interval = 1.000**.
3. **Randomized Backpressure**:
   - 64 requests driven through the core with pseudo-random `out_ready` stalling (33% backpressure rate).
   - When stalled, all in-flight stage data froze cleanly; `tag_out` matched expectations in-order with 100% data integrity and zero corruption.
4. **Pipeline Flush**:
   - 3 operations loaded into pipeline; `flush` asserted for 1 cycle.
   - All in-flight operations were purged; zero spurious outputs emitted during the subsequent 10 cycles.
   - New operation issued after flush was processed with exact 5-cycle latency and correct results.

---

## 5. Numerical Accuracy & Error Distribution Analysis

The numerical testsuite (`tests/test_approx_suite.py`) evaluated 4,131 test vectors across two independent simulation runs (full-speed and 25% randomized backpressure) against an independent exact IEEE-754 FP32 mathematical baseline:

### Error Summary vs Exact FP32 Baseline

| Operation | Total Vectors | Measured Max Relative Error | Measured Mean Relative Error | Median ULP Distance | Max Tolerated Threshold | Result |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **DIV** ($A / B$) | 1,600 | **0.1080%** ($1.08 \times 10^{-3}$) | **0.02236%** ($2.24 \times 10^{-4}$) | 941.5 | $\le 0.150\%$ | **PASS** |
| **SQRT** ($\sqrt{A}$) | 1,000 | **0.0006%** ($5.72 \times 10^{-6}$) | **0.00012%** ($1.22 \times 10^{-6}$) | 10.0 | $\le 0.005\%$ | **PASS** |
| **RSQRT** ($1/\sqrt{A}$) | 1,500 | **0.0006%** ($5.72 \times 10^{-6}$) | **0.00012%** ($1.18 \times 10^{-6}$) | 10.0 | $\le 0.005\%$ | **PASS** |

### Downstream Quantized Code Impact
- **LayerNorm (INT16 Q12 format, $\text{var} \in [10^{-6}, 100.0]$)**:
  - Max Code Difference: **1 LSB**
  - Mean Code Difference: **0.008 LSB**
  - Exact Bit/Code Match Rate: **99.2%** (496 / 500 samples matched exact FP32 INT16 code bit-for-bit)
- **Softmax (UINT16 format, 1.0 = 65535, $S \in [1.0, 99.0]$)**:
  - Max Code Difference: **14 LSB**
  - Mean Code Difference: **0.452 LSB**
  - Exact Bit/Code Match Rate: **74.3%**

> **Formal Note on Numerical Claims**:  
> In accordance with user instructions, these error metrics are empirical measurements on synthetic distributions and realistic layer normalization envelopes. They do **not** constitute proof of end-to-end full-model accuracy across all downstream transformer layers, which requires full graph co-simulation.

---

## 6. End-to-End Co-Simulation with `ds_vector` (Read-Only)

Without modifying any files in `/home/yang/Desktop/项目/v023_repair/ds_vector/`:
1. Compiled `ds_vector/tb/tb_vector_generic.sv` with `ddr_vector_engine_approx.sv` and candidate `approx_div_sqrt.sv`.
2. Executed regression fixtures:
   - `div_tail7`: Completed 7 elements, cycle count = 51, `fault=0`, `err=00`, `flags=10` (`V023_VECTOR_PASS`).
   - `div_1001`: Completed 1001 elements, cycle count = 2888, `fault=0`, `err=00`, `flags=10` (`V023_VECTOR_PASS`).
   - `sqrt_1001`: Completed 1001 elements, cycle count = 2739, `fault=0`, `err=00`, `flags=10` (`V023_VECTOR_PASS`).

---

## 7. Artifact Manifest & Source SHA256 Checksums

| File Path | SHA256 Checksum | Description |
| :--- | :--- | :--- |
| `rtl/approx_div_sqrt.sv` | `298a1fb5772c6a156c118b983521e2366ee3d6c361cb85a7395c2f64e7e0c343` | Top approximate math core (5 cycles, II=1, split RSQRT cone) |
| `rtl/approx_recip_lut.sv` | `b5d1ee5cbaca06a55ce6da67fc6c0fbbd88869c6e6aa5508f1c909c03bb4f41a` | 128-entry reciprocal seed LUT |
| `rtl/approx_rsqrt_lut.sv` | `cf0d0d03ec839b138acad933fe4561975e0690180ea1099721df3e33ec07e153` | 256-entry inverse square root seed LUT |
| `tests/tb_protocol_perf.sv` | `e89f9963741d5940a2c04d43214d14f97132e10cbe9627eded1045d4ec8c6969` | Real hardware latency, II=1, backpressure & flush testbench |
| `tests/tb_approx_div_sqrt.sv` | `dac1f146904081d0862734f1b2d472929fe4ba19d986ecd5cefad7bbbfba57d3` | File-driven vector regression testbench with watchdog |
| `tests/test_approx_suite.py` | `eda202afd46eee4e9fc21ba3f846f00052b143dd784db83da0c1e1f78a4ced5c` | Comprehensive test runner, exact baseline comparison, strict exit gating |
| `tests/test_parameter_assertions.py` | `e21ec3750f6c7439612ed9a3cff2affe18d239190e1f1b7f80f2e5c5d7551f56` | Parameter assertion & invalid tier rejection test |
| `run_all.sh` | (executable) | Unified test suite runner |

---

## 8. Failures & Unverified Scope

- **Vendor FMA**: Op 17 (FMA) is not implemented or substituted in this core; it remains handled by the separate vendor IP in the vector cluster.
- **Physical Timing (STA)**: No Vivado synthesis or STA was run; pipeline latency is stated purely in register cycles (5 cycles) with single-multiplier stages, with zero promises regarding physical nanosecond margins or 300/600 MHz board operation.
- **Complete Model Accuracy**: End-to-end task accuracy under real weights and whole-network activation sets is left to higher-level graph evaluation.
