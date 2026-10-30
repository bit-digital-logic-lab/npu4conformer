# ds_ddr 最终报告：DDR/AXI 带宽与整机 PL 自主控制

日期：2026-10-29。范围：**只做逻辑验证**（Icarus/Verilator/Python），未做综合、Vivado、
板卡、联网远控、push。原始 `model_a_v0_22(1).zip` 与 `work/`、旧 Git 工程均只读。

## 0. 结论摘要

1. **当前 `axi_dma_v019` 的吞吐问题不是“位宽不够”，而是单在途 + 每突发暴露延迟。**
   同负载 4096 beat（64KiB）读，在 BFM 延迟 32 cycle 时：
   `12,548 → 4,135 cycles`（3.03×，有效读利用率 32.6%→99.1%）；
   写 `7,404 → 4,815`（1.54×，55.3%→85.1%）；读写混合 `13,558 → 8,779`
   （1.54×，共享通道数据利用率 60.4%→93.3%）。延迟 64 cycle 时读
   `20,740 → 4,167`（4.98×，19.8%→98.3%）。
2. **但“多在途 DMA”不是万能药。** L=8 的读写混合 `8,777→8,745`（1.004×），
   原 vector/layout 小请求负载（20 read/16 write 请求，64beat 级）只换 DMA 时也略慢
   （add_scalar `7,882→7,887`，layout CASE0000 `563,652→566,367`）。瓶颈在算子串行/
   请求粒度，不在单笔 DMA 的 outstanding 深度。
3. **真正有效的搬运候选是“页级 ping-pong + 多在途 DMA”。** 4 页×64beat、消费者每页
   300 cycle 的同 RTL 对照：串行 `1,651 cycles`，预取 `1,339 cycles`，**1.233×**，
   实测 `overlap=303 cycles`、`stall=410`。这符合“A/W 真预取”，不是文件名预取。
4. **68 个闭合计划的实际数字**：useful MAC `3,461,011,968`（padded `3,991,404,544`），
   unique C48 `4,471,808`；矩阵 RUN-only PE `32,157,312 cycles`@125MHz=`0.2573s`，
   padded 有效 `124.12 MAC/cycle`、useful `107.63 MAC/cycle`。
   计划总周期 `1,560,822,594`=`12.4866s`；其中 vector `6.8155s`、layout `3.3535s`、
   matrix queue `2.2734s`、fetch `0.0420s`。阶段和 `12.4844s` 与总时间只差 `0.0022s`，
   **当前计划基本是串行链，不能把总和取 max**。
5. **平均字节量不是 12.5s 的主因**：矩阵 `125,143,040B` + vector/layout
   `807,885,856B` = `933,028,896B`；16B/cycle 半双工、125MHz 的传输下界 `0.4665s`
   （200/250/300MHz 分别 `0.2916/0.2333/0.1944s`）。whole-plan 实际有效
   `74.7MB/s`，只有 125MHz 峰值 2.0GB/s 的 **3.7%**；差距主要来自突发间气泡、
   逐请求串行、阶段依赖和 host/legacy 往返，而不是“DDR 平均带宽已经打满”。
6. **wholecase 153.775s 不能减 12.4866s 归因 DDR**。153.775s 中闭合计划 12.4866s、
   边界上传/下载 1.951+6.732=8.683s，剩余约 132.6s 是 host/ONNX/legacy/逐矩阵 UDP/
   Python 调度等，缺逐阶段 profile；591 个 legacy queue 的 upload 7.138s、read 7.379s、
   submit 0.981s、queue 0.762s 也只能解释其中约 16.3s。报告只把它列为“host/legacy
   非 PL 路径”，不冒充 DDR 延迟。
7. **整机自主**：当前 soc_full 是 6 个 PL master → smartconnect → `S_AXI_HP0_FPD`
   → PS 硬 DDR 控制器。PS CPU 不参与，但**没有绕过 PS 硬控制器**。本次新增
   `pl_graph_runner_v1` 控制骨架（4 节点乱序依赖/循环依赖 fault/子算子 fault 三例通过），
   但 68+591 节点、host 一次上传/下载、legacy 静态化仍未集成，见 §7 与
   `docs/PL_AUTONOMY.md`。

## 1. 证据分层（先读）

| 层 | 本轮内容 | 能说明 | 不能说明 |
|---|---|---|---|
| L0 计划统计 | 从 sealed `parameters002/manifest.json`+`parameters.bin` 解析 68 plan、98 matrix op、6231 descriptor、45055 指令 | 工作量、shape、C48 数、最小字节口径 | 板级时间 |
| L1 Icarus RTL | 原 `work/rtl` + 原测试；新增 v020/pingpong/graph runner + 新 BFM | 同负载 before/after、握手、bubble、golden | PS DDR 时序、物理频率 |
| L2 历史板测 | `work/BOARD_RESULT.json` 的计数器（125MHz、真实 CASE0000） | 真实计划的周期/字节/阶段 | 不能与 L1 混算；不能把 wholecase 差当 DDR |
| L3 综合/板级 | 本轮未做 | — | 300/600MHz 物理时序、面积、功耗 |

