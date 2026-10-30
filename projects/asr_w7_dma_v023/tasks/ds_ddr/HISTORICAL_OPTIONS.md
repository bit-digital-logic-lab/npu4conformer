# 历史方案索引与取舍（只读 Git 调查）

范围：`/home/yang/Desktop/ic设计竞赛` 的 Git 对象，只使用 `git log/show/ls-tree/rev-parse` 读取；
未 checkout、未修改该工程。项目根 `IC_GIT_REFERENCES.txt` 的 ref 名与短 commit 如下。
本文件只记录“可借鉴的机制”和“为何采用/拒绝”，不把历史板级/综合数字当作本轮实测。

## 0. 先纠正两个索引陷阱

1. `codex/kwt-ds-r6-mac32/64/128/256` 四个 ref 都指向同一个 snapshot 提交
   `8490830`（tree 内容相同），并没有四套不同的 mac32/64/128/256 RTL。
   它们最多证明“曾经按乘法器宽度做过分支命名”，不能作为宽度对比证据。
   真正可读的宽度/阵列证据在 `r6-bus128`、`r6-feed8x16`、`r6-array8x16`、
   `r7-fullwidth` 的 report/results 中。
2. `codex/kwt-ds-r6-resident_w` 指向 `79c8af1`，该提交是多个 r6 任务的共同基点，
   不是独立“全 W 驻留”结果；全 W/全 A 的对照应以
   `r7_resident_both`（`c01ca6e`）和 `r6_resident_a`（`812da1c`）为准。

## 1. 逐项取舍

