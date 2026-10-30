# INTERFACE — Epilogue Stream Engine (`epilogue_stream_engine_v023`)

本接口契约规范定义了 `epilogue_stream_engine_v023` 模块的硬件接口、信号时序、流协议及控制状态机行为。本轮整改（Round 2）专门针对独立数值审计发现的 **STREAM-1..4** 阻断问题进行了彻底重构与修复。

---

## 1. 模块定位与系统边界

`epilogue_stream_engine_v023` 是 512 维 Conformer/Transformer ASR 芯片中连接矩阵计算核心（`ds_matrix`）与向量处理/布局引擎/DDR（`ds_vector`/`ds_layout`/DMA）的核心融合处理引擎。

### 核心功能
1. **4 路并行流水处理**：每拍接收 4 路 48-bit 累加和（192 bits），经 INT48→FP32、FP32-FMA 缩放与偏移、ReLU 激活、FP32→INT16 量化饱和，输出 4 路 16-bit 整数（64 bits）。
2. **128-bit AXI 聚合打包**：内部将两拍 64-bit A16 结果聚合为一拍 128-bit（8 个 INT16 元素），为 DMA AXI 写入提供高带宽对齐通道。
3. **参数预装 DMA 端口**：支持独立 PL DMA 将通道 scale/bias 预装至片上专用参数 RAM（支持每通道/多参数），运行时完全摆脱 PS CPU 与 MMIO。
4. **重配置流水线排空保护**：在接收新描述符时，强制等待流水线在途 beat 与打包器完全排空，防止静态/动态配置串扰在途数据。
5. **多消费者 C48 Spill 旁路**：支持在片上后处理的同时，将原始 C48 数据按需旁路备份至 DDR。
6. **零残余中止排空**：`abort` 信号一拍清除全部流水线与打包暂存器，遥测计数器跨 abort 保持以供错误分析。

---

## 2. 顶层端口清单

### 2.1 时钟与复位控制
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | 系统工作时钟（设计目标 125 MHz / 8ns）。 |
| `rst_n` | Input | 1 | 异步低电平有效复位，内部同步释放。 |
| `abort` | Input | 1 | 同步全局中止/排空信号。高电平有效，一拍清空全部在途状态，不产生幽灵输出。 |

### 2.2 配置描述符接口 (`cfg_*`)
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `cfg_valid` | Input | 1 | 高电平表示有效配置描述符到来。 |
| `cfg_ready` | Output| 1 | **STREAM-4 修复**：仅在引擎完全空闲（在途计数器为 0、packer 为空、非 burst 中）时置高；彻底消除配置命中在途 beat 风险。 |
| `cfg_fma_mode` | Input | 2 | 0: 纯转换旁路（CONV_ONLY）<br>1: 缩放+偏置（SCALE_BIAS）<br>2: 仅缩放（SCALE_ONLY） |
| `cfg_relu_en` | Input | 1 | 高电平使能 ReLU 激活。 |
| `cfg_spill_c48` | Input | 1 | 高电平使能 C48 原始矩阵累加和旁路转储。 |
| `cfg_spill_fp32`| Input | 1 | 保留用于 FP32 中间量旁路。 |
| `cfg_scale` | Input | 32 | IEEE-754 binary32 缩放因子。当参数预装口未写入时作为默认 scale。 |
| `cfg_bias` | Input | 32 | IEEE-754 binary32 偏置常数。当参数预装口未写入时作为默认 bias。 |
| `cfg_tag` | Input | 16 | 描述符任务/Epoch Tag。 |

### 2.3 参数预装 DMA 端口 (`param_wr_*`) — **STREAM-3 修复**
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `param_wr_valid`| Input | 1 | PL DMA 参数写有效脉冲。 |
| `param_wr_ready`| Output| 1 | 始终为 1'b1，单拍无反压写入内部 256×32b RAM。 |
| `param_wr_addr` | Input | 8 | 参数 RAM 地址（addr 0 为 scale，addr 1 为 bias，支持每通道扩展）。 |
| `param_wr_data` | Input | 32 | IEEE-754 binary32 浮点参数字。 |

### 2.4 上游 C48 流接口 (`cval_*`)
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `cval_valid` | Input | 1 | 上游矩阵累加收集器数据有效。 |
| `cval_ready` | Output| 1 | 反压信号：当 4 个流水线 Lane 与 Spill 端口（若使能）均就绪且无 abort 时置高。 |
| `cval_data` | Input | 192 | 4 路 48-bit 有符号整数累加和：`[47:0]`, `[95:48]`, `[143:96]`, `[191:144]`。 |
| `cval_tag` | Input | 16 | 随 beat 严格对齐传输的 16-bit Tag。 |
| `cval_last` | Input | 1 | 当前 burst 最后一拍指示。 |

