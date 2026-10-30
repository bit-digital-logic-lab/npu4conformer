# 整机 PL 自主执行：依赖清单、迁移设计与未实现项

## 1. 物理拓扑（从 soc_full 脚本核对）

`work/scripts/build_full.tcl` 的实际连线：

```text
accelerator/m_axi ─┐
plans/read_axi ────┤
plans/write_axi ───┤   smartconnect (NUM_SI=6, NUM_MI=1)
plans/fetch_axi ───┼──────────────► ps/S_AXI_HP0_FPD
plans/layout_read ─┤
plans/layout_write─┘
aclk = 125MHz, 128-bit
```

- **PS CPU 不参与运行期数据/控制**：`ps/vm_pl.c` 只做 `plan[4]=1` 启动、轮询完成/错误；
  `gateway_async.c` 只做网络、参数装载 CRC/READY、地址边界和 `0xe400` 计划门铃。
  没有 CPU 神经网络算术、逐矩阵搬运或 per-node 调度。
- **但没有绕过 PS 硬 DDR 控制器**：6 个 PL master 经 smartconnect 进入
  `S_AXI_HP0_FPD`，后面是 Zynq PS 的硬 DDR 控制器。当前 bit/板级没有 PL 侧 MIG
  或独立 DDR 颗粒。若未来要“完全绕过 PS 硬控制器”，需要改板/改 PS 配置/加 MIG，
  属于未决硬件选项；不能从现有脚本许诺。
- 逻辑模型边界：本任务的 AXI BFM 把 DDR 当作独立 AXI 存储端（`BASE..BASE+MEM_BYTES`），
  这样可以在无板卡条件下测 AR/R/AW/W/B、延迟、背压、4KiB、有限队列；它不是
  PS DDR 控制器的时序模型，也不证明现有硬件可绕过 HP0。

## 2. 当前仍在 host/PS 的控制依赖（逐项）

| # | 位置 | 当前行为 | 为何是运行期依赖 | 迁移设计 |
|---|---|---|---|---|
| H1 | `work/host/fusion_backend.py: fuse_plan` | 每个闭合子图：host 上传输入 Q（`upload21`）、写 `0xe400` START、轮询、下载 FP32+Q16 | host 决定“下一个子图是谁”，并逐子图往返 | 预提交整图节点表；host 启动前只上传输入/权重/表；运行期零调用 |
| H2 | `work/host/fusion_backend.py: polls` | `while` 50ms sleep 轮询 `0xe400` 状态 | host 参与完成同步 | PL 单一 IRQ/状态；PS 只在最后读一次 done/error |
| H3 | `work/host/base_v021.py: native21` | 591 个 legacy queue：host 做 `dynamic_pack_task`、上传描述符+A+W、3 次 MMIO、轮询、读 C | host 逐矩阵布局/编码/调度 | 把 591 个 queue 的 shape/地址/描述符预编译进节点表；PL layout 引擎生成/搬运；W7 静态权重常驻 |
| H4 | `work/host/base_v021.py: matmul_special` | host 按 batch/row/col 循环调用 `native21` | host 决定 M/N 分块和 K 顺序 | 节点表写死 M/N/K 分块与每 C 的 K 顺序；PL 计划执行，host 不循环 |
| H5 | `work/host/backend_v021.py: resident_pack_task` | host 构造 descriptor、`A` block、`C` 地址 | host 生成运行期索引 | 启动前预生成；运行期只读 |
| H6 | `work/host/backend_v021.py: write_words` | 匹配到参数 blob 时发 `0xe300` DDR→PL SRAM copy；否则 host 逐字写 | host 参与 legacy 非矩阵数据搬运 | 全部改 PL DMA/布局；host 只做一次性参数装载 |
| H7 | `work/host/parameters.py: ParameterTransport` | 参数镜像按 1020B UDP 装载、CRC/READY | 启动前允许；运行期不允许 | 保留“启动前一次装载”；运行期 generation 不变 |
| H8 | `work/ps/vm_pl.c: vm211_run` | PS 按 `plan_index[68]` 找 program、启动一个 plan、轮询 | PS 逐 plan 控制 | PS 只写一个 graph doorbell；PL graph runner 自己取节点表 |
| H9 | `work/ps/gateway_async.c` | 网络 server、`0xe000/0xe100/0xe200/0xe210/0xe300` 地址检查和参数 CRC | PS 仍是网络/参数入口 | 保留启动前参数装载；运行期网络只允许只读 telemetry，禁止数据搬运/START 重放 |
| H10 | `work/scripts/compile_pl_plans.py` | host 编译期生成 68 个 plan、6231 个矩阵描述符、45055 条指令 | 编译期允许，运行期不应重新生成 | 把输出直接 seal 进参数镜像；启动前校验 SHA/CRC |
| H11 | `work/host/layout.py` / 向量 wrapper | host/旧路径做部分 layout/编码 | 运行期 host 参与 | 用 `ddr_layout_engine` / `ddr_layout_axi` 的 PL 版本；或预布局 |
| H12 | 外层 ONNX/Python (`fusion_executor`，不在 work 内) | host 图遍历、shape/scale 检查、Tensor 组装 | host 运行期控制流 | 启动前把图节点、依赖、tensor 地址、scale 地址全部编译成表；运行期只留 PL |

> 结论：当前“68 个 PL 计划”只去掉了闭合子图内部的逐矩阵 UDP 查询；
> **外层 DAG、591 个 legacy queue、边界输入/输出和 per-plan 轮询仍在 host/PS**。
> 因此不能声称“整机 PL 自主”，也不能把 wholecase 153.8s 的剩余时间都归因于 DDR。

