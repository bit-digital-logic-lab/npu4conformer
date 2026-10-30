# ds_protocol_audit — DMA/AXI/缓存/错误处理独立审查报告

日期：2026-10-29（UTC+8）
目录：`/home/yang/Desktop/项目/tasks/ds_protocol_audit`
性质：只读审查 + 本目录独立反例测试；未修改 `work/`、候选、旧竞赛项目；未综合、未 Vivado、未板卡、未 VNC、未网络部署、未 push。

## 1. 范围与边界

- 只读审查对象：
  `work/rtl/axi_dma_v019.sv`、`ddr_vector_axi.sv`、`ddr_vector_engine.sv`、
  `ddr_layout_axi.sv`、`ddr_layout_engine.sv`、`plan_submit_csr.sv`、
  `pl_execution_plan_v022.sv`、`task_queue.sv`、`queued_v020_monitored.sv`、
  `c_cache_banked4.sv`、`block_engine_l1bank_v020.sv`、`block_storage_dma_prefetch.sv`。
- 新增候选（只读快照）：`tasks/ds_ddr/candidate/axi_dma_v020_multi.sv`，
  快照 SHA-256 `7123c26fd3d91643497485c1ed7c9dedc3a4f06cf488bef36f711468dd6488e3`
  （`snapshots/axi_dma_v020_multi_snapshot_20261029.sv`）。
  审查期间该文件由 ds_ddr 更新过一次（早期 hash `7653b83e...`），见 PA-013。
- 未改任何原文件；所有新代码、日志、TB、报告均在本目录。
- 数值约束未改：W7(S/J/M)/positions/clip、A16/C48、每 C 的 K 顺序、FP32 FTZ/RNE/FMA、QDQ 边界均未触碰。
- 主机只参与离线准备；测试中的 AXI BFM 只是存储端协议模型，不是 DDR 时序/物理模型。
- 本报告不声称 300/600MHz 或时序达到；无 STA/综合/板卡。
- 阶段末读取到用户追加：新增严格流水 ds_pe_pipeline、gemini_pipeline_control 及历史 STA 审查；
  DMA/存储新候选需考虑 300/600MHz 控制路径寄存化，但**频率不能当作已验证**。见 PA-015。

## 2. 环境与复现

- Icarus Verilog 14.0（oss-cad-suite），`-g2012`。
- 复现：`bash scripts/run_all.sh`（只读 `work/`，日志写本目录 `reports/`）。
- 因 Icarus 的 `$value$plusargs("%s")` 对中文路径字节处理异常，fixture 通过
  `/tmp/opencode/vf`、`/tmp/opencode/lf` 的 ASCII 符号链接传入；符号链接只指向只读原 fixture。
- 每个报告目录含 `cmd.txt`（或 `run_all.sh` 的对应行）、`run.log`、`rc.txt`；
  编译日志在 `reports/compile/*.log` 和 `.rc`。
- 源码 SHA 清单：`reports/SOURCE_SHA256.txt`；原始 work 文件 hash 也在其中。

## 3. 已实测通过（证据，不是“现有 tests 通过”的同义重复）

| 证据 | 内容 | 结果 |
|---|---|---|
| `reports/dma_edge001` | v019：20 组定向反例（4KiB 0xFF0/0x1000、AR/AW/W/B 独立背压、RLAST 早/晚、RRESP 中途错误排空、BRESP abort、WSTRB tail、65535 beat、回绕、无 RLAST 观察） | `DMA_EDGE_PASS errors=0 cycles=70101` |
| `reports/vector_stress001` | 5 个 vector fixture × 3 随机种子；伪随机 AR/R/W/B 背压与 B 延迟；逐字节比对 + 32B tail guard | 15/15 PASS；`round_i16` 2002B、`add/mul/i16/i48` 4004B |
| `reports/layout_stress001` | 8 个 layout fixture：copy_i16 2002B、pack_matrix_edges 8192B、unpack_row/nchw 4620B、unpack_c48_compact 6930B、conv_padding 4096B、depthwise 2048B、case0000 157696B；7×2 seeds + case0000×2 | 16/16 PASS；C48 6B 片段跨 128-bit 行、4KiB 多次跨界、tail guard 全通过 |
| `reports/acl001` | 强制 A/source/dest=0xFFFFFFF0（32-bit 加法会回绕），64-bit ACL 必须拒绝 | `VECTOR_ACL_PASS fault=1 err=01 rb=0 wb=0`；`LAYOUT_ACL_PASS fault=1 err=01 rb=0 wb=0` |
| `reports/multi001` | 候选 v020_multi：多 outstanding AR、FIFO full、同拍 push/pop、4KiB、RRESP、早/晚 RLAST、WVALID 气泡、延迟 B、BRESP abort、zero/unaligned、32-bit wrap | 13 个功能场景 `MULTI_TEST_END errors=0`；另确认 1 个 metric 缺陷 PA-004 |
| `reports/strobe001` | 候选 v020_multi 单拍 WSTRB=0x0007；物理写正确 | `mem=00 01 02 00`（第 4 字节未写）；`write_bytes=16`（应为 3，PA-004） |
| `reports/csr001` | plan_submit_csr AXI-Lite：独立 AW/W、B 背压、坏 strobe 原子性、busy START 拒绝、64-bit 交错读 | 3 项通过；64-bit 交错读确认 PA-001 |
| `reports/plan_stall001` | plan 的 FETCH / WAIT_OP / ERROR_DRAIN 在 AXI/child 不返回时的行为；phase3 正常完成 | phase1/2 确认 PA-002；phase3 `done=1 fault=0 completed=1` |