| # | ref / commit | 具体文件 | 机制 | 适用性 | 采用 / 拒绝理由 |
|---|---|---|---|---|---|
| 1 | `codex/kwt-ds-r6-bus128` `f438e3f` | `hardware/experiments/r6_bus128/rtl/kwt_bus_burst_adapter.sv`, `kwt_bank_group.sv`, `kwt_cacc_cells.sv`, `kwt_operand_feed3.sv`, `kwt_feed_cell_engine.sv`; `graduate/ds_tasks/r6_bus128/WORKER_REPORT.md` | 16/64/128bit ready/valid burst adapter；128bit beat 拆成 8 个 16bit bank lane；2-entry read skid；2 cycle request→rd_valid；byte strobe、wrap-safe 尾拍；per-cell CACC；3×128bit feed = 24×16bit/cycle | 高：与当前 AXI128、W7/A16 存储层次直接相关 | **采用** burst 拆分、bank lane、尾拍 strobe、per-cell CACC 和“读写各一条通道”的端口纪律；**拒绝** A16W12 数值合同、固定 8×16 和 16bit W 容器（当前是 W7p8 + A16 + C48，且 W7 不能展开成普通整数乘）。其 128bit 实测 11,960 beats/层、95.19% slot、II=1 128 MAC/cycle 是历史 RTL 证据，不是本任务板级数字。 |
| 1b | `codex/kwt-ds-r6-bus64` `d937ebe` | `hardware/experiments/r6_bus64/rtl/kwt_bus64_adapter.sv`, `kwt_bank_1r1w.sv`, `kwt_cacc_cells.sv`, `kwt_ffn1_ii1_top.sv`; `graduate/ds_tasks/r6_bus64/WORKER_REPORT.md` | 64bit ready/valid burst；4 个写通道进 16bit bank；5-word 子字偏移；2-entry store join FIFO；3 个 CACC page；2-page output tile buffer；A 一次/B 每列 tile 一次 | 高：回答“窄总线 + 复用”能否替代宽总线 | **采用** byte enable、store join、3 page CACC、output tile buffer 和 A/B reuse；**拒绝**“64bit 必然不够”或“加宽必然 4×”——报告实测 8×16/64bit 22,222 cycles vs 16bit 75,068（3.38×）且 16bit duty 0.989、64bit duty 0.835，收益来自 II=1+复用+总线共同作用，不是位宽单独作用。 |
| 2 | `codex/kwt-ds-r6-feed8x16` `cc2259b` | `hardware/experiments/r6_feed8x16/rtl/*`; `graduate/ds_tasks/r6_feed8x16/WORKER_REPORT.md` | 8 A + 16 W 同步 bank，48B/cycle；II=1；2 页 operand；per-cell CACC；64/128bit 共享总线；tile 边界 K 重叠 | 高：说明“供数 bank + 页”比单纯加宽总线有效 | **采用** 每拍 8A+16W 的 bank 供数、A 行/W 列复用、页有效位和 task tag；**拒绝**“128bit 自动等于 2× 加速”的推断。报告实测 128b 16,298 cycles/层、输入 46,464B、相对旧串行 21.71×；这些是 99×64×256 的模型内结果，不是 CASE0000。 |
| 3 | `codex/kwt-ds-r6-resident_a` `812da1c` | `hardware/experiments/r6_resident_a/rtl/*`; `graduate/ds_tasks/r6_resident_a/WORKER_REPORT.md` | A 整层驻留 + W 双页；8×16；3 个 CACC page；128/64bit；A 复用 16.8×，W 复用 13× | 高：当前矩阵 A 分块会反复读 A；可把 A tile/行块驻留 | **采用** A 行块驻留和 W 双页的循环顺序；**拒绝**把该 report 的 14,544 cycles 直接套到 ASE/CASE0000（形状、W7 编码、C48 都不同）。其“A 驻留 14,544 vs A 每 tile 重载 28,806”是“复用优于加阵列”的直接证据。 |
| 4 | `codex/kwt-ds-r7-resident_both` `c01ca6e` | `hardware/experiments/r7_resident_both/rtl/kwt_resident_both_engine.sv`; `graduate/ds_tasks/r7_resident_both/WORKER_REPORT.md` | 全 A 14,336B + 全 W 32,768B + bias + output FIFO；per-tile 和 eager 两种调度；2 页 W 基线对照 | 中高：回答“要不要全 W 驻留” | **拒绝**全 W 驻留作为默认：冷任务 W 只搬一次，全 W 不减少 compulsory bytes；128bit 下 per-tile +6.17%、eager +9.28%，64bit 下 +0.74%/+1.67%。**采用**其结论：W 用 2 页 ping-pong，容量留给 A/C 和输出；只有能消除真实 stall 时才加容量。 |
| 5 | `codex/kwt-ds-r7-cacc` `9fd4aac` | `hardware/experiments/r7_cacc/rtl/kwt_cacc_pages.sv`, `kwt_pages_stream_engine.sv`; `graduate/ds_tasks/r7_cacc/WORKER_REPORT.md` | 2/3/4/8 个 CACC page；in-order drain；page 复用必须在最后一拍入 FIFO 后 | 高：当前 C48 累加器/C cache 的页数选择 | **采用** 3 page（128bit 17,461→16,309，−6.6%；4/8 page 无额外收益）和“page 多于 W 页深不会产生更多 tile 重叠”；**拒绝**把 40bit CACC 当 C48，且拒绝无 FIFO 的 page 复用。 |
| 6 | `codex/kwt-ds-r7-fifo` `6344eda` | `hardware/experiments/r7_fifo/rtl/kwt_out_fifo.sv`; `graduate/ds_tasks/r7_fifo/WORKER_REPORT.md` | 参数化 output FIFO 深度 8..512；show-ahead；full/high-water；stress backpressure | 高：输出写回与计算重叠 | **采用** 128 beat 深度（128bit 下 17,461→17,118，−1.96%；64bit 无收益）和“FIFO 只能吸收突发，不能创造带宽”；**拒绝** 256/512 的额外面积；**拒绝**用深度掩盖 DDR 平均带宽不足。 |
| 7 | `codex/kwt-ds-r7-packing` `9b6ff45` | `hardware/experiments/r7_packing/rtl/*`; `graduate/ds_tasks/r7_packing/WORKER_REPORT.md` | W12 / Y40 / Y48 外部格式；CRC-16；尾拍 byte strobe；W12 front-end unpack | 中高：当前 W7p8、C48 都是紧凑格式，尾拍/布局可借鉴 | **采用** 尾拍 byte strobe、按值宽计算 payload、CRC/长度自检（作为传输层校验，不改变数值）；**拒绝**把 Y48 当“输出格式变更”而不做数值验收；当前 C48 语义必须保留，不能为了字节数改成 Y40。报告 Y48 相对 Y64 输出 −25% 字节且周期不变，说明“输出字节”是独立优化维度。 |
| 8 | `codex/kwt-ds-r6-traffic` `49415ba` | `hardware/experiments/r6_traffic/model/*`, `logs/sweep.csv`, `graduate/ds_tasks/r6_traffic/WORKER_REPORT.md` | 16/64/128bit 精确 A/W/bias/output 流量；tile/驻留/layout/burst/latency/outstanding sweep；CACC row-port 约束 | 很高：本任务 AXI 建模的直接历史依据 | **采用** 16beat 突发、O≥2 隐藏延迟、O=1 每突发暴露延迟、tile-major layout 避免 overfetch、A 驻留使外部读最小 38,272B；**拒绝**“总线占用率低就加宽”的结论——报告明确指出当前 feeder II=C+2 才是 3.6% 利用率的主因，且 II=1 不改 CACC 会丢 93% 乘积。 |
| 9 | `codex/kwt-bus-budget` `9f1fd68` | `hardware/optimization/kwt_bus_capacity_model.py`, `kwt_bus_capacity_model.md`, `ffn1_perf_storage_tradeoff.md`, `dma_writeback_pipeline.md` | 统一“有效/填充”字节口径；512KiB SRAM 预算；乒乓端口 2 字/cycle；写回单口 SRAM 预读 | 高：避免把未补零 A 与补零物理读混算 | **采用** 有效 148,480B / 填充 153,600B 的双口径、每拍端口需求、写回预读；**拒绝** 147,840B 单口径和“12 层 W 全驻留仍宽裕”的说法：12×W16+padded A+bias+有效 Y+desc=515,584B，虽 ≤524,288B（余 8,704B），但再加 12 层 bias 就超 2,560B；不能据此说可随意全驻留。其 758,784B 逐 tile 重装是“为什么必须复用”的反例。 |
| 10 | `verified/dataflow-v2-functional-20261024` `cc3ac4c` | `hardware/rtl/control/kwt_dataflow_v2_ctrl.sv`, `hardware/rtl/dma/kwt_dma_2d.sv`, `hardware/architecture/dataflow_v2/{README,REPAIR_20261024}.md` | X 常驻、W 双页、2D stride、16×16 逻辑块、bias 一次、输出 stage、抽象 128bit 总线 | 中高：整机数据流和 2D 搬运 | **采用** X 常驻/ W 双页/ 2D 描述符/ 输出 backpressure；**拒绝** 16 MAC 行广播作为主算力（太慢），也拒绝把 12,527 cycles 小形状当成 CASE 性能。其“W/bias 与输出共用一条 DMA、无多通道 QoS”正是本任务要补的缺口。 |
| 11 | `archive/ws-before-prune-20261027` `0b178b7` | `hardware/SRAM约束与驻留数据流.md`, `hardware/A12W10紧凑打包与4x16_8x16驻留架构.md`, `hardware/CORE.md`, `hardware/versions/csa/...`, `hardware/ws/reports/*` | 16bit SRAM 宏端口/时序约束；32bit ICB 与 16bit 宏失配；奇偶 bank 成对；8(K)×8(N)/4(K)×16(N)；CSA 300MHz 预布局 | 很高：当前“带宽没跑满”的根因常在宏端口和 ICB 状态机，而不是阵列 | **采用** “容量≠端口带宽”、奇偶 bank 承接 32bit 字、追尾写回 FIFO、8×8/4×16 复用、CSA 的 300MHz 预布局仅作方向；**拒绝** 32bit ICB 吞吐直接套到 AXI128（本任务用户域是 128bit/16B per beat），也拒绝把 300MHz 预布局当物理签核。 |
| 12 | `codex/kwt-ds-r6-array8x16` `534fe5a` / `r7-fullwidth` `1131de3` | `hardware/experiments/r6_array8x16/rtl/*`, `r7_fullwidth/rtl/*`; 两个 WORKER_REPORT | 128 个物理乘法器、8×16、40bit CACC、2 tile bank、II=1、64bit slot | 高：阵列/累加器组织 | **采用** per-cell CACC、II=1、tile 级 overlap；**拒绝** 40bit C 和 64bit slot（当前是 C48 回绕），拒绝把 17,461 cycles 当本任务算力下界。 |
| 13 | `codex/kwt-architecture` `df93c87` | `hardware/architecture/compute_only_pipeline.md`, `README.md`, `speed_estimate.py` | 16 行广播、每拍 1 B 字、II=1、计算/导出/写回分段；147,840B 理论载荷 | 中：用于对照“计算核本身不是总线” | **采用** 计算/导出/写回分段和“更深流水不减少 II=1 的拍数”；**拒绝** 16 行广播的吞吐（99×64×256 需 114,688 拍，且 CACC 行端口冲突），也拒绝把 testbench 定时当平台吞吐。 |
| 14 | `codex/kwt-ds-r6-resident_w` `79c8af1` / `codex/kwt-ds-r6-mac*` `8490830` | 对应 tree 的 `hardware/experiments/*` 与 report | 仅有共同基点或无独立实现 | 低（索引陷阱） | **拒绝**把 ref 名当独立方案；需要宽度/驻留对照时回到 #3/#4/#5 的实测 report。 |

