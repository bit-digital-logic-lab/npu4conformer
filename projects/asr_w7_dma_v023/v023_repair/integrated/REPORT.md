# REPORT — V0.23 最终整合（候选可运行，整机验收仍阻断）

日期：2026-10-29  
目录：`/home/yang/Desktop/项目/v023_repair/integrated`  
范围：仅本地逻辑仿真。未综合、未 Vivado/STA、未上板、未 VNC、未 push。
`work/`、原 ZIP、旧候选和其他 worker 目录只读；本目录只新增整合代码、测试、
脚本、日志和报告。

## 0. 结论

**交付了一个真实可运行的精确路径 V0.23 整合候选；没有宣布整机通过。**

- 单次 CSR START 后，PL 自主执行 9 节点 WCPG superplan：
  `IN -> LAY(A) -> LAY(W) -> MAT -> VEC(I48->F32) -> VEC(MUL) -> VEC(ADD)
  -> VEC(F32->I16) -> LAY(final)`。
- 最终 1024 个 I16 与独立 numpy golden **逐位一致**；
- 精确 baseline（sealed vector/layout + separately-run V020 matrix）与 candidate
  **逐位一致**；
- 矩阵 V020 baseline 同 shape 通过，2921 cycles；candidate 1880 task cycles；
- 共享 AXI 账本 `ledger - interval = 0`，tag error = 0；
- 两个错误输入都给出确定 fault 并结束，不挂死。

但新强制门禁的四项独立结论仍是阻断：FMA/approx/stream 数值与协议错误、
sealed payload 未重定位、完整 591 DAG/executor 缺失、matrix/vector/layout
没有 abort/drain、CDC/综合/板卡未测。因此 `result.json` 的
`final_integration_complete=false`，`verdict` 不是 PASS。

## 1. 实际运行了什么（不是只写文件）

入口：`bash scripts/run_all.sh`。关键日志：

| 运行 | 结果 | 证据 |
|---|---|---|
| `tb_v023_integrated` 正常 9 节点 superplan | PASS，done=1，fault=0，23,819 cycles | `logs/integrated_run.log` |
| 输出 vs 独立 golden | 1024/1024 I16 一致，0 mismatch；C48/I48->F32/MUL/ADD/F32->I16 各级也 0 mismatch | `logs/check_integrated.log`, `logs/check_stages.log`, `reports/check_summary.json`, `reports/stage_check.json` |
| 精确 baseline chain（host-sequenced） | PASS，输出与 candidate/golden 一致 | `logs/baseline_chain.log` |
| V020 matrix baseline，M32/N32/K32，同 fixture | PASS，2921 cycles，compute 264 | `logs/base_mx_m32.log` |
| 坏 matrix queue magic | terminal fault 0x03，done=1，10,449 cycles | `logs/bad_queue.log` |
| 坏 vector op19 | terminal fault 0x07，done=1，12,349 cycles；layout 预热 3,072 B，零 vector 数据写 | `logs/bad_vec.log` |
| 项目 skill traffic-ledger | 271 transfers，7 resources，100% 覆盖 | `reports/traffic/` |
| 项目 skill module-activity-waveform | 7 lanes，单 timebase | `reports/integrated_activity.html` |

正常 chain 的关键计数：

```
INTEGRATED_STATUS busy=0 done=1 fault=0 err=00 cycles=23774 completed=9 last=8
INTEGRATED_MATRIX cycles=1880 compute=272 err=00
INTEGRATED_VECLAY vcyc=952 lcyc=6724 vrb=18560 vwb=14336 lrb=5120 lwb=5120
INTEGRATED_AXI rburst=130 wburst=141 rbeats=1828 wbeats=1600 rdstall=391 wrstall=691 tag_err=0
INTEGRATED_END done=1 fault=0 error=00 cycle=23819
INTEGRATED_RESULT PASS
```

## 2. 同批 shape/数值/背压下的 baseline 与 candidate

### 2.1 最终输出

fixture 是 M32/N32/K32、A16/W7、positions=0x3210、clip=1，矩阵整数 golden 来自
`ds_matrix/tests/gen_engine_vectors.py`。随后在 float32 中执行
`* 2^-10 -> + 0.5 -> RNE -> clip i16`，这是独立 golden，不是 RTL 自证。

| 路径 | 输出 |
|---|---|
| candidate 9 节点自主 chain | 1024/1024 I16 与 golden 一致 |
| exact sealed baseline chain | 1024/1024 I16 与 golden 一致 |
| baseline vs candidate | 0 mismatch |