关键实测点：

- v019 4KiB：`addr=0x04000FF0,16 beats` → AR `0x...0FF0 len0` + `0x...1000 len14`（第二笔 15 beat，ARLEN=14），总 256B；`addr=0x04001000` 单笔 len15。
- v019 RRESP 中途错误：8 beat 请求在 beat2 注入 SLVERR，仍接收/排空后续 beat 到 rlast，最后 `error=1`。
- v019 BRESP 错误：单笔写与多页写（0xFF0 的 1+15 beat）第一笔 SLVERR 后都不再发下一 AW；W 已接受笔数按 WSTRB popcount 计数（T12/T12b）。
- v019 最大合法 beat：65535 beats → 4096 个 burst、1,048,560 B、`read_index=0xFFFF`，16-bit 计数无溢出。
- 候选 v020_multi：FIFO 高水位 128（满），停止 consumer 后释放，256 beats 全收（`index=256`）；同拍 push/pop 256 beats 无丢/重；`ar_outstanding_max=4`、`b_outstanding_max=2`；早/晚 RLAST、RRESP/BRESP 均能 `done`，无 hang。
- 工程 fixture 的随机背压是**存储端 ready/valid 的随机化**，不是 DDR 时序/带宽模型。

## 4. 确认的问题（按严重性）

### PA-001（Medium）plan_submit_csr 的 64-bit 读回不是原子的
- 文件行：`work/rtl/plan_submit_csr.sv:23`（单 `snapshot_high`）、`88-115`（每个 64-bit 低字读都覆写同一 latch）。
- 触发：`read 0x20 → read 0x30 → read 0x24`。
- 最小复现：`reports/csr001`，`tb/tb_csr_snapshot.sv`。
- 实测：`0x24` 返回 `0xAABBCCDD`（fetch high），正确应为 `0x11223344`（cycles high）；`read56,read64,read60` 返回 `0` 而非 `0x01234567`。
- 影响：PS telemetry / 64-bit 计数器可能读错；不影响矩阵/向量数值，但会误导完成时间、字节数、roofline 统计。
- 修复：按地址索引 `snapshot_high[]`，或提供单次 64-bit 读；不要在“读任意低字”时共用一个高字 latch。

### PA-002（Medium，鲁棒性缺口）watchdog 不能约束“AXI 或 child 永不返回”
- 文件行：`work/rtl/pl_execution_plan_v022.sv:80-94`（FETCH 超时只置 `fetch_bad/error_code=09`，不置 `fault`、不离开 FETCH）、`100-109`（WAIT_OP 超时进入 ERROR_DRAIN，但 ERROR_DRAIN 等 `matrix_done/vector_done/layout_done` 无限期）。
- 触发：WATCHDOG=400；(a) plan fetch 的 AR 已被接受，R 永不返回；(b) instruction 已取回、matrix_valid 已发，matrix_done 永不返回。
- 最小复现：`reports/plan_stall001`，`tb/tb_plan_stall.sv`。
- 实测：
  - (a) 1000 cycles 后 `busy=1 done=0 fault=0 err=09 plan_state=3 wait=997 dma_state=2 bfm_ra=1`；`dma_state=2` 为 RDATA，证明 AR 已接受。
  - (b) `busy=1 done=0 fault=1 err=09 plan_state=10 wait=401 completed=0`，再等 600 cycles 仍无 done。
  - phase3（child 正常 done）`busy=0 done=1 fault=0 completed=1`，说明控制路径本身可用。
- 设计契约原文允许“排空已接受事务、不取消”；本发现不是要求取消 AXI，而是要求**有界**：超时后必须有 abort/drain 握手 + 第二 deadline/硬复位边界。当前“bounded watchdog”在通道卡死时无界。
- 修复建议：plan 产生 `child_abort`；child 停止发新事务、排空已接受 burst 后 `drain_done`；plan 在 `drain_timeout` 后置 `fault/done`（或请求 AXI firewall/reset）。FETCH 超时应同时置 `fault`，不要只写 error_code。