## 2. 对当前 V0.22 的直接结论

- **DMA 层**：历史 #8/#1 的“16beat + O≥2 + 分行 bank + 尾拍 strobe”与本次 BFM 结果一致：
  V019 单在途在每个突发后暴露一次延迟；V020 多 outstanding 在 32/64 cycle 延迟下把
  4096beat 读从 12,832/21,032 cycles 降到 4,391/4,424，写从 13,101/21,280 降到 4,673/4,712。
- **矩阵层**：历史 #3/#4/#5 说明“A 驻留 + W 双页 + 3 CACC page”优于“全 W 驻留/更深 FIFO”；
  当前 V0.22 的 `block_storage_dma_prefetch` 仍是整块 A/W 串行 + C 整块读写，应优先改成
  A 行块驻留、W 双页、C 三页/128beat 输出 FIFO，而不是继续加阵列。
- **整机层**：历史 #10/#11 都指出“X/W 预取、2D 描述符、输出追尾”是有效方向；
  但历史 #8 的 591 个外部 legacy queue 和 host DAG 仍是 V0.22 的真实缺口，
  不能用“PL plans 12.5s”代表 wholecase，也不能把 153.8s−12.5s 全算成 DDR 延迟。
- **不采用的“大改”**：把 W7 展开成 INT16 乘、把 C48 改成 40bit、把 A16W12 的
  CACC 宽度/输出格式直接搬过来、把 32bit ICB 的 1 字/拍当 AXI128 带宽、把
  300MHz 预布局当物理时序——这些都会破坏用户合同或把历史证据跨层拼接。

