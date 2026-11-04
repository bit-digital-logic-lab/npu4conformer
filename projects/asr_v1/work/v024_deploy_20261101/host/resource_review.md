# V0.24 128-node + iterhash 资源复核

审查时间：2026-11-01。范围：只读 RTL、现有综合日志与最终资源报告；本次仅写本文件，未改 RTL、未启动综合/实现、未访问硬件。

后续约束更新：用户要求保持原完整矩阵/PE/operand 设计。本文件中涉及这些模块的优化仅作历史评估，已冻结为未选方案，不作为部署方案。此后启动过的独立 operand 候选验证结果另存在 `optimizations/operand`，已在收到冻结要求后结束现有运行，未替换生产源。

## 1. 已确认的资源边界

本次对象为 `v024_unified_top`、`MAX_NODES=128`、`SEQ_ENABLE=0`、`xczu15eg-ffvb1156-2-i`，控制器通过综合脚本替换为 `analysis/wc_graph_ctrl_iterhash.sv`。`rtl/graph/wc_graph_ctrl.sv` 本身仍是原始组合 hash 版本，不能误把它当作已测候选。

最终综合报告：

- [资源总表](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/reports/core128_iterhash_utilization.rpt)
- [资源层次表](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/reports/core128_iterhash_utilization_hier.rpt)
- [综合日志](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/logs/synth_core128_iterhash_ooc.log)
- [选定源指纹](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/reports/DEPLOYMENT_ITERHASH_SOURCE_SHA256.json)

| 项目 | 已用 | 器件可用 | 比例 |
|---|---:|---:|---:|
| CLB LUT | 513,136 | 341,280 | 150.36% |
| 其中逻辑 LUT | 481,560 | 341,280 | 141.10% |
| 其中存储 LUT | 31,576 | 184,320 | 17.13% |
| FF | 445,750 | 682,560 | 65.31% |
| BRAM tile | 2 | 744 | 0.27% |
| DSP | 279 | 3,528 | 7.91% |

目前核心综合 LUT 比器件容量多 **171,856**，尚未计入板级互连/JTAG/两块输入 RAM。此前按 LUT1..LUT6 primitive 数直接相加得到约 545,522，不能替代这里已考虑 LUT combining 的 513,136。报告提示物理优化后计数可能降低；当前没有证据支持靠布局优化消除 50.36% 超量，不能直接据此宣布可部署或时序完成。

| 层次（下级与父级不能重复相加） | LUT | FF | BRAM | 观察 |
|---|---:|---:|---:|---|
| `matrix` | 241,281 | 220,588 | 0 | 两个独立矩阵执行器 |
| `matrix/cluster` | 111,703 | 95,410 | 0 | legacy C48 路径 |
| `matrix/u_fusion` | 128,079 | 123,861 | 0 | fused A16 路径 |
| `cluster/eng/array` | 90,511 | 45,173 | 0 | 256 个 PE |
| `u_fusion/u_engine/array` | 90,517 | 45,173 | 0 | 另一套 256 个 PE |
| 两处 `storage/banks`，每处 | 13,329 | 47,104 | 0 | 二维 operand RAM 未推断成功 |
| `graph/vec` | 200,775 | 63,750 | 0 | 最大单类优化目标之一 |
| `graph/vec/arithmetic` 本层，不含子模块 | 136,155 | 59,175 | 0 | 缓冲和寻址/选择逻辑占用很大 |
| `.../g_approx.apcore` | 48,100 | 397 | 0 | 需核查综合 cell 归属后定位 |
| `graph/ctrl` | 59,278 | 153,629 | 0 | 过宽依赖存储及动态元数据读取 |
| `graph/lay` | 8,259 | 5,388 | 2 | 已使用 BRAM，优先级低 |

综合采用 `flatten_hierarchy rebuilt`，层次重建可能把周边逻辑移入某个子层次。上表足以定位大范围，不能仅凭 `apcore=48,100 LUT` 断言其算术自身需要这么多资源；它的源码是种子 ROM 加分级乘法，没有变量除法，日志也显示 12 个 DSP。应在已有 DCP 中按实际 cell 名称/驱动锥核查，再决定是否改该模块。不要先删近似路径、改误差上限或用另一种数学算法替换。

## 2. 第一批：保持接口周期的局部修改