### PA-003（Low）v019 32-bit 地址加法在 4GiB 回绕
- 文件行：`work/rtl/axi_dma_v019.sv:31-33,35,40,68,79`（内部 `address[31:0]`，`m_axi_*addr={8'd0,address}`）。
- 触发：`read addr=0xFFFFFFF0 beats=2`。
- 最小复现：`reports/dma_edge001` T18。
- 实测：AR `0xFFFFFFF0 len0` 后 AR `0x00000000 len0`，`error=0`（第二笔读低地址）。
- 可达性：vector/layout/plan/queue 都在 64-bit 做 extent 检查（`reports/acl001` 证实拒绝 0xFFFFFFF0），所以当前不可达；属 defense-in-depth。
- 修复：内部地址改 40-bit，或在第一笔 AR 前检查 `addr+beats*16` 的高位。

### PA-004（Low）v020_multi `write_bytes` 忽略 WSTRB
- 文件行：快照 `snapshots/axi_dma_v020_multi_snapshot_20261029.sv:155-156`。
- 触发：4 beats，最后一拍 WSTRB=0x0007（51 字节）；或 1 beat、WSTRB=0x0007（3 字节）。
- 最小复现：`reports/multi001` W2；`reports/strobe001`。
- 实测：物理写正确（`mem=00 01 02 00`），但 `write_bytes=64` / `16`（按 16B/beat），应为 51 / 3。
- 影响：DDR 写字节 telemetry、roofline/带宽核算；不影响数据。
- 修复：`write_bytes <= write_bytes + pop16(write_strobe)`（与 v019 一致）。

### PA-015（Info / structural-risk）300/600MHz 控制路径寄存化尚未做，无 STA
- 文件/行：`axi_dma_v019.sv:31-33,44,62-79`；v020 快照 `62-85,145-172`；
  `ddr_vector_engine.sv:103-112`；`ddr_layout_engine.sv:44,164-171`。
- 触发/证据：只读源码审查；本任务禁止综合/STA，未测频率。
- 结构观察（不作为时序结论）：v019 的 `page_beats/limit/chosen` 组合减法-比较-选择直连
  `ARLEN/AWLEN`/`beats`；v020 的 `can_ar` 是 state/remaining/tag_cnt/`fifo_free>=chosen`
  的宽组合 AND，`b_out` 为 32-bit 比较/信用；`read_data=fifo[fifo_rd]` 是 128×128
  异步读；vector 的 `invalid_descriptor` 在 start 单拍做 64-bit 乘法/范围/overlap；
  layout 是 64-way tag 比较 + encoder。300/600MHz 下应先寄存/流水这些控制路径。
- 建议：请求边界寄存 `chosen/arlen`；用 0..MAX_OUT 的小信用计数器替代 32-bit `b_out`；
  寄存 `wlast/last`；FIFO 改同步读/BRAM 输出寄存；descriptor 校验拆 2-3 拍；
  tag 比较加一级流水。不得改数值语义；频率仍以 STA 为准。
- 状态：structural-risk，未实测；**不得据此声称 300/600MHz 达到**。

### 风险项（未计为已证实 bug）
- PA-005（Low/open-risk）：v020_multi 参数 `MAX_OUT` 2 的幂、`MAX_BURST<=16`、`FIFO_BEATS>=MAX_OUT*MAX_BURST` 无断言；默认 8/16/128 安全。`limit=...MAX_BURST[4:0]` 在 >31 时截断。
- PA-014（Low/open-risk）：v020_multi 的 `b_out` 在无 outstanding AW 时遇到 spurious B 会下溢到 0xFFFFFFFF，`can_aw` 永久为假。合规 slave 不会这样做，未做反例（需要故意非合规 B）。
- PA-006（Info）：v019 对 `beats==0` 报 `error=1` 且不发 AXI；当前引擎的 descriptor 校验不允许 0，属防御语义，需在接口文档写清。
- PA-007（Low/behavior）：v019 无内部超时；无 RLAST 时 120 cycles 仍 busy（接受 118 拍）。依赖上层 watchdog，而 PA-002 表明上层也不一定有界。

## 5. 排除的“假阳性”（保持证据链诚实）

