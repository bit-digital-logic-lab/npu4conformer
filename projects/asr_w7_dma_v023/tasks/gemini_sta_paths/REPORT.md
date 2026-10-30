# Empirical Timing Path Analysis & Pipeline Strategy Report

## 1. Project Background & Constraints Mandate

This report provides the empirical static timing analysis (STA) and architectural pipeline strategy for the FPGA tensor processor design, adhering strictly to the contract instructions:
- **Device & Target Family**: AMD Xilinx Zynq UltraScale+ `xczu15eg-ffvb1156-2-I` (Production 1.30, -2 speed grade, industrial grade).
- **Execution Mandate**: Bound to `EXECUTION_CONTRACT.md` and `work/DESIGN_CONTRACT_zh.txt`.
  - Host PS participates only once at the beginning to preload weights, inputs, and execution plans to DDR.
  - PL autonomously drives all DDR DMA, tensor operations, and intermediate residency/writebacks without PS CPU intervention or UDP queries.
  - W7p8/A16/C48 quantization, clipping (`clip && p == 12 && w >= 8`), and FP32 FTZ/RNE/FMA precision rules strictly preserved.
  - **Zero Synthesis / Zero Implementation / Zero Board Operations**: Strictly logical verification and empirical analysis. No Vivado runs, no git pushes.
  - **Zero Overclaim Mandate**: Target clock frequencies (300 MHz / 3.333 ns, 600 MHz / 1.667 ns) are engineering targets. Without a newly routed STA signoff report, timing closure cannot be declared. Faster simulation clock periods do not constitute timing proof.

---

## 2. Frequency Baseline Distinction: 125 MHz vs. 150 MHz

A primary finding is the clarification between historical signoff and user reference:
1. **Historical Package Baseline (`full002`)**:
   - Clock name: `clk100_raw` (derived from 200 MHz differential input on AL8 via MMCM CLKOUT1).
   - Constrained Period: **8.000 ns (125.000 MHz)**.
   - WNS (Worst Negative Slack): **+0.055 ns** (MET).
   - TNS: 0.000 ns across 326,545 endpoints.
2. **User Reference ("~150 MHz")**:
   - Period: **6.667 ns (150.000 MHz)**.
   - Delta from baseline: -1.333 ns.
3. **Empirical Fact**:
   - If the `full002` routed netlist is operated at 150 MHz, **100% of the 30 reported setup paths in `clk100_raw` fail timing**, with WNS dropping to **-1.278 ns**.
   - Therefore, the user reference of "~150 MHz" represents either an unverified board overclock or an unconstrained bench run. All formal pipeline cuts must start from the empirical 125 MHz signoff netlist.

---

## 3. Global STA Summary & Classification Breakdown

Parsing `timing_baseline/timing.rpt` (3.6 MB, 42,149 lines) yielded **601 distinct reported paths**.

### 3.1 Timing Summary by Clock Domain
| Clock Domain | Frequency | Period | WNS (ns) | TNS (ns) | WHS (ns) | THS (ns) | WPWS (ns) | Endpoints |
|---|---|---|---|---|---|---|---|---|
| `clk100_raw` (PL Main Core) | 125.0 MHz | 8.000 ns | +0.055 | 0.000 | +0.010 | 0.000 | +2.500 | 326,545 |
| `clk125_raw` (Ethernet MAC) | 125.0 MHz | 8.000 ns | +0.992 | 0.000 | +0.044 | 0.000 | +3.280 | 412 |
| `rgmii_rx` (PHY Ingress) | 125.0 MHz | 8.000 ns | +0.383 | 0.000 | +0.020 | 0.000 | +3.222 | 479 |
| `cal_clk_raw` (Delay Cal) | 333.3 MHz | 3.000 ns | +2.447 | 0.000 | +0.035 | 0.000 | +0.333 | 31 |
| `rgmii_tx` (PHY Egress Phase) | 125.0 MHz | 8.000 ns | +0.101 | 0.000 | +0.112 | 0.000 | - | 5 |
| `**async_default**` (Async Reset)| - | - | +0.770 | 0.000 | +0.203 | 0.000 | - | 1,568 |

### 3.2 Cell & Category Distribution Across All 601 Paths
- **CARRY8 Carry Chains**: 36 paths
- **DSP48E2 Multiplier / ALU Blocks**: 49 paths
- **Reset Pins / Asynchronous Recovery / Removal**: 222 paths
- **Clock Enable (`/CE`, `/GE`) Endpoints**: 37 paths
- **FMA / Floating Point ALU Core**: 50 paths
- **Wide Multiplexers (`MUXF7`, `MUXF8`)**: 1 path
- **Shift Registers (`SRLC32E`, `SRL16E`)**: 2 paths

