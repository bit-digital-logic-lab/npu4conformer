# REPORT — V0.24 图调度逐节点时间账与可选下一 payload lookahead

日期：2026-10-30  
目录：`/home/yang/Desktop/项目/v024_opt/ds_graph_prefetch`  
模型：`opencode-go/deepseek-v4.1-flash`  
范围：**仅本地 RTL 逻辑仿真**。未综合、未 Vivado/STA、未上板、未 VNC、未 push。
`v023_repair/`、`work/`、ZIP、其他 worker 目录全部只读；本目录只写自己的
RTL 副本、TB、脚本、冻结参考、日志和报告。

## 0. 结论（先说边界）

本轮最终 `bash scripts/run_all.sh` 的 rc=0，18/18 strict checks 通过；这只代表
**可复跑的图/互连局部候选**，不是整机 V0.24 验收：

- 重建了逐节点时间账和**exclusive union** 周期账；复现并纠正了被审查拒绝的
  “59.8% 控制开销”归因。该数字是“总周期 − 最后一个 op 的 telemetry”的算术
  产物，不是控制开销。
- 在 `wc_graph_ctrl` 中实现了**默认关闭、可选开启**的下一 payload lookahead。
  地址 ACL、依赖前沿、前一/在途节点写描述符自修改禁令、参数只读、SEQ 排除和
  epoch 失效全部实现；错误/abort/isolation 会清 epoch，不把预取当成成功。
- 同一 fixture、同一 BFM、同一 seed、同一完成/排空边界下：
  v023 基线 `23774` 拍，candidate lookahead off `23774` 拍，on `23660` 拍；
  **真实省 114 拍（0.48%）**。最终 512 个 I16 和 1024 个 C48 与独立 gold 全等。
- `header`/节点描述符预取在本契约下**真实省 0 拍**：header + 全部节点必须在
  START 后、任何 dispatch 前取回并做 FNV 校验，没有合法 engine 工作可重叠。
  真正有收益的是 next-payload lookahead。
- 共享 AXI 用真实多在途压力测：5 读主/3 写主、每条 8 burst，单 DDR 端口，
  R owner/tag 路由、B 乱延迟、隔离 gate 全部通过；**没有虚构 multi-HP 带宽**。
- 原有 SEQ 与 MAT/VEC/LAY 等待/inflight 互斥保留；lookahead 在 SEQ 计划里
  自动关闭，`has_seq=1, fetches=0`。

**没有**声称：完整 591 tensor DAG、sealed payload re-lower、FMA/approx/epilogue
整机接入、DDR PHY、多 HP 带宽相加、CDC、综合/STA/板卡、250/300/600 MHz、
整模型 WER/CER 或秒数。

## 1. 读过的输入、冻结参考与只读边界

已读：

- `v024_opt/REVIEW_DECISIONS.md`、`REVIEW_INPUT.txt`、`README.md`；
- `v023_repair/ds_closeout_safety/REPORT.md`、`INTERFACE.md`；
- `v023_repair/integrated/REPORT.md`、`INTERFACE.md`；
- `v023_repair/ds_cycle_chain_compare/REPORT.md`（59.8% 原始口径）；
- `v023_repair/ds_graph/REPORT.md`、`INTERFACE.md`；
- `v023_repair/ds_closeout_safety` 的 RTL/TB/fixture/脚本；
- 本目录 `USER_UPDATES.md`（运行前不存在，未从其他 worker 读取可变状态）。

冻结：

- `reference/REFERENCE_FREEZE.json` 由 `scripts/freeze_reference.py` 生成一次；
  `scripts/verify_reference.py` 在每次 `run_all.sh` 开始拒绝任何 hash 漂移。
- 冻结对象包括 `mem_normal.hex`、`mem_integrated.hex`、`gold_i16.hex`、
  `mat32/exp_c.txt`、`manifest.json`、`init.hex`、`integrated_meta.json` 和
  全部 `baseline_rtl/*.sv`。
- 最终 gold 不是 RTL 自证：`verify_reference.py` 从矩阵整数 gold `exp_c.txt`
  用独立 numpy float32 路径重算 `*2^-10 -> +0.5 -> RNE -> clip i16`，再与
  `gold_i16.hex` 逐字比较（0 mismatch）。plan blob SHA 也与 frozen meta 一致
  （`5c8afc4d…16bec`）。

关键 SHA：

