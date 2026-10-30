# HISTORICAL_OPTIONS.md: 历史方案调研与架构选项评估报告

## 1. 调研背景与约束边界

根据项目指导要求，本报告基于只读检索 `/home/yang/Desktop/ic设计竞赛/.git` 的完整历史演进（索引见项目根目录 `IC_GIT_REFERENCES.txt`），系统梳理了 `r6-mac`、`r6-bus`、`r6-resident`、`r7-cacc/fifo/packing`、`architecture/bus-budget`、`dataflow-v2`、`shared-row-csa` 及 `ws-before-prune` 等分支的代表性机制。

### 不可突破的数值与系统硬约束：
1. **量化与算术数值合同（Bit-Exact Contract）**：
   - 特殊权重格式：`W7(S/J/M)`，7位非线性组合编码（1位符号 `S`、2位指数索引 `J` 映射到 `positions[15:0]`、4位尾数 `M`，附带 `clip` 饱和校正），禁止直接展开为常规补码整数乘法；
   - 激活值：`A16`（16位有符号补码，包含极端边界 `-32768`）；
   - 累加器与输出：`C48`（48位有符号累加器，严格 INT48 补码自然回绕）；
   - 累加顺序：保持每个通道 C 内部的 K 维度累加顺序严格一致；
   - 向量浮点域：保持 FP32 FTZ（Flush-to-Zero）与 RNE（Round-to-Nearest-Even）FMA 结合顺序及严格 QDQ 边界。
2. **主机单次预加载自治原则（Autonomous PL Principle）**：
   - 主机 PS 仅在任务初始化阶段执行一次全量数据/权重/执行计划搬运到 DDR；
   - 运行期间禁止任何主机/PS CPU 逐算子、逐矩阵干预或 MMIO 搬运，由 PL 控制器与 AXI DMA 纯自主驱动，单中断完成/错误退出。

---

## 2. 关键历史方案逐项对比与评估矩阵