以下均为候选建议。没有候选的新综合报告，不能把逻辑存储位数当作已节省 LUT 数。

### 2.1 控制器 `nd_dep` 缩至 MAX_NODES

现成候选：[NARROW_DEP_REVIEW.md](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/analysis/NARROW_DEP_REVIEW.md) 和 [两行 patch](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/analysis/wc_graph_ctrl_iterhash_narrowdep.patch)。审查时状态文件仍写 `PREPARED_ONLY_NOT_COMPILED_NOT_SELECTED`。

保持 `node_buf` 的 1,536 位、完整 1,024-bit dependency 合法性检查、48-word hash、节点 ABI、128 节点容量，仅将内部 `nd_dep[128]` 的宽度从 1,024 改为 128，并在通过完整验证后写入低 128 位。头部保证 `node_count<=128`；每个节点 ID 等于顺序读取的索引；接受的依赖必须指向该节点之前的节点。因此接受计划中高 896 位恒为 0，移除它们不改变 readiness。

逻辑存储减少 114,688 bit；这不是测得的 FF/LUT 减量。即使假设整个 ctrl 的 59,278 LUT 都消失，也补不上 171,856 LUT 的缺口，所以不能把这项当作唯一解决方案。

验证：保留完整 checksum 和高位非法依赖负测，检查 127/128 边界、129 拒绝、跨 32/64 位依赖边界、HHASH/NHASH generation 失效、原矩阵/向量/布局回归；输出和错误类别不得变化。

### 2.2 将矩阵 operand bank 改为 generate 内一维 RAM

文件：[operand_banks_dual_v2.sv](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/rtl/matrix/operand_banks_dual_v2.sv:32)，模块名实际为 `operand_banks_dual_v1`。

当前每个 stage 把 A 写成 `mem[0:15][0:7]`、W 写成 `mem[0:15][0:63]`。综合日志从 178 行开始明确报告 `Synth 8-7186`，distributed 属性被忽略，二维元素未推断为 RAM。两个实例各有 47,104 FF，和有效 A/W 数据量一致；这是已经观测到的存储实现失败，不是仅看属性猜测。

最小修改：把 A 的 `reg [127:0] mem[0:7]` 声明移入每个 `arow` generate；每个 row 的写使能为原写条件再与 `aw_rowbank==r` 相与。把 W 的 `reg [7:0] mem[0:63]` 放入每个 `wcol` generate；每个 column 写固定的 `wr_data[c*8+:8]`。保留两 stage、每个 row/column 的独立读地址、原异步读、stage/half 选择与输出时序。目标先是正确推断分布式 RAM，无需立即增加 BRAM 读延迟。

验证：穷举两 stage、所有写 beat、两个 row/column half、32 个 k；验证写一个 A row 不污染其他 row；W 一拍更新 16 列；写 stage 0 与读 stage 1 并行；保持同地址读写的旧可观察语义。随后跑 legacy 与 fused 矩阵回归。综合验收须看到该层 FF 显著下降、RAM primitive 出现，且日志不再逐元素报属性无效。

### 2.3 合并向量 `omem` 的所有写点

文件：[ddr_vector_engine_pipe.sv](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/rtl/vector/ddr_vector_engine_pipe.sv:350)。

日志 375–381 行直接记录 `omem_reg` 因多个同地址写点而无法推断 RAM，溶解为 **32,768 个寄存器位**。CREAD/CDRAIN/CITER 中对同一 `omem[cb*128+out_word]` 分别出现完整 128-bit 写，尽管状态互斥，现写法未被工具合并成一个 RAM 写端口。

最小修改：从这些互斥分支收敛一个明确的 `omem_we/omem_addr/omem_wdata`，由唯一时钟过程写 RAM。保持原 `pack_insert`、末尾不足一整字时的写入、fault/collect 条件和旧值/NBA 顺序。第一轮保留异步 `wr_data`，先确认推断为 LUTRAM；不能只把属性换成 `block` 后假定会变 BRAM。

验证：1/2/3/4/7/8/9/255/256/257 元素，FP32 与 A16 输出、四 lane 与迭代路径、最后一个 beat 的 strobe、WREADY 任意停顿、双 bank 同时计算/写回、错误和中途 flush。每次严格比对全部有效元素、全部写地址/字节 strobe，不能用 zip 截短比较。

