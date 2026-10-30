# REPORT — Epilogue Stream Engine 专属整改报告 (gemini_stream_round2)

- **日期**：2026-10-29
- **工作目录**：`/home/yang/Desktop/项目/v023_repair/gemini_stream_round2`
- **执行约束**：仅本地 RTL 逻辑仿真（Icarus Verilog 14 + Python 精确参考模型）；严禁综合/Vivado/上板/VNC/push；其他 worker 与 work 目录只读；所有代码生成与运行在自己目录中完成。
- **结论**：**Stream 候选模块完全通过（stream_engine_pass=true）**。STREAM-1..4 全部彻底修复并通过独立测试台验证；但由于上游 FMA 算术核心仍有待修项（FMA-1/2/3），**系统整体验收继续不予声明 PASS（system_pass=false）**。

---

## 1. 任务背景与审计反例复盘

在 `ds_numeric_adversarial` 的独立数值验收审计报告中，`epilogue_stream_engine_v023.sv`（旧 SHA `b99a664b...`）被判定存在以下 4 项阻断性协议与功能违约（STREAM-1..4）：

| 缺陷编号 | 审计现象 | 根因定位 |
|---|---|---|
| **STREAM-1 (F11)** | `BP=0` 下 255/256 A16 Tag 错误；偶数拍 tag 被前一 packed beat 的 tag 覆盖。 | `assign a16_tag = p128_valid ? p128_tag : lane_tag[0];` 打包器未排空时污染 A16 单拍 tag。 |
| **STREAM-2 (F12)** | `BP=2` 下 A16 握手 402 次（出现 146 次重复采样）；协议违约。 | `a16_valid = lanes_out_all_valid && !abort;` 未包含 `!packer_full`，反压时不推进但持续置有效。 |
| **STREAM-3 (F13)** | `param_wr_*` 预装参数口无效；113/256 A16 beats 失配；实际输出仅跟随 cfg。 | `param_wr_valid/addr/data` 悬空无寄存器存储逻辑，`active_scale` 仅由 `cfg_scale` 更新。 |
| **STREAM-4 (F14)** | 2-beat burst 中最后一拍在流水线内被新 cfg 篡改；beat 1 输出为 6（期望 2）。 | `cfg_ready = !in_burst;` 在最后拍握手当拍即拉高，未等待 9 级流水线排空即加载新配置。 |

---

## 2. 架构整改方案与核心实现

为彻底根治上述问题，在 `gemini_stream_round2/candidate/epilogue_stream_engine_v023.sv` 中实施了如下重构：

### 2.1 A16 与 128-bit 打包流互斥解耦机制（修 STREAM-1 & STREAM-2）
* **互斥协议**：
  ```systemverilog
  assign a16_valid = lanes_out_all_valid && !p128_valid && !abort;
  assign a16_data  = cur_a16_data;
  assign a16_tag   = p128_valid ? p128_tag : cur_a16_tag;
  assign a16_last  = p128_valid ? p128_last : cur_a16_last;

  assign lanes_downstream_ready = !p128_valid && a16_ready && !abort;

  assign a16_packed_valid = p128_valid && !abort;
  assign a16_packed       = p128_data;
  assign a16_packed_last  = p128_last;
  ```
* **效果**：
  1. 当打包器准备发送 128-bit beat 时（`p128_valid=1`），`a16_valid` 强制为 0，流水线暂停推进；`a16_tag` 呈现打包第一拍保存的 `p128_tag`。
  2. 当 `a16_packed_ready=0` 发生反压时，`a16_valid` 恒为 0，A16 消费者绝无重复握手。实测 `BP=2` 下 A16 握手次数为精确的 **256/256**（0 次重复，`a16_count_mismatch=0`）。
  3. 当 `p128_valid=0` 时，A16 正常握手，`a16_tag` 取 `lane_tag[0]`。实测 19 组测试中 **0 处 tag 失配**。

