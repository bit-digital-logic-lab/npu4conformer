# REPORT — 独立数值验收审计（ds_numeric_adversarial）

日期：2026-10-29  
范围：仅本地 RTL 逻辑仿真（Icarus Verilog 14 + Python 精确算术 + C libc 交叉核对）。  
禁止项均未执行：未综合、未 Vivado、未上板、未 VNC、未 push；未修改任何被测模块或其它 worker 文件。  
结论：**整体不通过（overall_pass=false）**。i48→FP32、FP32→i16 在本文测试集内通过；修复版 FMA、修复版 approx、epilogue stream engine 仍有阻断性数值/协议错误。

---

## 1. 独立参考与“不自证”措施

1. `ref/refmodel.py` 用 Python 整数/Fraction 从零实现：
   - binary32 RNE（最近偶数）舍入、FTZ；
   - i48→FP32 精确整数转换；
   - 真正单次舍入 FMA：`round_once(x*s + b)`；
   - FP32→i16 的 RNE + `[-32768,32767]` 饱和、NaN→0、±Inf→饱和。
   没有 import 或复用 `gemini_epilogue/golden_epilogue.py`、`gemini_approx/golden/approx_model.py` 或任何被测方 golden。
2. `ref/c_ref.c` 用 C libc 做真正独立交叉核对：
   - i48→f32：`(float)(int64_t)`，37,166 向量，0 失配；
   - f32→i16：`lrintf` + 饱和，464,154 向量，0 失配；
   - FMA：`fmaf`，normal-input / finite / non-zero 结果 7,272 向量，0 失配。
   说明：FMA 的 subnormal/特殊值语义在 DUT 与 FTZ 契约之间本身存在差异，故交叉核对只取 normal-input finite non-zero 结果；这些正是本报告的主要 FMA 反例所在类别。
3. 每个仿真都有两层 watchdog：
   - Python `subprocess` 墙钟 watchdog，超时杀进程组并写 `logs/*.log`；
   - SV testbench 内 cycle watchdog，超限打印 `WATCHDOG: ...` 并以退出码 2 结束。
4. 所有结果保存在本目录；`result.json` 汇总失败、退出码、源码 SHA 和未验证范围。

---

## 2. 测试规模与结果总表

| 被测对象 | 测试 | 规模 | 结果 | 退出码 |
|---|---|---|---:|---:|
| old `epilogue_i48_to_f32` | 对抗向量 + 尾包/tag | 37,166 | **PASS**，0 失配 | 0 |
| old `epilogue_f32_to_i16` | 整数/半整数/边界/特殊/随机 | 464,154 | **PASS**，0 失配 | 0 |
| old `epilogue_fma_stage` | 真 FMA 参考，mode 0/1/2 | 8,734 | **FAIL**，4,271 失配 | 1 |
| old `approx_div_sqrt` TIER0/1/2 | DIV/SQRT/RSQRT + 特殊 + 反压 | 15,168 ×3 | **FAIL**；TIER0 因子 2 错误；TIER1=TIER2 逐位相同；三档延迟均为 4 | 1 |
| 新 `gemini_fma_repair` FMA | 同上 | 8,734 | **FAIL**，137 失配（normal 90） | 1 |
| 新 `gemini_fma_repair` FMA BP=1 | 随机反压 | 8,734 | **FAIL**，137 失配；stability=0 | 1 |
| 新 `gemini_fma_repair` flush | leaf/lane flush | 4 模块 | **PASS**，0 错误 | 0 |
| 新 `gemini_fma_repair` stream | 转换/FMA/ReLU/spill/abort/packed | 256 beats | **FAIL**：A16 tag 255/256 错；FMA 对抗 75 失配；param 口无效；reconfig 命中在途 beat | 1 |
| 新 `gemini_fma_repair` stream BP=2 | 128-bit packed 反压 | 256 beats | **FAIL**：A16 握手 402 次（146 重复） | 1 |
| 新 `gemini_approx_repair` TIER=1 | DIV/SQRT/RSQRT + 特殊 + 反压 | 15,168 | **FAIL**：DIV/RSQRT 边界因子 2；RSQRT(-0) 符号错；flags/stability/tag 通过 | 1 |
| 新 `gemini_approx_repair` flush | 5-cycle latency + flush | 3+1 请求 | **PASS**，0 错误 | 0 |
| 新 `gemini_approx_repair` 参数拒绝 | TIER=0/2, LATENCY=4/7 | 4 组 | **PASS**，全部 elaboration 拒绝 | 0 |