| 对象 | SHA-256 |
|---|---|
| `rtl/wc_graph_ctrl.sv` | `157b25c011aeea079da22e5e6efbb3042657bba7eba2319d3ea86625457f4148` |
| `rtl/wc_graph_top.sv` | `1b8a9bb16cdfa84407b691acbb56b06b5d7872484833d1107bcd102f4baab4ac` |
| `rtl/v023_integrated_top.sv` | `8346769cb0ffa0dba7d79864ad902314ec7196205f2921bb1c695f9eab66c260` |
| `rtl/v023_axi_shared.sv` | `cc4f243980b5fea26516c5f8ff6e4743d0d6642c9fae0d934fb8c52fbe84bfba` |
| `filelist_graph_prefetch.f` | `12ec61ba2637a313241ad5654a50312008513a3545f45bf0ffb37b0c72241d56` |
| `gold_i16.hex` | `296ae0193a999187c13f69631c218136b2d74f46d536b333a7d728a1b0f91ad5` |
| `mat32/exp_c.txt` | `2fd3ba338d626e55ff0c61a251273480a141af87c17fa477f72a61e5e0f8f0f8` |
| `mem_normal.hex` | `1c657402c61de080db36933f2392b2ab21fb07d57c08f7f0e95c458c67c57f37` |

## 2. 纠正 59.8% 假归因

### 2.1 被拒绝的原始算术

`ds_cycle_chain_compare` 原文：

```
总周期 21121
Matrix 1329 + Vector 659 + Layout 6492 = 8480
残差 12641 = 59.8%
```

其中 `Vector 659`、`Layout 6492` 是**最后一个 op 的 telemetry**，不是所有 op
的合计。安全审查已指出真实 CSR 合计是 vector `4643`、layout `16788`。本轮在
同 fixture 上复现了同一算术：

| 口径 | Matrix | Vector | Layout | 合计 | 总周期 | 残差 | 残差占比 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 最后一个 op telemetry | 1880 | 952 | 6724 | 9556 | 23774 | 14218 | **59.805%** |
| 逐 op CSR 合计 | 1880 | 4643 | 16788 | 23311 | 23774 | 463 | 1.95% |

所以 59.8% 不是“控制开销”，而是把最后 op 的计数器当成总和的算术错误。
即使逐 op CSR 合计，也不能直接当作互斥分区：engine 的 busy 区间会重叠/包络，
CSR 合计与 wall-clock 的差只有 463 拍，且不是纯粹的控制时间。

### 2.2 逐周期 exclusive union（真实账）

从 RTL 每周期 trace（`traces/gp_off.csv`）和 RTL 导出的 ledger 交叉核对，
每个 busy 周期只落入一个 exclusive 桶：

| 桶 | off 拍数 | 说明 |
|---|---:|---|
| fetch_only | 383 | 纯取指（header/node/payload），无 engine |
| dispatch_only | 8 | 纯等待 engine handshake |
| engine_only | 23339 | 有 engine 在途，无 fetch/dispatch |
| idle | 44 | scan/依赖等待且无上述活动 |
| fetch_engine | 0 | 取指与 engine 重叠 |
| dispatch_engine | 0 | dispatch 与 engine 重叠 |
| fetch_dispatch | 0 | 取指与 dispatch 重叠 |
| all | 0 | 三者同时 |
| **合计** | **23774** | 等于 `cycles` 和 busy 行数 |

真实非 engine exclusive 开销 = `383 + 8 + 44 = 435` 拍 = **1.83%**，不是
59.8%。`engine_only` 的 23339 拍也正好等于逐节点 engine active 拍数之和
（0+6715+3351+1901+1616+1042+1036+953+6725），说明这张账是自洽的。

### 2.3 逐节点时间账（off run）

`traces/gp_off.csv`，`engine_start/end` 为该节点 engine active 的起止，
`fetch_node/payload` 是按 state 归属的取指拍数，`done` 是 done_mask 位上升沿。
`other` 不是 idle；它是该节点从 descriptor 首次出现到 done 之间未被
engine/fetch/dispatch 覆盖的依赖等待/扫描时间，不能当互斥分区。

| node | type | engine start | engine end | engine cycles | fetch node | fetch payload | done |
|---:|---|---:|---:|---:|---:|---:|---:|
| 0 | IN | — | — | 0 | 28 | 0 | 300 |
| 1 | LAY | 322 | 7036 | 6715 | 28 | 20 | 7037 |
| 2 | LAY | 7068 | 10418 | 3351 | 28 | 23 | 10419 |
| 3 | MAT | 10421 | 12321 | 1901 | 28 | 0 | 12322 |
| 4 | VEC | 12336 | 13951 | 1616 | 28 | 12 | 13952 |
| 5 | VEC | 13972 | 15013 | 1042 | 30 | 13 | 15014 |
| 6 | VEC | 15038 | 16073 | 1036 | 28 | 13 | 16074 |
| 7 | VEC | 16094 | 17046 | 953 | 28 | 13 | 17047 |
| 8 | LAY | 17078 | 23802 | 6725 | 30 | 21 | 23803 |

