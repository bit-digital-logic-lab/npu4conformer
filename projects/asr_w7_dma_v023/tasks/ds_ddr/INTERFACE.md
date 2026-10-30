# INTERFACE — ds_ddr DMA / ping-pong / BFM 集成契约

本文件只描述 `tasks/ds_ddr/candidate/` 与 `bench/` 中新增模块的接口和已验证边界。
`work/`、ZIP、旧 Git 工程均只读；未做综合/STA/板级，任何频率都不是签核结论。

## 1. 文件与角色

| 文件 | 角色 |
|---|---|
| `candidate/axi_dma_v020_multi.sv` | 多 AR/读 FIFO、posted AW/B 信用、16beat/4KiB、错误后排空的 AXI128 DMA |
| `candidate/ab_pingpong_prefetch.sv` | 2 页 A/W 预取 + 描述符队列 + 页信用；本身不含 AXI，需配 DMA |
| `candidate/ddr_vector_axi_v020.sv` | 原 `ddr_vector_axi` 仅替换 DMA 的同负载 wrapper |
| `candidate/ddr_layout_axi_v020.sv` | 原 `ddr_layout_axi` 仅替换 DMA 的同负载 wrapper |
| `candidate/pl_graph_runner_v1.sv` | 4/32 节点依赖位图控制骨架，不是完整 CASE 执行器 |
| `bench/bfm/axi128_ddr_bfm_ds.sv` | 本任务钉住的共享 AXI128 BFM 修正副本 |
| `bench/tb_dma_compare.sv` | V019/V020 同负载 before/after + 错误/4KiB |
| `bench/tb_ab_pingpong.sv` | 串行 vs 预取，同 RTL/BFM/页数据 |
| `bench/tb_strobe_account.sv` | 部分 WSTRB 的 `write_bytes` popcount 回归 |
| `bench/tb_graph_runner.sv` | 乱序依赖/循环依赖/子算子 fault |

## 2. `axi_dma_v020_multi`

### 2.1 参数

| 参数 | 默认 | 约束/含义 |
|---|---:|---|
| `MAX_OUT` | 8 | 2 的幂；读 AR 与写 B 的最大在途数 |
| `FIFO_BEATS` | 128 | 读数据 FIFO 深度；`>= MAX_OUT*MAX_BURST` 时才能吃满在途 |
| `MAX_BURST` | 16 | 单 AXI 突发最大 beat；不得大于 16，仍按 4KiB 自动切分 |

elaboration 未加断言；集成时请自行检查 `MAX_OUT` 为 2 的幂、`FIFO_BEATS` 足够。
`MAX_OUT=2/4/8` 均已实跑；L=64 时 N=4 仍有约 20% 气泡，N=8 才接近满。

### 2.2 端口

与 `work/rtl/axi_dma_v019.sv` 的请求/数据/`done/error` 端口同名同义，额外增加：

```systemverilog
output reg [31:0] ar_outstanding_max, b_outstanding_max;
output reg [63:0] read_bubble_cycles, write_bubble_cycles, read_fifo_high;
```

- `request_valid/ready`：`request_ready = state==IDLE && rst_n`。**一次只能接一个
  request**；一个 request 内部分成多个 ≤16beat、不跨 4KiB 的突发。
- `read_valid/ready, read_data, read_index`：按序返回；`read_index` 在消费者
  `read_ready` 时递增，从 0 连续到 `request_beats-1`。上游按 index 消费即保持
  每 C 的 K 顺序。
- `write_valid/ready, write_data, write_strobe, write_index`：W 严格按序；
  `write_ready` 受 AXI `WREADY` 反压。`write_bytes` 按 **`popcount(WSTRB)`**
  累计（已修，见 §2.4）。
- `done`：单拍；读在最后一个已接受 R beat 且 FIFO 排空后，写在所有已发 AW 的
  B 返回后。`error` 与 `done` 同时有效，粘滞到下一 request 被接受。
- `read_bytes`：每个 R beat +16；`write_bytes`：每个 W beat +popcount。
- `m_axi_*`：AXI4，128bit，40bit 地址（内部零扩展），`ARSIZE/AWSIZE=4`，
  `ARBURST/AWBURST=INCR`，`ARCACHE/AWCACHE=0`。

### 2.3 顺序/错误/边界

- 地址必须 16B 对齐；`request_beats==0` 或非对齐 → `error=1,done=1`，不发 AXI。
- 每笔突发 `chosen = min(remaining, 16, (4096-addr[11:0])>>4)`，因此不跨 4KiB。
- 读错误：置 `err_sticky/error`，停止发新 AR；已接受 AR 的 R 继续排空，FIFO 排空后
  `done`。不取消已接受事务。
- 写错误：置 `err_sticky/error`，停止发新 AW；当前 W 继续按序发完，等待所有
  已接受 B 返回后 `done`。
