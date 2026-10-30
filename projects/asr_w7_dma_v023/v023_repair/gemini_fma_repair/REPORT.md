# Gemini Epilogue 融合乘加数值逻辑修复报告 (gemini_fma_repair)

**日期**: 2026-10-29  
**工作目录**: `/home/yang/Desktop/项目/v023_repair/gemini_fma_repair`  
**候选交付目录**: `/home/yang/Desktop/项目/v023_repair/gemini_fma_repair/candidate`  
**执行范围**: 仅本地逻辑仿真（Icarus Verilog + Python 3.12），未综合、未上板、未改动其他工作目录。所有仿真配备可诊断 Watchdog。

---

## 1. 任务背景与主验收阻断根因

在主验收阶段（见 `v023_repair/primary_acceptance/REPORT.md`），`gemini_epilogue` 模块整体验收被阻断，核心原因如下：
1. **乘法舍入反例复现**:
   `tb_fma_probe.sv` 实测 $0\text{x}3f800001 \times 0\text{x}3fc00000$ 返回 `3fc00001`，正确 IEEE-754 最近偶数舍入（RNE）期望为 `3fc00002`，报告 `ROUNDING_FAIL`。
2. **截断与伪 FMA 替代**:
   原 `epilogue_fma_stage.sv` 的 `fp32_mul` 直接对乘积 mantissa 截断（截取 `[46:24]`），毫无舍入逻辑；且在 FMA 模式下采用先乘后加（`prod = fp32_mul; add = fp32_add`），发生两次舍入/截断，非原工程要求的真实单次舍入（Single-Rounding FMA）。
3. **时序与流水虚构**:
   原 `fp32_add` 在单周期组合逻辑中包含 `while (!sum_mant[25])` 动态循环进行长规格化移位，却声称支持 300MHz/600MHz 高频，属于不可靠设计。
4. **测试虚假自证**:
   原 `tb_epilogue_random_stress.sv` 硬编码 `cfg_fma_mode = 0`（仅覆盖转换旁路），刻意避开 FMA 运算，未测试非平凡 scale/bias。

---

## 2. 原始工程契约核对 (`asr_fma_ip`)

经全面核对原工程文件（`work/rtl/ddr_vector_engine.sv`、`work/scripts/make_fma_fixture.py`、`work/scripts/test_fma_vendor.py` 以及原始 ZIP 内 `asr_fma_ip.xci`）：
- **真实 FMA 契约**: 原工程 `ddr_vector_engine.sv` (行 77) 例化 `asr_fma_ip` 处理 `op == 17`。其数值契约为真正的 IEEE-754 binary32 FMA，执行单次舍入（Single Rounding to Nearest Even, RNE）。
- **抵消算例证据**: `work/scripts/make_fma_fixture.py` 专门构造了：
  $$a = 1 + 2^{-23} (\text{0x3f800001}), \quad b = 1 - 2^{-23} (\text{0x3f7ffffe}), \quad c = -1.0 (\text{0xbf800000})$$
  若先做乘法舍入：$a \times b = 1 - 2^{-46} \to 1.0$，再加 $c = -1.0 \to 0.0$。
  而在真实 FMA 下：$a \times b + c = -2^{-46}$（在 FP32 下表现为指数 81 的正规数 `0xa8800000`）。
- **原 IP 参数**: Xilinx `floating_point:7.1` FMA，NonBlocking，Latency=12（原工程测试和流式接口不依赖固定拍数，依赖 `valid` 握手），单拍吞吐（Rate=1）。

---

## 3. 独立可信 Python 参考模型

在 `reference/fma_reference.py` 中实现了独立、数学精确的参考模型：
1. **精确有理数与整数 RNE 实现 (`fma_exact_rational`)**:
   - 彻底摆脱双精度浮点数近似的精度漏洞；
   - 将任意 FP32 输入精确映射为数学有理数 $\text{Fraction}(p, q)$，计算 $A \times B + C$ 的精确绝对值；
   - 提取理论无穷精度比特分布，严格按 IEEE-754 规则在半数（Tie）情况下判定 LSB 偶数位（Tie to Even LSB）；
   - 支持 FTZ（Subnormal flushed to zero）、NaN、Inf、带符号零的规范处理。
2. **硬件/C99 参考比对 (`fma_c99`)**:
   - 通过 Python `ctypes` 调用系统底层 `libm.so.6` 的标准 C99 单精度 `fmaf(float, float, float)`；
   - 随机抽取 1,000 组正规数及全部极值用例比对，`fma_exact_rational` 与 `fma_c99` 取得 100% 逐比特一致。

---

## 4. RTL 架构整改与流水拆解

重写了核心 FMA 单元及 Epilogue 融合级，放入独立 candidate 目录：