可见这条链是串行的：每个节点等前驱 done 后才启动，engine 窗口几乎不重叠。
所谓“非引擎 59.8%”主要就是这些 engine 窗口本身，而不是 12k 拍的控制逻辑。

机器可读：`reports/ledger.json`、`reports/node_ledger.csv`。

## 3. 可选下一 payload lookahead

### 3.1 接口

`wc_graph_ctrl` 新增参数：

```systemverilog
parameter integer LOOKAHEAD_EN = 0,      // 默认关闭，保持 v023 数据路
parameter integer LOOKAHEAD_WINDOW = 8   // 有界前向搜索
```

新增状态 `LREQ/LFETCH`，新增输出见 `INTERFACE.md`：`lookahead_valid/hits/
misses/fetches/aborts/epoch` 和 exclusive ledger 计数。`wc_graph_top_v023`、
`v023_integrated_top` 已把信号接到顶层，旧 TB 不接这些输出也能编译。

关于“下一 descriptor”：192B 节点 descriptor 在 START 后一次性取回并做 FNV
校验，已全部缓存，所以不存在可隐藏的“下一节点 descriptor 取指”。这里预取的
是每个节点 dispatch 时才需要的 VEC 64B / LAY 128B **payload descriptor**。
MAT 的 64B queue descriptor 仍由 matrix child 逐条取，本轮没有改它，也不把
它算进 lookahead 收益。

### 3.2 安全契约（实现，不只是口头）

payload 只有在以下全部成立时才预取：

1. **地址 ACL**：`readable()` 通过，且 payload 落在只读 param 或 external 窗口；
   arena payload 不 speculative read。
2. **依赖前沿**：候选节点的 predecessor mask 必须被
   `done_mask | 当前在途 engine 节点` 覆盖，不越过依赖。
3. **自修改禁令**：候选 payload 范围不得与前一个/任何在途节点声明的 output
   范围重叠。当前 ABI 里 VEC/LAY 目的地在 arena、payload 在 param/external，
   这条是 defense-in-depth；不是“假设不会重叠”。
4. **参数只读**：BFM `PROTECT_PARAM=1`，任何 param 写都会 `$fatal`；VEC/LAY
   payload base 也必须在 param 窗口内。
5. **SEQ 排除**：计划里只要出现 SEQ，`has_seq=1`，lookahead 完全关闭；
   不假设 SEQ 对 param 只读。
6. **epoch**：每次 speculative fetch 带 `lu_start_epoch`；START、fault、
   isolation、abort、FINISH 都递增 `lookahead_epoch`，旧 beat 永远不会被
   dispatch。正常 run epoch=2；fault/isolation run epoch=3 或 4，`valid=0`。

SEQ 与 MAT/VEC/LAY 的等待/inflight 互斥保持原逻辑：`direct_idle=~|e_active`，
`seq_active` 覆盖 DISPATCH 等待 + in-flight，MAT/VEC/LAY 仍要求 `!e_active[0]`。

### 3.3 真实测得的收益

同一 `fixtures/mem_normal.hex`、同一 `wc_safety_bfm`、同 seed、同 watchdog：

| 指标 | v023 基线 | lookahead off | lookahead on |
|---|---:|---:|---:|
| 总周期 | 23774 | 23774 | **23660** |
| fetch_only | 383 | 383 | 288 |
| engine_only | 23339 | 23339 | 23087 |
| fetch_engine | 0 | 0 | 243 |
| dispatch_only | 8 | 8 | 8 |
| idle | 44 | 44 | 34 |
| payload fetch cycles | 115 | 115 | 20 |
| lookahead fetch cycles | 0 | 0 | 243 |
| AXI read bursts / beats | 130 / 1828 | 130 / 1828 | 130 / 1828 |
| AXI tag errors | 0 | 0 | 0 |

- `lookahead_hits=6`、`misses=1`、`fetches=6`、`aborts=0`。唯一 miss 是链首
  node1 的 payload（它前面没有可重叠的 engine）；其余 6 个 VEC/LAY payload
  都在前一节点运行时预取成功。
- 总周期 `23774 -> 23660`，**真实省 114 拍（0.48%）**。
- 单端口 burst/beat 数完全不变：lookahead 只是把 payload 取指挪到 engine
  窗口内，没有增加 DDR 流量，也没有 multi-HP 带宽。
