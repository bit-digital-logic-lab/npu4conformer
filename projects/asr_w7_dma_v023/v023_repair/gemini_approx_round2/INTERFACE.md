# INTERFACE — gemini_approx_round2 Binding Contract

**Module**: `approx_div_sqrt` Approximate Math Core (DIV, SQRT, RSQRT)  
**Status**: Binding Contract & Production Implementation (Round 2 Rectification of APPROX-1..3 and Flush Integration)  
**Target Architecture**: 512-dimension Conformer/Transformer ASR inference accelerator (not KWT).  
**Consumer Modules**: `ds_vector` (`ddr_vector_engine_pipe`, `ddr_vector_engine_approx`), epilogue normalization clusters, and PL autonomous vector units.

---

## 1. Top-Level Module Interface & Port Contract

The module interface strictly conforms with Section 3 of `v023_repair/ds_vector/INTERFACE.md` while providing backward-compatible port instantiation:

```systemverilog
module approx_div_sqrt #(
    parameter integer TIER    = 1,    // Single production-ready tier (LUT seed + 1-step Newton-Raphson)
    parameter integer LATENCY = 5,    // Real hardware pipeline latency (cycles from in_valid to out_valid)
    parameter integer II      = 1     // Initiation interval (1 cycle for back-to-back throughput)
)(
    input  wire        clk,
    input  wire        rst_n,
    input              flush = 1'b0,  // Synchronous pipeline flush with backward-compatible default

    // Request interface (ready-valid handshake)
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [1:0]  op,            // 2'b00: DIV (a / b)
                                      // 2'b01: SQRT (sqrt(a), b ignored)
                                      // 2'b10: RSQRT (1 / sqrt(a), b ignored)
    input  wire [31:0] a,             // Operand A (IEEE-754 FP32)
    input  wire [31:0] b,             // Operand B (IEEE-754 FP32, divisor for DIV)
    input  wire [15:0] tag,           // Transaction token / bank tag, echoed on completion

    // Completion interface (in-order, ready-valid handshake)
    output reg         out_valid,
    input  wire        out_ready,
    output reg  [31:0] result,        // Approximate result (IEEE-754 FP32)
    output reg  [7:0]  flags,         // Status flags conforming to ALU contract
    output reg  [15:0] tag_out        // Tag echoed unchanged
);
```

### 1.1 Flush Integration Contract
- In Round 1, the port was declared as `input wire flush,` without a default value, causing elaboration warnings or high-impedance values for modules connecting without `.flush(...)`.
- In Round 2, the port declaration is formally updated to:
  ```systemverilog
  input flush = 1'b0,
  ```
- **Callers with flush**: Can instantiate `.flush(flush_sig)` for 1-cycle pipeline clearing.
- **Legacy callers without flush** (e.g. `ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv` line 160): Can instantiate `approx_div_sqrt` omitting `.flush(...)`; `flush` deterministically defaults to `1'b0` with zero compile errors and zero warnings.

---

## 2. Parameter Rules & Strict Assertions

The engine provides a single, fully-pipelined production tier:
- `TIER = 1`: Active production pipeline. Fake TIER 0 and TIER 2 have been pruned.
- `LATENCY = 5`: Exactly 5 clock cycles from handshake (`in_valid && in_ready`) to output assertion (`out_valid`).
- `II = 1`: Exactly 1 request accepted per cycle, producing 1 result per cycle continuously.

### Parameter Assertions
Any instantiation with mismatching parameters triggers both elaboration failure (missing illegal assertion module) and runtime `$fatal`:
- `TIER != 1`: Elaboration error (`illegal_tier_parameter_only_tier_1_supported`) and `$fatal`.
- `LATENCY != 5`: Elaboration error (`illegal_latency_parameter_must_be_5`) and `$fatal`.
- `II != 1`: Elaboration error (`illegal_ii_parameter_must_be_1`) and `$fatal`.

---

## 3. Operations & Register Boundary Pipelining

The critical composite multiplication cone from early designs remains cleanly split across registered pipeline stages:

| Stage | Input Regs | Combinational Operations Executed | Multipliers in Cone | Output Regs |
| :---: | :---: | :--- | :---: | :---: |
| **Stage 0** | Top Ports | Decode, IEEE-754 classification, Subnormal FTZ, Exp unbiased calc, Seed LUT lookup (`approx_recip_lut`, `approx_rsqrt_lut`). | 0 | `R0` (`val_r0`, `op_r0`, `tag_r0`, `spec_r0`, `xa_r0`, `xb_r0`, `seed_r0`, `sign_r0`, `exp_r0`, `k_r0`, `b_r0`) |
| **Stage 1** | `R0` | DIV: $X_B \times Y_0$ ($24 \times 16 \to 40$b) and $D_1 = 2.0 - X_B Y_0$;<br>RSQRT: $Y_0 \times Y_0$ ($16 \times 16 \to 32$b). | 1 | `R1` (`res_div_r1`, `rsqrt_sq_r1`, control/operands) |
| **Stage 2** | `R1` | DIV: Refined $Y_1 = Y_0 \times D_1$ ($16 \times 25 \to 41$b);<br>RSQRT: $X_A \times Y_0^2$ ($25 \times 32 \to 57$b) and $D_1 = 3.0 - X_A Y_0^2$ (58b sub). | 1 | `R2` (`div_y1_r2`, `rsqrt_d1_r2`, `xa_orig_r2`, control) |
| **Stage 3** | `R2` | DIV: Pass through refined seed;<br>RSQRT: Isolated Newton product $Y_1 = \frac{1}{2} Y_0 \times D_1$ ($16 \times 58 \to 74$b signed). | 1 | `R3` (`refined_y_r3`, `xa_orig_r3`, control) |
| **Stage 4** | `R3` | DIV: Numerator product $X_A \times Y_1$ ($24 \times 24 \to 48$b);<br>SQRT: Radicand product $X_A \times (2 Y_1)$ ($24 \times 24 \to 48$b);<br>RSQRT: Normalization shift only ($2 Y_1$). Multi-case normalization (fixes APPROX-1 & APPROX-2), FTZ/overflow check, IEEE-754 pack. | 1 (DIV/SQRT)<br>0 (RSQRT) | Output Regs (`out_valid`, `result`, `flags`, `tag_out`) |