---

## 4. Top 20 Representative Paths & Bottleneck Analysis

Below are the 20 most critical representative paths extracted by our automated analyzer:

```
+-----+---------+---------------+-------+----------+-----------+--------+-------------------------------------------------------------+
| ID  | Grp     | Type          | Slack | Delay(ns)| Logic/Net | Levels | Functional Endpoint / Bottleneck                            |
+-----+---------+---------------+-------+----------+-----------+--------+-------------------------------------------------------------+
| 61  | clk100  | Setup (Max)   | +0.055| 7.745    | 65%/35%   | 30     | accelerator: state_reg[3] -> storage/bad_reg/D (Worst WNS)  |
| 62  | clk100  | Setup (Max)   | +0.073| 7.781    | 62%/38%   | 25     | plans: layouts cfg_reg[237] -> source_address1_i_4_psdsp    |
| 63  | clk100  | Setup (Max)   | +0.082| 7.795    | 68%/32%   | 31     | accelerator: cfg_reg[258] -> storage/state_reg[0]/D         |
| 64  | clk100  | Setup (Max)   | +0.085| 7.754    | 62%/38%   | 26     | plans: layouts cfg_reg[237] -> source_address1_i_7_psdsp    |
| 331 | rgmii_tx| Setup (Max)   | +0.101| 1.452    | 81%/19%   | 1      | board/mac: data_oddr_inst/oddr[4] -> phy_txd[3]             |
| 65  | clk100  | Setup (Max)   | +0.109| 7.730    | 63%/37%   | 26     | plans: layouts cfg_reg[237] -> source_address1_i_8_psdsp    |
| 66  | clk100  | Setup (Max)   | +0.132| 7.744    | 69%/31%   | 31     | accelerator: cfg_reg[258] -> storage/state_reg[2]/D         |
| 67  | clk100  | Setup (Max)   | +0.141| 7.710    | 62%/38%   | 25     | plans: layouts cfg_reg[237] -> source_address1_i_11_psdsp   |
| 74  | clk100  | Setup (Max)   | +0.212| 7.664    | 43%/57%   | 32     | plans: vectors arithmetic numeric_core (FP32 ALU root_rem)  |
| 82  | clk100  | Setup (Max)   | +0.269| 7.604    | 54%/46%   | 24     | accelerator: compute core n_reg[4] -> state_reg[4]_rep      |
| 271 | rgmii_rx| Setup (Max)   | +0.383| 7.550    | 12%/88%   | 1      | board/mac: eth_mac_1g_rgmii_inst/rx_speed_count             |
| 211 | clk125  | Setup (Max)   | +0.992| 0.892    | 9%/91%    | 0      | board/mac: eth_mac_1g_rgmii_inst/rx_prescale_reg            |
| 1   | cal_clk | Setup (Max)   | +2.447| 0.512    | 15%/85%   | 0      | board/reset_cal: sync_reg_reg[24] -> sync_reg_reg[25]       |
| 341 | async   | Recovery      | +0.770| 1.870    | 9%/91%    | 1      | board/reset_cal: sync_reg[29] -> IDELAYCTRL/RST             |
| 91  | clk100  | Hold (Min)    | +0.010| 0.168    | 49%/51%   | 1      | engine/parallel_gemm: asr_fma_ip_HD2705 (Worst WHS)         |
| 92  | clk100  | Hold (Min)    | +0.011| 0.240    | 61%/39%   | 2      | accelerator: array rows[1].cols[14] a_out -> cols[15] mag0  |
| 94  | clk100  | Hold (Min)    | +0.012| 0.190    | 31%/69%   | 0      | ddr_connect: s02_mmu -> transaction_regulator skid buffer   |
| 96  | clk100  | Hold (Min)    | +0.012| 0.174    | 47%/53%   | 1      | plans: vectors numeric_core root_rem_reg[19] -> [21]         |
| 104 | clk100  | Hold (Min)    | +0.015| 0.263    | 55%/45%   | 1      | accelerator: array rows[15].cols[14] sum_reg[35] -> [40]    |
| 121 | clk125->| CDC Setup     | +6.866| 1.159    | 7%/93%    | 0      | board/mac: rx_fifo m_rst_sync1_reg -> m_rst_sync2_reg       |
+-----+---------+---------------+-------+----------+-----------+--------+-------------------------------------------------------------+
```

