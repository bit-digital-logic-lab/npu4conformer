# REPORT — V0.23 异常闭环 / 排空 / 隔离 / 计数收尾

日期：2026-10-30  
目录：`/home/yang/Desktop/项目/v023_repair/ds_closeout_safety`  
范围：**仅本地逻辑仿真**。未综合、未 Vivado/STA、未上板、未 VNC、未 push。  
`work/`、原 ZIP、其他 worker 目录、`primary_stream_fix` 均只读；本目录只写自己的
快照、RTL 补丁、测试、日志和报告。

## 0. 结论

**异常闭环候选在本地逻辑仿真中可复跑通过；整机 V0.23 仍不是 PASS。**

本轮交付的是系统异常闭环，而不是全模型验收：

- 复核并修复了 SEQ 互斥漏洞：原 `direct_idle=~|e_active[2:0]` **漏掉 LAY
  (bit 3)**，且 MAT/VEC/LAY 发射没有用 SEQ 在途状态门控；`seq_active` 只覆盖
  在途、不覆盖等待。负对照在同一负载下真实出现 SEQ+LAY 重叠 296 / 279 拍；
  修复后为 0。
- 新增真实 hung child 注入：SEQ 等待不接受（dispatch-wait）和已接受永不 done
  （in-flight）两种。旧控制器一直 busy，直到 TB 超时；新控制器在 watchdog 后
  进入 **故障隔离终态**：`done=1,fault=1,error=0x0E,isolation=1,requires_reset=1`，
  不把超时清成成功。
- 新增 AXI R/B 永久等待注入：plan 取指、C48 读、matrix C 写 B、vector D0 写 B。
  隔离后停止新 AR/AW/W，已有响应可继续排空；`rd_pending/wr_pending/b_pending`
  **从不在超时后清零**，只有真实响应才递减。永久不返回时 `quiesced=0`，
  明确要求全系统 reset；延迟返回时 `quiesced=1`，但子引擎仍 `requires_reset=1`。
- 用独立外部从机证明：只 reset DUT、不复位仍持有旧事务的端口时，新的 AR 会把
  旧 R beat 当成自己的数据（`new_ar=0x4000` 收到 `0x3000`）。因此**存在旧事务的
  端口不能复用**，必须全系统 reset（含从机/BFM/PS 侧）。
- 坏队列、非法算子注入：magic/backend/predecessor/queue-overlap、非法 matrix
  operator mask、非法 vector op19、非法 layout mode 7，全部给出确定 fault、
  `done=1`、无挂死、错误码与预期一致。
- 计数：报告里 `952/6724` 是**最后一个 op 的 telemetry**，不是 CSR 合计。
  真实 CSR 合计本来就是 `4643/16788`，与 busy 采样一致。另修了三个真实问题：
  CSR `fetch/operator/rejected` 被硬接 0；matrix 多 descriptor 队列只累计最后
  一个 task；guard 超时后可能二次 done 导致重复计数。
- 同负载 golden：normal 与 multitask 的 1024 个 I16 都与独立 numpy golden
  逐位一致；sealed baseline chain 仍 PASS 且与同一 golden 一致。

**没有**声称：完整 591 tensor DAG、sealed payload re-lower、全模型
WER/CER、板级 300/600MHz、CDC/STA、FMA/approx 的整机接入。FMA/approx 的
第二轮独立结果只作为门禁背景引用，本轮没有重跑它们，也没有把它们接进默认路径。

## 1. 读过的输入与门禁口径

已读：

- `primary_stream_fix/REPORT.md`：主 agent 亲修 65 项回归通过；旧
  `stream_param_port` 113 失配是测试未传 `PARAM_EN/ADDR/DATA`，不是端口未实现；
  packed/A16 有独立 tag；参数只是 2 个广播寄存器，不宣称 per-channel。
- `primary_acceptance/round2/result_primary_fma.json`：8734 向量，主 agent 独立
  复跑 0 mismatch。
- `primary_acceptance/round2/result_primary_approx.json`：15168 例通过；DIV 最大
  0.1114666%，SQRT 5.78e-6、RSQRT 5.72e-6，5 拍 II=1。
