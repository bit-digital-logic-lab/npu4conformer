# Hardware Interface & Timing Contract Specification

This document provides the formal interface contract, latency profiles, and upper-layer timing requirements for the audited computational units:
1. `pe_direct_v020.sv` (Baseline PE)
2. `pe_pipeline_cc_v023.sv` (Candidate A: Pipelined Carry-Chain PE)
3. `pe_pipeline_csa_v023.sv` (Candidate B: Dual-Rail CSA PE)
4. `array16_pipeline_v023.sv` (16x16 Systolic Sub-Array)

---

## 1. Port Interface Contract

All three PE variants share the identical pinout:

| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | Master clock |
| `reset` | Input | 1 | Synchronous active-high reset. Clears all pipeline registers and accumulators to 0. |
| `flush` | Input | 1 | Synchronous active-high flush. Clears systolic pass-through registers (`a_out`, `w_out`, `av_out`, `wv_out`) and internal multiplication pipeline registers (`valid`, `mag0`, `raw1`, etc.). **Does NOT reset `sum`.** Disables accumulation (`!flush && valid[N]`). |
| `clear_sum` | Input | 1 | Synchronous active-high accumulator reset. Resets `sum` (or `sum_s`/`sum_c`) to 0. **Does NOT clear in-flight multiplier pipeline stages.** |
| `a_in` | Input | 16 | Signed 16-bit operand A $[-32768, 32767]$. |
| `w_in` | Input | 7 | Neural weight code $W[6:0]$: `w_in[6]` (Sign S), `w_in[5:4]` (Position Index J), `w_in[3:0]` (Magnitude M). |
| `av_in` | Input | 1 | Valid strobe for operand A. |
| `wv_in` | Input | 1 | Valid strobe for weight code W. |
| `positions`| Input | 16 | Packed 4-nibble position shift table $\{P_3, P_2, P_1, P_0\}$. Each $P_j \in [0, 12]$. |
| `clip` | Input | 1 | Saturation clip enable. When asserted, $P=12$ and $M \ge 8$ clips magnitude to $32767$. |
| `a_out` | Output | 16 | Registered horizontal systolic forward of `a_in` (1 clock cycle delay). |
| `w_out` | Output | 7 | Registered vertical systolic forward of `w_in` (1 clock cycle delay). |
| `av_out` | Output | 1 | Registered horizontal valid forward (1 clock cycle delay). |
| `wv_out` | Output | 1 | Registered vertical valid forward (1 clock cycle delay). |
| `sum` | Output | 48 | Accumulated signed 48-bit sum (two's complement, wraps modulo $2^{48}$). |

---

## 2. Latency Profiles & Pipeline Stages

### Baseline PE (`pe_direct_v020.sv`)
- **Pipeline Depth / Latency**: **3 Clock Cycles**
- **Stage Breakdown**:
  - Cycle T: Input `av_in && wv_in == 1`.
  - Cycle T+1 (`valid[0]`): Absolute value `mag0`, multiplier `m0`, position `p0`, sign `neg0`.
  - Cycle T+2 (`valid[1]`): Unsigned product `raw1 = mag0 * m0`, shifter inputs `p1, mag1`.
  - Cycle T+3 (`valid[2]`): Variable shift `aligned`, saturation subtraction `magnitude`, conditional negation `product2`.
  - Cycle T+3 -> T+4 clock edge: Accumulation `sum <= sum + product2` occurs.

### Candidates A & B (`pe_pipeline_cc_v023.sv`, `pe_pipeline_csa_v023.sv`)
- **Pipeline Depth / Latency**: **4 Clock Cycles**
- **Stage Breakdown**:
  - Cycle T: Input `av_in && wv_in == 1`.
  - Cycle T+1 (`valid[0]`): Absolute value `mag0`, multiplier `m0`, position `p0`, sign `neg0`.
  - Cycle T+2 (`valid[1]`): Unsigned product `raw1 = mag0 * m0`.
  - Cycle T+3 (`valid[2]`): Stage 2A: Variable shift `aligned` and saturation subtraction `magnitude2a`.
  - Cycle T+4 (`valid[3]`): Stage 2B: 32-bit conditional negation `product2b`.
  - Cycle T+4 -> T+5 clock edge: Accumulation occurs (`sum <= sum + product2b` for CC; `sum_s, sum_c` compression for CSA).

---

## 3. Upper-Layer Flush Contract (`block_engine_l1bank_v020.sv`)

### Exact Timing Critical Path:
In `block_engine_l1bank_v020.sv`, `array16` executes four quadrants of 32 K-steps each:
1. Matrix operands enter systolic array with wavefront skew:
   - Row $r$ receives $A$ inputs at cycle $r$.
   - Column $c$ receives $W$ inputs at cycle $c$.
   - Bottom-right PE(15,15) receives its 32nd K-element (`ki = 31`) at:
     $$\text{run\_cycle} = 15 + 31 + 15 = 61$$
2. Draining at PE(15,15):
   - Cycle 61: Input pulse present at PE(15,15).
   - Cycle 62: `valid[0] = 1`
   - Cycle 63: `valid[1] = 1`
   - Cycle 64: `valid[2] = 1`
   - Cycle 65: `valid[3] = 1` in candidate CC & CSA!
3. `block_engine` State Transition:
   ```verilog
   RUN: if (run_cycle == 65) begin collect <= 0; state <= C_READ; end else run_cycle <= run_cycle + 1;
   ```
   - During `run_cycle == 65`, `state == RUN`, so `flush = (state != RUN) = 0`.
   - At clock edge $65 \to 66$:
     - Accumulation `sum <= sum + product2b` executes (since `!flush && valid[3]` is 1).
     - State transitions to `C_READ`, asserting `flush <= 1` during cycle 66.
4. **Zero-Slack Condition Warning**:
   - For Candidates CC & CSA (latency 4), there is **EXACTLY ZERO SLACK CYCLES**.
   - If `run_cycle` check was `run_cycle == 64`, or if `flush` is asserted even 1 cycle prematurely, PE(15,15)'s last partial sum is discarded.
   - **Constraint**: If any developer adds a 5th pipeline stage to the PE, `block_engine_l1bank_v020.sv`'s RUN counter **MUST** be extended from `run_cycle == 65` to `run_cycle == 66`.