### Critical Architectural Finding
**The PE array was NOT the critical path at 125 MHz.** The paths that fail first upon frequency scaling belong to:
1. **Matrix Storage Controller & Bounds Checker (`block_engine_l1bank_v020.sv`)**: 30 logic levels, 7.745 ns delay. Multi-dimensional block address generation (`block_address_v020.sv`) feeding into error/overflow status (`bad_reg`) in a single cycle.
2. **DDR Layout Engine (`ddr_layout_engine.sv`)**: 25-26 logic levels, 7.781 ns delay. Multi-term nested address multiplication (`({kernel_channel}*ih + input_y)*iw + input_x`) feeding `source_address1_i_*_psdsp`.
3. **Vector Arithmetic Unit (`asr_fp32_alu.sv`)**: 32 logic levels, 7.664 ns delay. Non-restoring divider and iterative square root recurrence loop.

---

## 5. Constraint Gaps & CDC Analysis

1. **Unconstrained Outputs (`check_timing.rpt`)**:
   - `phy_tx_clk` is reported under `checking no_output_delay (1)`.
   - RGMII TX clock forwarding is not constrained relative to board skew, relying on internal MMCM 90-degree phase shift.
2. **CDC Warnings (`cdc.rpt`)**:
   - **CDC-6 (Multi-bit with ASYNC_REG)**: 2 occurrences (`rd_ptr_gray_reg_reg[11:0]`). Maximum delay datapath only constraint is 8.000 ns; bus skew requirement is 8.000 ns.
   - **CDC-15 (Clock-enable controlled CDC, Depth 0)**: 26 occurrences (`wr_ptr_sync_commit_reg_reg[0..12]`). Pointer syncs rely on handshake flags without multi-flop synchronizers.
3. **Frequency Scaling Implication**:
   - As PL frequency increases from 125 MHz to 300/600 MHz, the 8.000 ns max delay datapath constraint is invalid. It must be replaced with `1.667 ns` and bus skew tightened to `< 0.800 ns`.

---

## 6. Independent Empirical Critique of `gemini_compute` Candidates

We conducted an independent code and structural audit of the two candidate modules in `tasks/gemini_compute/candidate/`:

### Candidate A: `pe_pipeline_cc_v023.sv` (Carry-Chain Pipeline)
- **Claim**: Solves the critical path of `pe_direct_v020` by splitting Stage 2 into Stage 2A and Stage 2B.
- **Structural Evidence**:
  In `pe_pipeline_cc_v023.sv` lines 49-53:
  ```verilog
  wire [31:0] aligned   = {12'd0, raw1} << p1;
  wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);
  reg [31:0]  magnitude2a;
  ```
- **Finding**: **Barrel shift and saturation subtraction are NOT separated**.
  - A 4-bit barrel shifter (multiplexing 20 bits into 32 bits based on `p1[3:0]`) feeds directly into a 32-bit subtractor in Stage 2A.
  - Only the conditional negate was deferred to Stage 2B (`product2b <= neg2a ? -magnitude2a : magnitude2a;`).
  - At 600 MHz (1.667 ns budget, ~1.40 ns effective data budget), the shifter (~0.55 ns) + 32-bit subtractor (~0.62 ns) + net delays (~0.45 ns) requires **~1.62 ns**.
  - **Verdict**: Candidate A cannot close timing at 600 MHz unless Stage 2A is split into isolated Shift and Saturation stages.

### Candidate B: `pe_pipeline_csa_v023.sv` (Dual-Rail CSA Pipeline)
- **Claim**: Replaces the 48-bit feedback carry chain with a 3:2 Carry-Save Accumulator (zero carry propagation).
- **Structural Evidence**:
  In `pe_pipeline_csa_v023.sv` lines 139-141:
  ```verilog
  // CPA (Carry Propagate Adder) resolving sum_s + sum_c
  // Evaluated outside the accumulation feedback critical loop.
  assign sum = $signed(sum_s + sum_c);
  ```
  In `array16_pipeline_v023.sv` line 66:
  ```verilog
  pe_pipeline_csa_v023 u_pe ( ... .sum(sums[(r*16+c)*48 +: 48]) );
  ```
  In `block_engine_l1bank_v020.sv` lines 76-77:
  ```verilog
  c_add = c_old + $signed({sums[(collect+lane)*48+47], sums[(collect+lane)*48+:48]});
  collected_values[lane*48+:48] = c_add[47:0];
  ```
- **Finding**: **The CPA output is unclocked and sampled combinatorially by the upper layer every cycle.**
  1. `assign sum = $signed(sum_s + sum_c);` is purely combinational.
  2. All 256 CPAs (12,288 full adders across 256 PEs) toggle dynamically on every cycle of compute, causing massive wasted switching power.
  3. When collecting results, the combinational CPA output flows through a 256:4 multiplexer into a **second 49-bit adder (`c_old + sums`)** before reaching the BRAM cache!
  4. **Verdict**: Candidate B merely pushed the carry-propagation delay outside the PE boundary into the memory collection interface. Without pipelining `sum` at the readout stage, it creates a severe system-level critical path.

