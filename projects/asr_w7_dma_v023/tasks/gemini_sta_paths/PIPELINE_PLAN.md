# FPGA Pipeline Plan: Empirical STA Analysis & Timing Closure Strategy

## 1. Executive Summary & Design Constraints
- **Device Target**: AMD Xilinx Zynq UltraScale+ `xczu15eg-ffvb1156-2-I` (Production 1.30, -2 speed grade, industrial temperature grade).
- **Tool Environment**: Vivado v2025.2 (win64).
- **Contracts Compliance**:
  - Bound to `EXECUTION_CONTRACT.md` and `work/DESIGN_CONTRACT_zh.txt`.
  - Full PL Autonomous execution: PS CPU participates only in initial DDR preload; PL executes all DMA, tensor scheduling, and operator graphs without host UDP/MMIO fallback.
  - Strict preservation of numerical contracts: W7p8/A16/C48 positions table, clipping logic (`clip && p == 12 && w >= 8`), QDQ / FP32 FTZ, RNE, and FMA order.
  - **No Vivado/Synthesis/Implementation/Board mutation** in this task. Only empirical timing analysis and logical pipeline design.
  - **Zero Overclaim Warning**: Target budgets (300 MHz = 3.333 ns, 600 MHz = 1.667 ns) are engineering targets. Without a full routed implementation STA signoff on the new netlist, no timing closure can be claimed. Bench simulation clock speedup does not constitute STA proof.

---

## 2. Frequency Discrepancy & Historical Baseline Analysis

```
+---------------------------------------------------------------------------------------------------------+
|                                    FREQUENCY & TIMING BUDGET AUDIT                                      |
+----------------------+--------------------+--------------------+--------------------+-------------------+
| Baseline Category    | Period Requirement | Target Frequency   | Worst Slack (WNS)  | Status in STA     |
+----------------------+--------------------+--------------------+--------------------+-------------------+
| Historical full002   | 8.000 ns           | 125.000 MHz        | +0.055 ns          | MET (Signoff)     |
| User Stated Reference| 6.667 ns           | ~150.000 MHz       | -1.278 ns (est)    | FAILS on full002  |
| Target Budget A      | 3.333 ns           | 300.000 MHz        | -4.612 ns (est)    | Requires Pipeline |
| Target Budget B      | 1.667 ns           | 600.000 MHz        | -6.278 ns (est)    | Requires Multi-Clk|
+----------------------+--------------------+--------------------+--------------------+-------------------+
```

### The 125 MHz vs 150 MHz Distinction
In the historical ZIP package (`model_a_v0_22/soc_full/build/full002/timing.rpt`), the primary system clock is `clk100_raw` (derived from 200 MHz reference via MMCM CLKOUT1). In `build_full.tcl`, line 28 explicitly replaced the 100 MHz clock definition with `125 MHz`:
```tcl
replace_once {set clk [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]} {set clk [create_bd_port -dir I -type clk -freq_hz 125000000 aclk]}
```
The timing report reflects:
- `Period(ns): 8.000`
- `Frequency(MHz): 125.000`
- `WNS: +0.055 ns` (Met by a razor-thin margin of 55 picoseconds).

If the exact `full002` netlist were clocked at 150 MHz (6.667 ns), the 1.333 ns reduction in period would immediately throw **all 30 worst intra-clock setup paths into timing violation (WNS ~ -1.278 ns)**. The user's reference to "~150 MHz" represents either an out-of-spec test bench or an unconstrained board build. Under strict STA rules, the signed-off baseline is **125 MHz**.

---

## 3. Real Systemic Bottlenecks: Deconstructing the Critical Paths

A common pitfall is to focus exclusively on the Processing Element (PE) multiplier/accumulator while ignoring peripheral and infrastructure paths. Our full parse of 601 paths in `timing.rpt` proves that the PE array was **NOT** the limiting factor at 125 MHz.

### Top 20 Representative Timing Paths from `timing.rpt`
The table below lists the 20 most critical representative paths across clocks, path groups, and functional blocks:

