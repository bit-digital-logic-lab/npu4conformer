# REPORT — ds_unified_graph (V0.24 unified candidate)

日期：2026-10-30  
目录：`/home/yang/Desktop/项目/v024_opt/ds_unified_graph`  
唯一执行模型：`opencode-go/deepseek-v4.1-flash`  
范围：**仅本地逻辑仿真**。未综合、未 Vivado/STA、未上板、未 VNC、未 push。
不承诺频率、整模型秒数或完整 591 tensor DAG。

## 0. 结论

已搭建 `unified/` 统一候选：

- 顶层以 `v023_repair/ds_closeout_safety` 的可靠收尾为基线，逐字节复制后再改；
- 新增**显式**融合 MAT 描述符（`MATF` / `A16C`，header `FUSION_ALLOW`），
  **不做未经证明的自动吞并**；不满足条件时走旧 C48 路径；
- 每列 scale/bias（32 项表）与单次舍入 FP32 FMA 已接入融合 MAT；
- 小图同时包含矩阵融合 + per-channel + DIV + SQRT + A16 layout copy；
- 独立 gold、独立 judge、真实 RTL 仿真、每个仿真有 `timeout` + TB watchdog；
- 正常完成已检查最后的 A16/C48 B 响应排空（`b_pending==0, quiesced==1`）；
- 故障注入以 `fault=1,error=0x0E,isolation=1,requires_reset=1,b_pending>0,
  quiesced=0` 结束，未把超时清成成功；
- 失败会让 `scripts/run_v024.sh` 非零退出；不使用旧 JSON PASS，不用 stub
  或同源 golden 自证。

**未通过/未完成**：整机 591 DAG、sealed payload re-lower、板级、CDC/STA、
综合、频率、全模型 WER/CER。存储 v3、layout-wide、W-reuse、fusion dual-bank、
epilogue ping-pong、graph lookahead、vector op17 均在统一回归中**延后**，
原因见 `MERGE_TABLE.md`，没有强行塞入。

## 1. 读过的输入与只读边界

已读：

- `v024_opt/REVIEW_DECISIONS.md`、`REVIEW_INPUT.txt`、`v024_opt/README.md`；
- `v023_repair/ds_closeout_safety/REPORT.md`、`INTERFACE.md`、`filelist_safety.f`；
- `v023_repair/integrated/INTERFACE.md`、`primary_stream_fix/INTERFACE.md`、
  `ds_closeout_fusion/INTERFACE.md`；
- 各 V0.24 worker 的早期 `INTERFACE.md`、`result.json`、`exit.json`、
  `ds_adversarial_review/FINDINGS.md`。

边界：只写本任务目录；`v023_repair/**`、`work/**`、ZIP、其他 worker 目录
全部只读；没有修改任何其他 worker 的源码。协作只通过 `INTERFACE.md`、
`MERGE_TABLE.md`、本报告和 `STAGE_FOR_REVIEW.md`。

## 2. 基线与来源

`unified/rtl` 初始等于 `ds_closeout_safety/rtl`（逐字节）。`SOURCE_SHA256.json`
记录每个基线文件的 SHA-256、统一目录中的 SHA-256 以及是否改动。被显式改动的
基线文件只有：

| 文件 | 改动 |
|---|---|
| `rtl/wc_graph_ctrl.sv` | 显式 MATF/A16C 描述符、consumer ledger、融合/回退门控 |
| `rtl/wc_graph_top.sv` | 暴露 `matrix_fused/pc_en/pc_base/fma_mode/relu` |

新增副本/模块不覆盖基线语义：`v024_unified_top.sv`、
`v024_matrix_queue_engine.sv`、`epilogue_stream_engine_v024.sv`、
`epilogue_lane_v024.sv`、`epilogue_i48_to_f32_v024.sv`、
`epilogue_fma_stage_v024.sv`、`matrix_stream_fusion_top_v024.sv`。

## 3. 显式融合 MAT 描述符（不自动吞并）

### 3.1 描述符

- header word 3 bit16 = `FUSION_ALLOW`（`0x00010000`）。
- MAT 节点 word14 = `MATF`：
  - `[31:16]=0x4D41`，`[15:14]=0`（A16 输出），
  - `[13]` per-channel 表使能，`[12]` ReLU，`[11:10]` FMA mode
    （0 conv-only / 1 scale+bias / 2 scale-only），`[9:0]=0`。
- MAT 节点 word15 = 保留参数块基址（本候选由 host 一次性预装，置 0）。
- 下游 A16 消费者 word14 = `A16C`（`0x41313643`），word15=0。

### 3.2 回退规则（保守）

只有以下全部成立才启用融合：

1. header `FUSION_ALLOW=1` 且 word14 语法合法；
2. `queue_count==1`（多 task/动态参数列表不融合）；
3. 该 MAT 的所有消费者都显式带 `A16C`，或该节点是 terminal `OUTPUT`；
4. 节点没有 fault。

