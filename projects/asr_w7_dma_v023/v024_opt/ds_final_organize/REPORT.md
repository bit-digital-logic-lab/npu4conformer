# REPORT — ds_final_organize (V0.24 最终整理与清洁导出)

日期：2026-10-30  
目录：`/home/yang/Desktop/项目/v024_opt/ds_final_organize`  
唯一执行模型：`opencode-go/deepseek-v4.1-flash`  
范围：**仅本地 RTL 逻辑仿真**。未综合、未 Vivado/STA、未上板、未 VNC、未 push；
不承诺频率、Fmax 或整模型秒数。

## 0. 结论

已生成 `final_export/`，按
`rtl/{matrix,memory,dma,vector,layout,graph,epilogue,common}`、
`sim/{tb,fixtures}`、`scripts/{sim,analysis}`、`software`、
`docs/{design,verification,performance}`、`skills`、`assets_manifest`
组织。

- 唯一编译清单：`final_export/filelist.f`（51 个 RTL 源文件，51 个唯一 module，
  无重复定义）。
- 唯一入口：`bash final_export/scripts/sim/run_export_all.sh`（仿真 → 独立 judge
  → 汇总 → manifest）。
- 本次在导出目录内真实复跑，主入口 rc=0：fused/fallback/multicons/badflag/
  hold/lane 全部 rc=0，独立 judge `V024_CHECK PASS`；focused baseline smoke 5/5
  通过。
- 集成基线是 `ds_unified_graph` 的 V0.24 小图候选，不是完整 512 维模型。
  独立审查的 AR-012 是统一 result 发布前的快照；本导出按冻结源重新跑，
  但不把模块 PASS 拼成整机/全模型 PASS。主 agent 仍需独立验收。

## 1. 读了什么、只读边界

已读：

- `REVIEW_DECISIONS.md`、`REVIEW_INPUT.txt`、`v024_opt/README.md`、
  `PRIMARY_PROGRESS_REVIEW*.md`、`REPAIR_FOLLOWUPS.json`、项目根 `README.md`；
- v023 的 `integrated`、`ds_closeout_safety`、`ds_closeout_numeric`、
  `ds_closeout_fusion`、`ds_matrix`、`ds_vector`、`ds_layout`、`ds_graph`、
  `primary_stream_fix` 的最新 `REPORT.md`/`INTERFACE.md`；
- `ds_unified_graph/{REPORT,INTERFACE,MERGE_TABLE,result,exit}`；
- `ds_adversarial_review/{REPORT,FINDINGS,result,exit}`；
- 各 V0.24 worker 的 `result.json`/`exit.json`/`USER_UPDATES.md`。

只写本任务目录。`v023_repair/**`、`work/**`、ZIP、其他 worker 目录均未修改。

## 2. 选择

### 2.1 进入唯一 `rtl/` 的集成源

`ds_unified_graph/unified` 的冻结源码，逐字节复制；主要新增：

- `v024_unified_top.sv`、`v024_matrix_queue_engine.sv`；
- 显式 `MATF`/`A16C` 融合描述符（`wc_graph_ctrl.sv`、`wc_graph_top.sv`）；
- `epilogue_stream_engine_v024.sv` + per-column table（32 scale + 32 bias）；
- `matrix_stream_fusion_top_v024.sv` 与 fusion framer/FIFO/blockbuf/writer；
- 修复版 7 级 129 位 FMA `fp32_fma_pipe.sv`（`3c1114bc…`，AR-001 closed）。

`v023_integrated_top` 与 `v023_matrix_queue_engine` 也作为 **baseline smoke**
的唯一源保留；它们与 V0.24 顶层是不同 module，不是重复定义。

### 2.2 未进入导出（保留在原目录）

详见 `final_export/assets_manifest/UNSELECTED.md`。摘要：

| 项 | 处理 | 理由 |
|---|---|---|
| storage v3 写合并 | 延后 | native 通过；generic 跨 4 KiB/背靠背未闭合（AR-008），统一 plan 两 descriptor 触发 MAT watchdog |
| layout wide | 延后 | 统一 plan mode-0 超 20k watchdog，墙钟约翻倍 |
| matrix W reuse | 延后 | 实测 W 读 6144→3072 B 成立，但 ABI 改动未在双顶层重验 |
| fusion dual-bank | 延后 | broadcast-only，未与 per-column 合并 |
| epilogue ping-pong/FP32 | 延后 | AR-006 双通道背压独立未闭合 |
| graph lookahead | 延后 | 自身 rc=1，无 MATF；账本纠正为 1.83%，不是 59.8% |
| vector op17 II=1/4-lane | 延后 | 端口变更；unified 数值路径用 op3/op4 |
| 旧 FMA `b062…` | 替换 | flush 握手 AR-001；选 repair `3c1114bc…` |

