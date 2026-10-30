# INTERFACE — gemini_approx Approximate DIV / SQRT / RSQRT Contract

**Status**: Published & Binding Interface Contract  
**Role**: `gemini_approx` Approximate Operator Engine  
**Target Consumer**: `ds_vector` (`ddr_vector_engine_pipe`), epilogue/fusion engines, and numerical execution clusters.  

---

## 1. Top-Level Module Interface: `approx_div_sqrt`

The module interface conforms strictly with Section 3 of `v023_repair/ds_vector/INTERFACE.md`:

```systemverilog
module approx_div_sqrt #(
    parameter integer TIER    = 1,    // 0: Low-Latency (PWL/LUT seed, Latency 2, II=1)
                                      // 1: High-Throughput (LUT + 1-step Newton, Latency 4, II=1) [DEFAULT]
                                      // 2: Low-Error (LUT + 2-step Newton, Latency 7, II=1)
    parameter integer LATENCY = 4,    // Measured pipeline latency (cycles from in_valid to out_valid)
    parameter integer II      = 1     // Initiation interval (1 cycle for back-to-back throughput)
)(
    input  wire        clk,
    input  wire        rst_n,

    // Request interface (ready-valid handshake)
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [1:0]  op,        // 0 = DIV (a / b)
                                  // 1 = SQRT (sqrt(a), b ignored)
                                  // 2 = RSQRT (1 / sqrt(a), b ignored)
    input  wire [31:0] a,         // Operand A (FP32)
    input  wire [31:0] b,         // Operand B (FP32, used for DIV)
    input  wire [15:0] tag,       // Opaque transaction tag, echoed on completion

    // Completion interface (in-order, ready-valid handshake)
    output wire        out_valid,
    input  wire        out_ready,
    output wire [31:0] result,    // Result (FP32)
    output wire [7:0]  flags,     // IEEE/Engine numeric status flags
    output wire [15:0] tag_out    // Tag echoed unchanged
);
```

---

## 2. Operation Semantics & Port Specifications

### 2.1 Handshake & Flow Control
- **`in_valid && in_ready`**: One request is consumed on the rising clock edge.
- **`out_valid && out_ready`**: One result is consumed on the rising clock edge.
- **Pipeline and Backpressure**:
  - The pipeline supports full backpressure: when `out_ready == 0`, `out_valid` stays asserted and `result`, `flags`, `tag_out` remain held without dropping in-flight transactions.
  - When internal pipeline registers are full during backpressure, `in_ready` deasserts cleanly.
  - Completion is guaranteed **strictly in-order**.

### 2.2 Supported Operations (`op[1:0]`)
| `op` | Symbol | Mathematical Function | Description | Typical Use Case |
| :---: | :---: | :---: | :---: | :---: |
| `2'b00` | `DIV` | $R = A / B$ | FP32 division via $A \times (1/B)$ reciprocal approximation | General division, Softmax normalization ($e_i / S$) |
| `2'b01` | `SQRT` | $R = \sqrt{A}$ | FP32 square root via $\sqrt{A} = A \times (1/\sqrt{A})$ | Standard deviation $\sigma = \sqrt{\text{var} + \epsilon}$ |
| `2'b10` | `RSQRT` | $R = 1 / \sqrt{A}$ | FP32 inverse square root | Direct LayerNorm normalization ($1/\sqrt{\text{var} + \epsilon}$) |

---

## 3. Numeric Tiers (三档实现)

| Tier | Configuration | Pipeline Latency | II | Hardware Cost | Typical Relative Error | Intended Use Case |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Tier 0** | Low Latency (`TIER=0`) | **2 cycles** | **1** | 128-entry LUT + linear interpolate / shift | $< 0.5\%$ ($< 5 \times 10^{-3}$) | Fast coarse normalization, INT8 target |
| **Tier 1** | High Throughput (`TIER=1`, Default) | **4 cycles** | **1** | 128-entry LUT + 1-step Newton-Raphson | $< 0.005\%$ ($< 5 \times 10^{-5}$) | **Recommended standard**: 100% adequate for W7A16 QDQ |
| **Tier 2** | Low Error (`TIER=2`) | **7 cycles** | **1** | 128-entry LUT + 2-step Newton-Raphson | $< 0.00001\%$ ($< 10^{-7}$, near-FP32) | High-precision scientific / FP32 baseline check |

---

## 4. Status Flags (`flags[7:0]`)

Conforms to `work/rtl/asr_fp32_alu.sv` and `v023_repair/ds_vector/INTERFACE.md`:

| Bit | Name | Trigger Condition | Engine Action |
| :---: | :---: | :---: | :---: |
| `flags[0]` | **Invalid Operation** | $A$ or $B$ is NaN; $0/0$; $\infty/\infty$; $\text{SQRT}(A)$ or $\text{RSQRT}(A)$ with $A < 0$ | Aborts vector job (`error_code=8'h04`) if enabled |
| `flags[1]` | **Division by Zero** | DIV with $B = \pm 0$ (and $A$ is finite non-zero); RSQRT with $A = +0$ | Aborts vector job (`error_code=8'h04`) if enabled |
| `flags[2]` | **Overflow** | Output exponent $\ge 255$ (saturated to $\pm \infty$) | Aborts vector job (`error_code=8'h04`) if enabled |
| `flags[3]` | **Underflow / FTZ** | Denormal/subnormal input or output flushed to signed zero | Updates status register, does not abort |
| `flags[4]` | **Approximate Result** | Asserted (`1`) whenever approximate logic computed the result | Informational marker, does not abort |
| `flags[7:5]` | Reserved | Tied to `3'b000` | N/A |

---

## 5. Corner Cases & Edge Semantics

1. **Subnormal Operands**:
   - Flush-To-Zero (FTZ) is applied to all subnormal inputs ($E=0, M \ne 0$) and intermediate results $< 2^{-126}$, asserting `flags[3]`.
2. **Zero Inputs**:
   - $A / (\pm 0) = \pm \infty$ with `flags[1]` (div-by-zero).
   - $\pm 0 / B = \pm 0$ with correct sign.
   - $\sqrt{+0} = +0$; $\sqrt{-0} = -0$.
   - $1/\sqrt{+0} = +\infty$ with `flags[1]`.
3. **Negative Inputs**:
   - $\text{SQRT}(A)$ and $\text{RSQRT}(A)$ for $A < -0$: returns Canonical NaN (`0x7fc00000`) and asserts `flags[0]`.
4. **Infinities & NaNs**:
   - Any NaN input returns Canonical Quiet NaN (`0x7fc00000`) with `flags[0]`.
   - $\infty / \text{finite} = \pm \infty$; $\text{finite} / \infty = \pm 0$; $\infty / \infty = \text{NaN}$ (`flags[0]`).
   - $\sqrt{+\infty} = +\infty$; $1/\sqrt{+\infty} = +0$.
5. **Near-Zero $\epsilon$ Range**:
   - In LayerNorm, $\text{var} + \epsilon$ where $\epsilon = 10^{-6} \approx 2^{-20}$. Handled safely without intermediate mantissa underflow or precision loss.