baseline chain 是 **host-sequenced**（TB 逐 descriptor 启动旧引擎），candidate 是
**PL 自主 superplan**；两者使用同一 fixture、同一 BFM、同一 AXI xbar、同一
descriptor 和同一 golden。baseline 的 matrix C48 由单独运行的 V020 matrix
baseline 生成并预装入 BFM（该 baseline 自身 1024/1024 与整数 golden 一致）；
因此 baseline chain 比较的是 vector/layout 精确算术，不把“预装 C48”当成矩阵
计算。

### 2.2 周期（同一 fixture，非板级时间）

| 项目 | exact baseline | candidate |
|---|---:|---:|
| matrix task cycles | 2921 | 1880 |
| matrix compute cycles | 264 | 272（PIPE=4 多 8 拍） |
| layout cycles（3 ops） | 10,386 + 5,198 + 10,402 = 25,986 | 6,724（总） |
| vector cycles（4 ops） | 5,070 + 8,096 + 8,083 + 4,941 = 26,190 | 952（总） |
| vector+layout 合计 | 52,176 | 7,676 |
| integrated chain 总 cycles | 约 55,097（不含 host 间隔，串行上界） | 23,819 |

这不是 153.8s→12.5s→0.15s 的整机收益，也不是 300/600MHz 结论；它只说明同一
逻辑负载下 candidate 的 engine 周期更少，且 matrix/vector/layout 的真实数据
通路走通。

### 2.3 实际流量（AXI 握手）

candidate（`reports/traffic/summary.json`）：

| 资源 | valid bytes | wire bytes | ledger - interval |
|---|---:|---:|---:|
| AXI R | 29,248 | 29,248 | 0 |
| AXI W | 25,600 | 25,600 | 0 |
| AXI R/W 共享 BFM union | 54,848 | 54,848 | -54,848（刻意不加入 per-master 账本） |

按张量：A16 2,048 B、W7 1,024 B、C48 6,144 B、F32 conv/scale/bias 各 4,096 B、
I16 2,048 B、plan 1,792 B、queue descriptor 64 B、payload 640 B。vector+layout
的读写恰好等于 baseline chain 的 BFM 计数（read 1,480 beats = 23,680 B，
write 1,216 beats = 19,456 B）；candidate 多出的 5,568 B read + 6,144 B write
是 plan/queue/payload 与 matrix C48 的真实流量，不是重复搬运。

重复候选：`scalars` 8 次读取共 128 B，唯一 16 B，**重复候选 112 B**（同一
scale/bias 标量按 vector 节点重复读取）。其他 A16/W7/C48/F32/I16 无重复候选。
这是可优化的真实重复，不直接扣成可省带宽。

## 3. 整合架构与接口适配清单

### 3.1 顶层与接口

- `v023_integrated_top`：CSR + WCPG 控制器 + 真实 matrix/vector/layout +
  共享 AXI 集中器；单 `clk`/`rst_n`。
- `v023_axi_shared`：5 read / 3 write masters，`CREDIT=8`、`QDEPTH=32`；
  AR 全局 in-order FIFO 按 owner tag 路由，AW/W/B 按 AW 顺序；tag/length
  错误计数。所有 master 的 AXI 端口形状在顶层显式拼接，未用同名模块覆盖。
- `v023_matrix_queue_engine`：`task_queue`（BACKEND=21）取 64 B V022
  descriptor，映射 `cfg_*`，驱动 `matrix_p2_cluster_v2`；带 terminal
  watchdog 和 isolation。它不是 sealed payload 的重定位执行器。
- `v023_vector_guard` / `v023_layout_guard`：保持原 wrapper 端口，增加
  terminal watchdog；没有 abort/drain 端口，超时只能 isolation，不能声称
  drained。
- `v023_vector_axi` / `v023_layout_axi`：只增加 `USE_APPROX_DIV_SQRT` /
  `MAX_PREFETCH` 参数，默认 exact/16。
- `plan_submit_csr_v023`：统一 CSR、IRQ、done_latched、64-bit 高字快照；
  integrated top 中一个 START、一个 DONE/IRQ。

### 3.2 同名/重复模块处理

- layout 的两个候选都定义 `ddr_layout_engine`；默认 filelist **只**编译
  `ddr_layout_engine_v023_burst.sv`，步进版不编译。
- vector 原 wrapper 是 `ddr_vector_axi`，candidate 是
  `ddr_vector_axi_pipe`/`v023_vector_axi`；integrated top 只实例化
  `v023_vector_guard -> v023_vector_axi`，不实例化 sealed `ddr_vector_axi`。
- matrix candidate 的 `axi_dma_v019.sv` 与 shared copy 同名；filelist 只保留
  `rtl/axi_dma_v019.sv` 一份，matrix cluster 使用自己的
  `axi_dma_v020_multi_v2`。
