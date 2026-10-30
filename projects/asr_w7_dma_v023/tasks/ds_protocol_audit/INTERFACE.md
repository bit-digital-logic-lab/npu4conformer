# INTERFACE — 被审查模块端口契约与主 agent 集成建议

本文件只描述**已存在的只读模块**的接口语义和**建议的契约增量**。
本任务没有新增可综合 RTL；新增文件仅为 `tb/` 下的测试/BMF 和 `scripts/`。
所有数值约束（W7(S/J/M)/positions/clip、A16/C48、每 C 的 K 顺序、
FP32 FTZ/RNE/FMA、QDQ 边界）保持不变。

## 1. `axi_dma_v019`（work/rtl/axi_dma_v019.sv，只读）

单 outstanding、AXI4、128-bit data、16-beat 最大 burst、4KiB 自动切分。

| 端口 | 方向/宽度 | 语义 |
|---|---|---|
| `clk,rst_n` | in | 同步低有效复位；`request_ready=state==IDLE&&rst_n` |
| `request_valid/ready` | in/out | 一次请求；`request_ready` 在 IDLE 为 1，可与 `done` 同拍 |
| `request_write` | in | 0=读，1=写 |
| `request_address[31:0]` | in | 必须 16B 对齐；内部零扩展为 40-bit AXI 地址 |
| `request_beats[15:0]` | in | 1..65535；0 → `error=1`，不发 AXI |
| `read_valid/ready, read_data[127:0], read_index[15:0]` | out/in | 读数据流；`read_index` 在每次 R 握手递增（跨 4KiB burst 连续） |
| `write_valid/ready, write_data[127:0], write_strobe[15:0], write_index[15:0]` | in/out | 写数据流；`write_ready=state==WDATA&&m_axi_wready` |
| `done,error` | out | `done` 单拍；`error` 在下一请求接收时清 0；错误在已接受事务排空后报告 |
| `m_axi_*` | AXI4 | AR/AW 地址 40-bit，ARLEN/AWLEN ≤15，ARSIZE=4，INCR；R/B 通道 |
| `read_bytes/write_bytes/read_bursts/write_bursts[31:0]` | out | 累计值；`write_bytes` 按 WSTRB popcount；不在每次请求清零 |

语义要点（实测见 `reports/dma_edge001`）：

- 4KiB：`address[11:0]+(len+1)*16 ≤ 4096`；地址 `0xFF0` 的 16-beat 会拆成
  `ARLEN=0` + `ARLEN=14`（两笔合计 16 beat）。
- RLAST 早：标记 error 并结束；RLAST 晚：继续接收直到 RLAST，标记 error，
  不取消已接受的 burst。RRESP 中途非 0：继续排空到 RLAST，再 error。
- BRESP 非 0：结束当前事务；不再发下一 AW；已发出的 W 由 B 排空。
- 无内部通道超时；无 RLAST 时会一直 busy（`reports/dma_edge001` T19）。
- **32-bit 地址加法在 4GiB 回绕**（PA-003）；当前调用者用 64-bit ACL 保护。

建议契约增量（未实现）：

```
input  wire [39:0] request_address;   // 或保留 32-bit + 增加 end_check
output wire        request_error;    // 地址/零长度拒绝的可观测原因
output wire        channel_timeout;  // 仅诊断；不取消已接受 AXI
```

## 2. `axi_dma_v020_multi`（候选快照 7123c26f...，只读）

参数：`MAX_OUT=8`（2 的幂，未断言）、`FIFO_BEATS=128`、`MAX_BURST=16`。
读：多 outstanding AR + 数据 FIFO；写：每 burst 完成后可提前发下一 AW，
B 可多笔在途；W 严格按序。

与 v019 的接口差异：

- 额外输出：`ar_outstanding_max, b_outstanding_max[31:0]`、
  `read_bubble_cycles, write_bubble_cycles, read_fifo_high[63:0]`。
- `read_index` 在 consumer pop 时递增；`read_data` 来自内部 FIFO。
- `m_axi_wvalid` 已与上游 `write_valid` 相与（当前快照）；WSTRB/WDATA 直通。
- `m_axi_bready` 恒 1。
- **`write_bytes` 目前按 16B/beat 递增，未按 WSTRB**（PA-004）。
- 读到错误后 `remaining<=0`、停止新 AR，排空已有 tag/FIFO 后完成；
  写错误后停止新 AW，排空 B 后完成（`reports/multi001`）。
- `can_ar` 只检查 `fifo_free>=chosen`；默认 8×16=128 与 FIFO 容量相等；
  若改小 FIFO/加大 MAX_OUT，需重新证明不会超订（rready 仍会反压，不会丢数，
  但会降低有效 outstanding）。

建议契约增量：

