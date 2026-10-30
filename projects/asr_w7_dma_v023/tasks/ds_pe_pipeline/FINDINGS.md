# FINDINGS — ds_pe_pipeline

本文件只记录逻辑设计与仿真结论。没有综合、实现、Vivado、板卡或新 STA。
机器可读版本见 `FINDINGS.jsonl`。

## 1. 历史时序基线事实

- `timing_baseline/full002` 是 **125 MHz** 构建：`clk100_raw` period 8.000 ns。
- `timing.rpt` 的 Design Timing Summary：WNS **+0.055 ns**，TNS 0，失败端点 0；WHS +0.010 ns。
- 最差 setup 路径不是 v020 PE，而是 `compute/core/state_reg[3]` → DSP48E2
  preadd/mult/ALU/PCIN → CARRY8 链 → `compute/storage/bad_reg/D`：
  data path 7.745 ns，30 logic levels，slack +0.055 ns。
- 用户所述“约 150 MHz”在本包中没有对应 STA 报告；不能与 full002 的 125 MHz 混为一谈。
- 300 MHz (3.333 ns) / 600 MHz (1.667 ns) 只是目标预算。**本任务不宣称任何候选达到这些频率。**

## 2. 流水切分结论

| PIPE_STAGES | 各级组合操作 | PE DRAIN | 16x16 ARRAY DRAIN | K=32 RUN end |
|---:|---|---:|---:|---:|
| 3 | ABS/DECODE → MUL → SHIFT+SUB+NEG → ACC | 4 | 19 | 65 |
| 4 | ABS/DECODE → MUL → SHIFT+SUB → NEG → ACC | 5 | 20 | 66 |
| 5 | ABS/DECODE → MUL → SHIFT → SUB → NEG → ACC | 6 | 21 | 67 |
| 6 | ABS/DECODE → MUL → SHIFT → SUB → NEG → SEXT48 → ACC | 7 | 22 | 68 |
| 4 CSA | 同 4-stage，但 ACC 为双轨 CSA；最终 CPA 再寄存 | 6 | 21 | 67 |

- 3-stage 是 baseline 等价形状，仍把 shift+sub+neg 堆在 Stage 2，只作为逐位对照，不声称改善时序。
- 4/5/6-stage 没有任何一级同时包含 mul+shift+sub+negate。
- 6-stage 的最后一级只做 32→48 位符号扩展寄存，把 48 位累加器输入从 negate 组合路径中隔离出来。

## 3. 控制器接口结论

- 不再写死 65。PE 和 16x16 array 都输出常量：
  - `PE_DRAIN = PIPE_STAGES + 1`（native CARRY）
  - `PE_DRAIN = PIPE_STAGES + 2`（CSA + 寄存 CPA）
  - `ARRAY_DRAIN = 15 + PE_DRAIN`
- `drain_done/pipe_empty` 在 `last_external_input_cycle + ARRAY_DRAIN` 精确拉高；
  仿真同时检查前一拍为 0、该拍为 1。
- 若接入旧 `block_engine_l1bank_v020`，必须把 `run_cycle==65` 改成
  `46 + ARRAY_DRAIN`（3/4/5/6 native 分别为 65/66/67/68；CSA 为 67）。
- `flush` 丢弃在途乘积但保留 `sum`；`clear_sum` 清 `sum` 但不清乘法流水，
  在途乘积之后仍会累加进已清零的累加器；`reset` 两者都清。

## 4. CSA vs FPGA CARRY

- CSA 反馈环只有 XOR/多数决，没有全宽进位传播。
- 但 CSA 需要两套 48-bit 状态（96 FF/PE），且输出仍要 48-bit CPA。
- 本实现把 CPA 寄存，增加 1 拍 drain。FPGA UltraScale+ 有原生 CARRY8，
  因此 **不认为 CSA 必然优于 native CARRY**；推荐版保留 native CARRY，CSA 作为对照。
- 没有资源/时序数值可宣称；只有 RTL 状态位数量的结构估算。

## 5. 验证覆盖

- PE 单积：32,768 cases = 128 W7 × 8 A corners（含 -32768）× P=0..15 × clip=0/1。
- 随机任务：300 × K=32，valid 气泡，逐拍 positions/clip 切换，INT48 顺序累加。
- 长流溢出：135,000 个最大幅值乘积，验证 INT48 自然回绕。
- 定向事件：reset/flush/clear 的 settled 与 in-flight 语义、valid 气泡，共 9 个场景。
- 16×16 波前：9 tiles，含随机密集、-32768、P=12 clip on/off、0xBA98 四位位置、
  A/W holes、完成后 flush/clear/reset。
- 所有 PE 与 array 输出均与独立 integer golden 及原版 baseline 逐位一致；
  `drain_done` 的精确拍点也被检查。

## 6. 未做 / 未证明

- 没有综合、实现、P&R、Vivado、bitstream、板卡、VNC、push。
- 没有新 STA；不能声称 125/150/300/600 MHz 中的任何新频率。
- 没有修改原 work/ZIP、block_engine、DMA、host、QDQ/FP32 逻辑。
- 16×16 array 的 `positions/clip` 必须在整个 wavefront 以及排空期（直到
  `drain_done`）保持静态；逐拍动态切换只在单 PE 测试中成立。
- `P>12` 按 baseline 行为保留；合同要求 `P<=12`，block_engine 已有检查。
- 资源数字是 RTL 声明状态位估算，不是综合结果。