- `m_axi_bready=1`；B 可多笔在途（受 `b_out<MAX_OUT`）。
- 不改变 W7/A16/C48、K 顺序、FP32/QDQ；DMA 只搬字节。

### 2.4 本次修正

`write_bytes` 旧实现为每 W beat +16，尾拍部分 strobe 会高估；已改为
`+popcount(write_strobe)`。`tb_strobe_account.sv` 用 64beat、8 种部分 strobe
同时跑 V019/V020，两者均得到 424B（`sum(popcount)=424`）。

## 3. `ab_pingpong_prefetch`

### 3.1 参数

`PAGE_BEATS=64`、`PAGE_AW=6`（页内 64 个 128bit word）、`DESC_DEPTH=8`。

### 3.2 端口

```systemverilog
input  start;
input  desc_valid/desc_ready;       // 描述符 = {addr,beats,tag,last}
output dma_req_valid/ready;         // 接 v020 的 request_*
output [31:0] dma_req_addr; output [15:0] dma_req_beats;
input  dma_read_valid/ready; ...    // 接 v020 的 read_*
input  dma_done/dma_error;
input  [1:0] consume_bank; input consume_done; input [PAGE_AW-1:0] consume_addr;
output [127:0] consume_data;
output [1:0] page_valid,page_busy;
output done,error;
output [31:0] prefetch_count,consume_count,overlap_cycles,stall_cycles,fill_cycles;
```

### 3.3 信用/顺序规则

- 只有 `page_valid & ~page_busy` 的页可被消费者占用；消费者在 `consume_done`
  同拍给出 `consume_bank`，页才释放。
- 无空页时停止从描述符队列发新请求，`stall_cycles` 递增；**不会覆盖正在消费的页**。
- 页数据按 `dma_read_index` 0..PAGE_BEATS-1 写入；消费者按 `consume_addr`
  递增读，保持 K 顺序。
- `PAGE_BEATS` 必须等于描述符 `desc_beats`；若 A/W 页大于 64beat，需同时改参数
  与页存储深度，不能用“预取”名称假设无限缓冲。
- 该模块只做页管理，不产生 AXI；必须外接 `axi_dma_v020_multi`（或契约相同的
  transaction DMA）。实测 4 页 ×64beat、消费者 300cyc/页：
  串行 1,651 → 预取 1,339 cycles（1.233×），overlap=303，stall=410。

## 4. vector/layout wrapper

`ddr_vector_axi_v020.sv` / `ddr_layout_axi_v020.sv` 的端口、descriptor 格式、
ACL、数值路径与 `work/rtl/ddr_vector_axi.sv` / `ddr_layout_axi.sv` 相同，仅把内部
两个 `axi_dma_v019` 换成 `axi_dma_v020_multi(.MAX_OUT(8),.FIFO_BEATS(128))`。

实测小请求负载**不应默认替换**：

| 负载 | v019 | v020 | 变化 |
|---|---:|---:|---:|
| vector add_scalar | 7,882 | 7,887 | +0.06% |
| vector mul_vector | 8,528 | 8,532 | +0.05% |
| vector i16_to_float | 4,805 | 4,807 | +0.04% |
| layout copy_i16 | 10,152 | 10,517 | +3.60% |
| layout CASE0000 embed conv0 | 563,652 | 566,367 | +0.48% |

原因：请求粒度 64beat、load/unpack/compute/write 相位固定，单请求在途深度不是
瓶颈；v020 的 FIFO/握手还多 1~3%。**按源码选择**：大范围连续搬运/多页预取用 v020，
<32beat 读请求保留 v019 或加 bypass。

## 5. `pl_graph_runner_v1`

`MAX_NODES=32`、`NODE_MAGIC=0x47525048`；节点 512bit 行含 magic/id/dep_mask/
op tag/参数。单 `start`、单 `done/fault/error_code`；只在 `(dep_mask & ~done_mask)==0`
时启动；循环依赖置 fault 0x04，子算子 fault 透传 0x05。

已测 4 节点：表顺序 0,3,1,2，依赖 1←0、2←0、3←1|2，实际启动 0,2,1,3，
completed=4；循环依赖/子算子 fault 各一例。**这是控制骨架**，不含真实 68+591
节点、节点表 AXI 抓取、host 一次装载、legacy 静态化、全图 liveness/arena 证明。
不能把 4 节点 PASS 当 CASE 自主执行。

## 6. BFM：`bench/bfm/axi128_ddr_bfm_ds.sv`

### 6.1 参数/端口

`PORTS/MAX_OUT/WFIFO/LAT_MIN/LAT_MAX/BLAT_MIN/BLAT_MAX/TURNAROUND/
READY_STALL_PCT/R_STALL_PCT/W_STALL_PCT/SEED`。

