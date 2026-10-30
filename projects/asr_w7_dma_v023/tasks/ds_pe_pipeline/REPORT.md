# REPORT — ds_pe_pipeline

**任务**：严格可配置 W7p8/A16/C48 PE / 16×16 阵列流水候选与逐任务等价验证  
**范围**：仅逻辑设计、integer golden、Icarus Verilog 仿真。  
**不做**：综合、实现、P&L、Vivado、bitstream、板卡、VNC、push、新 STA。  
**结论边界**：300 MHz (3.333 ns) 与 600 MHz (1.667 ns) 只是目标预算；
本报告不宣称任何候选达到 125/150/300/600 MHz 中的任何新频率。

---

## 1. 只读输入与证据边界

已读：

- `/home/yang/Desktop/项目/EXECUTION_CONTRACT.md`
- `/home/yang/Desktop/项目/work/DESIGN_CONTRACT_zh.txt`
- `tasks/gemini_compute/` 的候选、REPORT、HISTORICAL_OPTIONS、result
- `tasks/gemini_numeric_audit/` 的 REPORT、FINDINGS、INTERFACE、测试日志
- `work/rtl/pe_direct_v020.sv`、`array16_direct_v020.sv`、`block_engine_l1bank_v020.sv`
- `timing_baseline/` 的 full002 `timing.rpt`、`utilization.rpt`、`cdc.rpt`、
  `bus_skew.rpt`、`check_timing.rpt`、`hierarchy.rpt`、`drc.rpt`、`route_status.rpt`

原 `work/`、ZIP、其他 worker 目录均未修改。新增源码全部在
`tasks/ds_pe_pipeline/candidate/` 与本任务 `bench/`。

---

## 2. 历史 full002 时序事实（不是候选签核）

`timing_baseline/README.md` 明确：这是原 ZIP 的 full002 历史报告，
器件 `xczu15eg-ffvb1156-2-I`，历史主频 **125 MHz**；只用于原实现关键路径分析，
不等于新候选时序签核。

`timing.rpt`：

- Vivado v2025.2，Design State: Routed，Speed File -2，Temperature Grade I。
- Clock Summary：`clk100_raw` = 8.000 ns = **125 MHz**；
  `clk125_raw` = 8.000 ns = 125 MHz；`cal_clk_raw` = 3.000 ns = 333.333 MHz。
- Design Timing Summary：
  - WNS **+0.055 ns**，TNS 0，失败 setup endpoint 0；
  - WHS +0.010 ns，THS 0，失败 hold endpoint 0；
  - “All user specified timing constraints are met.”
- 最差 setup 路径（`clk100_raw`）：
  - Source `ps_system/ps_gateway_i/accelerator/inst/core/compute/core/state_reg[3]`
  - Destination `.../compute/storage/bad_reg/D`
  - Data Path Delay **7.745 ns**，Logic Levels **30**
  - 含 DSP48E2 preadd/multiplier/ALU/output 与 6 个 CARRY8
  - Slack +0.055 ns。
- 第二条路径：7.781 ns，25 levels，7 个 CARRY8，slack +0.073 ns。

**关键判断**：full002 的最差路径不是 `pe_direct_v020`，而是 compute/storage
的地址/控制/累加混合路径。因此不能用 full002 去证明 v020 PE 或本任务候选
能达到任何新频率。用户所说“约 150 MHz”在本包中没有对应 STA 报告；
本报告严格区分：

| 口径 | 数值 | 证据 |
|---|---:|---|
| full002 历史约束主频 | 125 MHz (8.000 ns) | `timing_baseline/timing.rpt` |
| full002 WNS | +0.055 ns | 同上 |
| 用户报告“约 150 MHz” | 未在本包验证 | 无对应 STA |
| 300 MHz 目标预算 | 3.333 ns | 仅预算 |
| 600 MHz 目标预算 | 1.667 ns | 仅预算 |

其他 full002 概况：LUT 136,676 (40.05%)，FF 101,210 (14.83%)，
CARRY8 7,633 (17.89%)，BRAM 524.5 (70.50%)，URAM 64 (57.14%)，
DSP 217 (6.15%)。CDC 有 2 个 CDC-6 multi-bit warning、26 个 CDC-15
clock-enable warning；bus skew 全部 MET（最差 slack 7.284 ns）。
这些是历史实现的事实记录，不是候选实现结果。

---

## 3. 基线 PE 的算术与瓶颈

`work/rtl/pe_direct_v020.sv` 保持：