## 2. baseline：原 RTL 测试真实复跑

`bench/run_baseline.py` 使用本机 Icarus 14，只读 `work/rtl` 与 `work/tests`，原测试语义不改。
唯一修复是 Icarus 14 的 `$readmemh` 不接受中文绝对路径：给 fixture/输出加 `/tmp/opencode`
ASCII 别名。结果：

| 测试 | 结果 | 规模 |
|---|---|---|
| csr001 | PASS | AXIL CSR 单测 |
| vector_rtl | PASS | 14 个数值/背压用例 |
| vector_axi | PASS | 14 个真实 2×AXI DMA 用例 |
| plan_rtl | PASS | 15 个计划/错误/依赖用例 |
| layout_rtl | PASS | 20 个布局用例 |
| reuse_rtl | PASS | 6 个周期复用用例 |
| alignment | PASS | 8 个非对齐用例 |

`bench/baseline/result.json`：`passed=true`，本次 host 约 55s（随主机负载变化；功能 PASS 与耗时无关）。跳过项仍诚实列出：
`matrix_epoch` 依赖 `model_a_v0_21_1/tests/tb_queue.sv` 与 W7/A16/C48 逐场景 vectors，
本目录缺依赖，未编造；`layout_cluster`、`protocol_native` 同理。

## 3. 当前 RTL 的真实阻塞点

### 3.1 `axi_dma_v019`：单在途、16beat、AR/R 与 AW/W/B 串行

源码 `work/rtl/axi_dma_v019.sv`：

- `page_beats`/`chosen` 把请求切成 ≤16 beat、不跨 4KiB；
- 读：`AR → RDATA`，必须等到 `RLAST` 才回 `AR` 发下一笔；
- 写：`AW → WDATA → BRESP`，必须等到 `BRESP` 才回 `AW` 发下一笔；
- 一个模块只有一个 `request_valid/ready`，同一时刻只有一笔在途。

因此每 16beat 突发暴露一次存储器延迟。BFM 的解析模型与实测一致：

```text
单在途读：T ≈ Nburst × (L + 16)   （L=32: 256×48=12,288，实测 12,548）
单在途写：T ≈ Nburst × (BLAT + 16)（BLAT=4..12，实测约 7,400，对 L 不敏感）
```

### 3.2 `block_storage_dma_prefetch`：整块串行，不是 A/W 双页预取

`work/rtl/block_storage_dma_prefetch.sv` 的 `bank_even/bank_odd` 只是 128bit beat
的奇偶 bank，不是 A/W 双页；状态 `RREQ→RDMA→RCHECK→HEADER→RPRE→RSCALAR` 与
`WSCALAR→WREQ→WDMA→WACK` 是**整块**串行：

- `RDMA` 必须把整个 1024 word 块收完才进 `RSCALAR`；
- `RSCALAR` 每拍 4 lane，1024 word → **256 拍**，A/W 供数与 DDR 阶段完全分离；
- `WSCALAR` 要收齐 1024 个 48bit C，按 6B/个拼成 128bit（1024×6=6144B → 384 beat），
  才开始 `WREQ`；`WACK` 还要等 BRESP。
- 所以文件名有 “prefetch”，但**没有计算-DMA 重叠**；A/W 读、C 读、C 写、计算是分离阶段。

`block_engine_l1bank_v020` 的时间口径必须分清：

- `matrix_pe_cycles` 只在 `state==RUN` 累加；`RUN` 是 `run_cycle 0..65`，每 quadrant
  **66 拍**，4 个 quadrant 顺序 → **264 拍/32×32×32 block**；另有 `COLLECT`
  `collect 0..252 step4` = **64 拍/quadrant**，以及 `C_READ`/`CLEAR`。
- board `matrix_pe_cycles=32,157,312` 对 **121,808** 个 32×32×32 block =
  **264.0 拍/block**，正好等于 `4×66`；说明该计数器是精确 **RUN-only**，
  不含 COLLECT/CLEAR/队列开销，所以 **124.12 MAC/cycle 只是 RUN-only**，
  不是整块服务率。
- 若 `RUN+COLLECT` 都串行，`4×(66+64)=520` 拍/block → padded 32768/520=**63.0
  MAC/cycle**，121,808×520=63,340,160 拍=`0.5067s@125MHz`（RTL 常数推导，板测计数器
  未单独给出 COLLECT 拍数）。
- 理想 32×32×32=32768 MAC / 256 = **128 拍**；RUN-only 264 拍 = 2.06× 理想，
  RUN+COLLECT 520 拍 = 4.06× 理想。这个差距的一部分可由 `matrix_queue=2.273s`
  包含的 DMA/等待/C 读写解释，但不能把 `matrix_pe` 的 124 MAC/cycle 当整块算力。