## 2.1 必须避免的历史结论误读

- **“64bit 必然不够”不成立**。历史 `r7_cacc/r7_fifo/r7_resident_both` 只在
  A16W12、8×16、40bit CACC、指定夹具下测到“64bit 已带宽受限/加 FIFO 无收益”；
  这是该配置/该负载的 roofline 结论，不是对所有 W7/A16/C48、所有重用方式的
  普遍断言。当前 64→128 的收益必须用本任务的 shape、重用和 BFM 重测。
- **“300/600MHz 已达到”不成立**。历史 `archive/ws-before-prune` 的 CSA 只有
  300MHz **预布局**方向；r6/r7 的 150/128bit 结果也不是 300/600MHz 物理签核。
  本轮 300/600MHz 只是流水目标，没有综合/STA；不能把频率缩放表中的数字当
  已实现频率。
- **“名称里有 prefetch 就是真预取”不成立**。当前 `block_storage_dma_prefetch`
  是整块 RDMA→RSCALAR→WSCALAR，A/W 与计算分离；真正的重叠必须像本任务
  `ab_pingpong_prefetch` 一样有页有效/释放和 overlap 计数。
- **“平均 DDR 带宽不够”不成立**。本任务 whole-plan 平均 74.7MB/s，但 BFM 在
  大范围连续 DMA 上可到 16B/cycle 的 93~98%；瓶颈是逐请求/阶段串行和 host
  往返，不是平均字节量。

## 3. 复现/只读命令

```bash
cd /home/yang/Desktop/ic设计竞赛
git rev-parse --short codex/kwt-ds-r6-bus128
git ls-tree -r --name-only codex/kwt-ds-r6-bus128 | grep r6_bus128
git show codex/kwt-ds-r6-bus128:graduate/ds_tasks/r6_bus128/WORKER_REPORT.md
git show codex/kwt-ds-r7-cacc:graduate/ds_tasks/r7_cacc/WORKER_REPORT.md
git show archive/ws-before-prune-20261027:hardware/SRAM约束与驻留数据流.md
```

未执行：checkout、branch、commit、push、Vivado、板卡、联网远控。