---

## 3. 阻断性发现

### 3.1 修复版 FMA 仍非真正 RNE，且极端指数对齐错误（FMA-1/2/3）

修复版通过了主验收反例 `0x3f800001 * 0x3fc00000 = 0x3fc00002`，但独立对抗集仍失败 **137/8,734**：

1. **RNE tie-to-even 错误**（90 个 normal-input 失配中的 24 个 bias=0 用例）：
   - `0x3f800003 * 0x3fc00000`：正确 `0x3fc00004`，DUT `0x3fc00005`。
   - `0x3f800007 * 0x3fc00000`：正确 `0x3fc0000a`，DUT `0x3fc0000b`。
   - 现象：恰好半 ULP 时 sticky 被错误置位，`round_up = round_bit && (sticky || lsb)` 把 tie 当成“大于半 ULP”，没有执行 tie-to-even。
2. **极端指数对齐错误**（66 个 normal/normal/normal 失配）：
   - `0x00800000 * 0x3f800001 + 0x3f800000`：正确 `0x3f800000`（1.0），DUT `0x0e800000`（≈2^-97）。
   - `0x00800000 * 0x3f800001 - 0x3f800000`：正确 `0xbf800000`（-1.0），DUT `0x8e800000`。
   - 现象：当乘积远小于 bias 时，对齐/规格化后的指数被错误选成乘积指数，而不是加数指数。
3. **特殊值**：`inf * 0` 返回 `±inf` 而非 NaN；`inf + (-inf)` 返回 `±inf` 而非 NaN；`+0*1 + (-0)` 与 `-0*1 + (+0)` 的零符号相反。共 34 个 inf-class、2 个 zero-class 失配。
4. **官方 1001 向量 fixture 不足**：`gemini_fma_repair/result.json` 的 1001/1001 通过不能覆盖 tie-even、极端指数对齐和 inf*0/inf-inf；本报告的反例均在该 fixture 之外。
5. `asr_fma_ip.sv` 包装器复用同一 `fp32_fma_pipe`，独立复跑同样 **137/8,734** 失配，因此不是包装层问题。

### 3.2 修复版 approx 仍有因子 2 边界错误（APPROX-1/2/3）

新 approx 正确删除了假三档、改为单档 `LATENCY=5, II=1`，并增加了 flush；结构整改通过。但数值仍有：

1. **DIV 因子 2**：`0x3f800000 / 0x41fffad2`（1.0 / 31.9998）：
   - 正确 0.0312524701；DUT `0x3d7fde3c` = 0.0624677986；相对误差 **99.881%**。
   - 这超出 `gemini_approx_repair/result.json` 宣称的 `div_max_rel_error=0.001080`。
2. **RSQRT 因子 2**：`RSQRT(0x7f7fffff)`：
   - 正确 5.421011e-20；DUT `0x1ffffff4` = 1.084201e-19；相对误差 **99.99985%**。
3. **RSQRT(-0) 符号**：`RSQRT(0x80000000)` 返回 `+inf`，IEEE-754 应为 `-inf`；`RSQRT(negative subnormal)` 同样。`flags[1]` 正确置位，但结果符号错。模型 LayerNorm 的 `var+eps` 为正，实际影响低，仍属边界错误。
4. **其余误差**：排除上述两个因子 2 用例后，DIV 最大相对误差 0.11147%（略高于报告的 0.1080%），SQRT/RSQRT 最大 5.78e-6；均值 DIV 0.0371%，SQRT 1.14e-6，RSQRT 2.51e-4。`flags` 语义（invalid/div0/overflow/underflow/approx/reserved）在 15,168 向量上 0 错误；反压 stability 0 错误；tag/order 0 错误；latency=5，II=1。
5. **旧版三档**：TIER0 因 `{seed,8'b0}` 把 Q16 seed 左移 8 位（应为 7 位）而整体因子 2；DIV 均值误差 73.3%。TIER2 与 TIER1 结果逐位相同，三档延迟均为 4，证实旧“三档”是虚假声明。新版删除该声明是正确的。

### 3.3 Epilogue stream engine 的 tag / ready-valid / 配置问题（STREAM-1..4）

FMA 修复目录中的 `epilogue_stream_engine_v023.sv` 与旧版 SHA 相同（`b99a...`），以下问题在新旧版均存在：

