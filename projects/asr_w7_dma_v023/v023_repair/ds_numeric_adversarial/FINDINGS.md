# FINDINGS — 数值对抗审计逐条记录

日期：2026-10-29  
工作目录：`/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial`  
约束：仅逻辑仿真；未综合/Vivado/板卡/VNC/push；未修改被测模块。  
总体：**不通过**。以下按严重度排列，均附可复现命令/日志/源码 SHA。

---

## F0. 独立参考的可信度

### F0.1 Python 精确参考
`ref/refmodel.py` 不依赖被测方 golden。关键实现：
- `round_f32()`：Fraction → binary32 RNE，溢出阈值 `(2^25-1)*2^103`，FTZ；
- `fma_bits()`：`round_once(x*s + b)`，不是先乘后加两次舍入；
- `f32_to_i16()`：RNE + 饱和，NaN→0，±Inf→饱和；
- `i48_to_f32_bits()`：精确整数转换。

### F0.2 C libc 交叉核对（`scripts/crosscheck_c.py`）
结果（`ref_c_crosscheck.json`）：

| 参考 | 向量数 | 失配 |
|---|---:|---:|
| i48→f32 vs C `(float)(int64_t)` | 37,166 | 0 |
| f32→i16 vs C `lrintf`+饱和 | 464,154 | 0 |
| FMA vs C `fmaf`（normal-input finite non-zero） | 7,272 | 0 |

因此下文 FMA 的 normal-input 失配不是参考模型误差。FMA 的 subnormal/特殊值语义在 DUT 与 FTZ 契约间有差异，单列，不作为主要阻断证据。

### F0.3 Watchdog
- Python 墙钟：`run_cmd(..., timeout)`，超时 `os.killpg` 并写 `WATCHDOG: wall-clock timeout`。
- SV cycle：各 TB `cycle > maxcycles` 时打印 `WATCHDOG: ...` 并 `$finish(2)`。
- 所有仿真均正常结束（rc=0 或 1/2 的断言失败），无墙钟超时。

---

## F1. 修复版 FMA：tie-to-even 错误（阻断）

**对象**：`gemini_fma_repair/candidate/epilogue_fma_stage.sv`  
`5d52cbc54e1f61029a9c24544ae573ab345ffc8335bb57964dbfbbe8b62183bd`  
`fp32_fma_pipe.sv` `3263c02d63a886f9a8701d19f8c07e3a1b66670ad737206b24846194736cb23f`  
`asr_fma_ip.sv` `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599`

**反例**：

| 输入 | 正确 RNE | DUT |
|---|---|---|
| `0x3f800003 * 0x3fc00000 + 0` | `0x3fc00004` | `0x3fc00005` |
| `0x3f800007 * 0x3fc00000 + 0` | `0x3fc0000a` | `0x3fc0000b` |
| `0x3f800001 * 0x3fc00000 + 0` | `0x3fc00002` | `0x3fc00002`（主验收反例已修好） |

**规模**：`result_fma_repair.json` → 8,734 向量，137 失配；其中 `by_class.normal = 90/8311`。  
**根因（代码级）**：`fp32_fma_pipe.sv:333`  
`wire round_up = s3_round_bit && (s3_sticky || s3_mant24[0]);`  
在精确半 ULP 的 tie 上，`s3_sticky` 被错误置 1，于是 `round_up=1`，没有执行 tie-to-even（保留位为偶时应舍去）。  
**复现**：
```bash
python3 scripts/run_suite.py --label fma_repair \
  --i48  /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_i48_to_f32.sv \
  --fma  /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_fma_stage.sv \
  --fma-pipe /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/fp32_fma_pipe.sv \
  --f32i16 /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_f32_to_i16.sv \
  --relu /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_relu.sv \
  --lane /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_lane.sv \
  --stream /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_stream_engine_v023.sv \
  --only fma
```
日志：`logs/fma_repair_fma.log`，输出：`logs/fma_repair_fma.out`。

---

## F2. 修复版 FMA：极端指数对齐错误（阻断）

**反例**：

| 输入 | 正确 | DUT |
|---|---|---|
| `0x00800000 * 0x3f800001 + 0x3f800000` | `0x3f800000` (1.0) | `0x0e800000` (≈2^-97) |
| `0x00800000 * 0x3f800001 + 0xbf800000` | `0xbf800000` (-1.0) | `0x8e800000` |
| `0x00800000 * 0x3fc00000 + 0x3f800000` | `0x3f800000` | `0x0e800000` |

**规模**：66 个 `normal/normal/normal` 失配（`result_fma_repair.json` `by_class.normal` 共 90，其中 24 个是 F1 的 bias=0 tie）。  
**现象**：乘积远小于 bias 时，结果指数被取成乘积指数；正确应取 bias 指数并保留 sticky。  
**C 核对**：`fmaf(0x00800000,0x3f800001,0x3f800000)=0x3f800000`，与 Python 参考一致。  
**复现**：同 F1；查看 `result_fma_repair.json` 的 `examples` 中 `x=00800000` 条目。