### 3.3 `ddr_vector_engine` / `ddr_layout_engine`：小请求 + 单请求

`ddr_vector_engine` 的 `CHUNK=256`，一次 `LIDLE→LREQ→LRX→LPRE→LUNPACK` 只发一笔
DMA，然后 `CIDLE→CREAD→CSEND→CWAIT` 逐元素算，最后 `WIDLE→WREQ→WPRE→WDATA` 逐拍写。
两个 bank 能 ping-pong，但每个 bank 的请求粒度很小（FP32 256 元素=64beat；
I16 256 元素=32beat），且算子内部 load/unpack/compute/write 的相位固定。
这解释了 §4.2 的“只换多在途 DMA 几乎不变”。

### 3.4 计划/整机

`pl_execution_plan_v022` 一次只执行一条 64B 指令（kind1 matrix / kind2 vector /
kind3 layout），`DISPATCH→WAIT_OP` 等子算子 done 后才下一条。`plan_count` 68 个
plan 由 PS/host 逐个启动；`whole_plan = matrix_queue + vector + layout + fetch`
几乎精确相加（§5），说明阶段之间没有真正重叠。

## 4. 参数化 AXI128 共享 DDR BFM 与 before/after

### 4.1 BFM

本报告钉住 `bench/bfm/axi128_ddr_bfm_ds.sv`（共享 BFM 的修正副本）：

- PORTS 个 AXI4 从端口共享一份 3×256KiB 逻辑地址窗口；每端口独立 AR/AW 队列
  （`MAX_OUT`）、W FIFO（`WFIFO`）与按序 B 响应队列；
- 可配 `LAT_MIN/LAT_MAX`（读首拍延迟）、`BLAT_MIN/BLAT_MAX`（B 响应延迟）、
  `READY_STALL_PCT`（AR/AW 随机反压）、`W_STALL_PCT`、`TURNAROUND`、`SEED`；
- 严格检查 16B 对齐、INCR、≤256beat、不跨 4KiB、地址窗口、WLAST/RLAST；
- 单条 128bit 半双工数据通道，每 cycle 最多一个 16B beat；换向前有可配空拍；
- 计数器区分 `bus_read/write_beats`、`bus_busy/idle/turnaround_cycles`、
  `read/write_bursts`、`ar/aw/r/w_stall_cycles`、`max_rd/wr_out`。
- 错误只注入 RRESP/BRESP；已接受事务必须排空，BFM 不取消。

**为什么有 `_ds` 副本**：2026-10-30 外部同时改写了
`bench/bfm/axi128_ddr_bfm.sv`。该版本在 Icarus 下不能展开（无参函数调用写法），
且存在三个真实协议缺陷：W FIFO 只收已 grant 的拍导致死锁、AW 接受未递增 `aw_cnt`、
每端口只有一个 `bpend` 无法支持 v020 的多 AW 在途 B；另外每拍强制换向会把共享
总线人为限成 50%。本任务在 `_ds` 副本中修正并实跑，原 shared 文件保持不动；
两者不能混用。修正点见 `FINDINGS.md` F7。

**这不是板级 DDR 模型**：没有 PS DDR 控制器、刷新、bank/row、PHY、时钟桥。

### 4.2 同负载 DMA 微基准（4096 beat = 64KiB，256 个 16beat 突发）

`bench/run_dma_compare.py`：同一 TB、同一 seed、同一 BFM 参数，只换
`axi_dma_v019` / `axi_dma_v020_multi`。v020 读路径最多 8 个 AR 在途 + 128beat
数据 FIFO，写路径在 B 信用允许时提前发下一笔 AW、B 最多 8 笔在途。

| 场景 | 方向 | v019 cycles | v020 cycles | 加速 | v019 util | v020 util |
|---|---|---:|---:|---:|---:|---:|
| L=8, BP=0 | read | 6,404 | 4,111 | 1.56× | 0.640 | 0.996 |
| L=8, BP=0 | write | 7,347 | 4,816 | 1.53× | 0.557 | 0.851 |
| L=8, BP=0 | mix | 8,777 | 8,745 | 1.004× | 0.933 | 0.937 |
| L=32, BP=0 | read | 12,548 | 4,135 | 3.03× | 0.326 | 0.991 |
| L=32, BP=0 | write | 7,404 | 4,815 | 1.54× | 0.553 | 0.851 |
| L=32, BP=0 | mix | 13,558 | 8,779 | 1.54× | 0.604 | 0.933 |
| L=64, BP=0 | read | 20,740 | 4,167 | 4.98× | 0.198 | 0.983 |
| L=64, BP=0 | write | 7,376 | 4,800 | 1.54× | 0.555 | 0.853 |
| L=64, BP=0 | mix | 21,183 | 8,760 | 2.42× | 0.387 | 0.935 |
| L=32, BP=25% | read | 12,638 | 4,135 | 3.06× | 0.324 | 0.991 |
| L=32, BP=25% | write | 7,588 | 4,874 | 1.56× | 0.540 | 0.840 |
| L=32, BP=25% | mix | 13,501 | 8,907 | 1.52× | 0.607 | 0.920 |

