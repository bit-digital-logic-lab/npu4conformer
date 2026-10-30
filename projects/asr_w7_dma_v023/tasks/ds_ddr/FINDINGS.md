# FINDINGS（阶段记录）

## F1 baseline

- 原 7 组 RTL 测试全部 PASS；Icarus 14 的中文 fixture 路径用 `/tmp/opencode` ASCII
  别名修复，未改输入模型。
- 跳过 `matrix_epoch` 等缺依赖测试，原因在 `bench/baseline/result.json`。

## F2 DMA/AXI

- `axi_dma_v019` 单在途、≤16beat、AR 等 RLAST、AW 等 BRESP；每突发暴露延迟。
- `axi_dma_v020_multi` 8 AR 在途 + 128beat 读 FIFO + posted write/B 信用。
- 4096beat，L=32：read 12,548→4,135；write 7,404→4,815；mix 13,558→8,779。
  L=64：read 20,740→4,167；write 7,376→4,800；mix 21,183→8,760。
  L=32 mix 8,779 是 8192beat 半双工下界的 93.3%（余下是 256 次换向/仲裁空拍）。
- 延迟隐藏阈值 N×16≥L：L=64 时 N=2/4/8 read = 10,390/5,238/4,167。
- L=8 mix 8,777→8,745（1.004×），低延迟混合读写不应盲目换 v020。
- 小请求 vector/layout 只换 DMA 略慢：add_scalar 7,882→7,887；
  layout CASE0000 563,652→566,367。**该负载不是 DMA outstanding 受限。**
- 短突发 L=32：1/4/7/13/16beat 读 v020 恒多 2 拍（38/41/44/50/53→40/43/46/52/55），
  写相同（14/17/20/26/29）；32/64beat 才快（read 102→71、200→103；
  write 63→55、123→93）。<32beat 读应留 v019 或 bypass。

## F3 ping-pong

- 同 RTL/同 BFM/4 页×64beat/消费者 300cyc：串行 1,651→预取 1,339 cycles，
  1.233×，overlap=303，stall=410（2 页信用真实上限）。
- `block_storage_dma_prefetch` 不是这个机制：整块 RDMA→RSCALAR（4 lane，1024 word
  =256 拍）→WSCALAR（1024×48bit 打包到 128bit=384 beat）→WREQ→WACK；A/W 与计算分离。

## F4 计划/下界（含主复核纠正）

- 68 plan / 98 matrix op / 6231 descriptor / 45055 instr；useful MAC 3,461,011,968，
  padded 3,991,404,544；unique C48 4,471,808。
- 32×32×32 block 数 **121,808**；`matrix_pe_cycles=32,157,312` / 121,808 = **264.0**
  拍/block，正好 4×66；所以 `matrix_pe_cycles` 是精确 **RUN-only**，不含 COLLECT。
- RUN-only padded 124.12 MAC/cycle；若 RUN+COLLECT 串行（4×(66+64)=520 拍/block），
  整块约 **63.0 MAC/cycle**，63,340,160 拍=0.5067s@125MHz；理想 32768/256=128 拍，
  RUN-only 2.06×、RUN+COLLECT 4.06×。这个计数器口径不能混。
- C DDR 流量按 4096-K 段计，不按每 32-K block；98 op 中 97 个 1 段、1 个 K=4608
  为 2 段，故 C write 30,769,152B + C read 1,867,776B；矩阵总 125,143,040B。
  `matrix_queue` 覆盖 DMA/wait/C 读写/flush，不能与 PE 相加。
- 总流量 933,028,896B；125MHz/16B 半双工下界 0.4665s；whole-plan 实际 74.7MB/s。
- compulsory 下界：唯一权重 81,007,616 + 边界 in 4,539,392 + out 16,508,928 =
  102,055,936B；实际 9.14×。唯一张量范围 12,592,128B；vector/layout 807,885,856B
  = 64.2×，是主要可减项。
- whole plan 12.4866s；stage 和 12.4844s；overlap 0.0022s；naive max 6.8155s
  只是独立假设，不采用。300/600MHz 是频率缩放目标，不是已实现/已签核。

## F5 整机自主

- 物理：6 PL master→smartconnect→PS S_AXI_HP0_FPD；PS CPU 不参与，但未绕过
  PS 硬 DDR 控制器。
- 仍在 host/PS：逐子图 fuse_plan 上传/START/轮询/下载、591 legacy queue、
  `0xe300` 参数拷贝、PS `vm211_run` 逐 plan 轮询、外层 ONNX 图。
- 已实现 `pl_graph_runner_v1` 4 节点控制骨架：case0 乱序依赖 pass、case1 循环依赖
  err04、case2 子算子 err05；68+591 未集成。

## F6 历史纠正

- `codex/kwt-ds-r6-mac32/64/128/256` 是同一 snapshot `8490830`，不是四套实现。
- 历史“64bit 必然不够”只在 A16W12/8×16/指定夹具成立，不能外推；300MHz 只是
  预布局方向，600MHz 无历史证据；不能把 300/600 当已实现。
- 300/600 不能与 125MHz 的 DDR 字节界直接乘频；DDR 用户域独立，当前无 CDC 桥接。

## F7 共享 BFM 外部更新与钉住修正（2026-10-30）

外部进程在 13:44 后改写 `bench/bfm/axi128_ddr_bfm.sv`（新增 `w_block`、
`bq_cnt` 信用等），但该版本在 Icarus 14 下不能展开且有真实协议缺陷：

1. 无参函数 `rnd` 在函数内被当变量引用，Icarus 报 “Unable to bind rnd”；
   改为 `rnd()`。
2. AW 接受路径只写 `aw_v/write_bursts`，未递增 `aw_cnt`，`wready` 永远等不到
   `wr_servable`，W 通道死锁；补 `aw_cnt` 增量。
3. W 数据只在 `grant_w` 时才入 FIFO，而 `grant_w` 又要求 `wf_cnt!=0`，形成
   循环依赖；改为 `wready = wf_cnt<WFIFO` 先入队，`grant_w` 再消费。
4. 每端口只有一个 `bpend/blat/berr`，v020 多 AW 在途时后续 B 覆盖前一笔，
   DUT 等不到全部 B；改为按端口 B 响应队列（`bq_*`，深度 `MAX_OUT`）。
5. 读写仲裁每拍强制换向并付 `TURNAROUND`，在双向持续可服务时把共享总线
   人为限制在 ~50%；改为保持当前方向直到该方向无可服务拍。
6. `aw_cnt/rd_cnt` 在同一拍既有接受又有完成时用两次 NBA 赋值，后写覆盖前写；
   改为 delta 计数。

修正版钉在 `bench/bfm/axi128_ddr_bfm_ds.sv`，所有 ds_ddr bench 只引用该副本；
原 shared 文件不修改、不混用。新增 `tb_strobe_account.sv` 验证
`write_bytes == sum(popcount(WSTRB))`：V019/V020 在 64beat、8 种部分 strobe
下均为 424B（旧 V020 候选按 16B/beat 计为 1024B，已修正为 popcount）。