```
function [4:0] pop16(input [15:0] strobe); // write_bytes += pop16(write_strobe)
// elaboration checks:
// (MAX_OUT & (MAX_OUT-1))==0, MAX_BURST<=16, FIFO_BEATS>=MAX_OUT*MAX_BURST
// b_out: only decrement if !=0; unexpected B -> err_sticky
```

## 3. `plan_submit_csr`（work/rtl/plan_submit_csr.sv，只读）

AXI-Lite slave；PS 只做计划指针/计数/START 和完成/错误读取。

寄存器（低 8 位地址，`[23:8]!=0` 或非字对齐 → SLVERR）：

```
0x00 RO magic A51A22D0       0x04 RO {fault,done_latched,busy}
0x08 RW plan_base             0x0C RW plan_count
0x10 WO START (wd==1,parameter_ready)  0x14 RO completed
0x18 RO index                 0x1C RO error_code
0x20/24 cycles lo/hi          0x30/34 fetch_cycles lo/hi
0x38/3C operator_cycles       0x40/44 vector_total
0x48/4C layout_total          0x50..0x5C byte counters
0x60/64 read_overlap          0x68/6C write_overlap
0x70 vector_elements          0x74 layout_elements
0x78 flags                    0x7C vector/layout error codes
0x80 hits                     0x84 misses
0x90 parameter_ready          0x94 generation   0x98 param_end
0x9C profile 10102201         0xA0/0xA4 matrix_total
0xA8/0xAC matrix_pe_total
```

语义：AW/W 独立，`awready=!awfull&&!bvalid`、`wready=!wfull&&!bvalid`；
B 在 AW+W 都到后一拍产生并保持；非法 strobe/地址/busy START → `BRESP=2`，
且不产生副作用；START 单拍；`done_latched` 粘滞，START 清 0；`irq=done_latched`。

**64-bit 读回契约缺陷（PA-001）**：当前所有 `0x20/0x30/0x38/0x40/...` 的低字读
共用一个 `snapshot_high`；交错读不同寄存器会返回错误高字。
建议 v2：为每个寄存器维护独立高字 latch，或新增 64-bit 读通道；PS 侧也应成对读。

## 4. `pl_execution_plan_v022`（work/rtl/pl_execution_plan_v022.sv，只读）

| 端口 | 语义 |
|---|---|
| `start, plan_base[31:0], plan_count[31:0], param_end[31:0], parameter_ready, generation[31:0]` | 一次 START；plan_base 64B 对齐，`plan_base+count*64≤param_end≤0x40000000` |
| `busy, done, fault, error_code[7:0], completed, index, rejected_starts, last_ticket` | 单完成出口；`done`/`irq` 单拍，`busy` 覆盖整个 plan |
| `dma_*` | 计划/向量 payload fetch 的 DMA 请求/数据接口（v019） |
| `matrix_valid/ready, matrix_queue_base/count, matrix_done/fault` | kind=1 子算子 |
| `vector_valid/ready, vector_descriptor[511:0], vector_done/fault` | kind=2 |
| `layout_valid/ready, layout_descriptor[1023:0], layout_done/fault` | kind=3 |
| `WATCHDOG` | 默认 12.5e9 cycles（125MHz≈100s）；FETCH/WAIT_OP 各自计时 |

指令格式：512-bit；`[31:0]=0x22504c4e`、`[63:32]=kind(1/2/3)`、`[95:64]=ticket≠0`、
`[127:96]=dependency`（index=0 时 FFFFFFFF，否则 index-1）、`[159:128]=pointer`、
`[191:160]=length`、`[511:192]=0`。

**watchdog 契约缺口（PA-002）**：FETCH 超时只置 `fetch_bad/error_code=09`，
不置 fault/不离开 FETCH；ERROR_DRAIN 等 child done 无限期。建议新增：

```
output wire        child_abort;   // 超时后请求 child 停止发新事务
input  wire        child_drained; // child 已排空已接受 AXI
output reg         drain_timeout; // 第二 deadline 已过
// 语义：abort 不取消已接受 AXI；drained 后 plan 完成；timeout 后 fault/done
// 由外部 AXI firewall/reset 或 supervisor 处理
```

## 5. `ddr_vector_axi` / `ddr_layout_axi`（只读）

两者都是“引擎 + 两个真实 v019 DMA”的封装，端口：

- 公共：`clk,rst_n,start,descriptor[511:0]/[1023:0],param_end,ready,busy,done,fault,
  error_code,numeric_flags/completed_elements/processed_elements,cache_hits/misses,
  cycles,read_bytes/write_bytes/read_bursts/write_bursts,
  read_m_axi_* / write_m_axi_*`。