写方向 v019 对 `LAT` 不敏感，是因为本 BFM 的写响应延迟由独立的
`BLAT_MIN/BLAT_MAX=4/12` 决定；旧版 BFM 把写响应也挂在 `LAT` 上，给出过
`13,101` 这类数字。当前表以修正后的 `_ds` BFM 为准，旧数字不再引用。

要点：

- **延迟隐藏阈值**：N 个在途 × 16beat ≥ L 才能填满。L=64 时：
  read N=2 `10,390`（util 0.394）、N=4 `5,238`（0.782）、N=8 `4,167`（0.983）；
  N=4 的 64beat 缓冲与 64cycle 延迟持平，仍有 `20.5%` 气泡；N=8 把气泡压到 `1.4%`。
- 读的稳态下界是 4096 beat + 初始 L；v020 在 L=32 的 `4,135` 相对
  `4096+32=4,128` 只有 7 cycles 握手开销，`bus_read_beats=4096`。
- mix 的理论下界是 `4096 read + 4096 write = 8,192 cycles`（半双工每拍一个 beat）；
  v020 L=32 `8,779` = 下界的 **93.3%**；v019 `13,558` = 60.4%。差出的 587 cycles
  是 256 个 16beat 突发之间的读/写换向与仲裁空拍，不是数据 beat。
- **busy 不是假满**：BFM 的 `bus_busy` 只统计数据 beat grant，不把命令等待算成忙。
  v020 mix `busy=8192/cycles=8779` 是真实数据占用；v019 read L=64
  `busy=4096/20740=19.8%` 才是“总线空闲但事务未完成”。
- L=8 时 v019 已有 8 个 16beat 突发可重叠，mix util 0.933；v020 只到 0.937，
  说明**低延迟、读写混合场景不应盲目换多在途**。

### 4.2.1 长短突发（L=32，同一 BFM）

| 请求 beat | v019 read | v020 read | v019 write | v020 write | 结论 |
|---:|---:|---:|---:|---:|---|
| 1 | 38 | 40 | 14 | 14 | 单 beat：v020 读多 2 拍，写相同 |
| 4 | 41 | 43 | 17 | 17 | 短读突发：v020 多 2 拍；写相同 |
| 7 | 44 | 46 | 20 | 20 | 同上 |
| 13 | 50 | 52 | 26 | 26 | 同上 |
| 16 | 53 | 55 | 29 | 29 | 16beat 单突发：v020 读仍有 2 拍开销 |
| 32 | 102 | 71 | 63 | 55 | 2 个突发：v020 1.44×/1.15× |
| 64 | 200 | 103 | 123 | 93 | 4 个突发：v020 1.94×/1.32× |

结论：v020 不是所有请求都更快。**<32beat 用 v019 或加 bypass；≥32beat 才启用
多 outstanding**。这与 vector/layout 小请求负载的负结果一致，也是“按源码选择”
而不是全局替换的依据。

### 4.3 原 vector/layout 夹具：小请求负结果

`bench/run_vector_compare.py` 用原 `tb_vector_axi`/`tb_layout_axi` 和独立 golden，
只替换 `ddr_vector_axi`/`ddr_layout_axi` 里的 DMA。代表值：

| 负载 | v019 cycles | v020 cycles | 变化 |
|---|---:|---:|---:|
| vector add_scalar | 7,882 | 7,887 | +0.06% |
| vector mul_vector | 8,528 | 8,532 | +0.05% |
| vector i16_to_float | 4,805 | 4,807 | +0.04% |
| layout copy_i16 | 10,152 | 10,517 | +3.60% |
| layout CASE0000 embed conv0 | 563,652 | 566,367 | +0.48% |

结论：**当前 vector/layout 是“请求粒度 + 逐元素相位 + 输出写回”受限**，
不是单笔 DMA outstanding 受限；v020 的 FIFO/握手还带来 1~3% 固定开销。
所以候选不能只做一个“更大 outstanding 的 v019”，必须同时做页级预取/请求批处理。
这也回应“别从名称猜真 prefetch”。

### 4.4 真实 A/W ping-pong 候选

`candidate/ab_pingpong_prefetch.sv`：

- 描述符队列 → 一个 `axi_dma_v020_multi` 读引擎 → 两个页缓冲（`PAGE_BEATS=64`）；
- 当前页被消费者占用时，后台把下一页写入空闲页；
- 无空闲页时停止发新描述符（信用），不覆盖正在消费的页；
- 页数据按 `read_index` 顺序写入，保持每个 C 的 K 顺序。