---

## F3. 修复版 FMA：特殊值错误（阻断/边界）

| 场景 | 正确 IEEE | DUT |
|---|---|---|
| `inf * 0 + 0` | NaN `0x7fc00000` | `0x7f800000` |
| `inf * 1 + (-inf)` | NaN | `0x7f800000` |
| `0 * 1 + (-0)` | `-0` (`0x80000000`) | `+0` |
| `-0 * 1 + (+0)` | `+0` | `-0` |

`by_class.inf = 34/106`，`by_class.zero = 2/24`。  
**影响**：模型正常路径通常不产生 inf/NaN，但 QDQ 错误处理/溢出保护会依赖这些语义；接口契约明确要求 NaN/Inf 规则。

---

## F4. 修复版 FMA：官方 1001 fixture 不足（流程问题）

`gemini_fma_repair/result.json` 声称 `vendor_fma_fixture 1001/1001 exact`，但：
- 该 fixture 不覆盖精确 tie-to-even（F1）；
- 不覆盖极端指数对齐（F2）；
- 不覆盖 `inf*0`/`inf+(-inf)`（F3）。
因此 1001/1001 不能作为 FMA 验收通过证据；本审计的 137 个失配均在其覆盖之外。

---

## F5. 旧 FMA：截断乘法 + 分离加法（历史负例）

`gemini_epilogue/epilogue_fma_stage.sv` `eacf04eb...`：
- 8,734 向量，4,271 失配；
- mode1 3,772/6,734；mode2 499/1,000；mode0 0/1,000；
- `by_class`：normal 4,067/8,311，nan 111/140，inf 54/106，subnormal 39/153。
- 主验收反例 `0x3f800001*0x3fc00000` 返回 `0x3fc00001`，正确 `0x3fc00002`。
- 结论：旧版是“截断乘法 + 无舍入加法”，不是单次舍入 FMA；修复版只修了部分症状。

---

## F6. 旧 approx：假三档 + TIER0 因子 2（历史负例）

`gemini_approx/rtl/approx_div_sqrt.sv` `e360e7e4...`：
- TIER0/1/2 三档在 15,168 向量上延迟均为 **4**，II=1；
- TIER1 与 TIER2 结果/标志 **15,168/15,168 逐位相同**（无第二次 NR）；
- TIER0 的 `refined_y = {seed_r1,8'b0}` 把 Q16 seed 左移 8 位（Q23 应为 7 位），整体因子 2：
  - DIV 最大相对误差 106.66%，均值 73.29%；
  - SQRT 最大 49.80%，均值 19.74%；
  - RSQRT 最大 33.39%，均值 16.55%。
- 结论：旧“2/4/7 拍三档、TIER2 更低误差”声明不成立；新版删除该声明是正确的。

---

## F7. 新 approx：DIV 因子 2（阻断）

`gemini_approx_repair/candidate/rtl/approx_div_sqrt.sv` `298a1fb5...`

**反例**：`0x3f800000 / 0x41fffad2`（1.0 / 31.9998）  
- 正确：0.03125247006269116  
- DUT：`0x3d7fde3c` = 0.062467798590660095  
- 相对误差：**0.9988115648251892（99.881%）**

**规模**：15,168 向量中仅 1 个 >10% DIV 用例；但它是真实边界，不能被“最大 0.108%”覆盖。  
**日志**：`logs/approx_repair2_approx_t1_bp0.out`。  
**复现**：见 REPORT 的新 approx 命令；`approx_worst_cases.json` 第一条 DIV。

---

## F8. 新 approx：RSQRT 因子 2（阻断）

**反例**：`RSQRT(0x7f7fffff)`（max finite）  
- 正确：5.421011023986243e-20  
- DUT：`0x1ffffff4` = 1.0842013970036802e-19  
- 相对误差：**0.9999985098839224**

**规模**：15,168 向量中仅 1 个 >10% RSQRT 用例；属指数边界。  
**日志**：同上；`approx_worst_cases.json` 第一条 RSQRT。

---

## F9. 新 approx：RSQRT(-0) 符号（边界）

| 输入 | 正确 IEEE | DUT | flags |
|---|---|---|---|
| `0x80000000` (-0) | `0xff800000` (-inf) | `0x7f800000` (+inf) | `0x02`（div0） |
| `0x80000001` (-subnormal) | `0xff800000` | `0x7f800000` | `0x0a`（underflow+div0） |
| `0x806ce3ee` (-subnormal) | `0xff800000` | `0x7f800000` | `0x0a` |

