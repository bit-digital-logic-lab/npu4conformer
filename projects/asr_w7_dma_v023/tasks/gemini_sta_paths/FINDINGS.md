# Empirical Timing Findings & Architectural Analysis (full002 Baseline)

## 1. Baseline Environment & Frequency Clarification
- **Device**: AMD Xilinx Zynq UltraScale+ `xczu15eg-ffvb1156-2-I` (Speed grade -2, Industrial).
- **Tool Version**: Vivado v2025.2 (Build 6299465).
- **Target Frequency Discrepancy**:
  - The historical Vivado implementation run (`full002`) constrained `clk100_raw` with **Period = 8.000 ns (125.000 MHz)**.
  - The user reference currently indicates **~150 MHz** (Period = 6.667 ns).
  - These two references are distinct and must not be conflated:
    - `full002` STA was signed off at 125 MHz with WNS = +0.055 ns.
    - If the exact `full002` netlist were clocked at 150 MHz (6.667 ns, a 1.333 ns reduction in clock period), all 30 reported setup paths in `clk100_raw` would immediately fail with WNS ~ -1.278 ns.
    - Therefore, the user's current "~150 MHz" represents either a different build, unconstrained margins, or over-clocked bench without full STA signoff.

## 2. Global Timing Summary (timing.rpt)
| Metric | Setup (WNS) | Setup (TNS) | Hold (WHS) | Hold (THS) | Pulse Width (WPWS) | Total Endpoints |
|---|---|---|---|---|---|---|
| Design Global | +0.055 ns | 0.000 ns | +0.010 ns | 0.000 ns | +0.333 ns | 329,103 |
| `clk100_raw` (125 MHz) | +0.055 ns | 0.000 ns | +0.010 ns | 0.000 ns | +2.500 ns | 326,545 |
| `clk125_raw` (125 MHz) | +0.992 ns | 0.000 ns | +0.044 ns | 0.000 ns | +3.280 ns | 412 |
| `rgmii_rx` (125 MHz) | +0.383 ns | 0.000 ns | +0.020 ns | 0.000 ns | +3.222 ns | 479 |
| `cal_clk_raw` (333.3 MHz) | +2.447 ns | 0.000 ns | +0.035 ns | 0.000 ns | +0.333 ns | 31 |
| `rgmii_tx` (125 MHz phase) | +0.101 ns | 0.000 ns | +0.112 ns | 0.000 ns | - | 5 |
| `**async_default**` | +0.770 ns | 0.000 ns | +0.203 ns | 0.000 ns | - | 1,568 |

## 3. Real Critical Path Bottlenecks (Why looking only at PE is fatal)
Analysis of the 30 worst setup paths in `clk100_raw` reveals that **the PE compute core is NOT the bottleneck limiting frequency at 125 MHz**. Instead, the top failing paths belong to three major infrastructure and address-generation subsystems:

1. **Storage Controller & Fault Logic (`ps_gateway_accelerator_0 / block_engine_l1bank_v020`)**:
   - **Worst Path**: `state_reg[3]/C` -> `bad_reg/D`
   - **Slack**: **+0.055 ns** (Requirement: 8.000 ns, Delay: 7.745 ns).
   - **Logic Levels**: **30** (Logic delay: 5.057 ns [65.3%], Net delay: 2.688 ns [34.7%]).
   - **Primitives**: `CARRY8` x 6, `DSP48E2` x 2 (DSP_ALU x 3, DSP_MULTIPLIER x 2, DSP_OUTPUT x 3), `LUT` x 10.
   - **Root Cause**: Address generation for matrix cache tiling (`block_address_v020`) cascaded through multi-dimensional index multipliers and 48-bit division/modulo, immediately checked by error detection logic (`bad_reg`) in a single cycle.

2. **DDR Layout Engine Coordinate Transformation (`ps_gateway_plans_0 / ddr_layout_engine`)**:
   - **Path**: `cfg_reg[237]/C` -> `source_address1_i_*_psdsp/D`
   - **Slack**: **+0.073 ns ~ +0.141 ns** (Requirement: 8.000 ns, Delay: 7.710 ~ 7.781 ns).
   - **Logic Levels**: **25 ~ 26** (Logic delay: 4.77 ~ 4.87 ns [~63%], Net delay: 2.82 ~ 2.94 ns [~37%]).
   - **Primitives**: `CARRY8` x 7, `DSP48E2` x 2, `LUT` x 4.
   - **Root Cause**: `source_address <= src + source_index * bytes;` where `source_index` computes multi-dimensional convolution/stride coordinates `(({kernel_channel}*ih + input_y)*iw + input_x)` without stage registers.

3. **DDR Vector Engine Arithmetic Unit (`ps_gateway_plans_0 / ddr_vector_engine / asr_fp32_alu`)**:
   - **Path**: Vector ALU state machine & non-restoring divider/root core
   - **Slack**: **+0.212 ns ~ +0.331 ns** (Requirement: 8.000 ns, Delay: 7.550 ~ 7.664 ns).
   - **Logic Levels**: **31 ~ 32** (Logic delay: 3.21 ~ 3.29 ns, Net delay: 4.26 ~ 4.39 ns).
   - **Primitives**: Deep iterative carry loops across `root_rem_reg` and ALU operand formatting.