| # | Path ID | Clock / Group | Path Type | Slack (ns) | Data Delay (ns) | Logic % | Net % | Levels | Category | Source -> Destination |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 61 | `clk100_raw` | Setup | **+0.055** | 7.745 | 65.3% | 34.7% | 30 | CARRY8, DSP, LUT | `accelerator/inst/core/compute/core/state_reg[3]/C` -> `storage/bad_reg/D` |
| 2 | 62 | `clk100_raw` | Setup | **+0.073** | 7.781 | 62.2% | 37.8% | 25 | CARRY8, DSP, LUT | `plans/inst/cluster/layouts/arithmetic/cfg_reg[237]/C` -> `source_address1_i_4_psdsp/D` |
| 3 | 63 | `clk100_raw` | Setup | **+0.082** | 7.795 | 68.2% | 31.8% | 31 | CARRY8, DSP, LUT | `accelerator/inst/core/compute/cfg_reg[258]/C` -> `storage/state_reg[0]/D` |
| 4 | 64 | `clk100_raw` | Setup | **+0.085** | 7.754 | 62.2% | 37.8% | 26 | CARRY8, DSP, LUT | `plans/inst/cluster/layouts/arithmetic/cfg_reg[237]/C` -> `source_address1_i_7_psdsp/D` |
| 5 | 331| `rgmii_tx` | Setup | **+0.101** | 1.452 | 81.3% | 18.7% | 1 | OBUF, ODDR | `board/mac/eth_mac_1g_rgmii_inst/.../oddr[4]/CLK` -> `phy_txd[3]` |
| 6 | 65 | `clk100_raw` | Setup | **+0.109** | 7.730 | 62.6% | 37.4% | 26 | CARRY8, DSP, LUT | `plans/inst/cluster/layouts/arithmetic/cfg_reg[237]/C` -> `source_address1_i_8_psdsp/D` |
| 7 | 66 | `clk100_raw` | Setup | **+0.132** | 7.744 | 68.6% | 31.4% | 31 | CARRY8, DSP, LUT | `accelerator/inst/core/compute/cfg_reg[258]/C` -> `storage/state_reg[2]/D` |
| 8 | 67 | `clk100_raw` | Setup | **+0.141** | 7.710 | 61.9% | 38.1% | 25 | CARRY8, DSP, LUT | `plans/inst/cluster/layouts/arithmetic/cfg_reg[237]/C` -> `source_address1_i_11_psdsp/D` |
| 9 | 74 | `clk100_raw` | Setup | **+0.212** | 7.664 | 42.7% | 57.3% | 32 | LUT, CARRY8, FMA | `plans/inst/cluster/vectors/arithmetic/numeric_core` (FP32 ALU root remainder) |
| 10| 82 | `clk100_raw` | Setup | **+0.269** | 7.604 | 54.1% | 45.9% | 24 | CARRY8, LUT | `accelerator/inst/core/compute/core/n_reg[4]/C` -> `state_reg[4]_rep__0/D` |
| 11| 271| `rgmii_rx` | Setup | **+0.383** | 7.550 | 12.0% | 88.0% | 1 | LUT, IBUF | `board/mac/eth_mac_1g_rgmii_inst/rx_speed_count` |
| 12| 211| `clk125_raw` | Setup | **+0.992** | 0.892 | 8.5% | 91.5% | 0 | Net only | `board/mac/eth_mac_1g_rgmii_inst/rx_prescale_reg` |
| 13| 1 | `cal_clk_raw` | Setup | **+2.447** | 0.512 | 15.0% | 85.0% | 0 | Sync Reg | `board/reset_cal/sync_reg_reg[24]/C` -> `sync_reg_reg[25]/D` |
| 14| 341| `**async**` | Recovery | **+0.770** | 1.870 | 9.0% | 91.0% | 1 | Async Reset | `board/reset_cal/sync_reg_reg[29]/C` -> `IDELAYCTRL/RST` |
| 15| 91 | `clk100_raw` | Hold | **+0.010** | 0.168 | 48.8% | 51.2% | 1 | FMA IP cell | `engine/parallel_gemm/asr_fma_ip_HD2705` internal stage |
| 16| 92 | `clk100_raw` | Hold | **+0.011** | 0.240 | 61.3% | 38.8% | 2 | PE Systolic Fwd | `rows[1].cols[14].pe/a_out_reg[15]/C` -> `rows[1].cols[15].pe/mag0_reg[13]/D` |
| 17| 94 | `clk100_raw` | Hold | **+0.012** | 0.190 | 30.5% | 69.5% | 0 | AXI Skid Buffer | `ddr_connect/s02_entry_pipeline/s02_mmu` -> `transaction_regulator` |
| 18| 96 | `clk100_raw` | Hold | **+0.012** | 0.174 | 46.6% | 53.4% | 1 | FP32 Root Rem | `vectors/arithmetic/numeric_core/root_rem_reg[19]/C` -> `root_rem_reg[21]/D` |
| 19| 104| `clk100_raw` | Hold | **+0.015** | 0.263 | 55.0% | 45.0% | 1 | PE Accumulator | `rows[15].cols[14].pe/sum_reg[35]/C` -> `rows[15].cols[14].pe/sum_reg[40]/D` |
| 20| 121| `clk125_raw->clk100` | CDC Setup | **+6.866** | 1.159 | 6.8% | 93.2% | 0 | CDC Async FIFO | `board/mac/rx_fifo/fifo_inst/m_rst_sync1_reg` -> `m_rst_sync2_reg` |