---

## 7. Multi-Frequency Pipeline Closure Plan

### 7.1 Target A: 300 MHz Closure (Budget: 3.333 ns, Margin >= 0.5 ns)
1. **`block_address_v020` / `block_engine_l1bank_v020`**:
   - Insert 2 pipeline stages: Stage 1 registers `(block_row * stride + block_col)`, Stage 2 registers `base + index * 6144`, Stage 3 evaluates `bad_reg`. Logic levels drop from 30 to 8 (~1.8 ns).
2. **`ddr_layout_engine.sv`**:
   - Insert 2 pipeline stages: Stage 1 registers channel stride product, Stage 2 registers multi-dimensional coordinate sum, Stage 3 registers `source_address`. Logic levels drop from 25 to 7 (~1.9 ns).
3. **PE Core**:
   - Use enhanced 4-stage carry-chain pipeline. The 48-bit carry chain (6 CARRY8s) in UltraScale+ -2 takes ~0.92 ns, fitting well inside 3.333 ns.

### 7.2 Target B: 600 MHz Closure (Budget: 1.667 ns, Effective Data Budget ~1.40 ns)
1. **Clock Domain Boundary**:
   - A single chip-wide 600 MHz clock is physically infeasible due to AXI interconnect and DDR controller limits.
   - Partition into **Local 600 MHz Compute Core** (PE array + L1 ping-pong buffers) and **300 MHz Controller Domain** (PL execution runner, layout engine, vector ALU, AXI DMA).
2. **PE Internal 6-Stage Pipeline Cuts**:
   - Cycle 1: `mag0 <= abs(a_in)`, `m0 <= saturated ? 8 : w[3:0]`, `neg0 <= sign`, `sat0 <= saturated`
   - Cycle 2: `raw1 <= mag0 * m0` (16x4 multiplier, ~0.70 ns)
   - Cycle 3: `aligned <= {12'd0, raw1} << p1` (isolated 4-bit barrel shifter, ~0.50 ns)
   - Cycle 4: `magnitude <= aligned - (sat ? mag : 0)` (isolated 32-bit subtractor, ~0.60 ns)
   - Cycle 5: `product <= neg ? -magnitude : magnitude` (conditional negate, ~0.45 ns)
   - Cycle 6: Accumulation:
     - If using CSA: `sum_s <= sum_s ^ sum_c ^ p48; sum_c <= (...) << 1;` (~0.25 ns).
     - **Mandatory Readout Register**: `sum_out <= sum_s + sum_c` latched ONLY on readout enable.

---

## 8. Verification & Artifacts Index

All analyses are 100% reproducible via the self-test suite:
```bash
python3 /home/yang/Desktop/项目/tasks/gemini_sta_paths/test_sta_analysis.py
```
Outputs and logs:
- `tasks/gemini_sta_paths/PATHS.csv`: Full database of 601 paths.
- `tasks/gemini_sta_paths/PIPELINE_PLAN.md`: Complete pipeline specifications.
- `tasks/gemini_sta_paths/INTERFACE.md`: Data schemas and CDC boundaries.
- `tasks/gemini_sta_paths/result.json`: Machine-readable results and metrics.
- `tasks/gemini_sta_paths/test.log`: Test log confirming 100% assertions passed.

### Source & Baseline SHA-256 Manifest
- `timing_baseline/timing.rpt`: `43b3449423958db335539997dc95f02df2667ed5ad45703b1f445ff95d10cda1`
- `tasks/gemini_compute/candidate/pe_pipeline_cc_v023.sv`: `2299f225a82f6849d3137bbda7ed505073e5a4d05d6d26796c2f1c02cc065e1e`
- `tasks/gemini_compute/candidate/pe_pipeline_csa_v023.sv`: `d9522e129a735cfe6ed414f4f0541c404370423203c7eda29af4744ac18603e9`
- `tasks/gemini_compute/candidate/array16_pipeline_v023.sv`: `f13ffa68682289d83977b4b87603e1aedf6f7de9717fbb639b399f298be9eb04`
- `work/rtl/pe_direct_v020.sv`: `7b43de74709f53f0212eb6a600c5d84b3c1aea5904c2f0dd1b6e32b300bc0317`
- `work/rtl/block_engine_l1bank_v020.sv`: `0a6f24fc51f79baf4f1ecca0b38a79180b0a56e19470bfdb4bec863b34a09c20`
- `work/rtl/ddr_layout_engine.sv`: `1ebcaaa58a61f23ab298ab901f184894eb230d6225b26779b8dbf97f54722c52`
- `work/rtl/ddr_vector_engine.sv`: `08a642d915f0d0a83d10c156a52c21bc20bd4f69b3ac8c402ca22c094381641d`