- A16 有符号补码，`-32768` 取绝对值仍为 32768；
- W7 = `{S, J[1:0], M[3:0]}`，`p = positions[J]`；
- `sat = clip && p==12 && M>=8`，饱和时 `M→8` 并减去 `|A|`；
- 20-bit raw product、32-bit shift/sub/negate、48-bit 自然回绕累加；
- 3 级 product pipeline，`valid[2]` 时累加。

基线 Stage 2 在一个时钟内做 32-bit 变长移位 + 32-bit 饱和减法 +
32-bit 条件取负，再进入 48-bit 累加反馈。这是本任务要拆的长组合段；
但本任务只做逻辑切分与等价验证，不做时序数值判断。

---

## 4. 候选流水：3/4/5/6 级精确切分

新增 `candidate/pe_w7_c48_cfg.sv`，参数：

- `PIPE_STAGES = 3/4/5/6`
- `ACCUM_MODE = 0` native CARRY，`1` dual-rail CSA
- `CPA_PIPE = 1` CSA 最终 CPA 寄存（默认）

| 配置 | Stage 0 | Stage 1 | Stage 2 | Stage 3 | Stage 4 | Stage 5 | 之后 |
|---|---|---|---|---|---|---|---|
| 3 | ABS/DECODE | MUL | SHIFT+SUB+NEG | — | — | — | ACC |
| 4 | ABS/DECODE | MUL | SHIFT+SUB | NEG | — | — | ACC |
| 5 | ABS/DECODE | MUL | SHIFT | SUB | NEG | — | ACC |
| 6 | ABS/DECODE | MUL | SHIFT | SUB | NEG | SEXT48 | ACC |

- 3-stage 是 baseline 等价形状，Stage 2 仍很长；它用于逐位对照，
  **不声称改善时序**。
- 4/5/6-stage 没有任何一级同时包含 multiply+shift+sub+negate。
- 6-stage 的 SEXT48 只是 32→48 位符号扩展寄存，用于把 48-bit 累加器
  输入从 negate 组合路径中隔离出来。
- 每级只寄存后续真正需要的字段，没有把整包 payload 全宽透传。

---

## 5. FPGA native CARRY 与 CSA 的取舍

| 维度 | native CARRY | dual-rail CSA + CPA |
|---|---|---|
| 累加反馈 | 48-bit CARRY8 链，反馈环含进位 | XOR/多数决，反馈环无全宽进位 |
| 累加状态 | 48 FF | 96 FF（sum_s + sum_c） |
| 输出 | 直接 sum | 仍需 48-bit CPA；本实现寄存 CPA |
| 额外延迟 | 0 | +1 拍 drain |
| FPGA 匹配 | UltraScale+ 有原生 CARRY8 | 占用软逻辑模拟 CSA，未必占优 |
| ASIC 匹配 | 长进位链代价高 | 更有吸引力 |

结论：**不盲目认为 CSA 必优**。在 FPGA 上保留 native CARRY 作为推荐基线；
CSA 作为对照/ASIC 探索。没有综合，因此不给出资源或时序胜负数值。

---

## 6. 控制器接口：done / 流水空 / LATENCY 常量

不再写死 65。RTL 直接输出常量：

```text
PE_DRAIN_native = PIPE_STAGES + 1
PE_DRAIN_csa    = PIPE_STAGES + 2
ARRAY_DRAIN     = 15 + PE_DRAIN
```

`DRAIN` 定义为：输入被接受拍到累加器更新边沿的拍数；
结果在更新边沿后的下一拍可见。**PE II=1**：每拍可接受一个 `av&&wv`；
16×16 array 每个 wavefront 每拍推进一个 K 元素。135k back-to-back
乘积测试覆盖了 PE 的 II=1 连续流。

| 配置 | PE_DRAIN | 16×16 ARRAY_DRAIN | K=32 RUN end |
|---|---:|---:|---:|
| 3-stage native | 4 | 19 | 65 |
| 4-stage native | 5 | 20 | 66 |
| 5-stage native | 6 | 21 | 67 |
| 6-stage native | 7 | 22 | 68 |
| 4-stage CSA + CPA | 6 | 21 | 67 |

16×16、K=32 的最后外部 A/W 输入在 `run_cycle=46`，所以
`RUN_END = 46 + ARRAY_DRAIN`。一般 K：`RUN_END = (K+14) + ARRAY_DRAIN`。
旧 `block_engine_l1bank_v020` 的 `run_cycle==65` 只对 3-stage/baseline 正确；
4/5/6-stage 必须分别改成 66/67/68，CSA 为 67。否则 bottom-right PE 的
最后一个乘积会被 flush 丢弃。