- `primary_acceptance/round2/result_primary_stream_bp2.json`、`REPORT.md`：stream
  BP2 的 tag/重复/数据通过；param 契约已由主 agent 修正。
- `integrated/REPORT.md`、`INTERFACE.md`、`result.json`、`progress.json`：9 节点
  exact chain、1024/1024 golden、AXI ledger 0、bad queue/bad vec 两个负例；同时
  明确列出 abort/drain、SEQ 并发、hung child、多 outstanding 未测。
- 各 worker 的 `USER_UPDATES.md`（`ds_integration`、`ds_numeric_adversarial`、
  `ds_control_fixes`、`gemini_fma_round2`、`gemini_approx_repair`、`ds_graph`）。

**旧门禁已过时**：`integrated/REPORT.md` 中“FMA 137 失配 / approx 3 个 signed-zero
失配”属于第一轮；第二轮已由主 agent 独立通过。本报告不沿用旧失败，也不把
第二轮局部数值通过外推为整机通过。默认 integrated 路径仍不含 FMA/op17 与
approx，本轮不改变这一点。

本项目是 **512 维 Conformer/Transformer ASR**（12 encoder + 6 decoder、
79 LayerNorm 等），不是 KWT-1 的 64 维/99 元素口径；本报告不使用旧 KWT
的 LayerNorm 方差范围或精度结论。

## 2. 目录与只读边界

- `integrated_copy/`：从 `integrated/` 复制的只读快照（不含 build 大文件）。
- `rtl/`：本任务修改后的 RTL 副本；只在本目录。
- `tb/`：新增安全 TB / BFM；`tb/wc_safety_bfm.sv` 是可注入 R/B 永久等待的
  AXI 从机。
- `scripts/`：fixture 生成、编译/运行、判定。
- `logs/`、`reports/`、`fixtures/`：真实运行证据。
- `PATCH.diff`：相对 `integrated_copy/rtl` 的 unified diff。
- `filelist_safety.f`：本任务唯一编译清单；没有 optional approx/FMA 候选。

## 3. 复核发现与修复

### 3.1 SEQ 互斥没有覆盖“等待/在途”，且漏掉 LAY

原 `wc_graph_ctrl.sv`：

```verilog
assign direct_idle = ~|e_active[2:0];   // bit3 = LAY 被漏掉
assign seq_active  = e_active[0];       // 只有在途，不含 DISPATCH 等待
```

SCAN 中 MAT/VEC/LAY 只看自己的 `e_active`，没有看 `e_active[0]`。因此：

- LAY 在途时 `direct_idle` 仍为 1，SEQ 可以启动（真实重叠 296 拍）；
- SEQ 在途时 LAY/MAT/VEC 仍可发射（真实重叠 279 拍）；
- SEQ 在 DISPATCH 等待 `seq_ready` 时，整个 FSM 卡在 DISPATCH，没有 watchdog；
- SEQ 已接受但永不 `done` 时，`e_active[0]` 永不清除，`busy` 永远为 1；
- 原 drain 逻辑只把 `drain_timeout` 置 1，然后继续等 `e_active` 清空，**没有终态**。

修复：

1. `direct_idle = ~|e_active`（含 LAY）。
2. `seq_active = e_active[0] || (state==DISPATCH && target 是 SEQ)`，覆盖等待。
3. MAT/VEC/LAY 发射条件加 `!e_active[0]`；`wc_graph_top` 再把 `vec_ready/
   lay_ready/mat_ready` 与 `!seq_active` 相与，做第二道门控。
4. 新增 `SEQ_WATCHDOG`：DISPATCH 等待（且 direct_idle）和 in-flight 分别计数；
   超时置 `error=0x0E, isolation=1, requires_reset=1`，清 `e_active`，强制
   `FINISH`。这是**隔离终态**，不是 drained。
5. 新增 `FETCH_WATCHDOG`：plan/header/node/payload 取指无进展超时同样隔离，
   防止 AXI R 永久不返回把图卡死在 HFETCH/NFETCH。
