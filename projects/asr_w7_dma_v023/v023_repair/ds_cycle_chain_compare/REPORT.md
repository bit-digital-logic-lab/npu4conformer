# ds_cycle_chain_compare：小链周期对比报告

## 结论（只限被测小链）

在冻结的 `integrated` 快照上，复用真实 RTL 跑通了同一套
`LAY(A) -> LAY(W) -> MAT(32x32x32) -> I48->F32 -> MUL -> ADD -> F32->I16 -> LAY(copy)`
数据链，并用同一张共享 AXI BFM 跑了三组输入/seed/存储延迟/背压完全相同的场景。
六个仿真（候选/基线 × 默认/随机背压/长存储等待）全部完成，最终 i16 输出与独立 gold
512/512 字一致，矩阵 C48 与 `ds_matrix` 整数 gold 1024/1024 一致，watchdog 未触发。

**可比区间总周期（不是整机加速比）：**

| 场景 | 基线 host-sequenced（周期） | 候选 单次 START 超级计划（周期） | 候选-基线差额 | 基线/候选 |
|---|---:|---:|---:|---:|
| 默认 | 53015 | 21121 | -31894 | 2.510x |
| 随机背压 | 55014 | 23744 | -31270 | 2.317x |
| 长存储等待 | 87973 | 33660 | -54313 | 2.614x |

这些数字是**小链从首次启动到最终写响应排空且 done 的仿真周期**，不是 CASE0000、
不是整机、不是板卡时间。基线与候选的控制/接口边界不同（见下），因此不把
2.3~2.6x 解释为整机加速比，只解释为“同负载可比区间”的周期差额。

## 范围与约束

- 仅逻辑仿真；未综合、未 Vivado、未 STA、未上板、未 VNC、未 push。
- 单时钟域；共享 AXI BFM 是逻辑存储模型，不是 DDR/PHY 时序模型。
- 编译使用 `iverilog`（单 job；脚本导出 `MAKEFLAGS=-j1`），未运行无界仿真。
- 只写本目录 `ds_cycle_chain_compare/`；`integrated/`、`work/rtl/`、
  `primary_stream_fix/`、`ds_matrix/tests/` 均只读。
- `integrated` 在快照时仍在被 `ds_integration`（PID 80333）修改；本任务在
  2026-10-29 23:02 复制快照 `snapshot/integrated_20261029T2302/` 后只跑快照。
  `ds_integration` 随后于 23:14 退出，未写本目录。证据见 `logs/readonly_check.txt`。

## 冻结输入与独立 gold

- 矩阵：M=N=K=32，A16/W7，`positions=0x3210`，`clip=1`，fixture seed=1234。
- 矩阵整数 gold：`inputs/mat32/exp_c.txt`（`ds_matrix/tests/gen_engine_vectors.py` 独立生成）。
- 后级 gold：`inputs/gold_i16.hex`，由 exp_c 经独立 numpy float32
  `*2^-10 -> +0.5 -> RNE -> clip i16` 计算，不读 RTL。
- 输入图：`inputs/mem_integrated.hex`；其中 plan blob 的 SHA 与
  `integrated_meta.json` 的 `plan_sha256` 一致。
- `scripts/verify_inputs.py` 已复核：exp/init SHA、plan SHA、重新计算的 gold 全部匹配
  （`reports/input_check.json`）。

关键 SHA：

| 对象 | SHA-256 |
|---|---|
| `inputs/mem_integrated.hex` | `1c657402c61de080db36933f2392b2ab21fb07d57c08f7f0e95c458c67c57f37` |
| `inputs/gold_i16.hex` | `296ae0193a999187c13f69631c218136b2d74f46d536b333a7d728a1b0f91ad5` |
| `inputs/mat32/exp_c.txt` | `2fd3ba338d626e55ff0c61a251273480a141af87c17fa477f72a61e5e0f8f0f8` |
| plan blob | `5c8afc4d8fe5b30317562e6474a8e79d56b03dd57617186f08dda05fdad16bec` |

全部输入、快照源码、本目录源码、日志的逐文件 SHA 在 `SOURCE_SHA256.json`。

## 场景定义（候选与基线完全相同）

BFM 统一为 `rtl_harness/axi128_bfm_scenario.sv`，`seed=1`：

| 场景 | 读 burst 起始延迟 | 写响应延迟 | 背压/间隔 |
|---|---:|---:|---|
| default | 0 | 0 | 所有 ready 恒 1，beat 间 0 拍 |
| rand_bp | LFSR 0..3 拍 | LFSR 0..3 拍 | AR/AW/W ready LFSR 随机拉低；beat 间 LFSR 0..3 拍 |
| long_wait | 48 拍 | 48 拍 | beat 间 1 拍 |

同一场景下候选和基线使用同一 BFM 实例参数、同一输入图、同一 seed、同一存储延迟和背压。
长等待不是靠“记账”加出来的，BFM 真正把 R/B 延后。

## 两个 DUT 的边界

- **候选**：`v023_integrated_top`，主机只写 plan_base/plan_count/START；图控制器、
  矩阵队列、向量、布局和共享 AXI 交叉开关都在 DUT 内。候选的 9 个节点包含
  IN 根节点，实际计算链与基线相同。