1. **A16 tag 被 128-bit packer 污染**：`a16_tag = p128_valid ? p128_tag : lane_tag[0]`。只要 packer 里有一个待发 beat，A16 的 tag 就变成上一个 packed beat 的 tag。BP=0 时 **255/256** A16 tag 错；例如 beat 2 得到 tag=1 而不是 2。
2. **A16 ready/valid 违约（packed 反压）**：`a16_valid = lanes_out_all_valid && !abort`，而 lane 的真实推进条件是 `lanes_downstream_ready = a16_ready && !packer_full`。当 `packer_full=1` 且外部 `a16_ready=1` 时，`a16_valid && a16_ready` 仍为真，但生产方不推进，消费者会重复采样同一 beat。BP=2 实测 **402 次 A16 握手 / 256 beats（146 次重复）**。
3. **参数预装口无效**：`param_wr_valid/addr/data` 只接了 `param_wr_ready=1`，没有任何写寄存器逻辑。通过参数口写 scale=0.5、cfg_scale=1.0，输出仍按 1.0 计算；113/256 A16 beat 与参数口期望不符。
4. **配置可命中在途 beat**：`cfg_ready = !in_burst`，而 `in_burst` 在最后一个输入握手当拍就清零；此时最后一个 beat 仍在 9 级 lane 中。实测：beat 在 scale=1.0 下被接收，随后立即写入 cfg scale=3.0，输出变成 6（应为 2）。
5. **通过项**：mode 0 转换、ReLU、spill 数据、128-bit packed 数据与奇数尾包补零在 BP=0 下 0 数据失配；abort 后 0 个 post-abort 输出，统计保留；leaf/lane flush 0 错误。

---

## 4. 实际 ASR 模型 vs 旧 KWT 混淆逐项核查

数据源（只读）：`tasks/ds_pl_autonomy/assets/manifest_v022.json`、`work/assets/parameters002/parameters.bin`、`v023_repair/ds_graph/analysis/nonmatrix_ops.json`。脚本：`scripts/audit_model.py`，输出 `model_audit.json`。

| 旧声明（gemini_approx/epilogue） | 实际项目模型 | 判定 |
|---|---|---|
| KWT-1 keyword transformer | Conformer/Transformer ASR encoder-decoder（`encoder.encoders.N`、`decoder.decoders.N`、`conv_module`、`norm_mha/norm_conv/norm_ff/norm_ff_macaron`） | **REFUTED** |
| LayerNorm 64 features | **512**（12 encoder + 6 decoder layers；79 个 LayerNormalization 实例） | **REFUTED** |
| LayerNorm var ∈ [1e-6, 1e2]，eps=1e-6 | 参数镜像中无 ONNX/校准数据，无法验证；该范围是旧 KWT/竞赛假设 | **UNVERIFIED**，不得冒用 |
| Softmax 99 elements/head | 24 个 Softmax（encoder 12 + decoder 12）+ 1 LogSoftmax；case0000 为 128 frames / 16 supplied tokens | **REFUTED**（99 是 KWT 关键词数） |
| scale/bias 可视为 trivial | 79 个 LayerNorm 输出 scale：min 1.356e-5，max 3.758e-3，median 1.102e-4；gamma 40,960 个值 100% 非 1，beta 39,936 个值 99.957% 非 0，范围分别 [-0.548,12.318]、[-14.785,8.166] | **REFUTED**；非平凡 scale/bias 必须测 |

因此本报告不使用旧 KWT 的 LayerNorm 范围来“证明”当前模型精度；也没有声称任何全模型 WER/CER 或 300/600 MHz 达标。

---

## 5. 未验证范围（诚实限定）

1. i48→f32 与 f32→i16 不是穷举证明，只是 37k/464k 对抗向量 + C libc 交叉核对；未覆盖全部 2^48 / 2^32 输入。
2. 未综合、未 Vivado STA；不声明 300/600 MHz 或任何 ns 裕量。
3. 未做完整 ASR 模型推理；没有 WER/CER；没有用当前模型的真实 LayerNorm 输入方差/epsilon 做端到端验证（只读树中无 ONNX/校准数据）。
4. FMA 的 subnormal 输入/零符号语义与 vendor IP 契约可能存在差异；本报告把 subnormal 失配单列，主要阻断证据是 normal-input 的 90 个失配。
5. stream engine 只用 BFM 验证，未接真实 ds_vector/ds_layout 消费者；packed 反压重复握手对下游的实际破坏需整合复现。
6. 新 approx 未在 ds_vector wrapper 内复测其未连接的 `flush` 端口；该端口默认值声明与源码不一致，属整合风险。