6. drain 超时改为强制 `FINISH`，并置 `drain_timeout/isolation/requires_reset`；
   迟到的 child done 不再 `mark_done`（避免把已放弃的节点记成成功）。
7. `requires_reset` 粘滞到 reset；`IDLE` 拒绝新的 START。

负对照/正对照（同一 fixture、同一 stub 延迟、同一周期口径）：

| 场景 | 旧控制器 | 修复后 |
|---|---|---|
| LAY 先，SEQ 后（LAY 300 拍） | SEQ 在 146 拍启动，LAY 140 拍启动，重叠 296 拍 | SEQ 450 拍启动，LAY 140 拍，重叠 0 |
| SEQ 先，LAY 后（SEQ 300 拍） | LAY 在 140 拍启动，SEQ 117 拍启动，重叠 279 拍 | LAY 444 拍启动，SEQ 117 拍，重叠 0 |
| SEQ 等待不接受 | 5005 拍仍 busy=1，TB 超时 | 3091 拍 `done=1,fault=1,err=0e,iso=1,requires_reset=1,seq_dto=1` |
| SEQ 接受但永不 done | 5005 拍仍 busy=1、seq_active=1 | 3095 拍 `done=1,fault=1,err=0e,iso=1,requires_reset=1,seq_ito=1` |
| 健康 SEQ+LAY 短延迟 | — | done=1,fault=0，重叠 0 |

> 这里的 SEQ child 是 TB 的可控 handshake stub（能真实接受、真实不返回），
> 不是 sealed V022 executor；本机没有该 executor，不能把它说成真实执行器已测。

### 3.2 AXI 永久等待 / 隔离 / 排空 / reset 契约

原 `v023_axi_shared` 没有 isolate 输入，超时后无法证明“停止新请求”；原 top
也没有把 guard 的 `isolation_req` 汇总。更严重的是：只 reset DUT 会把
`ar_count/aw_count/b_count` 清零，但外部从机仍可能持有旧 R/B；下一个 AR 会被
旧 R 命中。

修复后的契约（全部可在 `logs/` 复跑）：

- **停止新请求**：`v023_axi_shared.isolate=1` 时 `s_arvalid/s_awvalid/s_wvalid`
  强制 0，`m_arready/m_awready/m_wready` 强制 0；`s_rready/s_bready` 保持，
  用于排空已有响应。`iso_blocked` 统计被拒绝的新请求周期。
- **排空已有响应**：`rd_pending=ar_count`、`wr_pending=aw_count`、
  `b_pending=b_count`；只有真实 R/B 握手才递减，**任何超时/隔离都不清零**。
  `quiesced = (rd_pending==0 && wr_pending==0 && b_pending==0)` 是唯一可证明的
  “端口无旧事务”信号。
- **故障隔离终态**：`isolation_req=1` 表示已停止新 child 工作，但至少一个 child
  或端口无法证明 drained；`requires_reset=1` 表示在 reset 前不得再 START。
  `done=1` 只表示控制器已到终态，**不表示成功**；`fault=1` 与 `error=0x0E`
  同时存在。
- **reset 恢复**：`plan_submit_csr_v023` 新增 `lockout`。`requires_reset=1` 时
  写 START 返回 `BRESP=2`，`done_latched` 保持 1，`lockout_rejects` 递增，
  不会清计数、不会在旧端口上发新 AR/AW/W。若 `quiesced=0`，必须全系统 reset
  （含外部从机）；只 reset DUT 是**不安全**的。
- **延迟响应**：隔离后如果环境最终返回 R/B，pending 会真实降到 0，
  `quiesced=1`；但子引擎已被 watchdog 隔离，仍 `requires_reset=1`。这把
  “端口排空”和“child drained”分开，不混为一谈。

实测：

