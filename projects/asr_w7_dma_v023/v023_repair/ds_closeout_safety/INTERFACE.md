# INTERFACE — V0.23 异常闭环 / 安全收尾候选

状态：本地逻辑仿真候选；**整机 V0.23 未验收**。单时钟；无 CDC/异步 FIFO 声明。
本文件描述本任务相对 `integrated/` 新增/改变的接口与契约。未列出的接口保持
`integrated/INTERFACE.md` 语义。

## 1. 唯一编译清单

`filelist_safety.f` 是本任务唯一入口，包含且只包含一份：

- `ddr_layout_engine`：`rtl/ddr_layout_engine_v023_burst.sv`（步进版不编译）；
- `asr_fma_ip`：`rtl/fma_forbidden_stub.sv`（compile-only，op17 调用即 abort）；
- `axi_dma_v019` / `task_queue` / matrix/vector/layout/control 候选；
- 本任务新增的 `v023_*` 适配与 `wc_graph_ctrl.sv` / `wc_graph_top.sv` 副本。

`optional/approx/*` 不在默认清单。`filelist_baseline.f` 是只读 sealed baseline
清单；本任务另生成本地绝对路径版本 `filelist_baseline_local.f` 仅供复跑。

## 2. 顶层 `v023_integrated_top` 新增端口

参数新增：

```systemverilog
SEQ_WATCHDOG=200000, FETCH_WATCHDOG=200000,
VEC_WATCHDOG=200000, LAY_WATCHDOG=200000, MAX_PREFETCH=16,
DRAIN_WATCHDOG=64'd200000000, SEQ_ENABLE=0
```

`SEQ_ENABLE=0`（默认）保持原 integrated 行为：SEQ `ready` 接 0，SEQ 节点不能
启动。`SEQ_ENABLE=1` 时使用外部 SEQ handshake：

| 端口 | 方向 | 语义 |
|---|---|---|
| `seq_ready_i` | in | SEQ child 接受当前 `seq_valid_o` |
| `seq_done_i` | in | SEQ child 完成（单拍） |
| `seq_fault_i` | in | SEQ child 故障 |
| `seq_error_i[7:0]` | in | 故障码 |
| `seq_valid_o` | out | 控制器请求 SEQ（base/count 有效） |
| `seq_base_o[31:0]` | out | SEQ program base |
| `seq_count_o[31:0]` | out | SEQ program count |

新增状态/契约端口：

| 端口 | 方向 | 语义 |
|---|---|---|
| `isolation_req` | out | 已停止新 child 工作，但至少一个 child/端口不能证明 drained；不是成功 |
| `requires_reset` | out | 粘滞到 `rst_n`；为 1 时 CSR 拒绝 START |
| `port_quiesced` | out | `rd_pending==wr_pending==b_pending==0`，唯一可证明“端口无旧事务” |
| `rd_pending/wr_pending/b_pending[31:0]` | out | xbar 真实 outstanding 计数；超时/隔离不清零 |
| `iso_blocked_reqs[31:0]` | out | isolate 期间被拒绝的新 AR/AW/W 周期数 |
| `seq_dispatch_timeout` | out | SEQ 在 DISPATCH 等待 `seq_ready` 超时 |
| `seq_inflight_timeout` | out | SEQ 已接受但永不 `done` 超时 |
| `fetch_timeout` | out | plan/header/node/payload 取指无进展超时 |
| `vector_total_cycles/layout_total_cycles/matrix_total_cycles[63:0]` | out | **逐 op/逐 task 累加**，不是最后一个计数器 |
| `vector_op_count/layout_op_count/matrix_op_count[31:0]` | out | 完成的 op/task 数 |

原有 `vector_cycles/layout_cycles/matrix_cycles` 仍是“最后一个 op/task”的
telemetry；软件合计必须读 `*_total_cycles` 或 CSR 0x40/0x48/0xA0。

## 3. CSR 新增寄存器（AXI4-Lite，24-bit 地址）

原有 0x00..0xAC 语义不变；新增：

| offset | 读 | 语义 |
|---|---|---|
| 0xB0 | `{30'd0, requires_reset, isolation}` | 隔离/复位要求 |
| 0xB4 | `rd_pending` | 读 outstanding |
| 0xB8 | `wr_pending` | AW outstanding |
| 0xBC | `b_pending` | B outstanding |
| 0xC0 | `iso_blocked_reqs` | isolate 拒绝的新请求周期 |
| 0xC4 | `{31'd0, port_quiesced}` | 端口排空证明 |
| 0xC8 | `lockout_rejects` | `requires_reset=1` 时被拒绝的 START 次数 |

START（写 0x10=1）在 `requires_reset=1` 时：

- 返回 `BRESP=2`（SLVERR）；
- `done_latched` 保持 1，不清 counters；
- `lockout_rejects` 递增；
- 不向 graph 发 `start`，不向 AXI 发新 AR/AW/W。

CSR 0x40/0x48/0xA0 现在是逐 op/task 合计；0x30/0x38 的 fetch/operator
不再硬接 0；0x44 的 `rejected_starts` 接 graph 真实计数。

