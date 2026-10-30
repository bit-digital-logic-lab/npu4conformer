# Epilogue FMA & Stream Engine Interface Specification

## 1. 概述与设计定位

本模块为片上流式尾处理融合引擎（Epilogue Fusion Engine）及核心高精度浮点融合乘加单元（FP32 FMA）。
工作目录：`/home/yang/Desktop/项目/v023_repair/gemini_fma_repair`
候选交付目录：`candidate/`

模块职责：
承接矩阵计算单元输出的 4 通道 48-bit 累加值（C48），在片上流式执行：
$$\text{C48} \xrightarrow{\text{I48\_F32}} \text{FP32} \xrightarrow{\text{FMA (scale, bias)}} \text{FP32} \xrightarrow{\text{ReLU}} \text{FP32} \xrightarrow{\text{F32\_I16 (QDQ)}} \text{A16}$$
支持 64-bit 直接输出及 128-bit AXI 对齐打包，消除了矩阵结果反复写回与重读 DDR 的中间流量，保证严格 IEEE-754 单次舍入数值精度。

---

## 2. 核心模块与接口定义

### 2.1 4级流水单次舍入 FMA 核心: `fp32_fma_pipe.sv`

实现 IEEE-754 binary32 真实单次舍入（Fused Multiply-Add）$R = (A \times B) + C$。

- **时钟与复位**:
  - `clk`: 逻辑时钟。
  - `rst_n`: 异步低电平复位。
  - `flush`: 同步立即清空信号，1拍内将 S1~S4 所有有效状态清零。
- **上行握手与操作数**:
  - `in_valid` (input): 输入数据有效。
  - `in_ready` (output): 核心准备好接收新输入（支持全流水背压）。
  - `in_a [31:0]` (input): 操作数 A (FP32)。
  - `in_b [31:0]` (input): 操作数 B (FP32, 乘数/Scale)。
  - `in_c [31:0]` (input): 操作数 C (FP32, 加数/Bias)。
  - `in_tag [TAG_WIDTH-1:0]` (input): 事务 Tag，流水线透明传递。
  - `in_last` (input): 尾包指示。
- **下行握手与结果**:
  - `out_valid` (output): 计算结果有效。
  - `out_ready` (input): 下游接收准备就绪。
  - `out_result [31:0]` (output): 计算结果 (FP32)。
  - `out_tag [TAG_WIDTH-1:0]` (output): 对应输出 Tag。
  - `out_last` (output): 对应输出尾包指示。
- **流水级划分与时序特性**:
  - **Stage 1**: 操作数解包、特殊值（NaN/Inf/Zero/FTZ）检测、24x24 无符号整数乘法器（生成48-bit乘积）、指数差计算。
  - **Stage 2**: 132-bit 对齐移位器、48-bit 乘积与加数宽位加减法器、精确 Sticky 收集。
  - **Stage 3**: 132-bit 前导零检测（LZC / 优先编码器）、规格化移位器、基准指数调整。
  - **Stage 4**: IEEE-754 最近偶数舍入（RNE, Tie to Even LSB）、指数溢出（Overflow to Inf）与下溢（FTZ to 0）判定、特殊结果多路选择。
  - **流水延迟 (Latency)**: 固定 4 拍。
  - **吞吐率 (Throughput)**: 1 拍/结果（II = 1），无内部气泡。

---

### 2.2 原官方 IP 兼容包装: `asr_fma_ip.sv`

完全兼容原工程 `work/rtl/ddr_vector_engine.sv` 中调用的官方 Xilinx `asr_fma_ip` 接口契约：

```systemverilog
module asr_fma_ip (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        s_axis_a_tvalid,
    input  wire [31:0] s_axis_a_tdata,
    input  wire        s_axis_b_tvalid,
    input  wire [31:0] s_axis_b_tdata,
    input  wire        s_axis_c_tvalid,
    input  wire [31:0] s_axis_c_tdata,
    output wire        m_axis_result_tvalid,
    output wire [31:0] m_axis_result_tdata
);
```

- 原 IP 特性：NonBlocking（无反压 ready 输入，输入有效即入队），Latency = 4 拍，吞吐率 1 beat/cycle。
- 数值保证：已通过官方 `work/tests/fma_fixture/gold.hex` 全部 1001 个测试向量的逐比特比对验证（包括 $(1+2^{-23})(1-2^{-23}) - 1 = -2^{-46}$ 抵消算例）。

---

### 2.3 融合运算阶段: `epilogue_fma_stage.sv`

支持三种运行模式的操作数路由与流水旁路：

- **模式定义 (`mode [1:0]`)**:
  - `MODE_CONV_ONLY (2'd0)`: 卷积转换旁路。操作数直接穿透，延迟严格保持 4 拍与 FMA 对齐，保证绝对 0 算术失真。
  - `MODE_SCALE_BIAS (2'd1)`: 完整 FMA 模式。计算 $(x \times \text{scale}) + \text{bias}$，单次舍入 RNE。
  - `MODE_SCALE_ONLY (2'd2)`: 仅乘法缩放模式。计算 $x \times \text{scale} + 0.0$。
- **握手与反压**:
  - 上行 `in_valid` / `in_ready`，下行 `out_valid` / `out_ready`，支持全流水打拍与下游挂起保持。
- **保留诊断接口**:
  - 保留并修复了静态函数 `fp32_mul(a, b)`，采用标准 RNE 舍入，修复了原主验收中 `tb_fma_probe.sv` 反例。

---

### 2.4 单通道融合流水线: `epilogue_lane.sv`

级联 Stage 1~4：
1. `epilogue_i48_to_f32`: 48-bit 有符号整数转 FP32（2拍）。
2. `epilogue_fma_stage`: 4级流水 FMA / 旁路（4拍）。
3. `epilogue_relu`: ReLU 激活函数（1拍）。
4. `epilogue_f32_to_i16`: FP32 转 16-bit 有符号整数，带最近偶数舍入与 $[-32768, 32767]$ 饱和截断（2拍）。
- **总通道延迟**: 9 拍。
- **流水控制**: 各级间全握手直连，支持单拍 `flush` 清空。

---

### 2.5 顶层流式引擎: `epilogue_stream_engine_v023.sv`

- **上行接口**:
  - `cval_valid`, `cval_ready`: 4 通道 C48 数据握手。
  - `cval_data [191:0]`: 4 个 48-bit 累加和元素。
  - `cval_tag [15:0]`, `cval_last`: 流控制与尾指示。
- **下行 64-bit 接口**:
  - `a16_valid`, `a16_ready`: 4 通道 16-bit 激活值握手。
  - `a16_data [63:0]`: 4 个 16-bit 元素 `{lane3, lane2, lane1, lane0}`。
  - `a16_tag [15:0]`, `a16_last`.
- **下行 128-bit 打包接口**:
  - `a16_packed_valid`, `a16_packed_ready`: 128-bit AXI 节拍握手。
  - `a16_packed [127:0]`: 8 个 16-bit 元素（合并连续两个 64-bit 节拍）。
  - `a16_packed_last`: 包含奇数节拍补零（zero-padding）正确闭合逻辑。
- **溢出与旁路 (Spill)**:
  - `spill_valid`, `spill_ready`, `spill_data [191:0]`: 支持调试或多消费者分流。
- **统计寄存器**:
  - `stat_c48_beats_in`: 接收 C48 节拍计数。
  - `stat_a16_beats_out`: 发射 A16 节拍计数。
  - `stat_spill_beats`: 旁路溢出节拍计数。
  - `stat_ddr_bytes_saved`: 相比 DDR 往返节省的字节计数（48 字节/节拍）。