同 RTL、同 BFM、同 4 页数据，只改“串行送描述符 / 全预取”：

| 策略 | cycles | fill_cycles | overlap | stall | 结果 |
|---|---:|---:|---:|---:|---|
| 串行 | 1,651 | 404 | 0 | 0 | pass |
| 预取 | 1,339 | 404 | 303 | 410 | pass |
| 加速 | **1.233×** | — | — | — | 独立 golden |

`stall=410` 是 2 页缓冲的真实信用：消费者 300cycle/页，第二页已就绪时第三页
必须等；这不是错误，而是“容量不够时预取会停”。如果实际 A/W 页更大或计算更短，
应加页数/深度，而不是假装无限预取。

### 4.5 边界与错误排空

`bench/tb_dma_compare.sv` 还覆盖：

- **4KiB 边界**：读/写都从 `BASE+4080` 开始、300 beat（跨越 4KiB），v019/v020 均 PASS，
  各 20 个突发；BFM 对任何跨 4KiB/超过 16beat/非对齐事务直接 `$fatal`。
- **读错误**：注入 `RRESP=SLVERR`；v019 完成 1 个已接受突发（16beat）后报错；
  v020 完成已接受的 8 个 AR（128beat）后报错，未发新 AR，`done/error` 均正常。
- **写错误**：注入 `BRESP=SLVERR`；v019 完成 1 个已接受突发（16beat）；
  v020 完成已接受的 3 个 AW/B（48beat）后报错。两者都没有取消已接受事务，
  也没有在错误后继续发新请求；这是“错误后已接受事务排空”的真实 RTL 证据。

## 5. 从实际计划/shape 算工作量与理论下界

`bench/analyze_plan_workload.py` 解析 sealed 镜像，统计与板测计数器逐项对齐：

| 量 | 值 | 与板测 |
|---|---:|---|
| 68 plan / 98 matrix op / 6231 descriptor / 45055 instr | 对齐 | exact |
| useful MAC | 3,461,011,968 | — |
| padded MAC | 3,991,404,544 | — |
| unique C48 | 4,471,808 | — |
| vector elements | 82,953,300 | exact |
| layout elements | 16,784,752 | exact |
| matrix A/W/C bytes | 11,487,232 + 81,018,880 + 30,769,152 + 1,867,776 = 125,143,040 | 计算值 |
| vector/layout read | 452,330,768 | exact |
| vector/layout write | 355,555,088 | exact |

**流量口径说明（回应“别把 C 写每 K 段都计/忽略 C 读”）**：

- 98 个 matrix op 中 97 个 `ceil(K/4096)=1`，1 个 K=4608 为 2 段；C DDR 读写按
  4096-K 段计，不按每 32-K block 计。该 op 多 1 次 C 读 + 1 次 C 写：
  `C write=30,769,152B`、`C read=1,867,776B`，已计入矩阵 125,143,040B。
- 32-K 中间 `bk` 的 C 走 `c_cache_banked4`，`matrix_pe_cycles` 只覆盖 RUN；
  `matrix_queue=2.2734s` 覆盖 DMA/等待/C 读写/最后 flush，二者不能相加。
- layout cache：命中 11,358,772 / 未命中 3,100,573（命中率 78.6%）；实际
  read 452,330,768B 已含未命中流量，命中流量未重复计。最后 flush/evict 只在
  matrix queue 总时间里，未单列。

### 5.1 计算下界

| 计算域 | 矩阵 RUN-only 调度 | 矩阵 256MAC/cycle 理想 | vector 调度 | layout 调度 | whole plan 调度 |
|---:|---:|---:|---:|---:|---:|
| 125MHz | 0.2573s | 0.1247s | 6.8155s | 3.3535s | 12.4866s |
| 300MHz | 0.1072s | 0.0520s | 2.8398s | 1.3973s | 5.2027s |
| 600MHz | 0.0536s | 0.0260s | 1.4199s | 0.6986s | 2.6014s |

- 若把 `COLLECT` 也串行计入（§3.2 的 520 拍/block），矩阵整块服务约 `0.5067s@125MHz`
  / `0.2111s@300MHz` / `0.1056s@600MHz`；这是 RTL 常数推导，不是板测计数器。
- 矩阵 **RUN-only** `124.12 MAC/cycle`（padded）/`107.63`（useful），只有 16×16
  物理 256 MAC/cycle 的约 48.5%；原因是 `run_cycle=0..65` 的 4 quadrant 顺序、
  32 K 的波前填充/排空，不是乘法器数量。若把每 quadrant 的 `COLLECT` 64 拍也串行
  计入，整块服务率约 **63.0 MAC/cycle**（§3.2 的 520 拍/block 推导）；板测
  `matrix_pe_cycles` 只覆盖 RUN，不能把 124 当整块算力。