- `asr_fma_ip` 只有一个 compile-only forbidden stub；op17 未使用，若调用会
  `$fatal`。
- `operand_banks_dual_v1` 在 `operand_banks_dual_v2.sv` 文件中定义，filelist
  只编译该文件，未再添加同名副本。

### 3.3 整合中发现并修复的桥接缺陷（非 worker 算术）

1. 初版 xbar 把 1-based grant 直接存成 owner，且 FIFO 指针用 6 bit 存 32 项，
   在多 burst 后 owner/head/tail 越界为 x，matrix read 卡死。已改为
   `grant-1` owner 和 `$clog2(QDEPTH)` 指针；修正后 matrix/vector/layout
   全部完成。
2. WCPG 的 `vec_ok` 原 ACL 对 op14（I48->F32，a48=1）仍要求 `!a48`，会把真实
   合法 descriptor 判成 0x07。整合 copy 中改为在 op14 时检查 B 可读，
   不放宽任何地址/窗口/overlap 规则。
3. 精确 baseline TB 在同一个 posedge 同时改 descriptor 和 start，旧引擎可能
   采样到旧 descriptor；baseline 控制改为 negedge 设置，消除该测试竞争。
4. graph copy 暴露 `seq_active`，在 SEQ 活跃时 gate MAT/VEC/LAY 的 ready，
   避免 V022 SEQ 与 direct 节点同时占用同一引擎。

## 4. 门禁复核结果（独立意见，未静默忽略）

读取了 `primary_acceptance/REPORT.md` 和四个新任务的 `exit.json`/`result.json`/
`REPORT.md`：

| 任务 | 结论 | 对本整合的影响 |
|---|---|---|
| `gemini_fma_repair` | 自测 6 suites PASS，但独立审计仍 137/8,734 FMA 失配；stream tag/backpressure/param/reconfig 缺陷 | **不集成 FMA**；op17 只用 forbidden stub |
| `gemini_approx_repair` | 单档 5-cycle II=1 结构诚实；DIV/RSQRT factor-2、RSQRT(-0) 符号错误仍在 | **不集成 approx**；默认 exact |
| `ds_numeric_adversarial` | `overall_pass=false`；i48/F32->i16 通过，FMA/approx/stream 阻断 | 整机不得 PASS |
| `ds_integration_audit` | `verdict=blocked`；sealed payload/scratch alias、完整 DAG/executor、abort/drain、SEQ 并发、watchdog 等 19 项 | 整机不得 PASS |

具体独立反例（原文摘要）：

- FMA tie-even：`0x3f800003 * 0x3fc00000` 正确 `0x3fc00004`，DUT
  `0x3fc00005`；极端指数对齐 `0x00800000 * 0x3f800001 + 0x3f800000`
  正确 `0x3f800000`，DUT `0x0e800000`；`inf*0`/`inf-inf` 也错。
- FMA stream：A16 tag 255/256 错；packed 反压 402 次握手/256 beats；
  `param_wr_*` 不生效；运行中 cfg 改到在途 beat。
- approx：`1.0/31.9998` 返回约 2×；`RSQRT(0x7f7fffff)` 约 2×；
  `RSQRT(-0)` 返回 `+inf`；排除 factor-2 后 DIV max 0.11147%，
  SQRT/RSQRT 5.78e-6。
- 模型口径：实际参数镜像对应 512 维 Conformer/Transformer ASR（12 encoder +
  6 decoder，79 LayerNorm），不是旧 KWT-1 的 64 维/99 元素；旧 LayerNorm
  方差范围不得用于当前模型精度论证。
- 集成审计：698 个 tensor（16,771,840 B）与 sealed scratch
  `0x03000000..0x04000000` 重叠；89,118 个旧引用、25,021 个无映射；
  sealed payload 未 re-lower；591 真 tensor DAG/原 executor 缺失；local
  int16 ONNX 是不同 release。

本整合没有把上述任何一项改写成 PASS。我们的 A 路径（exact matrix ->
conversion -> vector -> layout）不经过 FMA/approx，因此可以在不违反门禁的
前提下给出局部可运行证据；但这不等于整机通过。

## 5. Trace / 波形 / 堵塞与重复

- `traces/integrated_trace.csv`：真实 `valid&&ready`/busy 逐周期采样；
  `traces/integrated_trace.jsonl` 由 `scripts/make_integrated_trace.py` 生成。
- `reports/traffic/`：traffic-ledger 的 transfers/tensors/intervals/summary；
  AXI R/W `ledger_minus_interval=0`，7 资源 100% 覆盖。
- `reports/integrated_activity.html`：module-activity-waveform 7 lanes（axi_r,
  axi_w, ddr_bfm, graph, matrix, vector, layout），单 timebase。
