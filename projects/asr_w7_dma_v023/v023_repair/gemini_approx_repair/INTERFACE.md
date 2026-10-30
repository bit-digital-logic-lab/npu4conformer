# INTERFACE — gemini_approx_repair Binding Contract

**Role**: `approx_div_sqrt` Approximate Math Core (DIV, SQRT, RSQRT)  
**Status**: Binding Contract & Production Implementation (Post-Repair Acceptance Revision)  
**Consumer**: `ds_vector` (`ddr_vector_engine_pipe`, `ddr_vector_engine_approx`), epilogue normalization clusters, and PL compute engines.

---

## 1. Top-Level Module Interface

The module interface conforms strictly with Section 3 of `v023_repair/ds_vector/INTERFACE.md` and provides backward-compatible port naming:

```systemverilog
module approx_div_sqrt #(
    parameter integer TIER    = 1,    // Single production-ready tier (1-step Newton-Raphson)
    parameter integer LATENCY = 5,    // Real hardware pipeline latency (cycles from in_valid to out_valid)
    parameter integer II      = 1     // Initiation interval (1 cycle for back-to-back throughput)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,         // Optional synchronous pipeline flush (clears in-flight transactions)

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

> **Compatibility Note**: The `flush` input port has a default value (`1'b0` in SystemVerilog). Modules instantiating `approx_div_sqrt` without the `.flush(...)` port connection (such as legacy `ds_vector` wrappers connecting `.rst_n(rst_n && !core_flush)`) compile and run without modification.

---

## 2. Parameter Rules & Strict Assertions

Following the primary acceptance audit findings, fake multiple tiers (the previous unpipelined Tier 0 and identical unrefined Tier 2) have been **completely eliminated**. The engine provides a single, fully-pipelined, production-grade tier.

### 2.1 Supported Configurations
- `TIER = 1`: High-throughput 1-step Newton-Raphson reciprocal/inverse-square-root pipeline.
- `LATENCY = 5`: Exactly 5 clock cycles from handshake (`in_valid && in_ready`) to output assertion (`out_valid`).
- `II = 1`: Exactly 1 request accepted per cycle, producing 1 result per cycle continuously.

### 2.2 Rejection of Illegal Parameters
Any instantiation specifying unsupported parameters will trigger compile-time and simulation-time assertions:
- `TIER != 1`: Elaboration error (`illegal_tier_parameter_only_tier_1_supported`) and `$fatal`.
- `LATENCY != 5`: Elaboration error (`illegal_latency_parameter_must_be_5`) and `$fatal`.
- `II != 1`: Elaboration error (`illegal_ii_parameter_must_be_1`) and `$fatal`.

---

## 3. Operations & Register Boundary Pipelining

To eliminate the composite multiplication combinational cone identified in primary acceptance, the pipeline operations are strictly isolated across registered boundaries:

| Stage | Input Regs | Combinational Operations Executed | Multipliers in Stage | Output Regs |
| :---: | :---: | :--- | :---: | :---: |
| **Stage 0** | Top Ports | Decode, IEEE-754 classification, Subnormal FTZ, Exp unbiased calc, Seed LUT lookup (`approx_recip_lut`, `approx_rsqrt_lut`). | 0 | `R0` (`val_r0`, `op_r0`, `tag_r0`, `spec_r0`, `xa_r0`, `xb_r0`, `seed_r0`, `sign_r0`, `exp_r0`, `k_r0`, `b_r0`) |
| **Stage 1** | `R0` | DIV: $X_B \times Y_0$ ($24 \times 16 \to 40$b) and $D_1 = 2.0 - X_B Y_0$;<br>RSQRT: $Y_0 \times Y_0$ ($16 \times 16 \to 32$b). | 1 | `R1` (`res_div_r1`, `rsqrt_sq_r1`, control/operands) |
| **Stage 2** | `R1` | DIV: Refined $Y_1 = Y_0 \times D_1$ ($16 \times 25 \to 41$b);<br>RSQRT: $X_A \times Y_0^2$ ($25 \times 32 \to 57$b) and $D_1 = 3.0 - X_A Y_0^2$ (58b sub). | 1 | `R2` (`div_y1_r2`, `rsqrt_d1_r2`, `xa_orig_r2`, control) |
| **Stage 3** | `R2` | DIV: Pass through refined seed;<br>RSQRT: Isolated Newton product $Y_1 = \frac{1}{2} Y_0 \times D_1$ ($16 \times 58 \to 74$b signed). | 1 | `R3` (`refined_y_r3`, `xa_orig_r3`, control) |
| **Stage 4** | `R3` | DIV: Numerator product $X_A \times Y_1$ ($24 \times 24 \to 48$b);<br>SQRT: Radicand product $X_A \times (2 Y_1)$ ($24 \times 24 \to 48$b);<br>RSQRT: Normalization shift only ($2 Y_1$). Exponent adjustment, FTZ/overflow check, IEEE-754 pack. | 1 (DIV/SQRT)<br>0 (RSQRT) | Output Regs (`out_valid`, `result`, `flags`, `tag_out`) |

**Timing Summary**:
- **Clock Latency**: Measured **exactly 5 cycles**.
- **Initiation Interval**: Measured **exactly 1 cycle**.
- **Composite Cone Elimination**: No stage contains more than one DSP-scale multiplier.

---

## 4. Handshake, Flow Control & Flush Semantics

1. **Request Handshake**: `in_valid && in_ready` consumes one operand pair on rising clock edge.
2. **Completion Handshake**: `out_valid && out_ready` completes one result on rising clock edge.
3. **Backpressure Stall**:
   - `in_ready = out_ready || !out_valid`.
   - When stalled (`out_ready == 0` while `out_valid == 1`), all in-flight pipeline registers hold their values cleanly.
   - `out_valid`, `result`, `flags`, and `tag_out` remain static; zero dropped transactions, zero reordering.
4. **Pipeline Flush**:
   - Asserting `flush == 1` synchronously clears `out_valid` and all internal stage valids (`val_r0..val_r3`).
   - In-flight operations are discarded in 1 cycle without producing phantom completions.
   - New operations issued immediately after flush deassertion execute with full correctness and 5-cycle latency.
   - Asynchronous `rst_n == 0` clears all pipeline registers.

---

## 5. Status Flags (`flags[7:0]`)

Conforms to Section 4 of `work/rtl/asr_fp32_alu.sv` and `ds_vector/INTERFACE.md`:

| Bit | Name | Trigger Condition | Engine Action |
| :---: | :---: | :--- | :--- |
| `flags[0]` | **Invalid Operation** | NaN input; $0/0$; $\infty/\infty$; $\text{SQRT}(A)$ or $\text{RSQRT}(A)$ with $A < 0$ | Aborts vector job (`error_code=8'h04`) |
| `flags[1]` | **Division by Zero** | DIV with $B = \pm 0$ (finite non-zero $A$); RSQRT with $A = +0$ | Aborts vector job (`error_code=8'h04`) |
| `flags[2]` | **Overflow** | Normal result exponent $\ge 255$ | Aborts vector job (`error_code=8'h04`) |
| `flags[3]` | **Underflow / FTZ** | Denormal/subnormal input or intermediate result flushed to zero | Updates status register, does not abort |
| `flags[4]` | **Approximate Marker** | Asserted (`1`) on any approximate normal computation | Informational flag, does not abort |
| `flags[7:5]` | Reserved | Tied to `3'b000` | N/A |