- **基线**：`tb_chain_baseline` 由主机依次启动 8 个描述符；矩阵用 sealed
  `block_engine_banked_v020 + block_storage_dma_wide4 + axi_dma_v019`，
  向量/布局用 sealed `ddr_vector_axi/ddr_layout_axi`，共享同一 `v023_axi_shared`
  测试台交叉开关和同一 BFM。
- 基线 `work/rtl/block_engine_l1bank_v020.sv` 为通过 Icarus elaboration，只把
  `beat/run_cycle/collect/quadrant/transfer_slot/sums` 的声明移到使用前，
  **没有逻辑改动**；diff 见 `logs/baseline_compat.diff`。
- 因控制边界不同（基线 8 次 host start、单在途 `axi_dma_v019`；候选 1 次 START、
  P2 cluster/多 DMA/图控制），本报告只给可比区间周期和差额，不给整机加速比。

## 周期拆分

### 1) 总周期与引擎自计数

“引擎自计数”取 DUT 的 `matrix_cycles`、CSR 累计的 `vector_cycles/layout_cycles`；
“残差”= 总周期 - 三个引擎自计数之和，包含图调度、握手、guard、共享端口等待等，
**不是**虚构的 PE 时间，也不与引擎周期相加成另一个总周期。

| 场景 | 基线 M / V / L / 和 / 残差 | 候选 M / V / L / 和 / 残差 |
|---|---|---|
| default | 2980 / 25688 / 24329 / 52997 / 18 | 1329 / 659 / 6492 / 8480 / 12641 |
| rand_bp | 3315 / 26143 / 25538 / 54996 / 18 | 1763 / 1009 / 6688 / 9460 / 14284 |
| long_wait | 4888 / 28018 / 55049 / 87955 / 18 | 5061 / 1763 / 7380 / 14204 / 19456 |

- 候选的 matrix/vector/layout 窗口与引擎自计数不同：例如 default 的 layout
  `busy` 窗口 16232 拍，而 layout 引擎自计数只有 6492 拍（3 个 layout 节点之和）。
  窗口包含 guard/调度包络，报告中以引擎自计数做拆分，窗口原始值保留在日志。
- 候选 default 的图控制器 `operator_cycles=20841`，其中引擎自计数 8480，
  差值 12361 是图/guard/握手/共享端口等待等“非引擎 active”时间。该差值不冒充
  矩阵/向量/布局计算周期。图控制器 plan/节点 fetch 自计数分别为 203/380/1154 拍
  （默认/随机/长等待），矩阵队列描述符 fetch 自计数分别为 8/17/59 拍，两者不要混淆。
- 长等待下，候选矩阵 5061 拍反而比基线 4888 拍多 173 拍（+3.5%）；这是实测结果，
  不修饰。候选矩阵的 C48 收集在长等待下更敏感（`c_collect_cycles=3753`），
  基线矩阵的 `scalar_cycles=1537`、`rdwait/wrwait=966/1587`。

### 2) 矩阵内部等待

| 场景 | 基线 matrix cycles / compute / rdwait / wrwait / scalar | 候选 matrix cycles / compute / queue / engine_wait / fetch / c_collect |
|---|---|---|
| default | 2980 / 264 / 210 / 435 / 1537 | 1329 / 272 / 1345 / 1335 / 8 / 825 |
| rand_bp | 3315 / 264 / 450 / 530 / 1537 | 1763 / 272 / 1788 / 1769 / 17 / 985 |
| long_wait | 4888 / 264 / 966 / 1587 / 1537 | 5061 / 272 / 5128 / 5067 / 59 / 3753 |

候选的 `queue/engine_wait/fetch/c_collect` 是矩阵队列适配器和 P2 cluster 的内部计数，
有重叠，不能相加当成总周期。

### 3) 共享 AXI 等待

| 场景 | 候选 xbar rd/wr stall | 候选矩阵 AR/AW/W 等待 | 候选向量 AR/AW/W 等待 | 候选布局 AR/AW/W 等待 | 候选 BFM read/write busy、B 等待 |
|---|---:|---:|---:|---:|---:|
| default | 160 / 1 | 160 / 1 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 1828 / 1932 / 0 |
| rand_bp | 435 / 41 | 401 / 18 / 63 | 25 / 17 / 104 | 4 / 6 / 53 | 4116 / 2361 / 209 |
| long_wait | 790 / 49 | 790 / 49 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 9766 / 8700 / 6768 |

基线同样场景的共享端口：default/short 的 xbar stall 为 0/0，BFM read/write busy
1672/3952；rand_bp xbar AR/AW/W 114/104/381，BFM 3817/4932、B 等待 603；
long_wait xbar 0/0，BFM 22708/23144、B 等待 19200。

说明：`BFM read/write busy` 包含正常 payload 传输和 B 等待，不是“纯等待”，
不能直接加到总周期；它与 xbar/per-engine stall 一起用于定位长等待来源。
长等待场景下主要增量在 BFM R/B 延迟和候选矩阵的 AR 等待，不在向量/布局端口争用。