每端口独立 AR/AW 队列（`MAX_OUT`）、W FIFO（`WFIFO`）、按序 B 队列（`MAX_OUT`）；
单条 128bit 半双工数据通道，每 cycle 最多一个 16B beat；换向有 `TURNAROUND` 空拍。
地址窗口：`0x0300_0000`、`0x0400_0000`、`0x1000_0000` 各 256KiB。
严格检查 16B、INCR、≤256beat、4KiB、WLAST/RLAST、地址窗口。
计数器：`cycles/bus_read_beats/bus_write_beats/bus_busy_cycles/bus_idle_cycles/
bus_turnaround_cycles/read_bursts/write_bursts/max_rd_out/max_wr_out/
ar_stall_cycles/aw_stall_cycles/r_stall_cycles/w_stall_cycles`。
错误只注入 RRESP/BRESP，已接受事务必须排空。

### 6.2 为什么是 `_ds` 副本

外部进程在 2026-10-30 改写了 shared `bench/bfm/axi128_ddr_bfm.sv`；该版本：

- Icarus 14 不能展开（无参函数 `rnd` 被当变量；已用 `rnd()` 修）；
- W 通道死锁（W 只在 grant 时入 FIFO，而 grant 又要求 FIFO 非空）；
- AW 接受未递增 `aw_cnt`（W 永远等不到 AW 信用）；
- 每端口只有一个 B pending，多 AW 在途时 B 被覆盖；
- 每拍强制读写换向，双向持续可服务时把总线人为限成 ~50%；
- 同一拍 `aw_cnt/rd_cnt` 两次 NBA 赋值互相覆盖。

`_ds` 副本逐项修正并实跑；shared 文件保持不动，两者不能混用。所有 ds_ddr
脚本/报告只引用 `_ds`。**这不是板级 DDR 模型**：无 PS DDR 控制器、刷新、
bank/row、PHY、时钟桥。

## 7. 300/600MHz 控制路径（结构建议，未验证）

无综合/STA，以下只是寄存化清单，不是频率结论：

- v020：把 `page_beats/limit/chosen` 在 request 接受时寄存；`m_axi_arlen/awlen/
  arvalid/awvalid` 由寄存器直接驱动；`wlast` 用寄存的 last 标志；`can_ar` 的
  `fifo_free>=chosen` 做成 issue credit 寄存器；FIFO 改同步读/BRAM 输出寄存。
- ping-pong：`free_mask/credit` 与页选择寄存；页存储用双口 BRAM；消费者
  `consume_addr` 到 `consume_data` 加一级输出寄存（会改变读延迟，需上层配合）。
- vector/layout：64-bit 乘法/`readable/overlap` 拆分到 2~3 拍 VALIDATE；
  layout 的 64-way `cache_matches` 和 256-bit `source_window` 加流水。
- 计算域 300/600MHz 与 DDR 用户域（当前 125MHz）之间必须加 async FIFO/信用桥；
  桥接吞吐不能超过 DDR 侧 16B/cycle 可达界。本任务未实现 CDC。
- 任何“300/600MHz 已实现”都必须等独立 STA/实现任务，不能引用本目录仿真 PASS。

## 8. 集成检查清单

1. 不要把 v020 直接替换所有 v019：<32beat 读请求保留 v019 或 bypass；
   先跑同负载 before/after。
2. `write_bytes` 必须按 WSTRB popcount；尾拍/`out16`/C48 打包都可能有部分 strobe。
3. 保持每 C 的 K 顺序：读侧按 `read_index` 递增消费；页预取按页内 index 写。
4. 保持 16beat/4KiB 切分和错误后已接受事务排空；不要在任何错误路径取消 AXI。
5. **多命令 posted C 写**：v020 一次只接一个 `request`（内部可多 burst），
   `request_ready` 只在 IDLE。若上层（如 `ds_storage_overlap` 的 `cseg/wr_req`）
   需要 8 个独立写命令同时在途，必须在前级加 transaction 队列/合并器，或每个
   命令一个 DMA；**不能假设 v020 的 B 多在途等于多命令接受**。
6. 读侧同理：一个 block 一个 request 可直接用；多 block 并发要在前级排队。
7. 使用 `_ds` BFM 复跑；不要与外部 shared BFM 混编译。
8. 数值合同（W7 S/J/M、positions/clip、A16/C48、INT48 回绕、FP32 FTZ/RNE/FMA、
   QDQ）不在 DMA/BFM 内，任何集成不得改动或用整数乘替代特殊 W7。

## 9. 复跑

```bash
cd /home/yang/Desktop/项目/tasks/ds_ddr
bash bench/run_all.sh
```

单独：

```bash
python3 bench/run_dma_compare.py
python3 bench/run_short_bursts.py
python3 bench/run_strobe_account.py
python3 bench/run_pingpong.py
python3 bench/run_vector_compare.py
python3 bench/run_graph.py
```

产物：`bench/reports/*.json`、`result.json`、`REPORT.md`、`FINDINGS.md`。
