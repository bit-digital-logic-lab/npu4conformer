# Timing Path Analysis & Pipeline Interfaces (INTERFACE.md)

## 1. Overview
This document specifies the software parser interface, data schema for `PATHS.csv`, clock domain boundaries, and hardware interface contracts for the pipelined FPGA system targeting 300 MHz and 600 MHz.

---

## 2. Python Analyzer CLI & Tool Interface

### Script Location
`/home/yang/Desktop/项目/tasks/gemini_sta_paths/parse_sta_timing.py`

### Usage
```bash
python3 /home/yang/Desktop/项目/tasks/gemini_sta_paths/parse_sta_timing.py
```
- **Inputs**:
  - `timing_baseline/timing.rpt` (3.6 MB, 42,149 lines)
  - `timing_baseline/cdc.rpt`
  - `timing_baseline/check_timing.rpt`
  - `timing_baseline/bus_skew.rpt`
- **Outputs**:
  - `tasks/gemini_sta_paths/PATHS.csv` (CSV formatted list of 601 paths)
- **Exit Code**: `0` on success.

---

## 3. Data Dictionary: `PATHS.csv`

The generated `PATHS.csv` contains 28 columns for every timing path extracted from `timing.rpt`:

| Column Name | Type | Description |
|---|---|---|
| `path_id` | Integer | Path index (1 to 601) corresponding to appearance order in `timing.rpt` |
| `clock` | String | Governing clock name (`clk100_raw`, `clk125_raw`, `cal_clk_raw`, `rgmii_rx`, etc.) |
| `path_group` | String | Vivado timing path group (`clk100_raw`, `rgmii_tx`, `**async_default**`, `(none)`) |
| `module` | String | Hierarchical module path of endpoint/startpoint (e.g., `ps_system/ps_gateway_i/accelerator`) |
| `path_type` | String | Check type (`Setup (Max at Slow Process Corner)`, `Hold (Min at Fast Corner)`, `Recovery`, `Removal`) |
| `slack_ns` | Float / String | Slack in nanoseconds, or `inf` for unconstrained/false paths |
| `requirement_ns` | Float | Timing requirement in nanoseconds (e.g., 8.000, 3.000, 2.000) |
| `data_delay_ns` | Float | Total datapath delay in nanoseconds |
| `logic_delay_ns` | Float | Cell logic delay component in nanoseconds |
| `logic_pct` | Float | Percentage of datapath delay attributed to cell logic |
| `net_delay_ns` | Float | Interconnect/routing delay component in nanoseconds |
| `net_pct` | Float | Percentage of datapath delay attributed to net routing |
| `cell_levels` | Integer | Number of logic cell levels along the path |
| `level_details` | String | Primitive breakdown of logic levels (e.g., `CARRY8=6 DSP_ALU=3 LUT6=5`) |
| `max_fanout` | Integer | Maximum fanout encountered on any single net along the datapath |
| `has_carry` | Binary (0/1) | 1 if `CARRY8` primitive is present on the datapath |
| `has_dsp` | Binary (0/1) | 1 if `DSP48E2` or DSP slice sub-element is present |
| `has_bram` | Binary (0/1) | 1 if `RAMB36E2`, `RAMB18E2`, `FIFO36E2`, or `URAM` is present |
| `has_fma` | Binary (0/1) | 1 if floating point ALU (`asr_fp32_alu` / `asr_fma_ip`) is in the path |
| `has_clock_enable`| Binary (0/1) | 1 if endpoint is a Clock Enable pin (`/CE` or `/GE`) |
| `has_reset` | Binary (0/1) | 1 if endpoint is a Reset pin (`/R`, `/S`, `/CLR`, `/PRE`) or async recovery/removal |
| `has_mux` | Binary (0/1) | 1 if wide multiplexer (`MUXF7`, `MUXF8`) or LUT multiplexer is present |
| `has_shifter` | Binary (0/1) | 1 if SRL primitive (`SRLC32E`, `SRL16E`) or dynamic shifter is present |
| `fails_150mhz` | Binary (0/1) | 1 if path fails setup under 150 MHz clock budget (Period = 6.667 ns) |
| `fails_300mhz` | Binary (0/1) | 1 if path fails setup under 300 MHz clock budget (Period = 3.333 ns) |
| `fails_600mhz` | Binary (0/1) | 1 if path fails setup under 600 MHz clock budget (Period = 1.667 ns) |
| `source_pin` | String | Full hierarchical pin name of the startpoint |
| `dest_pin` | String | Full hierarchical pin name of the endpoint |