- `300/600MHz` 只是**同一 RTL 调度**按频率缩放；没有流水重排、没有 STA。
  若把 66cycle/quadrant 的 skew 改成真正 32cycle/quadrant，矩阵理想可再减半
  （256MAC/cycle 列已给）。
- vector 的元素级下界不是 1 element/cycle：`CIDLE→CREAD→CSEND→CWAIT` 约 3 cycle/元素，
  再加 load/unpack/write；83M 元素在 125MHz 的 6.8s 主要是这个相位和 DMA，而不是 FP32
  乘法器数量。该部分由计算 worker 负责，本报告只给 DDR/控制边界。

### 5.2 传输下界（16B/beat，半双工共享通道）

| DDR 用户域 | 峰值 | 总字节下界 | vector/layout 下界 | matrix 下界 | whole-plan 实际有效 |
|---:|---:|---:|---:|---:|---:|
| 125MHz | 2.00GB/s | 0.4665s | 0.4039s | 0.0626s | 74.7MB/s（3.7%） |
| 200MHz | 3.20GB/s | 0.2916s | 0.2525s | 0.0391s | — |
| 250MHz | 4.00GB/s | 0.2333s | 0.2020s | 0.0313s | — |
| 300MHz | 4.80GB/s | 0.1944s | 0.1683s | 0.0261s | — |

**DDR 用户域频率独立，不能跟着 300/600MHz 计算域乘频**；上表分开列。
当前 RTL 的 `aclk` 同时给 PL 和 AXI（125MHz），**没有 CDC/异步 FIFO**；若要把
300/600MHz 计算域接到 125/200/250/300MHz DDR 用户域，必须增加 async FIFO/信用
桥接，桥接的吞吐不能超过 DDR 侧 16B/cycle 的可达界。本次没有实现该桥接，
所以不给“300/600MHz 下 DDR 带宽翻倍”的数字。
总字节下界只计 payload，不含 QDQ 重新读写、layout 中间量、参数重用和命令；
实际 vector/layout 的 452+356MB 已经包含这些真实流量，所以 0.40s 是“按实际字节”
的下界，不是更乐观的理论最小值。

**最小 DDR 字节（compulsory）**：从 shape 去重后，唯一权重块 1KiB×79,109 =
`81,007,616B`；边界输入 `4,539,392B`；最终输出 `16,508,928B`。若中间量全部留在
片上，绝对下界是 `102,055,936B`；实际 `933,028,896B` 是它的 **9.14×**。
若所有唯一张量范围（`12,592,128B`）都必须各写/读一次，粗下界 `127,240,192B`，
实际仍是 **7.33×**。这给出两个明确结论：

- 参数重用已经接近 1.0×：唯一权重 81.008MB vs 计划 W 读 81.019MB，闭合计划
  没有重复读同一权重；要靠“权重驻留”再省外部字节的空间很小。
- QDQ/layout/intermediate 是主要可减项：唯一张量范围只有 12.59MB，但 vector/layout
  实际读写 807.89MB = **64.2×**。这部分不是“DDR 峰值不够”，而是 QDQ 边界、
  layout scratch、ping-pong 重读和逐请求小搬运叠加出来的真实流量。

### 5.3 每 C48 退休 / 片上端口

- unique C48 `4,471,808` / matrix **RUN-only** `32,157,312 cycles` = **0.139 C48/cycle**
  = **6.7 bit/cycle**（按 unique 输出；C 在 K 上累加，不是每 cycle 退休）。
- 若按 RUN+COLLECT 的 63,340,160 拍/全块服务估算，C48 退休约 **0.0706/cycle**
  = **3.39 bit/cycle**；这就是“C 回写 48bit/拍再打包到 128bit”不能持续满 128bit
  的直接原因。
- 块级 C 读写是 4 个 C48/collect cycle = 192bit/cycle；`c_cache_banked4` 的
  Port A 每拍 4 个相邻 C，Port B 每拍 1 个 C 写回，冲突时 B 等待。
- 阵列 A/W 供数是 `a_left[255:0]` + `w_top[111:0]` = **368 bit/cycle = 46B/cycle**
  （16 个 A16 + 16 个 W7，每拍广播）；C 收集另需 192bit/cycle。
  300/600MHz 目标下片上端口需求为 46B×300M=13.8GB/s、×600M=27.6GB/s（仅 A/W），
  C 收集另为 192bit×300M=7.2GB/s、×600M=14.4GB/s；这还没有算 bank 冲突和布线。
  所以“片上端口”本身在 600MHz 是硬约束，不能只拿 DDR 峰值比较。
  **368bit/cycle 是阵列供数，不是 DDR 需求**；矩阵 DDR 平均只有 3.89B/PE-cycle，
  不能把内部端口宽度直接外推成外部带宽下界（反馈明确要求避免这一点）。