## 4. 共享 AXI 契约 `v023_axi_shared`

新增端口：

```systemverilog
input  wire isolate,
output wire [31:0] rd_pending, wr_pending, b_pending,
output wire quiesced,
output reg  [31:0] iso_blocked
```

- `isolate=1`：`s_arvalid/s_awvalid/s_wvalid=0`，`m_arready/m_awready/
  m_wready=0`；`s_rready/s_bready` 保持，已有 R/B 可继续排空。
- `rd_pending=ar_count`、`wr_pending=aw_count`、`b_pending=b_count`；只在
  真实 R/B 握手时递减，**任何超时/隔离都不清零**。
- `quiesced` 是端口可复用的必要证据；不是 child drained 的证据。
- `iso_blocked` 用于证明“停止新请求”确实发生。

**reset 契约**：`rst_n` 会清 xbar 的 pending FIFO/计数。若外部从机仍持有旧
事务，只 reset DUT 会让下一个 AR 消费旧 R beat（`tb_axi_reset_hazard.sv`
已实测 `new_ar=0x4000 -> stale_data=0x3000`）。因此：

- `quiesced=1` 时才可只 reset DUT；
- `quiesced=0` 时必须全系统 reset（DUT + 外部从机/BFM/PS 端口），不得复用
  仍有旧事务的端口。

## 5. Graph 控制器契约

新增参数/输出：

- `SEQ_WATCHDOG`：DISPATCH 等待（direct_idle 时）和 in-flight 分别计时；
  超时 `error=0x0E, isolation_req=1, requires_reset=1`，强制 FINISH。
- `FETCH_WATCHDOG`：取指无进展超时，同上。
- `DRAIN_WATCHDOG`：fault 后仍有 `e_active` 且超时，强制隔离终态，不伪造 drained。
- `isolation_req/requires_reset/seq_dispatch_timeout/seq_inflight_timeout/
  fetch_timeout/seq_wait_cycles/seq_run_cycles` 输出。

SEQ 互斥：

- `direct_idle = ~|e_active`（含 LAY）；
- `seq_active = e_active[0] || (DISPATCH && target==SEQ)`；
- MAT/VEC/LAY 发射条件含 `!e_active[0]`；
- top 层再把 `vec_ready/lay_ready/mat_ready` 与 `!seq_active` 相与。

隔离后：

- 迟到 child `done` 不清 `fault`、不 `mark_done`、不把节点记成功；
- `busy=0, done=1, fault=1, error=0x0E` 是**终态**；
- `requires_reset=1` 粘滞到 reset。

## 6. Child guard / matrix 计数

- `v023_vector_guard` / `v023_layout_guard` 新增：
  `total_cycles/total_busy_cycles/op_count/requires_reset`。
  `done` 每 op 只发一次（`reported` 锁存）；超时后引擎晚完成不会二次计数。
- `v023_matrix_queue_engine` 新增：
  `matrix_total_cycles/matrix_total_compute/matrix_total_rb/matrix_total_wb/
  matrix_op_count/requires_reset`。adapter 在每个 task `core_done` 累加；
  `S_WAIT` 等待 cluster 的 level `done` 清除后再进入 `S_RUN`，避免把上一个
  task 的 done 当成新 task 完成。
- `matrix_cycles` 仍是最后一个 task；`matrix_total_cycles` 是队列 child 合计。

## 7. 错误码

| 码 | 含义 |
|---|---|
| 0x01 | plan base/param 窗口非法 |
| 0x02 | parameter_ready/generation 失效 |
| 0x03 | 取指/队列 DMA 错误 |
| 0x04 | header/node 校验或 hash 错误 |
| 0x05 | child 通用 fault（无具体码） |
| 0x07 | WCPG payload/ACL 拒绝（非法 vector op/layout mode） |
| 0x08 | root/output provenance 错误 |
| 0x0A | 输出未保留 |
| 0x0E | **watchdog 隔离终态**（不是 drained；requires_reset=1） |
| 0x81 | matrix cfg/operator/overlap 非法 |

## 8. 测试入口

```bash
bash scripts/run_safety.sh          # 26 项 + sealed baseline，写 logs/rc.tsv
python3 scripts/check_safety.py     # 逐日志判定，写 result.json
```

`tb/tb_safety_integrated.sv` 支持 `+mode=0/1/2/3/4/5`、`+hold_r_lo/hi`、
`+hold_b_lo/hi`、`+release_after`、`+test_restart`、`+expect_*`。
`tb/tb_graph_mutex.sv` 用 `-DPATCHED` 编译修复版；不带宏则编译
`integrated_copy/rtl/wc_graph_ctrl.sv` 作为负对照。
`tb/tb_axi_reset_hazard.sv` 的外部从机故意忽略 DUT reset，用于反证端口复用危险。

## 9. 不在此接口内

- 完整 591 tensor DAG / sealed payload re-lower / 原 host executor；
- FMA/op17、approx、epilogue stream 的整机接入；
- CDC/异步 FIFO、综合/STA/板卡、300/600MHz；
- 全模型 WER/CER。