---

## 4. Multi-Clock Domain & CDC Interface Boundaries

For target frequencies >= 300 MHz and up to 600 MHz, the system architecture partitions into three asynchronous domains:

```
+-----------------------------------------------------------------------------------------------+
| Domain: CORE_600 (clk_pe: 600.000 MHz, Period = 1.667 ns)                                     |
|   - Inputs: a_left[255:0], w_top[111:0], av[15:0], wv[15:0], positions[15:0], clip           |
|   - Outputs: sums_s[12287:0], sums_c[12287:0] (Dual-rail) or pipelined sums[12287:0]          |
|   - Interface: Direct systolic synchronous connection to local L1 BRAM banks                  |
+-----------------------------------------------------------------------------------------------+
                                               ^
                                               | Dual-Clock Asynchronous FIFO
                                               v
+-----------------------------------------------------------------------------------------------+
| Domain: PL_CTRL_300 (clk_pl: 300.000 MHz, Period = 3.333 ns)                                  |
|   - Pipelined AXI DMA controller, DDR layout engine, and vector ALU                            |
|   - Readout interface: Pulls accumulated sums from PE array into banked L2/C-cache             |
|   - CDC Constraint: set_max_delay -datapath_only 1.667 ns across CDC boundary                 |
|   - Bus Skew: set_bus_skew -from [get_cells ...] -to [get_cells ...] 0.800 ns                 |
+-----------------------------------------------------------------------------------------------+
                                               ^
                                               | Dual-Clock AXI Stream FIFO
                                               v
+-----------------------------------------------------------------------------------------------+
| Domain: NET_125 (clk125_raw / rgmii_rx: 125.000 MHz, Period = 8.000 ns)                       |
|   - Ethernet MAC, RGMII interface, UDP transaction buffer                                     |
|   - CDC Constraint: Gray-code pointers with 2-stage ASYNC_REG flip-flops                      |
+-----------------------------------------------------------------------------------------------+
```

---

## 5. Pipelined PE Hardware Interface Contract

### Carry-Chain Candidate Contract (`pe_pipeline_cc_v023` enhancement)
- **Latency**: 5 cycles from `av_in && wv_in` valid to `sum` accumulation.
- **Stage Registers**:
  - `mag0`, `m0`, `p0`, `neg0`, `sat0` (Cycle 1)
  - `raw1`, `mag1`, `p1`, `neg1`, `sat1` (Cycle 2)
  - `aligned_reg` (Cycle 3, Barrel Shift isolated)
  - `magnitude_reg` (Cycle 4, Saturation Subtract isolated)
  - `product_reg` (Cycle 5, Conditional Negate isolated)
  - `sum <= sum + product_reg` (Cycle 6, 48-bit CARRY8 fast chain)

### Dual-Rail CSA Candidate Contract (`pe_pipeline_csa_v023` enhancement)
- **Accumulation Loop**:
  ```verilog
  sum_s <= sum_s ^ sum_c ^ p48;
  sum_c <= ((sum_s & sum_c) | (sum_s & p48) | (sum_c & p48)) << 1;
  ```
- **CPA Readout Contract**:
  - **Prohibition**: DO NOT drive continuous assign `assign sum = sum_s + sum_c;` into upper array wires.
  - **Mandatory Registering**:
    ```verilog
    always @(posedge clk) begin
        if (readout_enable) begin
            sum_out <= sum_s + sum_c;
        end
    end
    ```
  - Isolates the 48-bit CPA from the upper-level matrix collection muxes and second 49-bit cache adder.