| 历史分支 / Commit Ref | 核心文件 | 机制原理 (Mechanism) | 对当前工程适用性 (Applicability) | 采纳 (Adopt) / 拒绝 (Reject) 及原因 |
| :--- | :--- | :--- | :--- | :--- |
| **`codex/kwt-architecture`**<br>`df93c87f` | `hardware/optimization/ffn1_perf_storage_tradeoff.md`<br>`ffn1_perf_storage_tradeoff.py` | 提出分层证据模型（L0理想/L1 RTL结构/L2 SoC仿真/L3物理综合）；量化 512 KiB SRAM 约束下的数据流瓶颈与逐 tile 重载导致的吞吐崩溃。 | **高 (理论分析与证据分层)**<br>为理论下界推导与 DDR 搬运下界提供严格数学定义。 | **采纳分析方法，拒绝旧参数**：<br>采纳严格证据分层规范，禁止拼凑跨层数据；拒绝其旧形状 (99×64×256) 与旧存储尺寸。 |
| **`codex/kwt-bus-budget`**<br>`9f1fd686` | `hardware/optimization/kwt_bus_capacity_model.md`<br>`kwt_bus_capacity_model.py` | 建立总线利用率与容量分析模型，纠正了有效载荷（148.5KB）与逐 tile 重装载荷（758.8KB，膨胀 5.1 倍）的口径混淆，揭示了总线气泡根源。 | **高 (DDR 流量与突发分析)**<br>量化突发长度、总线位宽与端口带宽对算力利用率的制约。 | **采纳流量精算模型**：<br>用于本工程真实 DDR 流量下界与实际流量膨胀归因分析。 |
| **`codex/kwt-ds-r6-bus64`**<br>`d937ebef` | `rtl/kwt_bus64_adapter.sv`<br>`rtl/kwt_ffn1_ii1_top.sv` | 64-bit Ready/Valid 突发适配器，4路写通道分发到16-bit bank；实测总线占用率高达 97.46%，出现严重带宽饥饿与停顿。 | **低 (位宽受限)**<br>64-bit 宽度无法满足 300MHz/600MHz 高性能计算阵列的数据吞吐需求。 | **拒绝**：<br>64-bit 接口在 125MHz/200MHz DDR 域下仅能提供 1.0~1.6 GB/s，远低于 16×16 阵列每周期需要的大量操作数输入需求。 |
| **`codex/kwt-ds-r6-bus128`**<br>`f438e3f0` | `rtl/kwt_bus_burst_adapter.sv`<br>`rtl/kwt_operand_feed3.sv` | 128-bit 突发传输适配器，支持 8 个 16-bit 独立存储 bank 并行写入；2-cycle 请求到有效数据延迟，有效将总线占用率压低至 63.8%。 | **高 (AXI128 架构对标)**<br>当前工程采用 128-bit AXI 总线，其多通道 bank 分发机制可直接借鉴。 | **采纳其宽总线分发思路，拒绝其单在途控制**：<br>采纳 128-bit 并行数据解包与 bank 写入映射；重构其旧式单在途请求，引入多在途突发。 |
| **`codex/kwt-ds-r6-resident_a`**<br>`812da1ce` | `graduate/ds_tasks/r6_resident_a/WORKER_REPORT.md`<br>`hardware/experiments/r6_resident_a/` | A 矩阵（激活）整层常驻片上，W 矩阵流式分块加载；实测周期从逐 tile 重载的 28,806 拍降至 14,544 拍（加速 1.98 倍，流量减少 57.3%）。 | **高 (张量复用策略)**<br>对于 M 较小、N 较大的线性层或注意力矩阵，A 常驻可彻底消除 A 的重复加载。 | **采纳张量驻留思想**：<br>在 PL 执行计划与存储规划中，根据 M/N 比例动态实施 A 或 W 片上驻留，避免重复 DDR 访问。 |
| **`codex/kwt-ds-r6-resident_w`**<br>`79c8af14` | `hardware/experiments/pipeline_acceptance_20261023/` | 权重常驻片上，激活流式输入（Weight-Stationary）；分析了行时钟门控（ICG）在权重驻留期间的动态功耗收益。 | **高 (权重平摊与卷积优化)**<br>对于批处理或长序列推理，权重常驻极大降低参数 DDR 搬运带宽。 | **采纳权重驻留与时钟门控机制**：<br>在当前 16×16 阵列中，对于深通道卷积，权重加载后在各周期保持静止，降低动态翻转功耗。 |
| **`codex/kwt-ds-r7-cacc`**<br>`9fd4aace` | `graduate/ds_tasks/r7_cacc/run.sh`<br>`hardware/experiments/r7_cacc/rtl/kwt_cacc_cells.sv` | II=1 中心化累加存储器（Centralized Accumulator Bank），支持 2~3 页累加轮转，在计算完成时直接在存储器内叠加上偏置（Bias），排空与累加完全解耦。 | **中 (与当前脉动阵列存在拓扑差异)**<br>当前 V0.22 采用阵列内部分布式累加（每个 PE 独立寄存 INT48 sum）。 | **采纳其多页轮转排空逻辑，拒绝集中式存储池**：<br>保持 16×16 分布式 PE 累加，但引入两页 shadow-sum 或流水化排空，消除 `C_READ` 串行停顿。 |
| **`codex/kwt-ds-r7-fifo`**<br>`6344eda0` | `rtl/kwt_out_fifo.sv`<br>`rtl/kwt_array8x16_stream_engine.sv` | 参数化输出 FIFO（深度 8~512 beats），具有 `full/valid/high-water` 机制，实测当深度 ≥32~64 beats 时可彻底吸收 DDR 写通道反压与仲裁抖动。 | **高 (消除反压气泡)**<br>解决当前 `block_engine` 在 DDR 写回阻塞时向上反压停滞计算核心的硬瓶颈。 | **采纳**：<br>在计算阵列输出与 AXI 写 DMA 之间加入自适应输出缓冲 FIFO，隔离 DDR 延迟抖动。 |
| **`codex/kwt-ds-r7-packing`**<br>`9b6ff459` | `hardware/experiments/r7_packing/rtl/kwt_out_pack.sv`<br>`kwt_array8x16_stream_engine.sv` | 无损稠密打包格式（W12 打包为 1.5 字节/字，Y40/Y48 稠密流式传输）；有效将总线传输利用率提升 25%~37.5%。 | **低 (格式与数值合同冲突)**<br>当前工程明确规定 W7 权重已以紧凑 7-bit 打包存在，A 为 A16，C 为 C48。 | **拒绝修改数值精度，仅借鉴总线填充优化**：<br>严格保持 W7p8/A16/C48 格式，仅在 AXI 128-bit 边界对齐时使用对齐填充，不改变数值编码。 |
| **`codex/kwt-ds-r7-resident_both`**<br>`c01ca6e5` | `graduate/ds_tasks/r7_resident_both/results.json` | A 与 W 双驻留架构：在片上 SRAM 充足时，将小尺寸中间块的 A 和 W 同时缓存，仅流式更新 C。 | **中 (取决于片上 SRAM 容量)**<br>当前 UltraScale+ ZU15EG 片上具有充足 BRAM/URAM，支持在特定局部层双驻留。 | **有条件采纳**：<br>在执行计划调度器中识别小尺寸 GEMM（如 Attention 投影小分块），使能双驻留模式。 |
| **`verified/dataflow-v2-functional-20261024`**<br>`cc3ac4c7` | `hardware/architecture/dataflow_v2/README.md`<br>`hardware/rtl/control/kwt_dataflow_v2_ctrl.sv` | 2D 行优先 DMA 引擎 + 双缓冲（Double-buffered Ping-Pong）数据流控制器；实现后台 DMA 预取下一块与当前块计算的完全重叠。 | **极高 (彻底解决串行等待)**<br>当前 V0.22 的 `block_engine` 处于 `LOOKUP -> A_REQ -> A_DATA -> B_REQ -> B_DATA -> RUN -> C_READ` 的严格串行状态，计算与传输完全没有重叠！ | **核心采纳**：<br>将数据流控制器升级为真 Ping-Pong 双页模式：当 Page 0 在阵列中计算时，Page 1 由 AXI DMA 在后台预取，彻底隐藏 DDR 加载延迟。 |
| **`codex/shared-row-csa-snapshot-20261025`**<br>`bee799dd` | `hardware/rtl/kwt_csa32.sv`<br>`hardware/rtl/kwt_pe_csa.sv`<br>`hardware/rtl/kwt_array_quad.sv` | 双轨进位保留加法器（3:2 Carry-Save Accumulator），累加循环内无进位传播链（每拍直接更新 `sum ^ carry ^ product`）；在最终排空时使用共享加法器做进位解析。 | **高 (高频流水与时序收敛探索)**<br>为 300MHz/600MHz 超高频设计提供了进位链解耦的参考范例。 | **重构采纳并提供对比基准**：<br>旧代码基于 A12W10（32位累加），本项目将其重构为 **W7p8/A16 特殊量化与 INT48 双轨 CSA 累加核**，并与 FPGA 原生 CARRY8 进位链进行严格面积/时序/资源权衡对比。 |
| **`archive/ws-before-prune-20261027`**<br>`0b178b75` | `hardware/A12W10紧凑打包与4x16_8x16驻留架构.md`<br>`hardware/SRAM约束与驻留数据流.md` | 梳理了 SRAM 端口并发约束、紧凑打包与多核驻留调度，总结了早期 WS 架构的剪枝经验与存储冲突规避机制。 | **中 (多 Bank 端口仲裁参考)**<br>为避免输入 AXI 写入与阵列读取同一片上 Bank 发生冲突提供仲裁规范。 | **采纳其无冲突 Bank 映射原则**：<br>确保后台 DMA 写入页与前台计算读取页在物理 Bank 上正交分离，零等待冲突。 |