- **header 预取真实省 0 拍**。header 取指 `HFETCH`（含 HREQ）12 拍，node
  描述符 `NFETCH` 256 拍；它们必须在 START 后、任何 dispatch 前完成 FNV 校验，
  此时没有任何 engine 工作可重叠。把这段叫“header 预取收益”是不诚实的。
- 收益只有 0.48% 的原因：这条链本身串行，layout/vector engine 占绝对多数；
  payload 取指只有 115 拍，且共享单端口。结果不修饰。

输出/C48：baseline、off、on 的 512 个 I16 与独立 `gold_i16.hex` 均 0 mismatch；
1024 个 C48 与 `exp_c.txt` 均 0 mismatch；三次都 `quiesced=1`、pending=0、
`tag_err=0`。这是**同一完成/排空边界**的比较。

## 4. 共享 AXI 真实多在途压力

`tb/tb_axi_multi.sv` + `tb/axi_multi_bfm.sv`，单 AXI4 128-bit slave 端口，
`v023_axi_shared` 参数 `NR=5,NW=3,CREDIT=8,QDEPTH=32`：

- 5 个读主、3 个写主，每主 8 个 burst，长度 1..8 beat，地址互不重叠；
- BFM 真正接受多条 outstanding AR/AW；R 按 AR 顺序返回；B 按 AW 顺序返回但
  每条随机延迟 0..7 拍，允许 `b_pending>1`；
- 每个 R beat 按地址 pattern 校验 owner 路由，每个 W beat 校验数据与 WLAST；
- 在 `rd_pending>=8` 时插入 `isolate=1` 8 拍，检查 `s_arvalid/s_awvalid/
  s_wvalid` 全 0，且已接受事务继续排空。

实测：

| 指标 | 值 |
|---|---:|
| read bursts / beats | 40 / 180 |
| write bursts / beats | 24 / 108 |
| B responses | 24 |
| per-master xbar peak rd / wr | 7 / 7 |
| 全局采样 max rd_pending / wr_pending / b_pending | 32 / 16 / 4 |
| BFM max rd / aw / b pending | 32 / 16 / 4 |
| tag errors / data errors / WLAST errors | 0 / 0 / 0 |
| isolation handshakes during isolate | 0 |
| iso_blocked cycles | 9 |
| final quiesced / pending | 1 / 0 |

这证明 owner/tag FIFO、B 延迟、`b_pending>1` 和 isolate gate 在真实多 outstanding
下工作；它**不**证明多 HP 端口带宽可相加，也没有 DDR PHY/CDC 模型。

## 5. lookahead 开启后的安全/负例回归

`scripts/run_lookahead_safety.sh`，`tb/tb_lookahead_safety.sv`（从 v023 safety TB
复制后只加 `.LOOKAHEAD_EN(1)` 和 `SAFETY_LU` 打印；TB 内 `$fatal` 使失败非零）。
这个 safety TB 带 SEQ child 模型和不同的 watchdog，因此 normal 的 23805 拍
不能与 `tb_graph_prefetch` 的 23660 拍直接对比；此表只用于终态、gold、互斥和
epoch 检查，周期对照以 §3.3 为准。

| 测试 | 结果 |
|---|---|
| normal 9 节点 | done=1,fault=0,quiesced=1,cycles=23805；I16 gold 0 mismatch；hits=6,misses=1,fetches=6,aborts=0,epoch=2 |
| multitask MAT 2 descriptor | done=1,fault=0；matrix ops=2,total=3768；I16 gold 0 mismatch；hits=6 |
| SEQ 先 / LAY 先 | done=1,fault=0；`seq_direct=0`；`has_seq=1,fetches=0` |
| SEQ dispatch-wait 不接受 | done=1,fault=1,error=0x0E,iso=1,requires_reset=1,seq_dto=1；`valid=0,epoch=3` |
| SEQ 接受但永不 done | done=1,fault=1,error=0x0E,iso=1,requires_reset=1,seq_ito=1；`valid=0,epoch=3` |
| 坏 queue magic | done=1,fault=1,error=0x03,quiesced=1；`aborts=2,epoch=4,valid=0` |
| 非法 vector op19 | done=1,fault=1,error=0x07；`vec_total=0`；`aborts=1,epoch=4,valid=0` |
| 非法 layout mode 7 | done=1,fault=1,error=0x07；`layout_total=0`；`valid=0,epoch=3` |
| C48 读 R 永久不返回 | error=0x0E,iso=1,requires_reset=1；`rd_pending=1,quiesced=0`；`valid=0,epoch=3` |
| matrix C 写 B 永久不返回 | error=0x0E,iso=1；`b_pending=1,quiesced=0`；`valid=0,epoch=3` |
| 隔离后写 START | `BRESP=2`，`new_req=0`，`done_latched=1` |

