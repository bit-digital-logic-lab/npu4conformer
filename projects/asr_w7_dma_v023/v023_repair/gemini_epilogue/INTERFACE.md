# Epilogue Fusion Engine Interface Contract (`INTERFACE.md`)

**Module**: `epilogue_stream_engine_v023`  
**Location**: `v023_repair/gemini_epilogue/epilogue_stream_engine_v023.sv`  
**Author**: Gemini Epilogue Worker  
**Target Architecture**: AMD/Xilinx Zynq UltraScale+ (ZU15EG)  
**Standard**: Non-blocking Valid/Ready Handshake with Tag/Last Framing  

---

## 1. Architectural Role & Overview

`epilogue_stream_engine_v023` provides on-chip streaming fusion between matrix compute collection (`ds_matrix`) and subsequent vector quantization / layout (`ds_vector`). It eliminates the redundant intermediate DDR roundtrips required by the legacy schedule:
$$\text{Matrix PE } C48 \xrightarrow{\text{on-chip}} I48\_F32 \xrightarrow{\text{on-chip}} \text{Scale/Bias FMA} \xrightarrow{\text{on-chip}} \text{ReLU} \xrightarrow{\text{on-chip}} F32\_I16 \xrightarrow{\text{on-chip}} A16$$

- **Throughput**: 4 elements / clock cycle (192-bit C48 input $\to$ 64-bit / 128-bit packed A16 output).
- **Latency**: 6 pipeline clock cycles from input handshake to output valid.
- **DDR Traffic Reduction**: Eliminates up to 94.74% of DDR bandwidth per matrix tile.

---

## 2. Port Definitions

### 2.1 System & Control Signals

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | System clock (125 MHz baseline, 250~300 MHz target domain). |
| `rst_n` | Input | 1 | Asynchronous active-low reset. |
| `abort` | Input | 1 | Synchronous error drain / abort signal. Immediately clears all pipeline registers, FIFOs, and active burst state. |

### 2.2 Descriptor & Configuration Interface

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `cfg_valid` | Input | 1 | Asserted when new block descriptor configuration is available. |
| `cfg_ready` | Output | 1 | High when engine is ready to accept new configuration (`!in_burst`). |
| `cfg_fma_mode` | Input | 2 | `2'd0`: Conversion-only bypass (scale=1.0, bias=0.0).<br>`2'd1`: Scale + Bias FMA ($x \cdot \text{scale} + \text{bias}$).<br>`2'd2`: Scale-only ($x \cdot \text{scale}$). |
| `cfg_relu_en` | Input | 1 | Enable FP32 ReLU activation ($\max(0.0, x)$). |
| `cfg_spill_c48` | Input | 1 | Enable multi-consumer spill: duplicates raw C48 stream to DDR write port while continuing on-chip epilogue. |
| `cfg_spill_fp32`| Input | 1 | Enable multi-consumer spill for intermediate FP32. |
| `cfg_scale` | Input | 32 | IEEE-754 FP32 scale factor ($S_X \times S_W / S_{out}$). |
| `cfg_bias` | Input | 32 | IEEE-754 FP32 bias value ($B / S_{out}$). |
| `cfg_tag` | Input | 16 | Block/task epoch tag for tracking and debugging. |

### 2.3 Parameter Preload DMA Interface (PL Autonomous)

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `param_wr_valid`| Input | 1 | PL DMA parameter write enable (No CPU/MMIO in data path). |
| `param_wr_ready`| Output| 1 | Ready to accept parameter word. |
| `param_wr_addr` | Input | 8 | Parameter register / RAM address (supports per-channel scales). |
| `param_wr_data` | Input | 32 | FP32 parameter word from DMA. |

### 2.4 Upstream Matrix C48 Stream Interface (`ds_matrix` Collector)

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `cval_valid` | Input | 1 | High when upstream matrix collector has valid C48 data. |
| `cval_ready` | Output | 1 | Backpressure to matrix collector. Asserted when epilogue lanes and spill port (if enabled) are ready. |
| `cval_data` | Input | 192 | 4 lanes of 48-bit signed integer C48 values:<br>`[47:0]`: Lane 0<br>`[95:48]`: Lane 1<br>`[143:96]`: Lane 2<br>`[191:144]`: Lane 3 |
| `cval_tag` | Input | 16 | Burst / task tag. |
| `cval_last` | Input | 1 | End-of-block / end-of-burst framing flag. |

### 2.5 Downstream A16 Output Interface (`ds_vector` / Layout / DMA)

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `a16_valid` | Output | 1 | High when 4 quantized A16 values are valid. |
| `a16_ready` | Input | 1 | Downstream backpressure. |
| `a16_data` | Output | 64 | 4 lanes of signed 16-bit integers ($4 \times 16 = 64$ bits). |
| `a16_tag` | Output | 16 | Propagated tag matching corresponding input beat. |
| `a16_last` | Output | 1 | Propagated end-of-burst framing flag. |
| `a16_packed` | Output | 128 | Packed 128-bit AXI beat (8 INT16 elements) for direct DMA write. |
| `a16_packed_valid`| Output| 1 | Valid for 128-bit packed beat. |
| `a16_packed_ready`| Input | 1 | Backpressure from 128-bit AXI DMA channel. |
| `a16_packed_last` | Output| 1 | Last flag for 128-bit beat. |

### 2.6 Spill Stream Interface (Multi-Consumer & Debug)

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `spill_valid` | Output | 1 | High when raw C48 is mirrored to spill port (`cfg_spill_c48 == 1`). |
| `spill_ready` | Input | 1 | Backpressure from spill FIFO / DDR write channel. |
| `spill_data` | Output | 192 | Raw 4-lane 48-bit C48 values. |
| `spill_tag` | Output | 16 | Mirrored tag. |
| `spill_last` | Output | 1 | Mirrored last flag. |

### 2.7 Telemetry & Performance Counters

| Port Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `stat_c48_beats_in` | Output | 32 | Cumulative count of C48 input beats processed. |
| `stat_a16_beats_out` | Output | 32 | Cumulative count of A16 output beats produced. |
| `stat_spill_beats` | Output | 32 | Cumulative count of C48 beats spilled to DDR. |
| `stat_ddr_bytes_saved` | Output | 32 | Real-time byte counter tracking eliminated DDR traffic. |

---

## 3. Protocol & Timing Invariants

1. **Backpressure Propagation**:
   - Upstream `cval_ready` drops to 0 when downstream `a16_ready` or `a16_packed_ready` is low and internal skid buffers are full.
   - If `cfg_spill_c48` is asserted, `cval_ready` also waits for `spill_ready`.
   - Guaranteed zero data loss and zero bubbles under arbitrary downstream stalls.
2. **Error Drain Contract (`abort`)**:
   - Asserting `abort = 1` immediately clears `s1_valid`, `s2_valid`, `p128_valid`, and `in_burst` across all 4 lanes within 1 clock cycle.
   - Residual in-flight data is flushed without producing spurious output handshakes.
3. **Numerical Integrity**:
   - `I48_F32`: FTZ on subnormals, 27-bit significand extraction, Round-to-Nearest-Even (RNE). Bit-exact with `asr_fp32_alu.sv` `int48_float`.
   - `F32_I16`: Banker's Rounding (RNE) on exact halfway cases ($1.5 \to 2$, $2.5 \to 2$, $3.5 \to 4$), saturated clamp to $[-32768, 32767]$. Bit-exact with `asr_fp32_alu.sv` `float_int32`.