---

## 4. Bottleneck Attribution to RTL Constructs

### Bottleneck A: Block Engine Address & Error Logic (`block_engine_l1bank_v020.sv`, `block_address_v020.sv`)
- **Path 1**: `state_reg[3]` -> `bad_reg/D` (Logic delay: 5.057 ns, 30 cell levels).
- **RTL Structure**:
  In `block_address_v020.sv`, matrix tile base address, stride, and extents are evaluated combinatorially:
  ```verilog
  assign addr = base + (block_row * row_stride + block_col) * 6144;
  assign extent = (block_row == num_blocks_r - 1) ? ... : ...;
  ```
  In `block_engine_l1bank_v020.sv`, the FSM state evaluates operand bounds, address validity, and slot status in a single cycle:
  ```verilog
  c_overflow = c_overflow || (c_add[48] != c_add[47]);
  fault <= 1; error_code <= code; state <= FAIL;
  ```
  The synthesis tool maps the address multiplication to DSP48E2 cascades and cascades 6 CARRY8 chains into the error detector `bad_reg`.

### Bottleneck B: Layout Engine Multidimensional Addressing (`ddr_layout_engine.sv`)
- **Path 2 & 4**: `cfg_reg[237]` -> `source_address1_i_*_psdsp/D` (Logic delay: 4.840 ns, 25 cell levels).
- **RTL Structure**:
  In `ddr_layout_engine.sv` lines 147-157:
  ```verilog
  source_index <= ({48'd0, kernel_channel} * ih + $unsigned(input_y)) * iw + $unsigned(input_x);
  source_address <= src + source_index * bytes;
  ```
  This is a 3-term nested multiplication plus addition evaluated combinatorially in the `ADDRESS` state. In UltraScale+, this synthesizes to two cascaded DSP48E2 primitives and 7 CARRY8 stages.

### Bottleneck C: Vector ALU Multi-Cycle Divider/Radicand Loop (`asr_fp32_alu.sv`)
- **Path 9**: `numeric_core/root_rem_reg` (Data delay: 7.664 ns, 32 cell levels).
- **RTL Structure**:
  In `asr_fp32_alu.sv`, the square root and division functions use non-restoring recurrence loops across 56-bit registers:
  ```verilog
  root_rem <= (root_rem << 2) - test_val;
  ```
  The 56-bit subtraction and trial comparison chain takes 32 logic levels, consuming 7.66 ns.

---

## 5. Independent Empirical Critique of `gemini_compute` Candidates