---

## 4. Specific Round 2 Numeric Rectifications (APPROX-1..3)

### 4.1 APPROX-1: DIV 2x Factor Boundary Normalization
- **Finding**: $0x3f800000 / 0x41fffad2$ ($1.0 / 31.9998$) produced $0x3d7fde3c$ ($0.062468$), a 2x factor error with 99.88% relative error.
- **Root Cause**: When $X_A \approx 1.0$ and $X_B \approx 2.0$, Newton-Raphson approximation $Y_1 \le 1/X_B$ is concave from below and dips slightly below 0.5 ($0.49948$). In Q46, both bit 46 ($\ge 1.0$) and bit 45 ($\ge 0.5$) are 0. The old RTL only checked `if (div_num_prod[46]) ... else ...`, treating bit 44 as mantissa bit [22] and decrementing exponent by only 1 instead of 2.
- **Contract Fix**: Stage 4 incorporates full 3-way normalization:
  - `div_num_prod[46]`: mantissa `[45:23]`, exponent `exp`.
  - `div_num_prod[45]`: mantissa `[44:22]`, exponent `exp - 1`.
  - `else` ($< 0.5$ dip): mantissa `[43:21]`, exponent `exp - 2`.
- **Result**: Max DIV relative error across all 15,168 adversarial vectors reduced to **0.11147%** (0.001115), eliminating the factor-2 boundary defect.

### 4.2 APPROX-2: RSQRT Max Finite 2x Factor Boundary Normalization
- **Finding**: $RSQRT(0x7f7fffff)$ produced $0x1ffffff4$ ($1.0842e-19$) instead of $5.4210e-20$, a 2x factor error with 99.99985% relative error.
- **Root Cause**: For max finite float ($X_A \to 4.0$), $Y_1 \approx 0.5$ dips slightly below 0.5, so $rsqrt\_y\_norm = Y_1 \ll 1 = 0x7ffff4 < 1.0$. Bit 23 is 0 and bit 22 is 1. The old RTL did not normalize RSQRT at all, copying bits `[22:0]` into mantissa and setting exponent to $126 - k$.
- **Contract Fix**: Stage 4 checks bit 23 of `rsqrt_y_norm`:
  - `rsqrt_y_norm[23]`: mantissa `rsqrt_y_norm[22:0]`, exponent `126 - k`.
  - `!rsqrt_y_norm[23]`: mantissa `{rsqrt_y_norm[21:0], 1'b0}`, exponent `125 - k`.
- **Result**: Max RSQRT relative error reduced to **5.72e-6** (0.000572%), eliminating the factor-2 defect on max finite numbers.

### 4.3 APPROX-3: RSQRT(-0) & Negative Subnormal Signed Infinity
- **Finding**: $RSQRT(0x80000000)$ (-0) and negative subnormals returned $+inf$ (`0x7f800000`) instead of IEEE-754 $-inf$ (`0xff800000`).
- **Root Cause**: Stage 0 special case logic assigned `special_val_s0 = FP32_POS_INF` unconditionally when `is_zero(a_ftz)` was true.
- **Contract Fix**: Stage 0 assigns `special_val_s0 = a_sign ? FP32_NEG_INF : FP32_POS_INF;`.
- **Result**: Exact IEEE-754 signed infinity with `FLAG_DIV_BY_0` (`0x02`) on negative zero, and `FLAG_UNDERFLOW | FLAG_DIV_BY_0` (`0x0a`) on negative subnormals.

---

## 5. Status Flags Contract (`flags[7:0]`)

| Flag Bit | Name | Trigger Condition |
| :---: | :---: | :--- |
| `flags[0]` | `INVALID` | NaN operand, SQRT/RSQRT of strictly negative non-zero number, 0/0, $\infty/\infty$. |
| `flags[1]` | `DIV_BY_0` | Division by $\pm 0$ in DIV ($b = \pm 0$ with non-zero finite $a$), or $RSQRT(\pm 0)$. |
| `flags[2]` | `OVERFLOW` | Exponent exceeds $+127$ ($exp \ge 255$). Result clamps to signed infinity. |
| `flags[3]` | `UNDERFLOW` | Input subnormal flushed to zero (FTZ) or exponent drops $\le 0$. Result flushes to signed zero. |
| `flags[4]` | `APPROX` | Set on all valid approximate calculations (DIV, SQRT, RSQRT) to signal approximate result. |
| `flags[7:5]` | `RESERVED`| Reserved, strictly driven to `3'b000`. |

---

## 6. Verification and Repeatability

The verification suite can be run directly via:
```bash
cd /home/yang/Desktop/项目/v023_repair/gemini_approx_round2
./run_all.sh
```
All tests enforce strict assertions, wall-clock and cycle watchdogs, zero unconditional PASS messages, and return exit code 0.