`array16_w7_c48_cfg` 还输出 `drain_done/pipe_empty`，在
`last_external_input + ARRAY_DRAIN` 精确拉高；测试同时检查前一拍为 0。

---

## 7. 验证方法与结果

### 7.1 独立 integer golden

`candidate/golden_w7_c48.py` 只按算术合同实现，不 import/evaluate Verilog：
A16、W7(S/J/M)、positions nibble、clip 饱和、32-bit 中间截断、INT48 回绕。
`product32()` 与 `sum_products()` 作为 Python 参考。

### 7.2 PE 级

`bench/run_pe_tests.py` 同时驱动：

- 原版 `pe_direct_v020`
- `pe_w7_c48_cfg` 3/4/5/6-stage native
- `pe_w7_c48_cfg` 4-stage CSA

覆盖：

| 测试 | 规模 | 结果 |
|---|---:|---|
| 单积穷举：128 W7 × 8 A corner（含 -32768）× P=0..15 × clip=0/1 | 32,768 products / 622,592 cycles | 0 mismatch |
| 随机 K=32 任务：valid 气泡、逐拍 positions/clip、-32768 | 300 tasks / 15,600 cycles | 0 mismatch |
| 定向事件：reset/flush/clear settled & in-flight、valid 气泡 | 9 scenarios | 0 mismatch |
| INT48 长流溢出：最大幅值 back-to-back | 135,000 products | 0 mismatch，按 2^48 回绕 |

此外，3-stage 与 baseline 的**逐拍** `sum` 轨迹在 exhaustive/random/events/overflow
四个输出文件中全部相同；其他 4/5/6/CSA 在各自 drain 后与 golden/baseline 最终值相同。

事件语义实测：

- `reset` 清 sum 和在途乘积；
- `flush` 丢弃在途乘积、保留已累加 sum；
- `clear_sum` 清 sum 但不清乘法流水，在途乘积之后仍累加到已清零的 sum；
- `clear_sum && flush` 两者都清；
- `av=0` 或 `wv=0` 的气泡不产生乘积。

### 7.3 16×16 阵列波前

`bench/run_array_tests.py` 同时驱动：

- 原版 `array16_direct_v020`
- `array16_w7_c48_cfg` 3/4/5/6-stage native
- `array16_w7_c48_cfg` 4-stage CSA

9 个 tile：

1. 随机密集，P=1，clip=0
2. `-32768` + P=12 + clip=1 最大幅值
3. 混合符号 + P=12 + clip=1
4. positions=0xBA98（四个不同 nibble）+ clip=1
5. A/W valid holes/bubbles
6. `-32768` + P=12 + clip=0
7. 完成后 flush（sum 保持）
8. 完成后 clear_sum（sum 清零）
9. 完成后 reset（sum 清零）

结果：9 tiles / 840 cycles，256×9×6 个输出全部与 golden/baseline 逐位一致；
`drain_done` 对每个 tile、每个 candidate 在预测拍点前一拍=0、该拍=1。
这说明 16×16 波前、reset/flush/clear、positions/clip 切换、-32768、
valid 气泡均被覆盖。注意 array 的 positions/clip 在 wavefront 和 drain 期间
必须保持稳定，测试也是在排空期继续持有同一 positions/clip。INT48 溢出在 PE 级 135k 长流中覆盖；K=32 的阵列
单块在 48-bit 范围内不会自然溢出，因此没有为了“制造溢出”而改写阵列语义。

### 7.4 复跑

```bash
cd /home/yang/Desktop/项目/tasks/ds_pe_pipeline
make -j2
```

`-j2` 由 `make` 并行编译两个 testbench 实现；Icarus Verilog 自身没有 `-j`，
不会把 `-j2` 传给 `iverilog`。

单独复跑：

```bash
python3 bench/run_pe_tests.py
python3 bench/run_array_tests.py
```

日志：

- `bench/logs/final_make_j2.log`（编译命令 + 全部测试输出）
- `bench/logs/pe_tests_result.json`
- `bench/logs/array_tests_result.json`
- `bench/logs/pe_exhaustive.vvp.log`、`pe_random_tasks.vvp.log`、
  `pe_events.vvp.log`、`pe_overflow.vvp.log`
- `bench/logs/array_tiles.vvp.log`

---

## 8. 结构估算（不是综合）

按 RTL 声明状态位估算（不含组合 LUT、CARRY、DSP、布线）：

| 配置 | 估算 FF/PE | 256 PE 约 |
|---|---:|---:|
| baseline `pe_direct_v020` | ~176 | ~45k |
| 3-stage native | ~181 | ~46k |
| 4-stage native | ~214 | ~55k |
| 5-stage native | ~264 | ~68k |
| 6-stage native | ~312 | ~80k |
| 4-stage CSA + CPA | ~310 | ~79k |