否则 `mat_fused=0`，`v024_matrix_queue_engine` 走原有 `matrix_p2_cluster_v2`
（C48 输出）。旧的 V0.23 负例“word14/15 非零但 header 未允许”仍然报
`0x04`，不会因为新特性被放宽。

### 3.3 为什么不是自动吞并

融合候选从不检查“后继看起来像 epilogue”就吞并。后继必须由 plan 作者显式
标记 `A16C`；多 task 一律回退。这避免了 REVIEW_DECISIONS 第 5、8 条反对的
“未经证明的自动吞并”。

## 4. 每列 scale/bias 与单次 FMA

`epilogue_stream_engine_v024`：

- 32 项 scale + 32 项 bias 表；`param_wr_addr 0..31`=scale，`32..63`=bias，
  `64/65`=广播 scale/bias（旧语义）。
- C48 流是 **quadrant-major**：一段 = 一个 16×16 quadrant 的 16 列一行；
  列号 = `16*quadrant_col_half + 4*pair_in_segment + lane`。这是集成时实际
  发现并修正的映射（见 §6）。
- scale/bias 随数据一起经过 `epilogue_i48_to_f32_v024` 的 S1/S2 寄存，
  不直接组合送入 FMA，避免 AR-004 的 +2 beat 错位。
- 数值链：I48→F32（RNE/FTZ）→ **单次舍入 FP32 FMA**→可选 ReLU→I16
  （RNE + 饱和）。不是先 mul 再 add。

`fp32_fma_pipe` 采用 `ds_repair_fmaflush` 的修复版
（`in_ready=rst_n&&!flush&&…`，`out_valid=…&&!flush`），关闭 AR-001 的
flush 握手漏洞；端口/延迟契约不变（7 级、II=1）。

## 5. 合并与延后

详见 `MERGE_TABLE.md`。摘要：

| 项 | 决定 | 原因 |
|---|---|---|
| `ds_repair_fmaflush` 7 级 FMA | **合并** | 同端口、数值 bit-identical、AR-001 修复 |
| `ds_storage_write` v3 | 延后 | 单 task native 通过，但两 descriptor 的 legacy 队列在统一回归中 MAT watchdog `0x0E`，输出全零 |
| `ds_layout_wide` | 延后 | 本 plan 的 mode0 copy 使 LAY 超过 20k MAT watchdog，Icarus 墙钟约翻倍 |
| `ds_matrix_reuse` | 延后 | ABI 增加 `cfg_w_reuse`、独立 A/W stage release；未在 fused/legacy 双路径重验 |
| `ds_fusion_buffers` dual-bank | 延后 | dual top 仅广播参数，与 per-channel 表合并需新顶层 |
| `ds_epilogue_channels` ping-pong/FP32 | 延后 | 端口更宽，AR-006/AR-007 未关；本候选不需要 FP32 consumer |
| `ds_graph_prefetch` | 延后 | 整文件 controller 变体不含 MATF，且其自身 result rc=1 |
| `ds_vector_fma` / `ds_resume_vector` | 延后 | 增加 `abort/aborted` 端口；本图 DIV/SQRT 用原 approx core |

## 6. 集成中发现并修正的问题

1. **per-channel 列映射错误**：最初按“每 beat 4 列、32 列一行”索引，A16
   前 16 个元素对、之后错。对照 `fusion_c48_framer` 后确认 C48 是
   quadrant-major（一段 16 列），改为
   `col=16*half+4*pair+lane`，A16 512/512 全等。
2. **旧/新 AXI 双驱动**：矩阵 child 同时把 cluster 和 fusion 的输出接到
   `rd_*`/`wr_*`，导致 `z`。改为全部 `cl_*`/`fu_*` 再 mux；融合路径才真正
   拿到读口。
3. **telemetry 口径**：`stat_c48_beats` 是处理 beat 数，不是 DDR 字节；
   `stat_a16_words` 是 128-bit 字数。改为 `stat_c48_ddr_bytes` 和
   `a16_words*16`，融合路径证明 C48 DDR=0、A16=2048 B。
4. **per-channel 恢复**：`beat_cnt` 在 abort/新 config 时清零，避免 abort 后
   列号残留。
5. **仿真脚本**：`run_v024.sh` 逐仿真 `timeout`，judge 独立；fixture
   `REFERENCE_FREEZE.json` 先校验，防止“改 gold 过测试”。

## 7. 测试与结果

唯一入口：`unified/filelist_v024_unified.f`；复跑：
`bash unified/scripts/run_v024.sh`（编译 `-j1`，每个仿真有 `timeout`）。