- 读口只发 AR/R，写口只发 AW/W/B（封装里两个 v019 的未用方向仍连在端口上）。
- vector 校验（`ddr_vector_engine.sv:103-112`）：magic/zeros、count、op、period、
  a48/btiled/out16 组合、`sd` 对齐/arena 范围、A/B/C 64-bit `readable()` 和
  `overlap()`；无效 descriptor → `fault=1,error_code=1`，**不发 AXI**。
- layout 校验（`ddr_layout_engine.sv:69-84`）：magic、mode、total、bytes、对齐、
  各 mode 形状、`source_end/destination_end` 64-bit、`extent_bad`；无效 →
  `fault=1,error_code=1`，**不发 AXI**。
- 两者 `ready=!busy&&rd_request_ready&&wr_request_ready`；`done` 单拍；
  `fault` 后必须等两个 DMA 都 IDLE 才可再次 START。
- 实测 ACL：0xFFFFFFF0 被 64-bit 检查拒绝（`reports/acl001`）。
- 实测打包：6-byte C48 跨 128-bit、out16/out32 tail、4KiB 跨页均 byte-exact
  （`reports/vector_stress001`、`reports/layout_stress001`）。

## 6. 测试平台接口（仅仿真，不综合）

`tb/axi128_stress_bfm.sv`（`PORTS=1/2`）：

```
clk,rst_n,
araddr[PORTS*40], arlen[PORTS*8], arsize[PORTS*3], arburst[PORTS*2],
arvalid/arready, rdata[PORTS*128], rresp[PORTS*2], rlast/rvalid/rready,
awaddr/awlen/awsize/awburst/awvalid/awready,
wdata[PORTS*128]/wstrb[PORTS*16]/wlast/wvalid/wready,
bresp[PORTS*2]/bvalid/bready,
inject_read_error,inject_write_error,stall_r,
read_bursts/write_bursts/read_beats/write_beats
```

- 内部 `reg [7:0] memory[0:262143]`；地址映射 0x04000000..0x0403FFFF、
  0x10000000..0x1000FFFF；4KiB/ARLEN/WLAST/对齐检查 `$fatal`。
- `stall_r=1` 只停 R 通道（用于 PA-002 phase1）；伪随机 gate 由 xorshift32 驱动。
- `tb_strobe.sv` 是独立的最小 WSTRB 复现。

## 7. 300/600MHz 控制路径寄存化建议（结构目标，未验证）

用户阶段末要求：DMA/存储新候选考虑 300/600MHz 控制路径寄存化，不能把频率当已验证。
本任务无综合/STA，以下只是结构建议：

- v019：在请求边界寄存 `page_beats/limit/chosen`，让 `m_axi_arlen/awlen` 直接来自寄存器；
  `m_axi_wlast` 改为寄存的 last 标志；32-bit 地址增量/比较单独一级。
- v020_multi：`can_ar` 的“remaining/tag_cnt/fifo_free>=chosen”先打一拍或做成
  “issue credit”寄存器；`b_out` 改为 0..MAX_OUT 的小计数器 + registered empty；
  `read_data=fifo[fifo_rd]` 改同步读/BRAM 输出寄存；`m_axi_wlast` 寄存。
- vector：`invalid_descriptor` 的 64-bit 乘法/`readable/overlap` 拆分到 2-3 个
  VALIDATE 拍（layout 已有 VALIDATE/EXTENT1/EXTENT2 结构可借鉴）。
- layout：64-way `cache_matches` + encoder 加一级流水；`source_window` 256-bit 移位
  与 `fragment_*` 掩码按流水切分。
- 这些改动不得改 W7/A16/C48/K 顺序/FP32 语义；**无 STA 前不得声称 300/600MHz**。

## 8. 集成检查清单（主 agent）

1. 若用 v020_multi 替换 v019：先修 `write_bytes=popcount(WSTRB)`，并保留
   `m_axi_wvalid && write_valid`；跑 `reports/multi001` 的 W2 气泡测试。
2. 若改 `plan_submit_csr`：实现 per-register 高字/64-bit 读，跑 `reports/csr001`
   的 `read32,read48,read36` 序列。
3. 若改 plan watchdog：实现 abort/drain/第二 deadline，跑 `reports/plan_stall001`
   phase1/2，要求最终 `done=1`（fault 可为 1）而不是永久 busy。
4. 地址：要么把 v019 内部地址扩到 40-bit，要么在第一笔 AR 前做 4GiB 上界检查；
   保留 vector/layout 的 64-bit `readable()/extent_bad`（`reports/acl001`）。
5. 不要改 W7/A16/C48/K 顺序/FP32 FTZ/RNE/FMA；不要把本报告的 BFM 当作 DDR 时序。
6. 若追 300/600MHz：按第 7 节做控制路径寄存/流水，再另开 STA/实现任务；
   本目录的任何“PASS”都不构成频率证据。