---

## 6. 交付物与复现

- `result.json`：机器可读汇总（overall_pass=false、失败、SHA、退出码、未验证范围）。
- `FINDINGS.md`：逐条证据、根因、复现命令。
- `INTERFACE.md`：测试台/向量格式契约。
- `ref/refmodel.py`、`ref/c_ref.c`：独立参考。
- `tb/*.sv`：i48/FMA/i16/approx/stream/flush/asr_fma_ip 测试台。
- `scripts/gen_vectors.py`、`run_suite.py`、`crosscheck_c.py`、`audit_model.py`、`consolidate.py`。
- `logs/`：每个仿真的 stdout、退出码、watchdog 记录。
- `vectors/`：对抗向量。
- `model_audit.json`、`ref_c_crosscheck.json`、`approx_worst_cases.json`。

关键源码 SHA（完整清单见 `result.json`）：

| 对象 | SHA-256 |
|---|---|
| old `epilogue_fma_stage.sv` | `eacf04eb3c5078b908c71533a9cdf318986f228dbc68e0ac01879bfb36faa032` |
| old `approx_div_sqrt.sv` | `e360e7e455261ead4ee32ecacc93bed77f4de09458d3d689ae3eb3e948495ec1` |
| repair `epilogue_fma_stage.sv` | `5d52cbc54e1f61029a9c24544ae573ab345ffc8335bb57964dbfbbe8b62183bd` |
| repair `fp32_fma_pipe.sv` | `3263c02d63a886f9a8701d19f8c07e3a1b66670ad737206b24846194736cb23f` |
| repair `asr_fma_ip.sv` | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` |
| repair `approx_div_sqrt.sv` | `298a1fb5772c6a156c118b983521e2366ee3d6c361cb85a7395c2f64e7e0c343` |
| unchanged stream engine | `b99a664bc3e49bed21acf79c22281506e85ce347777ad578bfbe2c2a78984bce` |

复现入口：

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial
python3 scripts/gen_vectors.py
python3 scripts/audit_model.py
python3 scripts/crosscheck_c.py
python3 scripts/run_suite.py --label old_final
# 新 FMA（示例）
python3 scripts/run_suite.py --label fma_repair \
  --i48  /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_i48_to_f32.sv \
  --fma  /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_fma_stage.sv \
  --fma-pipe /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/fp32_fma_pipe.sv \
  --f32i16 /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_f32_to_i16.sv \
  --relu /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_relu.sv \
  --lane /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_lane.sv \
  --stream /home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate/epilogue_stream_engine_v023.sv \
  --only fma
# 新 approx
python3 scripts/run_suite.py --label approx_repair2 \
  --approx /home/yang/Desktop/项目/v023_repair/gemini_approx_repair/candidate/rtl/approx_div_sqrt.sv \
  --recip  /home/yang/Desktop/项目/v023_repair/gemini_approx_repair/candidate/rtl/approx_recip_lut.sv \
  --rsqrt  /home/yang/Desktop/项目/v023_repair/gemini_approx_repair/candidate/rtl/approx_rsqrt_lut.sv \
  --approx-has-flush --only approx
```

---

## 7. 结论

- **i48→FP32**：在本对抗集内未发现错误；尾包/tag/last/反压/稳定均通过。不能据此宣称 2^48 穷举正确。
- **FP32→i16**：在本对抗集内未发现错误（含所有整数/半整数边界、饱和、NaN/Inf、随机位型）；C `lrintf` 交叉核对一致。
- **FMA**：修复版修好了主验收那一个反例，但不是可信的单次舍入 RNE FMA；tie-even 与极端指数对齐仍有真实错误，且官方 1001 fixture 未覆盖。
- **approx**：修复版结构上诚实（单档、5 拍、II=1、flush、参数拒绝），但 DIV/RSQRT 仍有因子 2 边界错误，不能按 0.108% 上限验收；旧三档声明被证实虚假。
- **epilogue stream**：数据通路在 BP=0 下基本正确，但 A16 tag、packed 反压 ready/valid、参数预装、运行中重配置四项不满足接口契约，属阻断。
- **模型口径**：项目实际是 512 维 Conformer/Transformer ASR，不是 KWT-1；旧 64 维/99 元素/LayerNorm 范围不能用于当前模型精度论证。

因此：**本独立审计不给出 PASS；整体验收继续阻断。**