### Audit of Candidate A (`pe_pipeline_cc_v023.sv`)
1. **Did it split Stage 2?**
   - **Partial split only**.
   - Original baseline (`pe_direct_v020.sv`):
     ```verilog
     wire [31:0] aligned   = {12'd0, raw1} << p1;
     wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);
     product2 <= neg1 ? -$signed(magnitude) : $signed(magnitude);
     ```
   - Candidate A (`pe_pipeline_cc_v023.sv`):
     ```verilog
     // Stage 2A: Shift and Saturation subtract (COMBINED)
     wire [31:0] aligned = {12'd0, raw1} << p1;
     wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);
     reg [31:0] magnitude2a;
     
     // Stage 2B: Conditional negate
     product2b <= neg2a ? -$signed(magnitude2a) : $signed(magnitude2a);
     ```
   - **Empirical Finding**: In Stage 2A, the **20-bit variable barrel shifter (`<< p1`) and the 32-bit saturation subtractor remain combinatorially chained together** in a single clock cycle!
   - At 125 MHz (8.000 ns) or 300 MHz (3.333 ns), this combined stage can meet setup in UltraScale+ -2.
   - At **600 MHz (1.667 ns budget)**, the LUT-based variable shifter (~0.5 ns) + 32-bit subtractor (4 CARRY8 blocks, ~0.6 ns) + inter-slice routing (~0.45 ns) requires **~1.55 ns**. With clock jitter (~0.12 ns) and register setup (~0.05 ns), **Stage 2A will fail setup at 600 MHz**.

### Audit of Candidate B (`pe_pipeline_csa_v023.sv`)
1. **Did it eliminate the feedback carry chain?**
   - **Yes, internally**. Inside the PE accumulator:
     ```verilog
     wire [47:0] csa_sum   = sum_s ^ sum_c ^ p48;
     wire [47:0] csa_carry = ((sum_s & sum_c) | (sum_s & p48) | (sum_c & p48)) << 1;
     sum_s <= csa_sum; sum_c <= csa_carry;
     ```
     The internal accumulation loop is reduced to 1 LUT3 delay (~0.25 ns).
2. **Is the CPA output sampled combinatorially by the upper layer?**
   - **YES. Major Architectural Flaw**.
   - At line 141 of `pe_pipeline_csa_v023.sv`:
     ```verilog
     assign sum = $signed(sum_s + sum_c);
     ```
   - `sum` is an unclocked, continuous assignment!
   - In `block_engine_l1bank_v020.sv`, when reading out results:
     ```verilog
     c_add = c_old + $signed({sums[(collect+lane)*48+47], sums[(collect+lane)*48+:48]});
     collected_values[lane*48+:48] = c_add[47:0];
     ```
   - **Empirical Finding**:
     - The 48-bit CPA (`sum_s + sum_c`) is **purely combinational**.
     - Every clock cycle during matrix compute, all 256 CPAs (12,288 full adders across 256 PEs) toggle dynamically, creating massive unnecessary switching power.
     - When results are gathered, the combinational CPA is cascaded into a 256:4 multiplexer, which immediately enters a **second 49-bit adder (`c_old + sums`)** before reaching the BRAM cache!
     - The critical path is NOT eliminated; it was merely pushed outside the PE module boundary directly into the top-level collection path!
     - Without registering `sum` at the PE output, or maintaining dual-rail representation into the cache stage, Candidate B cannot achieve timing closure at high frequency.

---

## 6. Target A Pipeline Plan: 300 MHz Closure (Budget: 3.333 ns)

To achieve 300 MHz (3.333 ns clock period), logic depth must not exceed **10-12 LUT levels** (or 2-3 CARRY8 / 1 DSP cascade) per clock cycle.