### 2.4 A48 缓冲按奇偶元素分成两个一维 bank

同文件 321 行的循环一次写两项 `a48mem[...]`；日志 368–374 行指出同一过程中的多写端口导致 RAM 溶解成 **24,576 个寄存器位**。

合法描述符中 A48 仅用于 op14，且不允许 A scalar/B scalar；这是 `vector_desc_check_pipe.sv:44` 的现有检查。unpack 从 0 开始，每轮两个元素，最后一轮可只写一个。可把偶数与奇数元素分别存入两个 `48-bit × 256` 一维数组，地址含双 bank 选择和元素索引高位；每个数组每拍只有一个写端口。原四 lane operand mux 中，A48 只需实际有效的两个 lane，迭代小尾部只需 lane0；可以明确限定这些端口，但必须保留奇偶选择及末尾单元素。

先保持异步读取和已有 issue/collect 延迟。若要改为同步 BRAM，应作为下一批独立改动，重新设计 operand prefetch/valid，不能依靠 `ram_style` 自动补出流水。

验证：A48 正负极值、低 32 位与高 16 位的组合、1/2/3/8/9/255/256/257 元素、跨 128-bit 原始输入字边界、双 bank 切换；非法 A48+scalar/op 组合必须仍在产生 DMA 前拒绝。

### 2.5 先选择 operand 地址，再读 RAM

目前 B 端分别在 scalar、tiled、period、普通四个分支各写一次动态数组读取，C 也分别在 scalar/普通分支读取，A16/FP32 使用不同粒度读取。建议先计算每 lane 的最终元素/字地址，再给每个逻辑 RAM 一个明确读取表达式，最后进行 16/32-bit 子字提取。这样保留所有模式和异步时序，减少综合器不得不推断多个动态读端口的风险。实际端口/面积降低仍需综合确认。

当前 `CHUNK=256` 时，A/B/C/输出每个 bank 最多用 64 个 128-bit 字；现使用每 bank 128 字的 stride 并声明双 bank 256 字。可另做独立候选，将 stride 改为 64、总深度改为 128，所有地址改为有界位拼接。四组数组名义存储合计减少 65,536 bit；其中高地址可能已被综合常量传播去除，所以不能按这个数字估算净 LUT 收益。参数化版本应由 CHUNK 推导容量并加边界断言，不可悄悄破坏其他 CHUNK 配置。

## 3. 第二批：需要流水或资源调度变化

### 3.1 向量 raw/operand/output 使用真实 BRAM

当前 `raw` 有相邻两字异步读取，A/B/C 为多路异步取数，A48 有多写，omem 直接异步输出。属性不是 BRAM 保证。完成前述唯一写口/银行化后，优先把 omem 改为同步读加一个可停顿输出寄存器，明确保持 `WVALID && !WREADY` 时 data/strobe/last 不变；再处理 raw 两字窗口和 operand 预取。需要保留 load/compute/write 双缓冲重叠、所有 scalar/tiled/period/尾部模式和故障排空，不能直接全改成单口 RAM。

这批会改周期，需要重新标识 measured cycles；不能继续引用原 iterhash 的 CSR 18,804 周期或把不同版本周期混在一起。延迟改变后，host 仍以 sticky DONE、fault、pending、quiesced 与严格数值为准。

### 3.2 控制器 metadata 解除整表清零并分离端口

`nd_meta[128]` 每条 512 bit；当前 reset 和 START 均整表清零，且 dispatch、scan 和最多四个 child completion 的 `mark_done` 都动态读取元数据。直接去掉 reset 还不足以得到单个 BRAM，也不能把多个完成读合并成一个口而不处理同周期事件。

可先证明所有有效读都发生在完整节点装载/验证之后，再移除仅用于无效内容的整表数据清零；保留 `nstate`、`done_mask`、消费者统计、valid/计数等控制状态清零。进一步可在 dispatch 时把输出保留信息锁存在每个 engine 的小型上下文中，使 completion 无需回读大 metadata 表，scan/dispatch 再使用同步预读。该项涉及故障/并发完成状态机，不属于两行的小改动。

### 3.3 矩阵路径共享计算资源，保留两种语义