### 2.2 参数预装 DMA 端口真实语义（修 STREAM-3）
* **片上 256×32b 参数 RAM 与仲裁回退**：
  ```systemverilog
  reg [31:0] param_mem [0:255];
  reg        param_loaded;
  reg        param_bias_loaded;

  assign param_wr_ready = 1'b1;

  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          param_loaded <= 1'b0; param_bias_loaded <= 1'b0;
      end else if (abort) begin
          param_loaded <= 1'b0; param_bias_loaded <= 1'b0;
      end else if (param_wr_valid && param_wr_ready) begin
          param_mem[param_wr_addr] <= param_wr_data;
          param_loaded <= 1'b1;
          if (param_wr_addr == 8'd1) param_bias_loaded <= 1'b1;
      end
  end

  wire [31:0] eff_scale = param_loaded ? param_mem[0] : active_scale;
  wire [31:0] eff_bias  = (param_loaded && param_bias_loaded) ? param_mem[1] : active_bias;
  ```
* **效果**：在 `param_en=1` 时，预装参数优先生效；未写预装时平滑回退至描述符 `cfg_scale/bias`。`stream_param_port` 实测 0 失配。

### 2.3 流水线在途拍排空保护（修 STREAM-4）
* **全生命周期在途跟踪**：
  引入 `in_flight_beats` 计数器，在上游 `cval_fire` 时自增，在下游 `a16_fire` 时自减。
* **严格空闲断言**：
  ```systemverilog
  wire engine_idle = (in_flight_beats == 16'd0) && !pack_has_half && !p128_valid && !in_burst && !abort;
  assign cfg_ready = engine_idle;
  ```
* **效果**：在多任务流水切换或 `RECFG_AT` 触发时，`cfg_ready` 保持为 0，直到前一 burst 全部 9 级流水线及打包器彻底排空。实测 2-beat burst 中：
  `a16 = ["0001000100010001", "0002000200020002"]`，在途 beat 1 保持为 2，彻底杜绝了篡改成 6 的静默错误。

---

## 3. 验证矩阵与对比结果

复用 `ds_numeric_adversarial` 的独立测试台 `tb_stream.sv`、对抗输入向量 `vectors/stream.vec`、`vectors/stream_reconfig.vec` 及独立参考模型 `refmodel.py`，全量执行 20 组测试。