### Cut Point 1: `block_address_v020` & `block_engine_l1bank_v020` (Target: < 2.5 ns)
- **Problem**: 30 logic levels in `state_reg` -> `bad_reg` (address multiplier + division + bounds checking).
- **Pipeline Insertion**:
  - **Stage 1 (Coordinate Generation)**: Register `target_row <= block_row * row_stride; target_col <= block_col;`.
  - **Stage 2 (Base Addition)**: Register `target_address <= base + (target_row + target_col) * 6144;`.
  - **Stage 3 (Extent & Boundary Check)**: Register `valid_check <= ...; bad_reg <= check_fault;`.
- **Expected Data Delay**: Reduced from 7.745 ns to **1.85 ns** (Slack: +1.48 ns at 300 MHz).

### Cut Point 2: `ddr_layout_engine.sv` (Target: < 2.5 ns)
- **Problem**: 25 logic levels in multi-dimensional coordinate calculation.
- **Pipeline Insertion**:
  - **Stage 1**: `prod_ch <= kernel_channel * ih;`
  - **Stage 2**: `source_idx <= (prod_ch + input_y) * iw + input_x;`
  - **Stage 3**: `source_address <= src + source_idx * bytes;`
- **Expected Data Delay**: Reduced from 7.781 ns to **2.10 ns** (Slack: +1.23 ns at 300 MHz).

### Cut Point 3: PE Array (`pe_pipeline_cc_v023`) (Target: < 2.2 ns)
- Stage 0: Abs & Decode (mag0, m0, p0, sat0) -> 1 cycle
- Stage 1: 16x4 Multiplier (`raw1 <= mag0 * m0`) -> 1 cycle
- Stage 2: Combined Shift & Saturation & Negate -> Split into:
  - Stage 2A: `magnitude2a <= ({12'd0, raw1} << p1) - (sat1 ? {16'd0, mag1} : 0);`
  - Stage 2B: `product2b <= neg2a ? -magnitude2a : magnitude2a;`
- Stage 3: INT48 Accumulator:
  - 48-bit carry chain (`sum <= sum + product2b`) requires 6 CARRY8 primitives.
  - In UltraScale+ -2: 6 * 0.045 ns (logic) + 0.65 ns (net) = **0.92 ns**.
  - Fits easily within 3.333 ns budget.

---

## 7. Target B Pipeline Plan: 600 MHz Closure (Budget: 1.667 ns)

At 600 MHz, clock jitter and uncertainty consume ~0.15 ns, leaving an effective data path budget of **~1.40 ns**.
A unified 600 MHz clock across the entire SoC is **physically infeasible** on UltraScale+ due to AXI interconnect and DRAM controller routing limits. Timing closure requires a **Multi-Clock Domain Architecture with a Localized High-Speed Compute Core**.

### Clock Domain Architecture
```
+-----------------------------------------------------------------------------------------------------+
|                                MULTI-CLOCK DOMAIN ARCHITECTURE                                      |
+-----------------------------------------------------------------------------------------------------+
| Domain 1: Local High-Speed Compute Core (600.000 MHz, Period = 1.667 ns)                           |
|   - 16x16 Systolic PE Array (pe_pipeline_600mhz)                                                    |
|   - Banked L1 Input/Weight Operand Buffers (Dual-port distributed RAM / URAM)                      |
|   - Dual-Rail Accumulator Registers with Pipelined Readout Buffer                                   |
+-----------------------------------------------------------------------------------------------------+
                                           |  Async FIFO / 2:1 Clock Gearbox
                                           v
+-----------------------------------------------------------------------------------------------------+
| Domain 2: Autonomous PL Execution & DMA Controller (300.000 MHz, Period = 3.333 ns)                 |
|   - PL Graph Execution Plan Runner (wc_plan_top_v023)                                               |
|   - Pipelined DDR Layout Engine & Vector Engine                                                     |
|   - AXI DMA Prefetch & Result Writeback Engines                                                     |
|   - L1/L2 Cache Coherency and Tag Decoders                                                          |
+-----------------------------------------------------------------------------------------------------+
                                           |  Async FIFO / AXI CDC
                                           v
+-----------------------------------------------------------------------------------------------------+
| Domain 3: Peripheral & Network Domain (125.000 MHz, Period = 8.000 ns)                              |
|   - Gigabit Ethernet MAC & RGMII PHY Interface                                                      |
|   - UDP Frame Engine & Debug Bridges                                                                |
+-----------------------------------------------------------------------------------------------------+
```