`special_mismatch=3`。模型 LayerNorm 的 `var+eps` 为正，实际影响低，但接口契约的“negative zero / negative input”规则未完全满足。  
**源码位置**：`approx_div_sqrt.sv` 的 SQRT/RSQRT special 分支，`is_zero(a_ftz)` 时 `special_val_s0 = FP32_POS_INF`，未按 `a_sign` 取负。

---

## F10. 新 approx：通过项（结构整改）

- TIER=1、LATENCY=5、II=1：实测 latency 5（BP0 全部 5），II=1；BP=1 下 min latency 5，stall 时 stability=0。
- TIER=0/2、LATENCY=4/7：elaboration 失败（`illegal_*` 模块缺失），符合“删除假三档”的声明。
- flush：3 个在途请求 + 1 拍 flush → 0 个 phantom 输出；flush 后新请求 5 拍正确输出；`APPROX_FLUSH_ERRORS=0`。
- flags：15,168 向量上 invalid/div0/overflow/underflow/approx/reserved 语义 0 错误（`flag_semantic_errors=0`）。
- tag/order：0 错误；ready/valid 反压 stability=0。
- 误差（排除 F7/F8）：DIV max 0.11147%，mean 0.0371%；SQRT max 5.78e-6，mean 1.14e-6；RSQRT max 5.78e-6（排除 max-finite 因子 2），mean 2.51e-4。

---

## F11. Stream engine：A16 tag 被 packer 污染（阻断）

**对象**：`epilogue_stream_engine_v023.sv` `b99a664b...`（新旧版同 SHA）。

**代码**：
```systemverilog
assign a16_tag = p128_valid ? p128_tag : lane_tag[0];
```
当 128-bit packer 有待发 beat 时，A16 的 tag 取 `p128_tag`，而不是当前 lane 的 tag。

**实测**（BP=0，256 beats）：
- `tag_mismatch = 255/256`；
- 例：beat 2 得到 tag `0001`，期望 `0002`；beat 4 得到 `0003`，期望 `0004`。
- 数据本身 0 失配；packed 数据 0 失配。

**日志**：`logs/fma_repair_stream2_stream_m0_r0_s0_a-1_bp0_pe0.out`。  
**影响**：任何用 A16 tag 做 beat/epoch 对齐的下游会错位；这是接口契约“tag 逐拍传播”的直接违反。

---

## F12. Stream engine：packed 反压下 A16 ready/valid 违约（阻断）

**代码**：
```systemverilog
assign a16_valid = lanes_out_all_valid && !abort;
assign lanes_downstream_ready = a16_ready && (!packer_full);
```
真实推进条件是 `lanes_downstream_ready`，但对外 `a16_valid` 未包含 `!packer_full`。当 `packer_full=1` 且 `a16_ready=1` 时，外部看到 `valid&&ready`，生产方却不推进，消费者会重复采样。

**实测**（BP=2：`a16_ready=1`，`a16_packed_ready` 随机）：
- A16 握手 **402** 次，期望 256 次，重复 **146** 次；
- packed 仍为 128 拍、0 数据失配（packer 本身正确）；
- `a16_count_mismatch=146`。

**日志**：`result_fma_repair_stream_bp2b.json`，`logs/..._bp2_...out`。  
**影响**：A16 与 packed 两个下游同时使用时，A16 路径会重复输出；属 AXI-stream 协议违约。

---

## F13. Stream engine：参数预装口无效（阻断）

**代码**：`param_wr_ready = 1'b1;`，但 `param_wr_addr/data` 没有任何写入逻辑；`active_scale/bias` 只由 `cfg_*` 更新。  
**实测**：`param_en=1, param_addr=0, param_data=0x3f000000 (0.5)`，`cfg_scale=0x3f800000 (1.0)`，mode=2：
- 按参数口期望（0.5）比较：113/256 A16 beat 失配；
- 实际输出与 cfg_scale=1.0 一致。
**日志**：`result_fma_repair_stream2.json` → `stream_param_port`。  
**影响**：INTERFACE 声称“PL DMA 参数预装、支持 per-channel scales”，实际不可用。

---

## F14. Stream engine：运行中重配置命中在途 beat（阻断）

**代码**：`assign cfg_ready = !in_burst;`；`in_burst` 在最后一个输入握手当拍清零，但该 beat 仍在 9 级 lane 中。  
**实测**：2-beat burst，初始 scale=1.0；beat1（last）被接收后立即写入 cfg scale=3.0：
- beat0 输出 1（正确，旧 scale）；
- beat1 输出 **6**（错误，应为 2；新 scale 3.0 命中了在途 beat）。
**日志**：`result_fma_repair_stream2.json` → `stream_reconfig`，`a16=["0001000100010001","0006000600060006"]`。  
**影响**：描述符切换/多任务流水时，最后一个 beat 可能用错 scale/bias，数值静默错误。

---

## F15. Stream engine：通过项