- 首版 multi TB 在 FIFO 满测试中出现 `tag_cnt=7/remaining=16` 看似候选丢事务；实际是 TB 的 AR 队列 `qc` 在“同一拍 push+pop”时两处赋值互相覆盖。修正为净计数 `qc<=qc+push-pop` 后，候选 256-beat FIFO full 正常完成（R2 PASS）。**不记为候选 bug。**
- multi TB 的 W2 `mem[base+51]` 一度非 0，疑似 WSTRB 被忽略；独立 `tb_strobe.sv` 用同一快照、同一 slave 写法证明候选忠实转发 WSTRB（`mem=00 01 02 00`），故该现象是 TB 侧多测试内存交互/记录问题，**不记为候选 bug**；仅保留可复现的 `write_bytes` metric 缺陷。
- 审查开始时候选 `7653b83e...` 的 `m_axi_wvalid` 未与 `write_valid` 相与；当前快照 `7123c26f...` 已加 `&&write_valid`，W2 气泡回归通过。作为历史记录（PA-013），不冒充当前缺陷。

## 6. 未测 / 不能声称

- **FMA op17**：extracted tree 无官方 `asr_fma_ip` simulation netlist；vector 测试链接 `fma_forbidden_stub.sv`（用到即 `$fatal`），fixtures 仅用 op 0/2/7/15/14。未重跑 FMA 数值；不得把本报告当作 FMA 正确性证据。
- **c_cache_banked4 / block_engine_l1bank_v020 / block_storage_dma_prefetch**：V022 plan cluster 不实例化这些 legacy 模块；本报告仅源码审查，未做 epoch/重用、c_cache 冲突、WSCALAR abort 反例。若主 agent 集成，需补测。
- **物理 DDR / 300/600MHz / STA / 综合 / 板卡**：未做；随机 BFM 不是 DDR 时序或带宽模型；所有“通过”仅是逻辑/协议/打包证据。
- **完整 CASE0000 整模型**：未在本任务执行；fixture `case0000_embed_conv0` 只是 layout 的 157696B 数据搬运片段，不是整模型推理。
- **v019 的 40-bit 物理地址空间**：只在 32-bit 测试空间验证；PA-003 是本地回绕，未验证 >4GiB DDR。
- **task_queue / queued_v020_monitored 的 owner 仲裁与 retire**：仅源码审查；未做独立反例。它们是旧 queue 路径，不属于 V022 plan cluster 的 vector/layout 执行链。
- **layout cache 的 clear-vs-inflight**：源码上 `cache_valid<=0` 只在 `start&&ready` 分支；`ready=!busy&&rd_request_ready&&wr_request_ready`，即两个 DMA 都 IDLE，因此“clear 与 inflight 冲突”在该路径按构造不可达。未用强制违规做反例。
- **block_engine 的 fail() 清 valid/dirty 与 writeback**：`fail()` 只在 `write_ack`/错误之后或 compute 错误时调用；legacy 模块未做 RTL 反例，见 PA-012。

## 7. 对主 agent 的集成建议（优先级）

1. **PA-001**：CSR 读回改为 per-register 高字或 64-bit 单读。PS 固件在读取任何 64-bit 计数时不要交错读其他计数器（即使硬件修了，也建议软件成对读）。
2. **PA-002**：新增 abort/drain 契约和硬边界；至少让 FETCH 超时置 `fault`，并在 ERROR_DRAIN 增加第二 deadline。若无法取消 AXI，则明确“卡死需外部 AXI reset/firewall”，并在板级 supervisor 中实现。
3. **PA-004**：若 v020_multi 替换 v019，先修 `write_bytes=popcount(WSTRB)`，否则会污染字节/带宽统计。
4. **PA-003/PA-005/PA-014**：作为防御性修复/参数断言，不阻塞当前集成。
5. 保留 `tb/tb_dma_edge.sv`、`tb/tb_vector_stress.sv`、`tb/tb_layout_stress.sv`、`tb/tb_dma_multi.sv`、`tb/tb_csr_snapshot.sv`、`tb/tb_plan_stall.sv` 作为回归；`scripts/run_all.sh` 可重跑。
6. 不改 W7/A16/C48/K 顺序/FP32 语义；本任务所有测试都是只读 DUT + 独立 BFM，未引入数值 stub 冒充算子。

## 8. 计数与文件

- 运行单元：20（v019 定向）+ 15（vector）+ 16（layout）+ 2（ACL）+ 13（multi 功能）+ 3（plan phase）+ 1（CSR）+ 1（strobe）= **71 个场景组**。
- 结果：67 个功能/协议组通过；4 个确认缺陷（PA-001..004，其中 PA-004 为 metric）；4 个风险/行为项（PA-005/006/007/014）；1 个结构时序风险（PA-015，未测）；4 类未测（FMA、legacy cache/block、物理时序/DDR、整模型）。
- 报告目录：
  `reports/dma_edge001, vector_stress001, layout_stress001, acl001, multi001, strobe001, csr001, plan_stall001, compile`。
- 源码/候选 SHA：`reports/SOURCE_SHA256.txt`。
- 接口契约：`INTERFACE.md`。
- 结论 JSON：`result.json`；逐条：`FINDINGS.jsonl`；进度：`progress.json`。