## 3. 目标：一次预提交图/计划，PL 自主执行

### 3.1 启动前（host 只参与一次）

1. 主机把全部输入、权重、scale/bias、布局参数、执行计划、矩阵描述符、图节点表搬到 DDR；
   写入后做 SHA/CRC，最后一次 READY。
2. PS 只写一个 `GRAPH_START(base,count,generation)` 门铃；之后不再写数据/START。
3. 运行期所有 DDR 读写由 PL 的 DMA/算子完成；中间量驻留/回写由 PL 计划决定。
4. 完成/错误只通过一个 IRQ/状态字报告；host 最后一次性读输出（或由 PL DMA 到指定
   host 可见缓冲）。host 不再逐算子/逐矩阵请求。

### 3.2 节点表（建议 64B/节点，DDR 连续）

| word | 字段 | 含义 |
|---:|---|---|
| 0 | magic `GRPH` | 表项有效 |
| 1 | kind | 0=matrix,1=vector,2=layout,3=barrier |
| 2 | node_id | 0..MAX_NODES-1 |
| 3 | dep_mask | 32/64 位依赖位图（可扩展为 dep_list 指针） |
| 4 | plan_addr | 现有 `pl_execution_plan_v022` 的 plan 地址 |
| 5 | plan_count | 指令数 |
| 6/7 | in/out_addr | DDR 张量地址 |
| 8 | bytes | 预期字节数/元素数 |
| 9 | flags | QDQ/layout/边界/ACL 标志 |

所有 plan payload、matrix queue、vector/layout descriptor 都必须在启动前生成并 seal；
节点表只是索引，不含运行期 host 计算。

### 3.3 PL graph runner（本次已写控制骨架）

`tasks/ds_ddr/candidate/pl_graph_runner_v1.sv`：

- 一次 `start`，按 `node_count` 从节点表读取 64B 行；
- 维护 `done_mask`；节点 `dep_mask & ~done_mask == 0` 才可启动；
- 按就绪顺序扫描（不是简单顺序执行）；子算子 `op_start/op_done/op_fault` 握手；
- 全部完成发一个 `done`；循环依赖/坏 magic/子算子错误发一个 `fault+error_code`；
- `done`/`fault` 都是单出口，不在错误后继续发新节点。

已跑三例（`bench/tb_graph_runner.sv`，Icarus）：

| case | 内容 | 结果 |
|---|---|---|
| 0 | 表顺序 0,3,1,2；依赖 1←0、2←0、3←1\|2 | 启动序列 0,2,1,3；completed=4，done，pass |
| 1 | 0↔1 循环依赖 | fault=1，err=0x04，pass |
| 2 | 子算子 fault | fault=1，err=0x05，pass |

**这不是完整集成**：`op_*` 目前是桩，尚未把 68 个 plan、591 个 legacy queue、
matrix/vector/layout 子模块和真实 DDR 抓取接上；节点表读取也还是本地 64B 行模型，
未接 `axi_dma_v020_multi`。这些是下一步工作，不能把骨架测试当成 CASE 自主执行。

## 4. 迁移后的内存/带宽边界

- 参数镜像 173,715,968B 在 `0x10000000..`；68 个 plan 在 `0x19de74c0..0x1a5ab180`；
  运行期不再上传参数（generation 不变）。
- 中间量：68 个计划的 `temp_end` 最大 `0x068EF000`（110,030,848B），
  落在 `0x03000000..0x08000000` 的 80MiB arena 内；但 591 个 legacy 节点的
  lifetime 未做全图 liveness，不能保证现有 arena 足够。需要：
  1. 对 68+591 节点做 lifetime/alias 分析；
  2. 中间量按 lifetime 复用，或分块 spill 到 DDR；
  3. 对每个 C 的 K 累加顺序做约束，不能为了复用改变 K 顺序。
- 带宽：本任务实测 whole-plan 总字节 933,028,896B（矩阵 125,143,040 + vector/layout
  807,885,856），在 16B/cycle 半双工、125MHz 下传输下界 0.4665s；实际 whole plan
  12.4866s。也就是说**平均字节量不是 12.5s 的主因**；主因是单在途突发气泡、
  逐请求串行、计划阶段串行和 host/legacy 往返。300/600MHz 只降低计算/控制周期，
  DDR 用户域必须单独列频；不能把 125MHz 的字节下界按 300/600 直接缩。

## 5. 未实现/未决（诚实清单）

1. 完整 68+591 节点图 runner 未接真实子算子/DDR；当前只有 4 节点骨架和桩。
2. 591 个 legacy queue 的静态化、W7 权重常驻、动态 A/C 的 PL 布局未完成。
3. 边界输入/输出“host 只一次”只设计了协议；未做真实主机侧一次上传/下载的端到端测试。
4. 物理 DDR 是否可绕过 PS 硬控制器未决；当前 soc_full 明确经 `S_AXI_HP0_FPD`。
5. 300/600MHz 无综合/STA/板级；只有 RTL 逻辑仿真和流水目标。
6. 历史 wholecase 153.775s 的逐阶段 profile 缺失；不能把 153.775−12.487 全算 DDR。
7. `pl_graph_runner_v1` 的节点表读取是本地 64B 行模型，不是多 outstanding AXI；
   接入时应复用 `axi_dma_v020_multi` 并加表项 CRC/版本检查。