| 测试配置 | 测试点 | 旧版结果 | Round 2 修复后 | 判定 |
|---|---|---|---|:---:|
| `stream_conv_bp0` | Mode 0 纯转换 (BP=0) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_conv_relu_bp0` | Mode 0 + ReLU (BP=0) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_fma_bp0` | Mode 1 FMA 对抗缩放偏置 (BP=0) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_fma_relu_bp0` | Mode 1 FMA + ReLU (BP=0) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_fma_real_bp0` | 真实 ASR LayerNorm 参数 (BP=0) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_scale_only_bp0` | Mode 2 仅缩放 (BP=0) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_spill_bp0` | C48 原始矩阵转储 (BP=0) | FAIL (tag 255 错) | **PASS** (256 转储拍, 0 数据/tag 错) | **FIXED** |
| `stream_abort_bp0` | 中途 Abort (beat 100, BP=0) | FAIL (tag 90 错) | **PASS** (0 幽灵输出, 统计保留) | **FIXED** |
| `stream_param_port_bp0` | 参数预装 DMA 端口 (BP=0) | FAIL (113 数据错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_conv_bp2` | Mode 0 打包反压 (BP=2) | FAIL (402/256 次握手) | **PASS** (精确 256 A16, 128 打包, 0 重复) | **FIXED** |
| `stream_conv_relu_bp2`| Mode 0 ReLU (BP=2) | FAIL (402/256 次握手) | **PASS** (精确 256 A16, 128 打包, 0 重复) | **FIXED** |
| `stream_fma_bp2` | Mode 1 FMA (BP=2) | FAIL (402/256 次握手) | **PASS** (精确 256 A16, 128 打包, 0 重复) | **FIXED** |
| `stream_spill_bp2` | Spill 转储通道 (BP=2) | FAIL (402/256 次握手) | **PASS** (精确 256 A16, 128 打包, 0 重复) | **FIXED** |
| `stream_param_port_bp2`| 参数预装通道 (BP=2) | FAIL (113 数据错+重复) | **PASS** (精确 256 A16, 128 打包, 0 错) | **FIXED** |
| `stream_conv_bp1` | 全通道随机反压 (BP=1) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_conv_relu_bp1`| Mode 0 ReLU (BP=1) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_fma_bp1` | Mode 1 FMA (BP=1) | FAIL (tag 255 错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_abort_bp1` | 随机反压下 Abort (BP=1) | FAIL (tag 错) | **PASS** (0 幽灵输出, 统计保留) | **FIXED** |
| `stream_param_port_bp1`| 参数预装 + 随机反压 (BP=1) | FAIL (113 数据错) | **PASS** (0 数据错, 0 tag 错, 0 count 错) | **FIXED** |
| `stream_reconfig` | 运行中在途重配置测试 | FAIL (输出 6 错误) | **PASS** (输出 2 正确, 0 串扰) | **FIXED** |

**综合通过率：20 / 20 组测试全部通过（0 failures, 0 timeout, rc=0）**。

---

## 4. 关键源码与依赖 SHA-256

| 模块 | 路径 | SHA-256 | 状态 |
|---|---|---|---|
| **epilogue_stream_engine_v023.sv** | `gemini_stream_round2/candidate/epilogue_stream_engine_v023.sv` | `5a2a111c35f3e688574cb4ae8df5e03edd1f09793272d182cea60829ace25ffd` | **本轮新候选 (PASS)** |
| epilogue_i48_to_f32.sv | `gemini_fma_repair/candidate/epilogue_i48_to_f32.sv` | `637a7b327d35760bc5d741128d04f77bcddde87cc40886dcf24aff09cebd29bf` | 依赖 (只读) |
| epilogue_fma_stage.sv | `gemini_fma_repair/candidate/epilogue_fma_stage.sv` | `5d52cbc54e1f61029a9c24544ae573ab345ffc8335bb57964dbfbbe8b62183bd` | 依赖 (算术待修) |
| fp32_fma_pipe.sv | `gemini_fma_repair/candidate/fp32_fma_pipe.sv` | `3263c02d63a886f9a8701d19f8c07e3a1b66670ad737206b24846194736cb23f` | 依赖 (算术待修) |
| epilogue_f32_to_i16.sv | `gemini_fma_repair/candidate/epilogue_f32_to_i16.sv` | `c51d3327a7fcfbe7e584f1efa275413644147669c9d216ea7f5fbf31b864af6b` | 依赖 (只读) |
| epilogue_relu.sv | `gemini_fma_repair/candidate/epilogue_relu.sv` | `0e008b394489fcdd2f453aeebee5288f1b812d715c5e8840d47f19bcb3142c4d` | 依赖 (只读) |
| epilogue_lane.sv | `gemini_fma_repair/candidate/epilogue_lane.sv` | `d00b4d57776a605cbed790d19e9a7be7bb4b0f1751d4f6b617a9ca35489435f7` | 依赖 (只读) |

---

## 5. 已知限制与诚实声明

依据用户专项指示（“只写自己的stream候选，FMA依赖先用已有版且明确算术仍待修，不得声称系统PASS”），作出如下诚实限定：

1. **FMA 算术核心待修（FMA-1/2/3）**：
   - 本模块所依赖的底层 `epilogue_fma_stage.sv` 与 `fp32_fma_pipe.sv` 沿用已有 `gemini_fma_repair` 版本。
   - 该版本在独立对抗审计中仍存在 137/8,734 个失配（RNE tie-to-even 未舍入至偶数、极端指数乘积远小于加数时对齐选错指数、Inf/NaN 特殊值处理不合规）。
   - 该问题由专属算术整改轨道（`gemini_fma_round2`）负责修复，**本项目系统验收继续保持阻断，不得声明系统 PASS**。
2. **底层 FMA Bypass 移位寄存器缺陷说明**：
   - 深入代码分析发现，`epilogue_fma_stage.sv:150-162` 的 MODE_CONV_ONLY bypass 移位寄存器（`bp_s1..s4`）未带有有效位跟踪；当上游发生气泡输入（如同时开启 Spill 与随机反压）时，该 shift-register 会复制旧数据。本轮 stream 候选通过严格在途同步确保了协议正常，但 FMA 模块自身的流水线旁路逻辑仍建议在 FMA 轨道一并规范化。
3. **未综合与未上板**：
   - 本整改严格限于本地 Icarus Verilog 14 逻辑仿真，未执行综合、Vivado STA 或板级调试，不作任何物理时序与频率声明。

---

## 6. 复现验证入口

在本地 Linux 终端执行以下命令即可一键复跑完整验证套件：

```bash
cd /home/yang/Desktop/项目/v023_repair/gemini_stream_round2
./run_all.sh
```

输出将自动写入 `result.json`，各个子测试日志位于 `logs/*.log` 与 `logs/*.out`。