### 2.5 下游 A16 与 128-bit 打包流接口 (`a16_*` / `a16_packed_*`) — **STREAM-1, STREAM-2 修复**
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `a16_valid` | Output| 1 | 4 路量化 A16 有效信号。**与 `a16_packed_valid` 严格互斥**。 |
| `a16_ready` | Input | 1 | 下游 A16 消费者反压。 |
| `a16_data` | Output| 64 | 4 路 16-bit 整数：`[15:0]`, `[31:16]`, `[47:32]`, `[63:48]`。 |
| `a16_tag` | Output| 16 | **STREAM-1 修复**：在 A16 握手当拍呈现当前 A16 beat 的 tag；在 packed 握手当拍呈现打包起始 beat 的 tag。二者互斥，彻底消除污染。 |
| `a16_last` | Output| 1 | 对应 A16 beat 的 last 标志。 |
| `a16_packed` | Output| 128 | 聚合 8 个 INT16 元素的 128-bit 打包数据。 |
| `a16_packed_valid` | Output| 1 | 128-bit 打包数据有效标志。 |
| `a16_packed_ready` | Input | 1 | 下游 128-bit 打包通道反压。 |
| `a16_packed_last`  | Output| 1 | 打包通道帧尾标志。若 burst 为奇数拍，在最后产生一拍高 64 位补零的 packed last beat。 |

### 2.6 多消费者 Spill 转储接口 (`spill_*`)
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `spill_valid` | Output| 1 | 仅当 `active_spill_c48=1` 且上游握手成功时置高。 |
| `spill_ready` | Input | 1 | Spill 接收端（DDR 写 FIFO）就绪信号。 |
| `spill_data` | Output| 192 | 复制的原始 192-bit C48 数据。 |
| `spill_tag` | Output| 16 | 复制的 16-bit Tag。 |
| `spill_last` | Output| 1 | 复制的 Last 标志。 |

### 2.7 性能与遥测计数器 (`stat_*`)
| 端口名 | 方向 | 位宽 | 描述 |
| :--- | :---: | :---: | :--- |
| `stat_c48_beats_in` | Output| 32 | 成功进入引擎的 C48 输入拍数。 |
| `stat_a16_beats_out` | Output| 32 | **STREAM-2 修复**：成功发往下游的真实 A16 拍数（消除了反压重复握手虚增）。 |
| `stat_spill_beats` | Output| 32 | 成功转储到 Spill 端口的拍数。 |
| `stat_ddr_bytes_saved` | Output| 32 | 若未开启 spill，每拍节省 48 字节 DDR 读写流量。 |

---

## 3. 核心协议与时序规则

### 3.1 A16 与 128-bit 打包流互斥握手规则（STREAM-1 & STREAM-2）
* **单 Tag 端口时分复用安全**：由于 DUT 接口仅有一根 `a16_tag` 端口，如果 `a16_valid` 与 `a16_packed_valid` 在同拍有效，下游两端无法同时获得正确的专属 Tag。整改后采用**时分互斥解耦机制**：
  - 当 packer 攒满 128-bit（或命中奇数尾包 last）时，激活 `p128_valid`。
  - 在 `p128_valid=1` 期间，`a16_valid` 强制置 0，流水线推进停止（`lanes_downstream_ready=0`）。
  - `a16_tag` 输出 `p128_tag`（对应 packed 第 1 拍的 tag），等待 `a16_packed_ready` 握手。
  - 握手完成后，`p128_valid` 清零，A16 恢复使能，`a16_tag` 输出当前 A16 beat 的 tag。
* **彻底消除反压重复握手（STREAM-2）**：当 packed 接收端处于反压状态（`a16_packed_ready=0`）时，`a16_valid` 保持为 0，A16 消费者绝不会在等待期间发生重复握手采样，彻底杜绝了旧版 402/256 次重复采样的问题。

### 3.2 参数预装 DMA 端口协议（STREAM-3）
* **DMA Autonomous 语义**：在输入 burst 启动之前或任务重配前，PL DMA 通过 `param_wr_valid` 向 `param_mem[addr]` 预装浮点 scale 与 bias。
* **优先级规则**：
  - 若 `param_loaded=1`（曾有参数预装写入），引擎优先使用参数 RAM 中的值（`param_mem[0]` 为 scale，`param_mem[1]` 为 bias）。
  - 若未进行参数预装，引擎回退使用描述符中的 `cfg_scale` 与 `cfg_bias`。
  - `abort` 或系统复位时，清空预装标志。`cfg_valid` 的更新不抹除已预装参数。

### 3.3 重配置排空保护协议（STREAM-4）
* **排空检测器**：
  $$\text{engine\_idle} = (\text{in\_flight\_beats} == 0) \land \neg\text{pack\_has\_half} \land \neg\text{p128\_valid} \land \neg\text{in\_burst} \land \neg\text{abort}$$
* **反压握手**：
  - 当流水线内部有任何在途 beat、或打包器尚有半字未发出、或处于多拍 burst 接收过程中时，`cfg_ready` 严格保持为 0。
  - 配置发起方必须维持 `cfg_valid` 等待 `cfg_ready` 变高。
  - 保证新配置参数绝不跨越流水线作用到前一任务的末尾 beat 上。
