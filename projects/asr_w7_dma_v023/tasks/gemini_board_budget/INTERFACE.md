# INTERFACE: `gemini_board_budget` Analysis & Modeling Engine

## 1. 模块定位与职责

本模块 `gemini_board_budget` 负责端到端量化建模、硬件拓扑审计、官方权威文献对齐与算力-带宽反推分析，为 V0.22 架构演进提供独立可复核的理论与工程上限预算。

- **工作目录**: `tasks/gemini_board_budget`
- **主要交付物**:
  - `budget.py`: 可运行的理论下界、读写解耦、张量生命周期与 PE 脉动带宽反推计算脚本。
  - `budget.json` / `result.json`: 结构化预算与多维度情景表数据。
  - `test_budget.py`: 自动化校验套件，覆盖数值合同、公式守恒性与拓扑边界。
  - `REPORT.md`: 完整工程技术报告，包含精确文献页码/表号、板卡证据、双路径架构、读写分解与 PE 阵列匹配。
  - `FINDINGS.md` / `FINDINGS.jsonl`: 关键技术发现与证据链。

---

## 2. 核心架构契约与约束边界

1. **执行合同保证 (`EXECUTION_CONTRACT.md`)**:
   - 主机仅参与初始参数与执行计划一次性装载至 DDR。
   - 运行期间所有算子调度、DMA 搬运、中间量流转完全由 PL 硬件控制器自主驱动。
   - PS 软件不参与推理期控制流，不依赖逐算子 CPU 中断或网络握手。

2. **硬件时钟域解耦 (DS925 & UG949)**:
   - **局部计算域 (Compute Domain)**: 125 MHz、150 MHz、300 MHz、600 MHz（仅作为 PL 局部流水线探索，600 MHz 绝非接口域）。
   - **外设接口域 (Interface Domain)**: 标称最高 $\le 333\text{ MHz}$（DS925 -2 速度等级上限）；当前基线锁定在 125 MHz。
   - **跨时钟域契约**: 计算域与接口域之间必须通过异步 FIFO（XPM_FIFO_ASYNC）与握手同步器实现严格 CDC，不得直连。

3. **外存通路拓扑契约 (UG1085 & PG201)**:
   - **路径 A (PS 硬 DDR4 控制器)**: 64-bit 物理总线 @ 800 MHz (1600 MT/s, 12.8 GB/s 理论峰值)。PL 侧经 SmartConnect 汇聚至单 128-bit HP0 端口（125 MHz 峰值 2.0 GB/s）。
   - **路径 B (PL 独立 DDR4 MIG)**: 32-bit 物理总线 @ 1200 MHz (DDR4-2400, 9.6 GB/s 峰值)，完全绕过 PS 互连与 PS 控制器。

---

## 3. PE 与带宽匹配数学模型

$$P_{\text{equiv}} \le \frac{B \times I}{f_c}$$

- $P$: 脉动阵列 PE 规模 ($R \times C$)。
- $B$: DDR 有效带宽 (Byte/s)。
- $I$: 算术强度 (MAC/Byte)，计算方式为 $I = \frac{M \times N \times K}{2MK + KN + 6MN}$（基于 W7p8=1B, A16=2B, C48=6B）。
- $f_c$: 局部计算时钟频率 (Hz)。
- 实际利用率上限: $\eta = \min\left(1.0, \frac{P_{\text{equiv}}}{P}\right) = \min\left(1.0, \frac{B \times I}{P \times f_c}\right)$。
