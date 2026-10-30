# REPORT — FMA-1..3 专项全面修复验收报告（Round 2）

**日期**：2026-10-29  
**工作目录**：`/home/yang/Desktop/项目/v023_repair/gemini_fma_round2`  
**执行原则**：仅本地 RTL 逻辑仿真；未综合、未 Vivado、未上板、未 VNC、未 push；其他 worker 和 work 保持完全只读；所有代码及脚本均在本工作目录。  
**模型背景**：本项目为 512 维 Conformer/Transformer ASR 语音识别加速，非 64 维 KWT-1 模型。  
**验收结论**：**通过（overall_pass=true）**。独立黑盒审计 8,734 例向量中的 137 个历史失败已 100% 修复（失配数由 137 彻底清零为 **0**）；额外 20,000 例随机/对抗边界向量测试 **0 失配**；反压稳定性（BP=0/BP=1）**0 错误**；单拍 Flush 报错 **0**。严格保留真正单次舍入 FMA 契约，未修改任何参考模型降低验收要求。

---

## 1. 任务背景与独立黑盒验收依据

上一阶段独立数值验收审计（`ds_numeric_adversarial`）在 8,734 个测试向量下报告了 `gemini_fma_repair` 的 137 个阻断性失配，具体包括：
1. **FMA-1 (Tie-to-even 错误)**: 24 个 `bias=0` 用例中，在恰好半 ULP 的 tie 上 sticky 位误置 1，破坏偶数舍入；
2. **FMA-2 (极端指数对齐错误)**: 66 个用例中，乘积远小于加数（$E_C \gg E_P$）时，对齐移位被截断，且规格化指数被错误取为乘积指数；
3. **FMA-3 (特殊值处理错误)**: 34 个 Inf 相关失配（`inf * 0`、`inf + (-inf)` 未返回 NaN）、2 个符号零失配（非零抵消产生了 `-0` 而非 IEEE-754 规定的 `+0`）；
4. **Subnormal FTZ 缺陷**: 11 个 Subnormal bias 用例因隐含位强行置 1 未按 FTZ 归零参与累加。

**验收措施与“不自证”承诺**：
- **只读黑盒复用**：直接复用 `/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial` 目录下的 `vectors/fma.vec`（8,734 向量）以及 `ref/refmodel.py` 纯 Python Fraction 整数精确参考，未修改参考脚本中的任何一行，未降低舍入或 FTZ 标准；
- **双层 Watchdog 防御**：每个仿真执行均具备 Python 子进程墙钟看门狗（超时主动终止进程组）及 SystemVerilog 仿真周期看门狗（超限退出码 2 并报错打印）；
- **全流水背压与状态机验收**：在 BP=0（全速）、BP=1（50% 随机背压）下逐拍校验 `STABILITY_ERRORS`，确保下游 stall 时输出严格冻结。

---

## 2. 根因剖析与 RTL 级修复方案

### 2.1 FMA-1: Tie-to-even 与 Sticky 位误置根因
- **原代码缺陷**：在 `fp32_fma_pipe.sv:161` 中：
  ```verilog
  if (s1_exp_diff - 10'sd78 >= 10'sd25) begin
      c_aligned = 132'd0;
      c_sticky_bit = |s1_mant_c;
  ```
  当输入加数 $C = 0.0$（即 `in_c = 32'h00000000`）时，Stage 1 的 `s1_mant_c` 依然被无条件赋予 `{1'b1, 23'd0}`（即 `0x800000`），导致 `c_sticky_bit = |s1_mant_c = 1`！这一虚假的 sticky 位贯穿流水线传递到 Stage 4，使得判定式 `round_up = round_bit && (sticky || lsb)` 中的 `sticky` 永远为真，将本应保留偶数的半 ULP 错误当成了“大于半 ULP”强行进位。
- **修复方案**：引入严格 FTZ 解包：当 $C$ 指数为 0 时，其实际有效尾数 $mant\_c = 0$。并建立精确的 128-bit 移位掩码收集低位截断位，杜绝任何零操作数产生虚假 sticky。