## 输出与 gold 核对

每个场景、每个 DUT 均检查：

- 最终布局输出 512 个 32-bit 字 vs `gold_i16.hex`：**0 mismatch**；
- `stage_c48.hex` 重建 1024 个 C48 vs `exp_c.txt`：**0 mismatch**；
- `CAND_RESULT PASS` / `BASE_RESULT PASS`，无 watchdog。

原始输出和日志在 `runs/<scenario>/<candidate|baseline>/`。
`result.json` 中的 `all_outputs_and_c48_match_gold=true` 是对这 6 个运行的汇总，
不是“模块 PASS 拼成系统 PASS”。本任务的状态仍是
`small_chain_logic_pass_full_system_pending`。

## primary_stream_fix 是否计入

已读 `primary_stream_fix/INTERFACE.md` 和 `REPORT.md`：

- 它是 4-lane epilogue 流式模块，新增 `a16_packed_tag`，参数 addr0=scale、
  addr1=bias，模块级 65 项回归通过；报告中的 267 拍 vs 旧 394 拍是
  **模块 testbench 周期**。
- 冻结的 `filelist_integrated.f` 中没有 `epilogue_stream_engine`/`fma_stage`，
  当前矩阵到向量的路径仍然是 C48 写回存储再由 vector 读取，**没有接融合**。
- 因此本报告**没有把 127 拍 packed 输出收益或它的模块 PASS 算进来**。
- 本链没有使用 FMA 算子（op17）；`fma_forbidden_stub` 仅在链接期提供接口，
  一旦真的调用 FMA 会 `$fatal`，本次未触发。没有用 stub 替换实际参与运算的算术。

## 复跑

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_cycle_chain_compare
./run_all.sh
```

脚本执行：输入/gold 复核 → 单 job 编译候选与基线 → 三种场景各跑候选/基线 →
输出与 C48 核对 → `result.json`/`SOURCE_SHA256.json` 更新。单次全量约 2 分钟
（long_wait 候选约 50 秒）。不运行无界仿真，每个 vvp 有 `timeout 240` 和 TB
`+watchdog=120000` 双层截止；watchdog 触发时会打印图/矩阵/xbar/BFM 状态。

Watchdog 可诊断性自测（预期失败，不进入 PASS 统计）：`run_all.sh` 用
`+watchdog=100` 故意截断默认场景，要求进程非零退出且日志出现
`WATCHDOG_FIRED`；当前证据 `runs/watchdog_selftest/candidate/run.log`
显示 `waiting_done cycle=100`，并打印图/矩阵/xbar/BFM 状态。该自测证明
watchdog 不是空壳，也不把失败运行算成通过。

单独复跑一个场景（示例）：

```bash
cd runs/default/candidate
vvp ../../../build/tb_candidate.vvp \
  +memfile=../../../inputs/mem_integrated.hex +outfile=out.hex \
  +watchdog=120000 +lat_mode=default +seed=1
```

基线把 `tb_candidate.vvp` 换成 `tb_baseline.vvp`，并加
`+exp=../../../inputs/mat32/exp_c.txt`。

## 限制与未测

1. **只覆盖 32x32x32 小链**；不是 CASE0000、不是完整模型、不是外层 591 队列，
   也没有官方 FMA/模型级 WER/CER 证据。
2. **控制/接口不同**：基线是 host 逐描述符启动，候选是单 START 图自治；
   不能把区间比值直接外推为整机加速比。
3. **共享 AXI 是逻辑 BFM**：没有 DDR PHY、bank/row、真实带宽和 CDC；所有周期是
   单时钟仿真拍数，不是 ns、不是板卡主频。
4. **未综合/STA**：不声称 300/600 MHz，不声称时序收敛。
5. **primary_stream_fix 未接入**：融合收益未计入；当前链仍是 C48→存储→vector。
6. **矩阵基线源码兼容处理**：只移动声明顺序以通过 Icarus；diff 已保留，逻辑未改。
7. 候选 `layout_busy` 包络与 layout 引擎自计数差异较大，报告已分别列出；不要把
   包络值当成单节点 layout 执行周期。
8. 快照之后 `integrated` 可能继续变化；本报告只对
   `snapshot/integrated_20261029T2302/` 的 SHA 负责。

## 证据索引

- 输入复核：`reports/input_check.json`、`logs/verify_inputs.log`
- 编译：`logs/compile_candidate.log`、`logs/compile_baseline.log`
- 六个原始运行：`runs/{default,rand_bp,long_wait}/{candidate,baseline}/run.log`
- watchdog 自测：`runs/watchdog_selftest/candidate/run.log`（预期非零退出）
- 输出：`runs/*/*/out.hex`、`runs/*/*/stage_c48.hex`
- 汇总：`result.json`、`reports/check_results.log`
- 源码/输入/日志 SHA：`SOURCE_SHA256.json`
- 只读与快照证据：`logs/readonly_check.txt`
- 基线声明移动 diff：`logs/baseline_compat.diff`
- 阶段记录：`progress.json`