### 4.1 4级平衡流水单次舍入 FMA 单元 (`candidate/fp32_fma_pipe.sv`)
抛弃单级大组合逻辑，严谨拆分为 4 级同步流水线，彻底消除组合循环：
- **Stage 1 (Decode & 24x24 Multiply)**:
  - 提取符号、指数、尾数（补隐含 1）；
  - 特殊值判定：NaN、Inf、Zero / FTZ；
  - 24x24 无符号整数乘法器生成 48-bit 乘积 $M_p = M_a \times M_b$；
  - 计算乘积基准指数 $e_p = e_a + e_b - 127$ 及加数指数差 $\Delta e = e_p - e_c$。
- **Stage 2 (Wide Accumulator Alignment & Add/Sub)**:
  - 采用 132-bit 宽累加器，固定放置 48-bit 乘积于中间高权位；
  - 相对移位加数 $C$（移位范围 $[-26, +106]$），所有移出边界的尾数自动折算为 `sticky` 位；
  - 比较符号与幅值，执行 132-bit 加法或减法，单次运算，无中间精度截断。
- **Stage 3 (Leading Zero Count & Normalization)**:
  - 132-bit 优先编码器/前导零检测（LZC），检测最高有效 1 的位置；
  - 快速多路桶形移位器完成规格化左移/右移；
  - 准确提取 24-bit 候选尾数、Round 位及全下位累积的 Sticky 位。
- **Stage 4 (RNE Rounding & IEEE-754 Formatting)**:
  - 执行最近偶数舍入：`round_up = round_bit && (sticky || mant24[0])`；
  - 尾数进位自适应指数增量；
  - 溢出判为 $\pm\infty$，下溢按 FTZ 清零；
  - 输出多路选择器集成 NaN、Inf、Zero 及规整数。
- **反压与清空**:
  - 各级配备寄存器前向反压保持信号（Skid Buffer 机制），上游 `in_ready` 与下游 `out_ready` 严格自适应；
  - 同步 `flush` 信号在 1 拍内清空 S1~S4 全部有效位，零气泡复位。

### 4.2 原 IP 接口适配器 (`candidate/asr_fma_ip.sv`)
完全封装 `fp32_fma_pipe`，提供与原官方 Xilinx `asr_fma_ip` 100% 引脚一致的 AXI-Stream 接口，非功能 Stub，真实流水计算。

### 4.3 融合级调度器 (`candidate/epilogue_fma_stage.sv`)
- 整合 `fp32_fma_pipe`，通过模式控制实现：
  - `MODE_CONV_ONLY (0)`: 4 拍穿透旁路，保留输入逐位原样，零精度损失；
  - `MODE_SCALE_BIAS (1)`: 全 FMA 运算 $(x \times \text{scale}) + \text{bias}$；
  - `MODE_SCALE_ONLY (2)`: 缩放乘法 $x \times \text{scale} + 0.0$。
- 修复并保留了静态诊断函数 `fp32_mul(a, b)`（带 RNE 舍入），确保直接调用测试也能 100% 通过。

---

## 5. 测试套件与验证结果

执行脚本: `./run_all_tests.sh`（严格 `-j1` 运行，每个仿真均具备 Watchdog）。

| 测试套件 | 验证范围与内容 | 测试向量数 | 结果 | 退出码 |
| :--- | :--- | :---: | :---: | :---: |
| **SUITE 1: Python 参考模型** | `reference/fma_reference.py`: 有理数 RNE 对比 glibc `fmaf`、Tie 测试、抵消测试 | 1,000+ 随机 | **PASS** | 0 |
| **SUITE 2: FP32 FMA 单元** | `tests/tb_fp32_fma_pipe.sv`: 主验收反例、抵消测试、两向 Tie 测试、非平凡 scale/bias、极值、下溢 FTZ、反压暂挂、同步清空 | 13 项关键检查 | **PASS** | 0 |
| **SUITE 3: 主验收反例复测** | `tests/tb_probe_acceptance.sv`: 静态函数 `fp32_mul` 与流水线数据流实测 $0\text{x}3f800001 \times 0\text{x}3fc00000$ | 2 项独立探针 | **PASS** (`3fc00002`) | 0 |
| **SUITE 4: 官方 FMA Fixture** | `tests/tb_asr_fma_fixture.sv`: 挂接 `asr_fma_ip.sv`，完全回放 `work/tests/fma_fixture/memory.hex` 并比对 `gold.hex` | 1001 向量 | **PASS** (1001/1001 比特一致) | 0 |
| **SUITE 5: Epilogue Lane 集成** | `tests/tb_epilogue_lane.sv`: 单通道 C48 $\to$ FMA $\to$ ReLU $\to$ QDQ A16 链路；测试模式 0/1/2、ReLU 截断、饱和 $[-32768, 32767]$、反压及 Flush | 11 项全链路检查 | **PASS** | 0 |
| **SUITE 6: Top Stream Engine 压力**| `tests/run_epilogue_stream_stress.py`: 4通道流式引擎顶层，非平凡 scale/bias、奇数拍尾包补齐、持续随机反压、中途 Abort 突变与自恢复 | 87 拍 64-bit / 46 拍 128-bit | **PASS** (100% 比特一致) | 0 |