没有把 4x4、重复 worker 树、失败实验目录复制进 `rtl/`；原目录、失败日志和
mutant 均未删除、未移动。

## 3. 真实复跑与证据

入口：`final_export/scripts/sim/run_export_all.sh`。串行编译，每个仿真有
shell `timeout` 和 TB watchdog，正常完成检查最后的 B 排空。日志在
`final_export/docs/verification/logs/`，逐 run rc 在 `rc.tsv`。

| 测试 | rc | 结果 |
|---|---:|---|
| fused 小图（MATF + per-column + DIV/SQRT + A16 copy） | 0 | 18,724 cycles；A16 512/512、copy 512/512；`used=1,c48_ddr_bytes=0,a16_bytes=2048`；`b_pending=0,quiesced=1` |
| explicit fallback（2 descriptor + 非 A16C） | 0 | 16,973 cycles；`used=0`；I16 512/512；已排空 |
| multi-consumer fallback | 0 | 19,749 cycles；`used=0`；已排空 |
| MATF 无 `FUSION_ALLOW` | 0 | 383 cycles；`error=0x04`，无融合 |
| fused A16 写 B 永久不返回 | 0 | 30,720 cycles；`fault=1,error=0x0E,isolation=1,requires_reset=1,b_pending=8,quiesced=0`；隔离后无新 AR/AW/W |
| 定向 FMA | 0 | 64/64 单次舍入 gold 一致；64/64 与 mul+add 不同 |
| DIV / SQRT | 0 | worst rel 9.102e-4 / 5.089e-6，容差内 bad=0 |
| baseline smoke | 0 | normal/multitask/bad-queue/bad-vec/hold-B 5/5 `SAFETY_RESULT PASS`（focused，不是 26 项全跑） |

独立 judge 先校验 `REFERENCE_FREEZE.json`；任何 fixture 改动、数值不符、
非排空或错误终态都会非零退出。没有使用旧 JSON PASS、stub 或同源 golden。

## 4. 文件、映射与冻结

- `final_export/filelist.f`：唯一编译清单；
- `final_export/assets_manifest/OLD_TO_NEW.csv`/`.md`：旧→新映射；
- `final_export/assets_manifest/SOURCE_SHA256.json`：每个导出文件 SHA + 来源；
- `final_export/assets_manifest/FILE_SHA256.txt`：可 `sha256sum -c`；
- `final_export/assets_manifest/UNSELECTED.md`：未入选优化及理由；
- `final_export/assets_manifest/MISSING_ASSETS.md`：原模型/大资产缺口；
- `final_export/sim/fixtures/REFERENCE_FREEZE.json`：参考元数据冻结
  （仅路径从 `fixtures/...` 改为 `sim/fixtures/...`，字节未变）；
- `final_export/docs/design/BASE_SOURCE_SHA256.json`：unified 基线每文件 SHA。

`make_manifest.py` 重新解析 filelist，51 个 module 唯一，10 个冻结参考全部
匹配，150 个文件 `sha256sum -c` 通过；导出目录共 159 个文件（含生成的
manifest 文件和 31 个记录日志）。

## 5. 未完成 / 不声称

- 完整 512 维 ASR、591 tensor DAG、CASE0000、sealed payload re-lower；
- 原 ONNX、完整 host executor、WER/CER、量化精度；
- 综合、Vivado/STA、Fmax、资源、功耗、CDC/多时钟；
- 板卡 DDR/HP 拓扑、MIG/PHY、VNC、push；
- 频率目标、整模型秒数；
- 逐 tile per-channel host DMA（本候选是 START 前一次性 64 word 预装）；
- 4-lane op17 FMA；
- 自动融合吞并。

## 6. 复跑

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_final_organize/final_export
bash scripts/sim/run_export_all.sh
```

依赖：Python 3 + NumPy、Icarus Verilog 14（`iverilog -g2012`/`vvp`）、
bash `timeout`、`sha256sum`。脚本会重建 `logs/` 与 `build/`；本次归档的
运行日志已复制到 `docs/verification/logs/`。
