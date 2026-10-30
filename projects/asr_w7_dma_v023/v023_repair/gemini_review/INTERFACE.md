# INTERFACE — Multi-Agent Collaboration & Review Contracts

**Task**: `gemini_review`  
**Role**: Verification & Architecture Audit Standard  
**Published To**: `ds_integration`, `ds_vector`, `ds_layout`, `ds_matrix`, `ds_graph`, `gemini_approx`, `ds_control_fixes`, `gemini_epilogue`  
**Date**: 2026-10-29  

---

## 1. Unified Telemetry & Reporting Contract

为了杜绝指标偷换和虚报，所有向最终整合工件 `ds_integration` 汇报的模块必须遵循以下 JSON 统一数据模式：

```json
{
  "module_name": "string",
  "scope": "whole_model | closed_68_subset | unit_kernel",
  "execution_tier": "theoretical_bound | rtl_simulation | board_measurement",
  "clock_domains": {
    "system_axi_mhz": 125.0,
    "compute_array_mhz": 125.0
  },
  "metrics": {
    "total_cycles": 0,
    "active_compute_cycles": 0,
    "dma_stall_cycles": 0,
    "dma_read_bytes": 0,
    "dma_write_bytes": 0,
    "effective_bandwidth_gbps": 0.0
  },
  "numerical_fidelity": {
    "baseline_model": "FP32_FTZ_RNE_exact | Python_golden",
    "tested_samples": 0,
    "max_absolute_error": 0.0,
    "max_relative_error_pct": 0.0,
    "int16_quantized_mismatch_rate_pct": 0.0,
    "int16_max_lsb_difference": 0
  },
  "coverage_and_unimplemented": {
    "covered_features": [],
    "explicit_unimplemented_gaps": []
  }
}
```

---

## 2. Binding RTL Interface Contracts

### 2.1 Approximate DIV / SQRT / RSQRT Contract (`gemini_approx` ↔ `ds_vector`)
- **Top Module**: `approx_div_sqrt`
- **Handshake**: Ready/Valid with strictly in-order completion.
- **Backpressure**: When `out_ready == 0`, `out_valid` remains asserted and `result`, `flags`, `tag_out` are held stable without dropping transactions.
- **Contract Ports**:
  ```systemverilog
  module approx_div_sqrt #(
      parameter integer TIER    = 1,   // 0: 2-cycle LUT, 1: 4-cycle LUT+NR, 2: 7-cycle LUT+2NR
      parameter integer LATENCY = 4,
      parameter integer II      = 1
  )(
      input  wire        clk, rst_n,
      input  wire        in_valid,
      output wire        in_ready,
      input  wire [1:0]  op,        // 0: DIV (A/B), 1: SQRT (sqrt A), 2: RSQRT (1/sqrt A)
      input  wire [31:0] a, b,
      input  wire [15:0] tag,
      output wire        out_valid,
      input  wire        out_ready,
      output wire [31:0] result,
      output wire [7:0]  flags,     // flags[4]: approximate marker; flags[3]: FTZ underflow
      output wire [15:0] tag_out
  );
  ```

### 2.2 Epilogue Stream Interface Contract (`ds_matrix` ↔ `gemini_epilogue`)
- **Upstream C48 Stream**: Emits 4 parallel C48 lanes (`192-bit`) per cycle with backpressure.
- **Downstream A16 Stream**: Emits 4 parallel INT16 lanes (`64-bit`) and packed `128-bit` beats.
- **Contract Rules**:
  1. `cval_valid && cval_ready` advances upstream data;
  2. `cfg_spill_c48`: When asserted, C48 is duplicated to the DDR write stream; when deasserted, C48 DDR write is bypassed;
  3. `abort`: Synchronous one-cycle abort flushes all in-flight pipeline registers, immediately resetting valid outputs to 0.

### 2.3 Systolic Array Flush & Draining Contract (`ds_matrix`)
- **Modules**: `pe_w7_c48_cfg`, `array16_w7_c48_cfg`, `block_engine_prefetch_v2`
- **Latency Equation**:
  $$\text{PE\_DRAIN} = \text{PIPE\_STAGES} + 1 + (\text{ACCUM\_MODE} == 1\ ?\ 1\ :\ 0)$$
  $$\text{ARRAY\_DRAIN} = 15 + \text{PE\_DRAIN}$$
- **Controller Rules**:
  1. `run_finished` MUST wait for `run_cycle >= last_input_cycle && array_drain_done`;
  2. `flush` MUST NOT be tied to `state != RUN`. It must be asserted ONLY on `reset || state == FAIL`;
  3. No hardcoded 65-cycle constants are permitted in the RTL.

### 2.4 CSR Snapshot Contract (`ds_control_fixes`)
- **Modules**: `plan_submit_csr_v023`
- **Rule**: Every 64-bit counter has an independent snapshot high-register bank. A low-word read atomically latches `{high, low}` for that specific address; subsequent high-word reads return that latched value even if other registers are accessed concurrently.