[v024_matrix_queue_engine.sv:351](C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core/rtl/graph/v024_matrix_queue_engine.sv:351) 同时实例化 legacy `cluster` 和 fused `u_fusion`；`fused_r` 只做 reset、start 与 AXI 选择。动态互斥并不会删除另一套硬件。两处阵列各约 90,500 LUT，确有重复成本。

合法的保功能方向是共享一个 `block_engine_prefetch_v2` / 16×16 PE 阵列及 A/W 存储，由锁存的本次任务模式将 C48 输出送 legacy DDR 写回或 fused framer/epilogue/A16 writer。必须仍支持 legacy 的 C48 读入累加、C48 写回、queue_count>1 与所有不能融合的 descriptor 回退；fused 路径仍要保持 C48 DDR 字节为 0、A16 字节计数正确、B 响应全部完成才释放 tile、perchannel 表预装载不被 legacy 任务错误清除。

这不是简单删掉 `cluster` 实例：当前两顶层分别拥有 engine/storage/DMA/reset，需统一共享边界，测试 legacy→fused→legacy、连续多 tile/跨 K、fault/timeout/isolation。可确认存在一套阵列的重复成本，但不能直接宣称净节省 111,703 LUT；共享后的 mux/控制、必须保留的 legacy writeback 仍占资源。

### 3.4 PE 的 DSP 映射，可作为保持数学合同的候选

两阵列目前均显示 DSP=0，而总 DSP 只使用 279/3,528。PE 源码已根据 PIPE_STAGES 生成实际需要的寄存器，不能把 `[0:5]` 的声明直接视为六级全被保留。若存储修复仍不足，可单独考察 16×4 无符号乘法和 48-bit modulo 累加的 DSP 映射，保留原位宽、signed/unsigned 解释、clip、shift、flush 和 latency，不先降低位宽或换 W7 数学定义。

这是需验证的映射建议，无实测节省量。重点验证 A=-32768、W 符号/J/M 全组合、clip 且 p=12/M>=8、48-bit 回绕、连续 valid 和 clear/flush。若 DSP 管脚寄存器映射要求增加阶段，必须同步更新 drain 合同并重新完整回归。

## 4. 暂不作为主攻点

- `c_cache_banked4_pipe` 源码有同步读/写及同地址 write-first bypass，但报告两份各约 3,000 LUT、0 BRAM。可检查模板或显式 RAM 实现，不过总量约 6,100 LUT，不能单独解决超量；改动必须保持每 bank 独立 mask 和 RAW bypass。
- `fusion_a16_blockbuf` 为 4,752 LUT、16,655 FF，异步读 128×128 RAM。可用唯一写口+同步读/skid 改 BRAM，需保持 duplicate 检查、scatter tag 与 drain 停顿；优先级低于向量与重复阵列。
- 近似数学种子、误差阈值、最大节点容量、legacy fallback 和全量校验不应为了先塞进芯片而默默删减。
- `approx_div_sqrt.flush` 目前漏接，综合日志 103–104 行有警告；现集成通过 `rst_n&&!core_flush` 复位它。应单列端口卫生修正并验证，不能把这条警告解释为 48k LUT 的已知根因。

## 5. 交付/验证顺序

建议先分别形成小候选：nd_dep 缩窄；operand 二维转独立一维 bank；omem 单写口；A48 奇偶 bank；地址先选择后读。每项保留独立 patch/源指纹和局部对照结果，确认后再组合，避免一次同时改时序、数学与存储而无法定位回归。

局部验证通过后，新综合需实际观察存储 primitive、FF、LUT 与报告警告；如果仍超过预算，再决定同步 BRAM/PE 映射/共享矩阵工程，而不是提前承诺任何一个候选足够。需要同时为板级逻辑留资源余量。

最终组合必须重跑现有合法图、所有非法/容量/依赖/checksum/generation/fault/drain 测试，并扩展候选影响的访问模式；参考整个 8,192-word dump 的完整一致性/约定数值误差，长度必须精确。真实 FMA IP、顶层所有端口、零 blackbox、full implementation 的 setup/hold/未约束路径/DRC 门控均需保留。

平台实现脚本目前硬编码 `core/build/v024_core128_iterhash_synth.dcp`。选定新候选后必须同步新的 DCP 路径和指纹，不能把旧超资源 DCP 和新源文件混用。host 的最终板验脚本与准备输入本次未改；真实板验只能在新 bit/ltx 通过实现门控后执行。目前没有新候选板上成功证据。