这些只是结构估算，不是 Vivado 资源报告。真实映射、CARRY8/DSP 推断、
扇出、拥塞和时序必须等后续综合/实现。

---

## 9. 推荐与未证明

**推荐用于后续 STA 的逻辑候选**：

- 4-stage native CARRY：相比 3-stage 拆开 SHIFT+SUB 与 NEG，寄存器开销可控，
  是首选候选。
- 5/6-stage native：作为更深切分探索；6-stage 额外隔离 48-bit 符号扩展/累加输入，
  但寄存器更多。
- 4-stage CSA：作为 FPGA vs ASIC 对照，不作为 FPGA 默认推荐。

**未证明**：

- 未做综合/实现/P&R/Vivado/板卡；没有任何新 WNS/TNS 或频率。
- 不能把仿真时钟改快当作时序证明；本报告没有这样做。
- 不能从 full002 的 125 MHz 推导用户“约 150 MHz”或其他版本。
- 未修改 host/PL DMA/DDR 控制流；本任务不证明端到端 PL 自主执行。
- 16×16 array 的 positions/clip 必须整波前及排空期（直到 drain_done）静态；
  逐拍动态只在单 PE 成立。
- `P>12` 保留 baseline 行为；合同要求 P<=12。

---

## 10. 交付文件

```text
tasks/ds_pe_pipeline/
  REPORT.md
  FINDINGS.md
  FINDINGS.jsonl
  INTERFACE.md
  result.json
  progress.json
  SHA256SUMS.txt
  Makefile
  run_all.sh
  candidate/
    pe_w7_c48_cfg.sv
    array16_w7_c48_cfg.sv
    golden_w7_c48.py
  bench/
    tb_pe_cfg_compare.sv
    tb_array_cfg_compare.sv
    run_pe_tests.py
    run_array_tests.py
    vectors/
    logs/
```

---

## 11. SHA-256（新增源码/测试 + 只读基线）

见 `SHA256SUMS.txt`。关键项：

```text
d8b5089073f4629f113b7735316593b77335ad99d8adf0c6757bd2d70269f179  candidate/pe_w7_c48_cfg.sv
c4203e0b7fc21b1b11e82579343236089342352d70b167b70791b8e69c03daae  candidate/array16_w7_c48_cfg.sv
f800f019f6a69eb7317ee665ac3362cff68504c9f6c0857ab400ed06805b8483  candidate/golden_w7_c48.py
5a287e0fdee80ec3df0f6b989cf493156dc51a63438ee249d415d5db96800d21  bench/tb_pe_cfg_compare.sv
0e9b677d243b94483477cbfe9b84d0e5216ddd2cd9dc41c20124ed26f42c27db  bench/tb_array_cfg_compare.sv
1e77088ab33e0b597741d90d5306219049c256b50a64da0b556b5bd9ae9426ce  bench/run_pe_tests.py
504df7b9b5636de32b44ee92f907ad45e6d4f95a4a9625bc7a9d5fd801f6ae43  bench/run_array_tests.py
18c46e113c1911234066df03326119d54ed332dc1c3cd43418091e5aa7dfd0c6  Makefile
7b43de74709f53f0212eb6a600c5d84b3c1aea5904c2f0dd1b6e32b300bc0317  ../../work/rtl/pe_direct_v020.sv
77c66aeea9dd40eb927f8f8e0658b707188427f51138af5f726ded0dc9c3fd56  ../../work/rtl/array16_direct_v020.sv
0a6f24fc51f79baf4f1ecca0b38a79180b0a56e19470bfdb4bec863b34a09c20  ../../work/rtl/block_engine_l1bank_v020.sv
43b3449423958db335539997dc95f02df2667ed5ad45703b1f445ff95d10cda1  ../../timing_baseline/timing.rpt
fa1f91271a389a1b66b0099643ffffd6e7c2c349042dba66ee0886cae7be084d  ../../timing_baseline/utilization.rpt
```

---

## 12. 一句话结论

在严格保持 W7p8/A16/C48、positions/clip、-32768、INT48 回绕和原有事件语义的前提下，
本任务给出了 3/4/5/6 级可解释 PE 切分、16×16 阵列候选、独立 integer golden
和逐任务/波前/事件验证；接口用 `DRAIN/ARRAY_DRAIN/drain_done` 取代写死 65。
历史 full002 是 125 MHz 且其关键路径不在 PE，本任务没有新 STA，
因此不声称任何候选达到 150/300/600 MHz。
