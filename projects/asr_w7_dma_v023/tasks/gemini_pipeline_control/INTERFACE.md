# Interface Contract: Pipeline Controller <-> Systolic PE Array

## 1. Array Signal Interface
The parameterized block execution controller (`block_engine_pipeline_ctrl_v023`) interfaces with the 16x16 systolic array using the following standard port list:

| Signal | Direction (Array perspective) | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | Synchronous core clock |
| `reset` | Input | 1 | Active-high synchronous system reset |
| `flush` | Input | 1 | Synchronous active-high flush. Clears in-flight multiplier pipeline registers. **Does NOT clear accumulators.** Safe protocol: Controller asserts ONLY on abort/reset or when array is known empty. |
| `clear_sum` | Input | 1 | Synchronous active-high accumulator reset. Resets all 256 PE accumulators to 0. Safe protocol: Controller asserts ONLY prior to starting a fresh quadrant calculation. |
| `a_left` | Input | 256 | Left input vector: 16 rows $\times$ 16-bit signed operands |
| `w_top` | Input | 112 | Top input vector: 16 cols $\times$ 7-bit neural weight codes $\{S, J[1:0], M[3:0]\}$ |
| `av` | Input | 16 | Valid strobes for each of the 16 row operands |
| `wv` | Input | 16 | Valid strobes for each of the 16 column weight codes |
| `positions` | Input | 16 | Packed position table $\{P_3, P_2, P_1, P_0\}$ (each 4 bits $\in [0, 12]$) |
| `clip` | Input | 1 | Clipping saturation enable |
| `sums` | Output | 12288 | Accumulated partial sums: 256 PEs $\times$ 48-bit signed two's complement |
| `pipe_empty` | Output (Optional) | 1 | High when all internal PE stages contain no valid data. Tied high or ignored if not provided. |
| `drain_done` | Output (Optional) | 1 | High when the last injected operand has finished accumulating into all PEs. |
| `pe_drain_cycles` | Output (Optional) | 8 | Constant reporting PE pipeline latency + accumulation overhead. |
| `array_drain_cycles` | Output (Optional) | 8 | Constant reporting array-level wavefront skew (15) + PE drain cycles. |

## 2. Latency & Timing Parameterization
1. **Elaboration-Time Parameter `PE_LATENCY`**:
   - Supported values: $3, 4, 5, 6, 8, \dots$
   - Number of cycles from input presentation at PE$(r, c)$ to the clock edge updating `sum` is `PE_LATENCY`.
   - Baseline PE (`pe_direct_v020.sv`): `PE_LATENCY = 3` (DRAIN = 4).
   - Candidate Carry-Chain PE (`pe_pipeline_cc_v023.sv` / `pe_w7_c48_cfg` stage 4): `PE_LATENCY = 4` (DRAIN = 5).
   - Candidate 5-stage PE: `PE_LATENCY = 5` (DRAIN = 6).
   - Candidate 6-stage PE: `PE_LATENCY = 6` (DRAIN = 7).
   - Candidate 8-stage PE: `PE_LATENCY = 8` (DRAIN = 9).
2. **Total Run / Drain Cycle Formula**:
   $$\text{DRAIN\_CYCLE\_LIMIT} = 31 + 15 + 15 + \text{PE\_LATENCY} = 61 + \text{PE\_LATENCY}$$
   - $31$: Last $K$-step operand ($ki = 31$, since $K = 32$ per quadrant).
   - $15$: Row skew (injection at row 15 delayed by 15 cycles).
   - $15$: Column propagation (horizontal systolic shift across 16 columns).
   - $\text{PE\_LATENCY}$: PE pipeline delay from input arrival to accumulator write.
3. **Array Output Stability**:
   - At clock cycle `DRAIN_CYCLE_LIMIT`, all 256 PE accumulators are bit-exact, stable, and ready for collection.
   - The controller transitions from `RUN` / `DRAIN` to `C_READ` at or after `DRAIN_CYCLE_LIMIT`.

## 3. Clear and Flush Safety Protocols
- **Flush Protocol**:
  - In baseline, `flush = (state != RUN)`. This was hazardous because any transition out of `RUN` immediately wiped in-flight registers.
  - In candidate controller, `flush` is driven only during `reset`, `FAIL`, or after pipeline drain verification is confirmed.
- **Clear Sum Protocol**:
  - `clear_sum` is only asserted when `state == CLEAR`.
  - Transitions to `CLEAR` occur only when:
    1. Previous quadrant results have been completely collected via the pipelined collection multiplexer into BRAM or output payload.
    2. Pipeline is fully drained (`drain_done` asserted or run counter $\ge \text{DRAIN\_CYCLE\_LIMIT}$).
    3. No in-flight tokens exist.