- C48 退休率按实际矩阵调度：125MHz 为 0.139 C48/cycle；若同一调度到 300/600MHz，
  等效约 41.7/83.4 M C48/s（4.471M unique C48 / 0.1072/0.0536s），但这是
  “频率缩放”不是“流水重排”后的结果。
- 矩阵 DDR 平均 `125,143,040B / 32,157,312 = 3.89B/PE-cycle`，只有 16B/cycle 的
  **24.3%**；矩阵不是平均带宽打满，而是**块级 C 读写 + 单在途 + 队列**造成等待。

### 5.4 依赖图 critical path 与重叠边界

| 项 | cycles | 时间@125MHz |
|---|---:|---:|
| matrix queue（含 PE/DMA/等待） | 284,175,569 | 2.2734s |
| vector | 851,939,384 | 6.8155s |
| layout | 419,186,668 | 3.3535s |
| plan fetch | 5,250,673 | 0.0420s |
| 阶段和 | 1,560,552,294 | 12.4844s |
| whole plan | 1,560,822,594 | 12.4866s |
| 表观重叠 | 270,300 | 0.0022s |
| naive max（仅独立假设） | 851,939,384 | 6.8155s |

- 68 个计划按 host 依赖串行启动；matrix/vector/layout 是**有依赖的阶段**，
  不能把总和取 max。实际 whole plan 几乎等于阶段和（重叠 0.0022s），
  说明当前 runner 没有跨阶段/跨计划重叠。
- 若未来把独立子图并行化，理论上界是 `max(阶段)` 而不是 `sum`；但只有在
  依赖图允许、且 DDR/端口能同时供数时才成立。当前没有证据支持 6.8155s 的
  整机可实现值。
- 每个计划内部：vector 的读/计算/写有 ping-pong 重叠（原 TB 要求
  `read_compute_overlap>0 && write_compute_overlap>0`），但**计划之间**没有。

**条件式可实现调度估计**（不是硬编单值）：

| 假设 | 125MHz | 300MHz | 600MHz | 说明 |
|---|---:|---:|---:|---|
| 当前串行、不隐藏内存 | 12.4866s | 5.2027s | 2.6014s | 同 RTL 频率缩放，DDR 用户域不随频 |
| 每阶段内存完全隐藏，阶段仍串行 | 10.4263s | 4.3443s | 2.1721s | matrix max(.2573,.0607)+vector 6.8155+layout 3.3535 |
| 矩阵 256MAC/cycle 且内存隐藏 | 10.2937s | 4.2892s | 2.1446s | 只把矩阵从 .2573 降到 .1247 |
| 依赖图允许阶段全并行（未证） | 6.8155s | 2.8398s | 1.4199s | 仅对照，当前 DAG 不支持 |

读法：把每个阶段的内存下界 0.4039s（vector/layout 合计）完全隐藏，125MHz 也只能从
12.49s 降到约 10.43s；**瓶颈是 vector/layout 的逐元素相位和计划串行**，不是
平均 DDR 字节。要到 6.82s 以下必须同时做阶段并行和算子重构，不能只换 DMA。

## 6. 为什么实测未满（归因表）

| 现象 | 证据 | 归因 | 可行动作 |
|---|---|---|---|
| v019 读 L=64 只有 19.8% 利用率，每 16beat 后空 | §4.2；`T≈N(L+16)` | 单在途，AR 等 RLAST；每突发暴露 L | v020 多 AR + 读 FIFO；N×16≥L |
| v019 写约 55% 且对 L 不敏感 | §4.2 | AW 等 BRESP，W/B 串行；`BLAT=4..12` | v020 posted write/B 信用 |
| v020 L=32 mix 93.3% 但仍非 100% | §4.2 | 256 个突发换向/仲裁空拍；4096+4096 下界 8192 | 已是共享通道可达界附近；再快需全双工/更宽/多通道/更长突发 |
| vector 小请求只换 DMA 不变 | §4.3 | 请求粒度 64beat、load/unpack/compute/write 相位；引擎一次一请求 | 请求批处理/页级 ping-pong/多 bank 同时发 |
| 矩阵平均只有 3.89B/PE-cycle | §5.3 | 每块 C 6KB 读写、A/W 重装、单在途；不是平均带宽 | A 驻留/W 双页/C 3 页 + 多在途 + 大突发 |
| whole plan 12.5s 几乎等于阶段和 | §5.4 | 计划串行、子算子 wait；没有跨阶段 overlap | graph runner/依赖调度；但需保持 K 顺序 |
| wholecase 153.8s | 历史板测 | host/ONNX/legacy/逐矩阵 UDP/Python；不是纯 DDR | 预提交整图、591 静态化、host 一次上传/下载 |
| 300/600MHz 不能直接套 | 无 STA | 频率只是目标；DDR 用户域独立 | 先做 CDC/流水/端口预算，再谈物理频率 |