| 注入 | 结果 |
|---|---|
| plan 取指 R 永久不返回 | `fetch_to=1, err=0e, iso=1, requires_reset=1, rd_pending=1, quiesced=0` |
| C48 读 R 永久不返回 | vector watchdog 3000 拍；`rd_pending=1, quiesced=0`；`held_r=1` |
| matrix C 写 B 永久不返回 | `b_pending=1, quiesced=0`；`held_b=1` |
| vector D0 写 B 永久不返回 | `b_pending=1, quiesced=0`；`held_b=1` |
| C48 R 延迟到隔离后返回 | `quiesce rd_pending=0, quiesced=1`，但 `requires_reset=1` |
| 隔离后再次写 START | `BRESP=2, lockout_rej=1, done_latched=1, new_req=0` |
| 只 reset DUT、从机保留旧 R | 新 AR `0x4000` 收到旧数据 `0x3000`，`HAZARD_STALE_CONSUMED` |

`tb/tb_axi_reset_hazard.sv` 的外部从机故意忽略 DUT reset，证明“端口复用”会
消费旧 beat；这不是建议行为，而是反证：有旧事务时必须全系统 reset。

### 3.3 坏队列 / 非法算子

| 注入 | 错误码 | 终态 |
|---|---|---|
| queue magic 0xdeadbeef | `0x03` | done=1,fault=1,iso=0,quiesced=1 |
| queue backend=20（期望 21） | `0x03` | 同上 |
| predecessor=0（>= current 0） | `0x04` | 同上 |
| A base 与 queue 重叠 | `0x81` | 同上 |
| matrix allowed=0 / c_completed=1 | `0x81` | 同上 |
| vector op19（ACL 拒绝） | `0x07` | done=1,fault=1；`vec_total=0`，零 vector 数据写 |
| layout mode=7（ACL 拒绝） | `0x07` | done=1,fault=1；`layout_total=0`，零 layout 写 |

这些负例都 `done=1`，没有靠 TB 超时结束；错误码由 RTL 给出，不是测试台伪造。

### 3.4 busy / CSR 计数不一致的真实原因

`integrated/REPORT.md §5` 写 “CSR per-op 合计 vector 952、layout 6724，明显小于
busy 4643/16788”。复核后：

1. **952/6724 是最后一个 op 的 telemetry 端口**（`vector_cycles_o` /
   `layout_cycles_o`），不是 CSR 合计。CSR 0x40/0x48 在正常 9 节点 run 中本来就是
   `4643/16788`；逐 op 为 vector 1615+1041+1035+952=4643，layout
   6714+3350+6724=16788，与 busy 采样完全一致。报告把“最后一个计数器”当成了
   合计，这是口径错误，不是 RTL 少算。
2. 真实问题一：integrated top 把 CSR 的 `fetch_cycles/operator_cycles/
   rejected_starts` 硬接 `0/0/0`。修复后 normal run 读到 `fetch=366,
   operator=23339`，与 graph 内部一致。
3. 真实问题二：matrix child 的 `matrix_cycles` 是**最后一个 task** 的周期；
   一个 MAT 节点含多个 descriptor 时，CSR 会少算。修复为 adapter 内
   `acc_cycles/acc_compute/acc_rb/acc_wb/acc_ops` 按 task 累加；多 descriptor
   测试（2 个 task）得到 `matrix_total=3770, matrix_ops=2`，正好是
   1880+1890。
4. 真实问题三：guard 在超时后 `done=eng_done||timeout_pulse`，若被隔离的引擎
   之后又完成，会再发一次 done，CSR 会重复加。修复为 `reported` 锁存，一次
   op 只发一个 done。
5. 真实问题四：`VEC_WATCHDOG/LAY_WATCHDOG` 参数没有接到 guard（guard 用默认
   200000），所以“可配置 watchdog”实际未生效。已接好；本轮用
   matrix/vector/seq 3000、layout 20000、fetch 3000 做故障注入。
6. matrix busy 1900 vs task cycles 1880 的 20 拍差是 adapter 的
   S_CHECK/S_START/S_WAIT/S_DONE 驻留，不是 PE 计算；报告分开列
   `busy_cycles` 与 `op_cycles`，不再把 busy 当 PE 时间。

## 4. 同负载 golden 与周期

- normal：`done=1,fault=0,error=0,cycles=23774,completed=9,last=8`；
  1024 个 I16 与 `integrated_copy/fixtures/gold_i16.hex` **512/512 word 全等**
  （0 mismatch）。