### 关键反例解决证据
1. **主验收乘法探针**:
   ```
   STATIC FUNCTION: MUL got=3fc00002 expected=3fc00002
   [PASS] STATIC FUNCTION: ROUNDING_PASS
   PIPELINED STREAM: MUL got=3fc00002 expected=3fc00002 tag=1234 last=1
   [PASS] PIPELINED STREAM: ROUNDING_PASS
   PRIMARY ACCEPTANCE PROBE RESOLVED 100%
   ```
2. **官方 FMA 抵消反例**:
   ```
   === STARTING ASR_FMA_IP FIXTURE TEST (1001 VECTORS) ===
   === FIXTURE RESULTS: 1001 matches, 0 errors ===
   V022_OFFICIAL_VENDOR_FMA_PASS: 1001/1001 EXACT MATCHES
   ```

---

## 6. 与旧融合设计 (gemini_epilogue) 全面对比

| 指标 / 特性 | 旧融合实现 (`gemini_epilogue`) | 本次整改实现 (`gemini_fma_repair`) | 改进与修复收益 |
| :--- | :--- | :--- | :--- |
| **乘法舍入策略** | 粗暴截断低位（无 Round/Sticky/LSB） | IEEE-754 标准 RNE（带 LSB 偶数判定） | 消除主验收 `3fc00001` 反例，产出正确 `3fc00002` |
| **FMA 数值契约** | 先乘后加（截断两次，非真 FMA） | 132-bit 宽累加器单次舍入（True FMA） | 完美通过 $(1+2^{-23})(1-2^{-23})-1 = -2^{-46}$ 抵消测试 |
| **流水结构与时序** | 单拍组合内含 `while` 循环移位 | 严格 4 级寄存器切割（乘法/累加/LZC/舍入） | 消除物理长组合路径，消除综合推断闭环隐患 |
| **原 IP 兼容性** | 仅声明接口准备，内部为分立组合 | 提供可仿真的全功能 `asr_fma_ip.sv` | 1001/1001 匹配官方 Vendor Golden Netlist 测试 |
| **测试覆盖模式** | 仅测 `mode=0`（旁路模式），刻意回避 FMA | 全面覆盖 Mode 0、1、2、非平凡浮点参数 | 彻底杜绝假通过与未决算术盲区 |
| **流式尾包与打包** | 缺乏奇数节拍边界鲁棒性 | 128-bit Packer 尾拍自动补零闭合 | 尾包不丢失、不挂死、对齐 AXI128 协议规范 |
| **异常恢复 (Abort)** | 仅外层寄存器复位 | 全流水线 4 级打拍瞬时清除，零气泡复位 | 突发异常后可在下个节拍立即接收新描述符 |

---

## 7. 源码 SHA-256 清单

```
asr_fma_ip.sv:                  634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599
epilogue_f32_to_i16.sv:          c51d3327a7fcfbe7e584f1efa275413644147669c9d216ea7f5fbf31b864af6b
epilogue_fma_stage.sv:           5d52cbc54e1f61029a9c24544ae573ab345ffc8335bb57964dbfbbe8b62183bd
epilogue_i48_to_f32.sv:          637a7b327d35760bc5d741128d04f77bcddde87cc40886dcf24aff09cebd29bf
epilogue_lane.sv:                d00b4d57776a605cbed790d19e9a7be7bb4b0f1751d4f6b617a9ca35489435f7
epilogue_relu.sv:                0e008b394489fcdd2f453aeebee5288f1b812d715c5e8840d47f19bcb3142c4d
epilogue_stream_engine_v023.sv:  b99a664bc3e49bed21acf79c22281506e85ce347777ad578bfbe2c2a78984bce
fp32_fma_pipe.sv:                3263c02d63a886f9a8701d19f8c07e3a1b66670ad737206b24846194736cb23f
reference/fma_reference.py:      50e68e0d9b4dbcb3b0ff9d936e788bc5916ca119df946927da08436ca6d5f073
run_all_tests.sh:                bc3fa6054ae52010156ceea63a1e2f758ba0d5c0e176378a576c9ea24d266e74
```

---

## 8. 失败与未验证范围声明 (诚实报告)

- **失败数**: 0（全部 6 个测试套件通过，退出码 0）。
- **未验证范围 (严格遵循执行契约声明)**:
  1. **未进行 Vivado 物理综合与 STA 静态时序分析**: 根据最高执行契约，当前阶段严格禁止调用 Vivado / 综合 / 上板。流水线已做细致 4 级切分，消除了单周期长逻辑，但物理 300MHz/600MHz 主频指标必须由后续后端 STA 报告为准，不虚构已达标。
  2. **未上板验证真实 DDR 带宽**: 流式引擎片上节省了中间 DDR 访存流量（每节拍省 48 字节），但全图端到端加速比依赖系统顶层全图闭环及板级实测。
  3. **未直接运行全网络 ONNX 评估**: 当前验证聚焦于 C48 $\to$ FMA $\to$ A16 的流式正确性与 IEEE-754 字节级精确度，整图识别率（WER/CER）需在全图集成阶段评测。