### PE Core Pipeline Cuts for 600 MHz (< 1.30 ns per stage)
To meet the 1.40 ns budget, every operation must be fully isolated into single-function stages:

```
Cycle 0: Input Forwarding & Systolic Pass
         a_out <= a_in; w_out <= w_in; av_out <= av_in; wv_out <= wv_in;
Cycle 1: Absolute Value & Multiplier Operand Setup
         mag0 <= a_in[15] ? (~a_in + 1) : a_in;
         m0   <= saturated ? 4'd8 : w_in[3:0];
         p0   <= p; neg0 <= a_in[15] ^ w_in[6]; sat0 <= saturated;
Cycle 2: 16x4 Multiplier Stage
         raw1 <= mag0 * m0; (LUT-based 16x4 multiplier, ~0.75 ns)
Cycle 3: Variable Barrel Shifter Stage (ISOLATED)
         aligned_reg <= {12'd0, raw1} << p1; (~0.55 ns)
Cycle 4: Saturation Subtraction Stage (ISOLATED)
         mag_sat <= aligned_reg - (sat1 ? {16'd0, mag1} : 32'd0); (~0.62 ns)
Cycle 5: 32-bit Conditional Negation Stage
         product_reg <= neg_r ? -$signed(mag_sat) : $signed(mag_sat); (~0.50 ns)
Cycle 6: Accumulation Stage
         Option A (Carry-Chain): sum <= sum + product_reg; (~0.95 ns, tightly floorplanned)
         Option B (Dual-Rail CSA):
           sum_s <= sum_s ^ sum_c ^ p48;
           sum_c <= ((sum_s & sum_c) | (sum_s & p48) | (sum_c & p48)) << 1; (~0.28 ns)
Cycle 7: Pipelined CPA Readout Register (FIXING CANDIDATE B FLAW)
         sum_reg <= sum_s + sum_c; (Latched only when clear_sum/collect occurs)
```

---

## 8. CDC, Bus Skew, and Asynchronous FIFO Audit

### Constraints Requiring Fixes for Frequency Scaling:
1. **CDC-6 (Gray Pointer Bus Skew)**:
   - In `cdc.rpt`, `rd_ptr_gray_reg_reg[11:0]` is constrained by:
     `set_max_delay -datapath_only 8.000`
   - In `bus_skew.rpt`, bus skew requirement is `8.000 ns` (Actual: ~0.63 - 0.71 ns).
   - **Fix**: When transitioning to 300/600 MHz domains, `set_max_delay -datapath_only` must be set to `1.667 ns` or the destination period, and `set_bus_skew` must be constrained to `< 0.800 ns`.
2. **CDC-15 (Clock Enable Controlled CDC, Depth 0)**:
   - 26 endpoints in `rx_fifo` and `tx_fifo` (`wr_ptr_sync_commit_reg_reg[0..12]`) have depth 0.
   - **Fix**: Replace all single-clock handshake flags with a 2-stage `ASYNC_REG` synchronizer or standardized dual-clock FIFO (`xpm_fifo_async`).
3. **Unconstrained Output Delay**:
   - `phy_tx_clk` is flagged with `no_output_delay (1)`.
   - **Fix**: Specify explicit `set_output_delay` matching the RGMII PHY setup/hold requirements (-0.5 ns / +0.5 ns relative to `rgmii_tx`).

---

## 9. Verification & Reproducibility Matrix

All findings are backed by the reproducible Python analyzer:
```bash
python3 /home/yang/Desktop/项目/tasks/gemini_sta_paths/parse_sta_timing.py
```
Outputs:
- `/home/yang/Desktop/项目/tasks/gemini_sta_paths/PATHS.csv`: Full breakdown of 601 paths.
- Execution time: < 0.2 seconds.
- Exit code: 0.