## 7. 整机 PL 自主控制

详见 `docs/PL_AUTONOMY.md`，这里只列结论：

- 物理拓扑：6 个 PL master → smartconnect → `S_AXI_HP0_FPD` → PS 硬 DDR 控制器；
  **PS CPU 不参与 ≠ 绕过 PS 硬控制器**。当前没有 PL MIG/独立 DDR，不能许诺绕过。
- 仍在 host/PS 的依赖：逐子图 `fuse_plan` 上传/START/轮询/下载；591 legacy queue 的
  host 布局/描述符/MMIO/读 C；`write_words` 的 `0xe300` 参数拷贝；PS `vm211_run`
  逐 plan 启动/轮询；外层 ONNX 图遍历。逐项迁移表见 `docs/PL_AUTONOMY.md` §2。
- 已实现：`candidate/pl_graph_runner_v1.sv` 的 4 节点控制骨架：
  - case0 表顺序 0,3,1,2，依赖 1←0、2←0、3←1|2，实测启动 0,2,1,3，completed=4；
  - case1 循环依赖 fault=1/err=0x04；
  - case2 子算子 fault=1/err=0x05。
- 未实现：68+591 节点接入、真实子算子、节点表 AXI 抓取、host 一次上传/下载端到端、
  legacy 静态化、全图 liveness/arena 证明。**不能把骨架当 CASE 自主执行。**

## 8. 候选源码与复跑

候选（全部在 `tasks/ds_ddr/candidate/`）：

| 文件 | 作用 |
|---|---|
| `axi_dma_v020_multi.sv` | 多 AR/读 FIFO、posted write/B 信用、16beat/4KiB、错误排空 |
| `ab_pingpong_prefetch.sv` | 2 页 A/W 预取 + 描述符队列 + 页信用 |
| `ddr_vector_axi_v020.sv` | 原 vector wrapper 换 v020，用于同负载 before/after |
| `ddr_layout_axi_v020.sv` | 原 layout wrapper 换 v020 |
| `pl_graph_runner_v1.sv` | 单 start、依赖位图、单 done/fault 控制骨架 |
| `bench/bfm/axi128_ddr_bfm_ds.sv` | 钉住的共享 AXI128 BFM 修正副本（见 §4.1） |
| `bench/tb_strobe_account.sv` | 部分 WSTRB 的 `write_bytes` popcount 回归 |
| `INTERFACE.md` | 给主 agent / 其他 worker 的端口与集成契约 |

复跑：

```bash
cd /home/yang/Desktop/项目/tasks/ds_ddr
python3 bench/run_baseline.py
python3 bench/analyze_plan_workload.py
python3 bench/run_dma_compare.py
python3 bench/run_vector_compare.py
python3 bench/run_short_bursts.py
python3 bench/run_strobe_account.py
python3 bench/run_pingpong.py
python3 bench/run_graph.py
python3 bench/analyze_bounds.py
python3 bench/make_result.py
```

产物：`result.json`、`bench/reports/{dma_compare,vector_dma_compare,short_burst,strobe_account,pingpong,graph_runner,plan_workload,bounds}.json`、
`bench/reports/BOUNDS.md`、`HISTORICAL_OPTIONS.md`、`docs/PL_AUTONOMY.md`、`bench/logs/`。

## 9. 诚实边界

1. 未做综合/Vivado/STA/板卡/联网；300/600MHz 只是流水目标，不是物理时序结论。
2. BFM 是逻辑 AXI 模型，不是 PS DDR 控制器/PHY/刷新/bank/row 时序；不能把 BFM 的
   93~99% 直接当板级 DDR 效率。外部共享 BFM 与 `_ds` 修正副本已分开，见 §4.1/F7。
3. 历史板测 125MHz、wholecase 153.775s 与本次 Icarus 完全分开；没有用
   `153.775−12.487` 声称 DDR 延迟。
4. 原 vector/layout 小请求负载下 v020 略慢，已如实报告；没有为了“加速”改小
   golden、改精度或用整数乘替代特殊 W7。
5. `pl_graph_runner_v1` 是控制骨架，不是完整图执行；68+591 节点、host 一次装载、
   legacy 静态化均未完成。
6. 完整模型依赖 `model_a_v0_21_1` / `model_a_lowbit_v13` 的部分测试未在本目录，
   `matrix_epoch` 等跳过项已在 baseline JSON 说明，未编造 CASE 精度。
7. `matrix_pe_cycles` 是 **RUN-only**；`COLLECT/C_READ/最后 flush` 未含在 124
   MAC/cycle 内，整块 520 拍/block=63.0 MAC/cycle 是 RTL 常数推导，不是板测计数器。
8. 历史“64bit 必然不够”只对 A16W12/8×16/指定夹具成立；300MHz 是预布局方向，
   600MHz 无历史证据；本轮没有把 300/600 当已实现频率。