- mode 0 转换、ReLU、spill 数据、128-bit packed 数据/尾包补零：BP=0 下 0 数据失配。
- abort：0 个 post-abort 输出；`stat_c48_beats_in`/`stat_a16_beats_out` 保留。
- leaf flush：i48/fma/f32i16/lane 0 错误；新 FMA/lane 延迟调整后 0 错误。
- 反压稳定性：FMA BP=1 stability=0；approx BP=1 stability=0。
- 但上述 tag/readyvalid/param/reconfig 问题仍使 stream engine 不可验收。

---

## F16. i48→FP32：未发现错误

- 37,166 向量：0 失配，tag/last 0 错误，stability=0；
- 覆盖：0、±1、2^k±1、k=0..47、±2^47、tie/just-below/just-above（t=24..47）、随机 48-bit；
- C `(float)(int64_t)` 交叉核对 0 失配。
- 结论：本测试集内通过；不宣称 2^48 穷举。

---

## F17. FP32→i16：未发现错误

- 464,154 向量：0 失配，tag 0 错误，stability=0；
- 覆盖：n∈[-33000,33000] 的整数/±0.5/±0.25/±0.75、clamp 边界 ±32767.5/±32768.5、NaN/Inf/±0/subnormal、200k 随机位型；
- C `lrintf`+饱和交叉核对 0 失配。
- 结论：本测试集内通过；RNE/饱和/NaN/Inf 行为与独立 C 参考一致。

---

## F18. 实际模型 vs KWT 混淆（口径阻断）

脚本：`scripts/audit_model.py` → `model_audit.json`。

| 项 | 旧声明 | 实测 |
|---|---|---|
| 模型族 | KWT-1 keyword transformer | Conformer/Transformer ASR encoder-decoder |
| encoder/decoder 层数 | — | 12 / 6 |
| d_model | 64 features | **512** |
| LayerNorm 实例 | — | 79（输出 scale 数组 [512]） |
| Softmax | 99 elements/head | 24 Softmax（12+12）+1 LogSoftmax；case0000 128 frames/16 tokens |
| LayerNorm 输出 scale | 未说明 | 79 个：min 1.356e-5，max 3.758e-3，median 1.102e-4 |
| gamma/beta | 可视为 trivial | gamma 40,960 个值 100% 非 1；beta 39,936 个值 99.957% 非 0；范围 [-0.548,12.318]/[-14.785,8.166] |
| var ∈ [1e-6,1e2], eps=1e-6 | 直接引用 | 只读树中无 ONNX/校准数据，**无法验证**；不得用旧 KWT 范围冒充当前模型 |

**结论**：旧 gemini 报告的 LayerNorm/Softmax 域假设来自 KWT/旧竞赛，不是本项目 ASR 模型；不能据此宣称“当前模型精度可用”。

---

## F19. 未验证/不可声称

1. i48/f32i16 非穷举；FMA/approx 也未穷举所有 2^32 输入。
2. 未综合/未 STA；不声称 300/600 MHz 或 ns 裕量。
3. 未做完整 ASR 推理/WER/CER；无当前模型真实 LayerNorm 输入分布。
4. FMA subnormal 输入/零符号与 vendor IP 契约的差异未裁决；本报告只用 normal-input 90 个失配作主阻断。
5. stream 只用 BFM；未接真实 ds_vector/ds_layout。
6. 新 approx 的 `flush` 端口在 `ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv:160` 未连接；源码 `input wire flush` 无默认值，与 INTERFACE “default 0” 不一致；该整合风险未在 wrapper 内复测。
7. 未验证 128-bit packed 反压重复握手对真实下游的破坏；仅证明 A16 接口层重复。

---

## F20. 建议的整改顺序（不修改被测代码，仅建议）

1. FMA：修正 tie-even 的 sticky 生成；重做“乘积远小于 bias”的指数选择/对齐；补齐 inf*0、inf+(-inf)、零符号；把本报告 `vectors/fma.vec` 加入回归。
2. Approx：修正 DIV/RSQRT 在“商/结果接近 2 的幂”时的规格化分支（当前因子 2）；修正 RSQRT(-0) 符号；把 `vectors/approx.vec` 的 15,168 向量加入回归。
3. Stream：A16 tag 固定取 `lane_tag[0]`；`a16_valid` 在 `packer_full` 时拉低（或不要把 packer_full 放进 lane ready）；实现 `param_wr_*` 或从接口删除；`cfg_ready` 改为等 lane 完全排空；把 tag/BP2/reconfig/param 用例加入回归。
4. 口径：删除 KWT-1/64/99/var 范围声明；用当前 512 维 ASR 参数重新做 LayerNorm/Softmax 域分析；没有 ONNX 就标 UNVERIFIED。
5. 所有“100% PASS”脚本必须去掉无条件打印；每个断言失败必须影响退出码。