- multitask：同一 9 节点链，MAT 队列 2 个 descriptor；最终 1024 个 I16 仍与
  同一 golden 全等；`matrix_total=3770,matrix_ops=2`；`cycles=25661`。第二个
  descriptor 写 C2 仅用于验证“逐 task 累计”，不是新的数值/精度结论。
- sealed baseline chain：`BASE_CHAIN_RESULT PASS`，输出与同一 golden 全等。
- normal AXI：`rburst=130,wburst=141,rbeats=1828,wbeats=1600,tag_err=0`，
  `rd_pending=wr_pending=b_pending=0,quiesced=1`。
- 这些是 **testbench 周期**，不是板级主频/全模型秒数；没有 STA/板卡证据。

## 5. 测试清单（26 项，全部通过）

`scripts/run_safety.sh` 串行执行，`timeout` + TB 内 watchdog 双重限时；
`logs/rc.tsv` 记录每次 rc。`scripts/check_safety.py` 逐项读取日志，不接受
“超时即通过”。

| # | 测试 | 结论 |
|---:|---|---|
| 1 | normal exact path + per-op CSR + golden | PASS |
| 2 | matrix 多 descriptor 逐 task 合计 | PASS |
| 3/4 | SEQ 先 LAY 后：修复 / 旧版负对照 | PASS / 旧版重叠 296（预期 FAIL） |
| 5/6 | SEQ 先于 LAY：修复 / 旧版负对照 | PASS / 旧版重叠 279（预期 FAIL） |
| 7 | 健康 SEQ+LAY | PASS |
| 8/9 | SEQ 等待不接受：修复 / 旧版 | 隔离 0x0E / 旧版超时（预期） |
| 10/11 | SEQ 接受永不 done：修复 / 旧版 | 隔离 0x0E / 旧版超时（预期） |
| 12–18 | 坏 queue/非法 matrix/vector/layout | 全部预期错误码、done=1 |
| 19–22 | R plan / R C48 / B matrix / B vector 永久等待 | 隔离、pending 不清零 |
| 23 | C48 R 延迟排空 | quiesced=1，但 requires_reset=1 |
| 24 | 隔离后 START 拒绝 | BRESP=2、new_req=0 |
| 25 | reset 复用端口 hazard | 旧 R 被新 AR 消费（反证） |
| 26 | sealed baseline chain | PASS、golden 一致 |

完整机器可读结果：`result.json` / `reports/safety_summary.json`。

## 6. 关键 SHA 与复跑

`SHA256SUMS.txt` 覆盖本目录交付文件；`SOURCE_SHA256.json` 记录：
integrated 快照、本任务 RTL、fixture/golden、门禁输入的 SHA-256。
`result.json` 内含 `gate_context` 与本轮 verdict。

复跑：

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_closeout_safety
bash scripts/run_safety.sh
```

单测：

```bash
vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex \
  +outfile=logs/out.hex +watchdog=40000
vvp build/tb_mutex_p.vvp +memfile=fixtures/mutex_hang_run.hex \
  +watchdog=5000 +mode=2 +expect_iso=1 +expect_fault=1
vvp build/tb_hazard.vvp
```

编译为单线程 `iverilog -g2012`；没有 `-j` 并行。每个仿真都有 `timeout` 和
TB 内 `cyc > watchdog` 双重保护。

## 7. 未完成 / 不能声称

- 完整 CASE0000、591 真 tensor DAG、68 program 的 sealed payload re-lower 和
  原 host executor 仍缺失；本轮只测 integrated 9 节点 exact chain。
- SEQ 的“真实 hung child”是可控 handshake stub；没有 sealed V022 executor 可接。
- FMA/op17、approx、epilogue stream **没有**接进默认路径；第二轮数值结果只作为
  门禁背景引用，本轮未重跑。不能把本轮局部安全测试当成全模型 WER/CER 证据。
- 多 outstanding 峰值 >1、真实 DDR/PS HP 拓扑、CDC/异步 FIFO、综合/STA/板卡、
  300/600MHz 均未测。
- 本轮没有修改 `primary_stream_fix` 或其他 worker；`integrated_copy` 仅只读快照。