### 2.2 FMA-2: 极端指数对齐截断与基准指数混淆根因
- **原代码缺陷**：在原实现中，乘积 $P$ 被固定放置在累加器高位 `[102:55]`，仅依靠对 $C$ 左移或右移来对齐。然而当 $E_C \gg E_P$（例如 $E_C = 127, E_P = 1$）时，$C$ 理论上需要左移 200+ 拍。原代码为了强塞入 132-bit 累加器，粗暴加入 `if (c_shift > 106) c_aligned = ... << 106;`，并在 Stage 3 中硬编码 `s3_exp = s2_exp_p + msb - 101`，导致对齐后的 $C$ 指数被严重截断，结果指数被强行锚定在极小的乘积指数 $E_P$ 上（1.0 被计算为 $2^{-97}$）。
- **修复方案**：**重构为主导操作数（Dominant Operand）动态比较架构**：
  1. 将乘积 $P \in [1, 4)$ 规格化为 48-bit 整数 $P_{norm}$（MSB 固定在 bit 47，对应有效指数 $E_{P\_eff}$）；
  2. 将加数 $C$ 扩展为 48-bit 整数 $C_{norm} = \{M_C, 24'd0\}$（MSB 固定在 bit 47，对应有效指数 $E_{C\_eff}$）；
  3. 比较 $(E_{P\_eff}, P_{norm})$ 与 $(E_{C\_eff}, C_{norm})$，选取较大者为锚定主导操作数 $D$（基准指数 $E_{base} = E_D$），较小者为下属操作数 $S$；
  4. 计算移位量 $shift = E_D - E_S \ge 0$。因为两者 MSB 均在 bit 47，当 $shift \ge 1$ 时，$S \gg shift \le 0.5 < 1.0 \le D$，保证在有效减法时 $D - (S \gg shift) \ge 0$ **恒成立，绝对无借位翻转**；
  5. 采用 129-bit 宽位累加器，当 $shift \le 120$ 时完整保留移位低位，基准指数严格以 $E_D$ 为原点调整，彻底根除对齐截断与指数错位。

### 2.3 FMA-3: 特殊值与 IEEE-754 零符号规则
- **NaN 产生条件补充**：Stage 1 组合逻辑增加 `inf * 0` 识别（任一操作数为 Inf 且另一操作数在 FTZ 下为 0）以及 `inf + (-inf)` 识别（加法异号无穷大相加），统一派发 IEEE-754 规范静默 NaN（`0x7fc00000`）；
- **非零抵消为正零**：在有效减法且两非零操作数完全抵消时（$s2\_sum\_acc = 0$ 且无 sticky），根据 IEEE-754 RNE 规则，非零抵消结果符号**必须为正零（`+0`，即 `0x00000000`）**。仅当输入本身即为负零相加时才输出 `-0`（`0x80000000`）。原实现误将减法主导操作数的负符号赋予了抵消结果，现已彻底纠正。

### 2.4 Mode 0 旁路流水线严格打拍对齐
- 在 `epilogue_fma_stage.sv` 中，将 Mode 0 旁路数据与模式标记统一打包进 `fp32_fma_pipe` 的参数化扩展 Tag（`TAG_WIDTH + 34`）中。旁路数据与 FMA 计算共享完全相同的级联握手信号（`s1_ready..s4_ready`、`s1_valid..s4_valid`、`flush`），从架构上杜绝了独立 shift register 在复杂背压反弹时的错位可能。

---

## 3. 测试规模与验证结果总表

所有仿真均以 `-j1` 顺序编译执行，无总超时，每个测试具备看门狗监控。

| 测试套件 | 测试对象 | 向量规模 | 反压模式 | 退出码 | 结果与失配数 | 状态 |
|---|---|---:|---|---:|---|:---:|
| `adversarial_fma_bp0` | `epilogue_fma_stage` | 8,734 | BP=0 (全速) | 0 | 0 mismatches, 0 stability errors | **PASS** |
| `adversarial_fma_bp1` | `epilogue_fma_stage` | 8,734 | BP=1 (50% 随机) | 0 | 0 mismatches, 0 stability errors | **PASS** |
| `random_fma_bp0` | `epilogue_fma_stage` | 20,000 | BP=0 (全速) | 0 | 0 mismatches, 0 stability errors | **PASS** |
| `random_fma_bp1` | `epilogue_fma_stage` | 20,000 | BP=1 (50% 随机) | 0 | 0 mismatches, 0 stability errors | **PASS** |
| `asr_fma_ip_adversarial`| `asr_fma_ip` (AXIS包装)| 8,734 | NonBlocking | 0 | 0 mismatches | **PASS** |
| `asr_fma_ip_random` | `asr_fma_ip` (AXIS包装)| 20,000 | NonBlocking | 0 | 0 mismatches | **PASS** |
| `flush_test` | `epilogue_lane` 链 | 4 级模块 | 手动冲刷测试 | 0 | FLUSH_ERRORS = 0 | **PASS** |
| `official_fma_fixture` | `asr_fma_ip` | 1,001 | 官方 Golden 向量 | 0 | 1001/1001 matches, 0 mismatches | **PASS** |
| `tb_probe_acceptance` | `epilogue_fma_stage` | 探针测试 | 临界舍入点 | 0 | 0x3f800001*0x3fc00000=0x3fc00002 | **PASS** |
| `tb_epilogue_lane` | `epilogue_lane` (I48→A16)| 11 场景 | 全模式/ReLU/饱和 | 0 | 11/11 passed | **PASS** |

### 3.1 核心反例修复前后对比验证

| 测试场景 / 向量 | 真实 IEEE-754 RNE | 旧版 DUT (round 1) | 新版 DUT (round 2) | 修复判定 |
|---|---|---|---|:---:|
| `0x3f800003 * 0x3fc00000 + 0` (Tie-Even) | `0x3fc00004` (偶数位) | `0x3fc00005` (误进位) | `0x3fc00004` | **FIXED** |
| `0x3f800007 * 0x3fc00000 + 0` (Tie-Even) | `0x3fc0000a` (偶数位) | `0x3fc0000b` (误进位) | `0x3fc0000a` | **FIXED** |
| `0x00800000 * 0x3f800001 + 0x3f800000` (极端指数) | `0x3f800000` (1.0) | `0x0e800000` ($\approx 2^{-97}$) | `0x3f800000` | **FIXED** |
| `0x00800000 * 0x3f800001 - 0x3f800000` (极端指数) | `0xbf800000` (-1.0) | `0x8e800000` ($\approx -2^{-97}$) | `0xbf800000` | **FIXED** |
| `+val - val` (非零完全抵消) | `0x00000000` (+0) | `0x80000000` (-0) | `0x00000000` | **FIXED** |
| `inf * 0` | `0x7fc00000` (NaN) | `0x7f800000` (Inf) | `0x7fc00000` | **FIXED** |
| `inf + (-inf)` | `0x7fc00000` (NaN) | `0x7f800000` (Inf) | `0x7fc00000` | **FIXED** |
| Subnormal Bias (FTZ) | 正确按 0.0 处理 | 强置隐含位造成大误差 | 严格 FTZ 匹配 | **FIXED** |

---

## 4. 交付文件清单与源码 SHA-256

所有产物均位于 `/home/yang/Desktop/项目/v023_repair/gemini_fma_round2`：

| 文件路径 | SHA-256 校验和 | 功能说明 |
|---|---|---|
| `candidate/fp32_fma_pipe.sv` | `1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12` | 核心 4 级流水 IEEE-754 RNE FMA |
| `candidate/epilogue_fma_stage.sv` | `34b55dc340b33ee570c540453662404579a77b2f8e2b166dbb2563ab3740c00b` | 融合阶段路由、扩展 Tag 旁路打拍 |
| `candidate/asr_fma_ip.sv` | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` | 官方 Xilinx AXI-Stream IP 包装 |
| `candidate/epilogue_i48_to_f32.sv` | `637a7b327d35760bc5d741128d04f77bcddde87cc40886dcf24aff09cebd29bf` | 48-bit 累加值转 FP32 |
| `candidate/epilogue_f32_to_i16.sv` | `c51d3327a7fcfbe7e584f1efa275413644147669c9d216ea7f5fbf31b864af6b` | FP32 转 INT16 QDQ 饱和截断 |
| `candidate/epilogue_relu.sv` | `0e008b394489fcdd2f453aeebee5288f1b812d715c5e8840d47f19bcb3142c4d` | 片上 ReLU 激活函数 |
| `candidate/epilogue_lane.sv` | `d00b4d57776a605cbed790d19e9a7be7bb4b0f1751d4f6b617a9ca35489435f7` | 单通道端到端流水线集成 |
| `candidate/epilogue_stream_engine_v023.sv` | `b99a664bc3e49bed21acf79c22281506e85ce347777ad578bfbe2c2a78984bce` | 4 通道 128-bit 打包流式引擎 |
| `run_all_tests.sh` | (可执行脚本) | 全套回归一键自测入口（退出码 0） |
| `result.json` | (机器可读报告) | 汇总全部测试集规模、退出码与失配统计 |
| `progress.json` | (阶段状态记录) | 标注文档最终完成状态 |
| `INTERFACE.md` | (契约文档) | 模块端口、流水级时序与验收契约规范 |

一键复现命令：
```bash
cd /home/yang/Desktop/项目/v023_repair/gemini_fma_round2
./run_all_tests.sh
```

---

## 5. 诚实限定与已知限制

1. **逻辑仿真限定**：本整改工作仅在本地 Icarus Verilog 14 + Python 环境下完成了逻辑级时序仿真验证。未启动 Vivado 综合与实现，未在真实的物理 FPGA 板卡上运行，亦不就实际时钟主频（如 300/600 MHz）做未经 STA 的假定。
2. **算子 scope 限定**：专属任务范围仅针对 FMA-1..3（`fp32_fma_pipe.sv` 与 `epilogue_fma_stage.sv`），未修改其他算子（如 approx 或 stream engine 外部接口）。
3. **FTZ 契约范围**：模块遵循 FTZ（Flush-to-Zero）规范，所有 Subnormal 输入与输出均被刷新为带符号的 0，不保留 IEEE-754 渐进式下溢（gradual underflow）的小数部分，这与深度学习硬件加速器的通用数值实践一致。
4. **全模型推理**：未运行全图 ASR 推理，未提供 WER/CER 指标。