| 测试 | 结果 |
|---|---|
| fused 小图：MATF + per-channel + DIV + SQRT + A16 copy | `done=1,fault=0,error=0,cycles=18724`；A16 512/512、copy 512/512 与独立 gold 全等；`FUSION used=1 c48_ddr_bytes=0 a16_bytes=2048`；`b_pending=0,quiesced=1`；rc=0 |
| fallback：MATF 请求但 `queue_count=2` + 非 A16C consumer | `used=0,cycles=16973`，legacy C48；I16 512/512 与独立 gold 全等（v2 cluster；v3 延后）；rc=0 |
| 多消费者：MATF `count=1`，一个 A16C + 一个未标记 consumer | `used=0,cycles=19749`，回退 legacy C48；done=1,fault=0；rc=0 |
| header 未允许但节点带 MATF | `done=1,fault=1,error=0x04,cycles=383`，未执行任何融合；rc=0 |
| fused A16 写 B 永久不返回 | `fault=1,error=0x0E,isolation=1,requires_reset=1,b_pending=8,quiesced=0,cycles=30720`；隔离后新 AR/AW/W=0；rc=0 |
| 64 条定向 FMA vs mul+add | RTL 与单次舍入 gold **64/64 bit-exact**；64/64 与 mul+add 不同；rc=0 |
| DIV / SQRT | 最大相对误差 DIV=9.102e-4、SQRT=5.089e-6，均在冻结容差内；flag/approx 语义见 `v024_ref.json` |

最终一次入口脚本运行：`RUN_V024_PASS`，`logs/run_v024_final.log` 与
`logs/rc.tsv` 六个仿真全部 `rc=0`。

独立 gold 来自 `scripts/gen_v024_graph.py`：ds_matrix 的独立整数模型 →
numpy float32 → 单次舍入 FMA → RNE/clip；不读 RTL 输出。DIV/SQRT gold
由输入数组独立计算。所有 fixture/gold SHA 冻结在 `REFERENCE_FREEZE.json`。

### 7.1 回归范围说明与 base smoke

上述 6 个仿真是**统一候选**的验收；不是 V0.23 的 26 项异常收尾全跑。

为避免把“默认路径未回归”建立在旧 PASS 上，另跑了定向 base smoke：
`unified/scripts/run_base_smoke.sh` 用统一后的 controller/top 重编译
`tb_safety_integrated`，覆盖：

| base smoke | 结果 |
|---|---|
| `safety_normal`（默认 header 未允许融合，9 节点 exact） | rc=0，`SAFETY_RESULT PASS` |
| `safety_multitask`（MAT 队列 2 descriptor） | rc=0，`SAFETY_RESULT PASS` |
| `bad_queue_magic`（错误码 0x03） | rc=0，`SAFETY_RESULT PASS` |
| `bad_vec_op`（错误码 0x07） | rc=0，`SAFETY_RESULT PASS` |
| `hold_b_c`（B 永久不返回，0x0E 隔离） | rc=0，`SAFETY_RESULT PASS` |

日志：`unified/logs/base_*.log`、`unified/logs/run_base_smoke.log`。
这些 timeout 用 180–360s；原 `run_safety.sh` 的 90/120s 在本机高负载下会
把仍在推进的 `safety_normal` 杀掉（rc=124），且 `run_safety.sh` 与
`run_v024.sh` 共用 `logs/rc.tsv`，不能并发跑。因此本报告**不**声称
“V0.23 26 项全通过”；只声称统一候选 6 个仿真 + 独立 judge + 上述 5 项
base smoke 通过。`wc_graph_ctrl/top` 的改动只增加显式融合分支，默认
header 未允许时行为与 V0.23 相同；未用旧 PASS 代替。

## 8. 未完成 / 不声称

- 完整 591 tensor DAG、sealed payload re-lower、host executor；
- 综合、Vivado/STA、CDC/异步 FIFO、板卡、VNC、push；
- 频率、Fmax、整模型秒数、WER/CER；
- 真实 DDR/HP 拓扑、多 HP 带宽相加；
- 自动融合吞并；
- 存储 v3 / layout-wide / W-reuse / fusion dual-bank / epilogue ping-pong /
  graph lookahead / vector op17 的整机接入（见 `MERGE_TABLE.md`）；
- per-channel 表由 host 在 START 前一次性预装 64 word；不是每 tile host DMA，
  也不是 PL 自主 DDR 预取。

## 9. 文件与判据

- `unified/filelist_v024_unified.f`：唯一编译清单；
- `unified/scripts/run_v024.sh`：生成 fixture → 编译 → 5 仿真 → judge → SHA；
- `unified/scripts/check_v024.py`：独立判据，任何数值/终端状态不符非零退出；
- `unified/REFERENCE_FREEZE.json`：参考 SHA；
- `unified/logs/rc.tsv`：每次仿真的 rc/耗时（由入口脚本写）；
- `unified/SHA256SUMS.txt`：交付文件 SHA；
- `SOURCE_SHA256.json`、`MERGE_TABLE.md`、`STAGE_FOR_REVIEW.md`。

最终 `result.json` 记录 rc、SHA、测了什么、没做什么；`exit.json` 由
supervisor 在进程退出时写。**主 agent 验收不因 exit 0 自动通过**：本报告
的“通过”只对应上表 6 个真实仿真和独立 judge。