这些负例证明：lookahead 不会在错误/隔离后把 stale payload 当成功；epoch 会清，
pending 不会因超时清零；SEQ 互斥和现有 watchdog/drain 契约未被破坏。

## 6. 文件、唯一 filelist 与复跑

- 唯一候选编译清单：`filelist_graph_prefetch.f`。默认 `LOOKAHEAD_EN=0`，
  `-DLOOKAHEAD_ON` 只改 TB 的 parameter override，不改变 filelist。
- 基线对照清单：`filelist_baseline_graph.f`，只编译冻结的 `baseline_rtl/`，
  不是候选交付清单。
- `rtl/` 是 v023 `ds_closeout_safety` RTL 的本目录副本；只有
  `wc_graph_ctrl.sv`、`wc_graph_top.sv`、`v023_integrated_top.sv` 有本任务改动。
- `baseline_rtl/` 是冻结的 v023 原文，用于同输入/same-BFM 对照。
- TB：`tb_graph_prefetch.sv`（trace/C48/ledger）、`tb_lookahead_safety.sv`
  （安全负例）、`tb_axi_multi.sv` + `axi_multi_bfm.sv`（互连压力）、
  `wc_safety_bfm.sv`（同 v023 的参数只读 BFM）。
- 所有编译 `iverilog -g2012` 单线程；每个仿真有外部 `timeout` 和 TB 内
  cycle watchdog。`logs/rc.tsv`、`logs/rc_lookahead.tsv` 记录每次 rc。

复跑：

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_graph_prefetch
bash scripts/run_all.sh
```

单独跑关键项：

```bash
python3 scripts/verify_reference.py
python3 scripts/ledger.py --off-log logs/gp_off.log --off-trace traces/gp_off.csv \
  --on-log logs/gp_on.log --on-trace traces/gp_on.csv \
  --json reports/ledger.json --csv reports/node_ledger.csv
vvp build/tb_axi_multi.vvp +watchdog=20000
bash scripts/run_lookahead_safety.sh
python3 scripts/check_results.py
```

`run_all.sh` 只有在 frozen reference、independent gold、baseline/off/on 输出、
C48、ledger、AXI stress、lookahead safety、18 项 strict checks 全部通过时才
返回 0；任一失败返回非零。

## 7. 测了什么 / 没测什么

**测了（本轮真实运行）**：

- v023 基线、candidate off、candidate on 三次同 fixture/BFM/seed 的 9 节点链；
- 最终 I16 512 word + C48 1024×48-bit 与独立 gold；
- 逐周期 exclusive union、逐节点 engine/fetch/dispatch/done 时间账；
- opt-in payload lookahead 的 6 hit/1 miss/0 abort 和 114 拍真实收益；
- SEQ 互斥、SEQ hang wait/run 隔离、坏 queue、非法 vector/layout、R/B 永久
  hold、隔离后 START 拒绝；
- 共享 AXI 40 read/24 write burst 的真实多在途压力、B 随机延迟、b_pending>1、
  isolate gate。

**没测 / 不能声称**：

- 完整 CASE0000、591 真 tensor DAG、68 program 的 sealed payload re-lower、
  原 host executor；
- FMA/op17、approx DIV/SQRT、epilogue stream 的整机接入；
- 矩阵/向量/layout 的 abort/drain 端口（本设计仍只能 isolation，不能伪造
  drained；B 未返回时 `quiesced=0` 是正确结果）；
- DDR PHY、真实 PS HP 拓扑、多 HP 带宽相加、CDC/异步 FIFO；
- 综合/STA/板卡/VNC/push、250/300/600 MHz、整模型 WER/CER/秒数；
- 1024 节点全 DAG 的大规模时序/面积；`MAX_NODES=1024` 的数组只在仿真中实例化。

## 8. 证据索引

- 严格判定：`reports/check_summary.json`（18/18）
- 周期账：`reports/ledger.json`、`reports/node_ledger.csv`
- trace：`traces/gp_base.csv`、`traces/gp_off.csv`、`traces/gp_on.csv`
- 三次输出/C48：`logs/gp_{base,off,on}_{final,c48}.hex`
- AXI：`logs/axi_multi.log`
- lookahead 安全：`logs/lu_*.log`、`logs/rc_lookahead.tsv`
- 源码/输入 SHA：`SOURCE_SHA256.json`、`SHA256SUMS.txt`
- 接口：`INTERFACE.md`
- 结果：`result.json`（含 rc、SHAs、测了什么、未完成）