- 模块 busy 采样：graph 23,774、matrix 1,900、vector 4,643、layout 16,788
  cycles。**这些是 busy 采样，不是 PE 纯计算时间**；CSR 的 per-op cycles
  合计 vector 952、layout 6,724，明显小于 busy 采样，说明 busy 包含非计算
  驻留/等待。该口径差异尚未修，不能把 busy 当 PE 时间或加速比。
- 堵塞：AXI R `wait_memory` 1,901 cycles，AXI W 1,282，共享 BFM 2,804；
  主要来自 superplan 依赖串行、layout/matrix 等待和 BFM 随机延迟。未采样到
  重复 A16/W7/C48/F32/I16；唯一重复候选是标量 112 B。
- 没有虚构 PE 周期；matrix 的 `compute=272` 来自 worker 真实计数器，
  trace 的 matrix lane 只标 busy。

## 6. 舍入/近似参数

- 默认 exact：vector DIV/SQRT/EXP/LOG 走 `asr_fp32_alu`；FMA op17 不执行。
- 矩阵：A16 有符号、W7p8 含 parity、INT48 累加、positions=0x3210、clip=1；
  C48 6 B 连续流。
- I48->F32：RNE（`int48_float`）；FP32->I16：RNE + `[-32768,32767]` 饱和。
- golden 使用 signed C48 -> `float32` -> `*2^-10` -> `+0.5` -> RNE -> clip；
  1024/1024 与 RTL 一致。
- 近似候选（未集成）：single tier，`LATENCY=5`、`II=1`、128-entry recip LUT、
  256-entry rsqrt LUT、一次 Newton；独立实测 DIV max 0.1080%（报告口径）但
  独立审计发现 factor-2 边界，故不作为验收配置。
- 没有 STA，因此不声明 300/600 MHz、ns 裕量或 CDC 时序。

## 7. 版本 SHA 与证据

`result.json` 内含完整 integrated source SHA；关键：

| 文件 | SHA-256 |
|---|---|
| `rtl/v023_integrated_top.sv` | `a3b75801...` |
| `rtl/v023_axi_shared.sv` | `4f4ab388...` |
| `rtl/v023_matrix_queue_engine.sv` | `4bc44e36...` |
| `rtl/wc_graph_ctrl.sv`（整合 copy） | `a6776253...` |
| `rtl/wc_graph_top.sv`（整合 copy） | `9a8cd823...` |
| `filelist_integrated.f` | `26ba3735...` |

门禁输入 SHA（完整值见 `result.json`）：`primary_acceptance/REPORT.md`
`e0fd6a91...`；`ds_numeric_adversarial/result.json` `2ee4e79d...`；
`ds_integration_audit/result.json` `d0701190...`；`gemini_fma_repair/result.json`
`ceca1ac1...`；`gemini_approx_repair/result.json` `563d17fc...`。

原始证据全部保留在 `logs/`、`traces/`、`reports/`、`fixtures/`，未覆盖
worker 目录。`SHA256SUMS.txt` 覆盖本目录源码/脚本/filelist。

## 8. 受测范围与未测

**受测**：单时钟逻辑；CSR 单 START；WCPG 9 节点依赖；LAY copy mode0；
MAT V022 queue descriptor（M32/N32/K32，A16/W7/C48）；vector op14/2/0/15；
F32/I16 QDQ 边界；共享 AXI R/W 仲裁/credit/tag；坏 queue magic、坏 vector
op19；final I16 golden；baseline 同负载输出；traffic/waveform skill。

**未测/未完成**：

- 完整 CASE0000、591 真 tensor DAG、68 program 的 sealed payload re-lower；
- 全图纯 PL 的 host executor/ONNX 依赖（本机缺失）；
- FMA/op17、approx 集成、epilogue stream 集成；
- matrix/vector/layout 的 abort/drain；plan_v023 child contract 的真实接通；
- mixed SEQ + direct 并发仲裁；hung child watchdog 的故障注入（代码路径有，
  本次未制造真实挂死）；
- 多 outstanding 峰值 >1 的实际工作负载；本 run `rd_peak=wr_peak=1`；
- 真实 DDR/PS HP 拓扑、CDC/异步 FIFO、综合/STA/板卡、300/600MHz；
- 全模型 WER/CER/量化精度；旧 KWT 范围不适用。

## 9. 复跑

```bash
cd /home/yang/Desktop/项目/v023_repair/integrated
bash scripts/run_all.sh
```

单独复跑见 `README.md` / `INTERFACE.md`。所有仿真串行、带 timeout/watchdog；
不修改其他 worker 文件。