## 4. CDC & Constraint Audit
- **Check Timing (`check_timing.rpt`)**:
  - `no_output_delay`: Exactly 1 port (`phy_tx_clk`). The RGMII TX clock is forwarded without output delay constraint; it relies on internal MMCM phase shift (90 degrees).
  - Combinational loops: 0. Unconstrained internal endpoints: 0.
- **CDC Report (`cdc.rpt`)**:
  - **CDC-6 Warning (Multi-bit with ASYNC_REG)**: `rd_ptr_gray_reg_reg[11:0]` in `rx_fifo` and `tx_fifo`. Constrained with `set_max_delay -datapath_only 8.000` and bus skew requirement (8.000 ns).
  - **CDC-15 Warning (Clock enable controlled CDC, Depth 0)**: 26 endpoints (`wr_ptr_sync_commit_reg_reg[0..12]`). Pointers are synchronized across domains without multi-flop synchronizers, gated only by commit handshake signals.
  - **Frequency Scaling Implication**: If PL frequency is raised to 300 MHz or 600 MHz, the 8.000 ns CDC datapath and bus skew constraints MUST be re-calculated, or cross-domain FIFO pointers will suffer metastability and order corruption.

## 5. Independent Empirical Critique of `gemini_compute` Candidates

### Candidate A (`pe_pipeline_cc_v023.sv`)
- **Stated Purpose**: Pipelined Carry-Chain PE splitting Stage 2 into Stage 2A and Stage 2B.
- **Empirical RTL Evidence**:
  - In `pe_direct_v020.sv`, Stage 2 performed:
    1. Variable barrel shift (`{12'd0, raw1} << p1`)
    2. Saturation subtract (`aligned - (sat1 ? {16'd0, mag1} : 32'd0)`)
    3. Conditional negate (`neg1 ? -$signed(magnitude) : $signed(magnitude)`)
  - In `pe_pipeline_cc_v023.sv`:
    - Stage 2A contains:
      ```verilog
      wire [31:0] aligned = {12'd0, raw1} << p1;
      wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);
      reg [31:0] magnitude2a;
      ```
    - Stage 2B contains:
      ```verilog
      product2b <= neg2a ? -$signed(magnitude2a) : $signed(magnitude2a);
      ```
  - **Critical Finding**: **Barrel shift and saturation subtraction remain coupled in Stage 2A!**
    - The 4-bit barrel shifter (multiplexing 20 bits into 32 bits based on `p1[3:0]`) immediately feeds into a 32-bit subtractor before being registered into `magnitude2a`.
    - At 125 MHz / 150 MHz, this passes easily. At 300 MHz (3.333 ns), it can fit within ~1.5 ns.
    - However, at **600 MHz (1.667 ns budget)**, clock uncertainty (~0.15 ns) + register setup/clock-to-out (~0.12 ns) leaves only ~1.4 ns data budget. The cascaded shifter + 32-bit carry chain + net delays (~1.55 ns) **will violate setup**.
    - Stage 2A must be split into separate Shift and Saturation stages for 600 MHz operation.

### Candidate B (`pe_pipeline_csa_v023.sv`)
- **Stated Purpose**: Dual-Rail CSA PE eliminating the 48-bit feedback carry chain with a 3:2 Carry-Save Accumulator.
- **Empirical RTL Evidence**:
  - Inside the PE accumulation loop:
    ```verilog
    wire [47:0] csa_sum   = sum_s ^ sum_c ^ p48;
    wire [47:0] csa_carry = ((sum_s & sum_c) | (sum_s & p48) | (sum_c & p48)) << 1;
    ```
    This successfully reduces the accumulation loop delay to a single LUT3 level (~0.25 ns).
  - **HOWEVER**, at the module boundary:
    ```verilog
    assign sum = $signed(sum_s + sum_c);
    ```
    - `sum` is driven combinatorially by a 48-bit Carry Propagate Adder (CPA).
    - In `array16_pipeline_v023.sv`, `sum` is connected to top-level `sums[(r*16+c)*48 +: 48]`.
    - In `block_engine_l1bank_v020.sv`, `sums` is sampled by:
      ```verilog
      c_add = c_old + $signed({sums[(collect+lane)*48+47], sums[(collect+lane)*48+:48]});
      collected_values[lane*48+:48] = c_add[47:0];
      ```
  - **Critical Finding**:
    1. **Unregistered CPA Output**: `sum` is NOT registered at the CPA output. It remains a purely combinational net.
    2. **Cascaded Upper-Level Adder**: When `block_engine_l1bank_v020` collects results, the combinational CPA adder (`sum_s + sum_c`) is **directly cascaded** through a 256:4 multiplexer into a **second 49-bit adder** (`c_old + sums`) before being written to BRAM!
    3. **Continuous Switching Power**: Because `sum = sum_s + sum_c` is an unclocked combinational assignment, all 256 CPAs (12,288 full adders) toggle dynamically on every cycle of compute, even though `sum` is only read out during the `COLLECT` state.
    4. **False Speedup at System Level**: While the inner feedback loop within the PE is theoretically relieved of carry propagation, the CPA latency is pushed directly onto the collection/writeback path. Without adding an output register or keeping dual-rail format up to the BRAM cache, the CPA remains a critical combinational path sampled by the upper layer.