---

## 3. 核心机制采纳与集成规划

根据上述调研，本项目确定以下技术路线：
1. **计算核微架构**：
   - 深入解析原版 `pe_direct_v020.sv` 的三级流水与组合逻辑瓶颈；
   - 构建 **候选方案 A（精细流水化进位链 PE `pe_pipeline_cc_v023`）**：在保持 FPGA 原生专用 CARRY 链极高能效的同时，将 Stage 2 的移位与符号取反/饱和拆分为两级流水，消除长组合路径，达成 300MHz/600MHz 目标预算；
   - 构建 **候选方案 B（双轨 CSA 累加 PE `pe_pipeline_csa_v023`）**：借鉴 `kwt_csa32` 思想，在累加循环内维护 48-bit `sum_s` 与 `sum_c`，彻底消除反馈累加链中的任何跨位进位依赖，并在输出阶段提供流水化 CPA（Carry Propagate Adder）排空机制；
   - 给出清晰的延迟变化规范，并为顶层阵列提供 `valid/flush/clear_sum` 的无缝排空适配。
2. **数据流与内存架构集成（对接 `ds_ddr` 协同工作）**：
   - 借鉴 `dataflow-v2` 与 `r6-resident_a`，彻底终结当前 V0.22 的 `RUN` 与 `DMA` 串行轮转；
   - 在片上开辟双缓冲（Ping-Pong Buffer），实现 `T = max(T_compute, T_dma)` 的理想重叠；
   - 输出端集成 `r7-fifo` 弹性缓冲，消除 DDR 写通道反压导致的阵列停顿。
