# REPORT — ds_layout_wide (V0.24 Layout 128-bit beat fast path)

日期：2026-10-30  
目录：`/home/yang/Desktop/项目/v024_opt/ds_layout_wide`  
范围：**仅本地逻辑仿真**。未综合、未 Vivado/STA、未上板、未 VNC、未 push。  
`v023_repair/`、`work/`、ZIP、其他 v024 worker 目录均只读；本目录只写自己的
RTL 副本、测试、脚本、日志和报告。唯一执行模型
`opencode-go/deepseek-v4.1-flash`。所有任务结果仍需主 agent 独立验收。

## 0. 结论先行

以 `v023_repair/ds_layout/rtl/ddr_layout_engine_v023_burst.sv`
（SHA256 `4e45a39d…eb893`，也是 `ds_closeout_safety/filelist_safety.f`
选中的 layout 引擎）为冻结基线，交付同端口 drop-in 候选
`rtl/ddr_layout_engine_wide.sv`：

- mode 0 连续 copy：16 字节整拍快路径，源端可任意 16B phase，目标端对齐后
  每拍搬 8 个 A16（bytes=2）或 4 个 32-bit（bytes=4）元素；
- mode 1 / mode 3：32 列行/瓦片行内的 16 字节整拍快路径；行内可跨多个
  8 元素组，32 列边界与 `n` 边界分别处理；
- unaligned 头/尾、零填充、6 字节 C48、mode 2/4、行/瓦片切换全部回退到原
  标量 FSM；`FASTPATH=0` 与基线逐计数器完全一致（70 例）；
- mode 2 只做预取门控 `MODE2_PREFETCH`，实测有收益但不宣称消除全部多读。

**模块级逻辑证据通过；整机/全模型仍未验收。** 没有频率、没有整模型秒数。

最终交付 SHA256：
`rtl/ddr_layout_engine_wide.sv` = `5477651c09c98781de3b6fe5d8a913c93fb685414fc4971685f15f87eae5c365`。
`bash scripts/run_all.sh` 端到端复跑 **rc=0**（`logs/run_all.log` 最后一行
`ALL DONE rc=0`）；`result.json` 的 `rc=0`、`verdict=PASS_LOCAL_LOGIC`
来自同一次复跑。主 agent 仍需独立验收，不能只凭本 worker 退出码。

## 1. 读过的输入与只读边界

已读：`v024_opt/REVIEW_DECISIONS.md`、`REVIEW_INPUT.txt`、`v024_opt/README.md`、
`v023_repair/ds_layout/REPORT.md` 与 `INTERFACE.md`、
`v023_repair/ds_closeout_safety/REPORT.md` 与 `INTERFACE.md`、V0.23 layout
RTL/tests/scripts。`USER_UPDATES.md` 在本任务开始时不存在，已建立并在收尾前
复查（无新指令）。

基线冻结：

| 文件 | SHA256 |
|---|---|
| `rtl/ddr_layout_engine_baseline_burst.sv` | `4e45a39dcb07daeefc190d383ede885e57718f9a60c9d23eda61c4dae11eb893` |
| V0.23 原文件 | 同上 |
| `rtl/u16_divmod.sv` | `5ed69ab1748a321dc65b5e04ef32241b0e9568449707495ce19d6f6358e2f162` |
| `rtl/axi_dma_v019.sv` | `930775c6ab8f1461ccd081f6b81f68b34f2da8f0fdf96c68b51b05f01da9b531` |
| `tests/ddr_layout_axi_ref.sv` | `a4728ffac826ef48776171598ebde6f58c8726f903d8b6af10cedb504c47a4c2` |
| `tests/axi128_memory_bfm.sv` | `dd2e5a075f3605cee30aa5b506bd6271a0b434a12c9d12cc377f12b18c17cf58` |

完整冻结清单见 `SOURCE_SHA256.txt` / `REFERENCE_FREEZE.json`。

## 2. 实现

### 2.1 快路径触发条件

一个 fast step 只产生一个 16 字节目标 beat（`wb_strb=16'hffff`）：

- mode 0：`bytes∈{2,4}`、`total-linear_index>=16/bytes`、
  `destination_address[3:0]==0`；源 phase 任意（读 1~2 条 cache line 后移位）；
- mode 1：`bytes==2`、目标 beat 对齐、`col+8<=32`、`cc+8<=n`、`rr<m`；
- mode 3：`bytes∈{2,4}`、目标 beat 对齐、组不跨 32 列源 tile 行、
  `col+16/bytes<=n`、`row<m`；
- mode 2/4 不进入；`bytes==6` 不进入；源 beat 跨 4 KiB 不进入；目标未对齐
  的头元素、`total` 尾部、零填充元素、任何不满足条件的组都走原标量路径。

### 2.2 源读取与预取

- 源 beat 可跨两条 16B line：第一拍 `FAST_LOOKUP/READ/CAP` 取低 line，
  第二拍取高 line，`{hi,lo}>>(phase*8)` 组装。
- miss 时 **从真正缺失的 line** 发起 fetch（`pf_base_line`），而不是从组起始
  地址重复取已命中的 line；fetch 仍受当前源连续段、4 KiB 页和声明的源
  extent 三重截断。这一修正消除了早期原型在 mode 1 上多读的 4~49 beat/例。
- mode 2 的 `pf_cap` 改用 `MODE2_PREFETCH`（默认 1）；mode 0/1/3 仍用
  `MAX_PREFETCH=16`。

### 2.3 写合并与 4 KiB

- fast beat 直接进入原 16-beat posted buffer；`wb_count==15`、页内最后
  16B（`line[11:0]==0xFF0`）、mode 3 的真实行尾 gap、或完成时 flush。
- 每拍 16B 对齐，单拍不可能跨 4 KiB；burst 在页尾强制截断。
- 快路径回标量时，下一标量元素与最后一个 fast beat 地址连续，因此**不强制
  flush**；由标量 PACK 在真正的行间 gap 或页尾处 flush（`full_n>n` 时如此）。
  mode 3 的 `full_n==n` 行尾本身连续，允许跨行合并；`full_n>n` 行尾强制
  flush。这样 official `unpack_row_fp32` 的写请求从原型 35 降回 19，与基线
  相同，同时保留 gap 安全。

### 2.4 标量 fallback

原 `LOOKUP→…→VALUE→PACK→NEXT` 标量 FSM 未被删除。C48 6B 的
`source_part/value_hi` 清零、`take` 跨行拆分、尾部 strobe 全部保留。
`FASTPATH=0` 只关闭 fast 入口，其余逻辑与基线逐计数器一致。

## 3. 正确性证据

所有正常用例都要求：同一 DDR 初值、同一 descriptor、同一
`axi128_memory_bfm`、同一 testbench 完成口径；`done` 后检查读写/B 全部排空；
失败 rc 非零。每个仿真同时有外部 `timeout` 和 TB 内 `cycle>5,000,000`
watchdog。

| 套件 | 数量 | 参考 | 结果 |
|---|---:|---|---|
| 官方 8 正常 | 8 | 保留 fixture gold；并核对该 gold 与独立 Python 模型一致 | 8/8 |
| 官方 12 错误/ACL/lifecycle | 12 | 与 V0.23 相同 rc/fault/无副作用 | 12/12 |
| 描述符 fuzz | 57 | 与 V0.23 fault/err/processed/memhash 一致 | 57/57 |
| 独立 Python gold | 32 | `scripts/layout_model.py` 逐字节 | 32/32 |
| 保留随机 | 100 | 独立模型 + 基线计数 | 100/100 |
| 新随机/短尾 | 52 | 独立模型 + 基线计数 | 52/52 |
| 新 unaligned/4KiB/行边界 | 53 | 独立模型（目标偏移可变） | 53/53 |
| 标量 fallback 等价 | 70 | FASTPATH=0+MODE2=16 vs 基线，逐计数器 | 70/70 |
| C48 6B 负对照 | 2 | 去掉 `source_part` 清零应失败；候选应通过 | 2/2 |
| mode 2 门控 A/B | 45 | gate1 / gate16 / 基线 | 45/45 |

### 3.1 指标完整性审计（回应主审查 USER_UPDATES）

`scripts/audit_metrics.py` 逐行检查 245 个正常用例（官方 8 + gold 32 +
edge 53 + random 152）：

- 每个用例的 base/wide 都必须是 `pass=1, rc=0`，且 RTL 侧成功后才进入统计；
- `cycles/processed/read_requests/write_requests/read_beats/write_beats/
  read_bytes/write_bytes` 在两侧都必须存在且为整数；缺失即非零失败；
- wide 侧还必须有 `fast_elements/fast_beats/fast_groups`；
- 唯一允许的缺失是 **v023 基线侧的 fast 计数器**（基线 RTL 没有快路径、TB
  也不会打印），共 245 例；审计把它显式计数为
  `allowed_absent_baseline_fast_counters=245`，**不转成 0、不参与快路径统计**；
- `scripts/selftest_failure_rc.sh` 故意从一条 random 记录删除 `wide.cycles`，
  真实审计退出码为 1（`logs/failure_rc_selftest.log` 的
  `FAILURE_PATH_RC_NONZERO_OK`），证明缺指标不会被静默吞掉。

审计结果：`logs/metric_audit.log`（`rows=245 ok=True errors=0`）。

## 4. 性能与流量

全部正常套件（官方 8 + gold 32 + edge 53 + random 152，共 245 例）合计，
同输入、同 BFM、同完成口径：

| 指标 | V0.23 基线 | wide 候选 | 变化 |
|---|---:|---:|---:|
| 总 cycles | 3,700,151 | 2,948,405 | 0.797×（-20.3%） |
| 有效字节（processed×元素字节） | — | 1,748,388 | — |
| 写字节（按 strobe） | 1,748,388 | 1,748,388 | 相同 |
| 读字节 | 1,203,120 | 1,198,416 | -4,704 |
| 读行 overfetch（行） | 13,882 | 13,588 | -294 |
| 读请求 | 34,685 | 35,426 | +741（+2.1%） |
| 写请求 | 7,395 | 7,411 | +16（+0.2%） |
| fastpath 覆盖率 | — | 153,256 / 692,049 = 22.1% | — |

分套件：

| 套件 | 例数 | cycles 基线→wide | 比值 | fast 覆盖 | 读行 overfetch | 读/写请求 |
|---|---:|---:|---:|---:|---:|---:|
| 官方 8 正常 | 8 | 397,315→382,568 | 0.963 | 3.3% | 54→54 | 1,778→1,779 / 746→746 |
| gold 32 | 32 | 515,789→429,870 | 0.833 | 18.2% | 1,990→1,909 | 5,080→5,351 / 935→935 |
| edge 53 | 53 | 460,391→247,818 | 0.538 | 60.9% | 438→438 | 2,363→2,403 / 887→887 |
| random 152 | 152 | 2,326,656→1,888,149 | 0.812 | 20.5% | 11,400→11,187 | 25,464→25,893 / 4,827→4,843 |

官方总比值只有 0.963，是因为 `case0000_embed_conv0`（mode 2，330,327 拍，
78,848 元素）原样保留并主导了总 cycles；**不能用该总比值代表 mode0/1/3**。
官方中真正可走快路径的三例（copy/pack/unpack_row）合计
32,288→17,541 拍（0.543）。

### 4.1 分模式（官方 8 例，同负载）

| 官方用例 | mode | 元素 | cycles 基线→wide | 比值 | fast/processed | 读 beat | 读行 overfetch | 读请求 | 写请求 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| copy_i16 | 0 | 1001 | 6,538→1,149 | 0.176 | 1000/1001（99.9%） | 126→126 | 0→0 | 8→8 | 8→8 |
| pack_matrix_edges | 1 | 4096 | 17,313→11,995 | 0.693 | 1056/4096（有效元素 1056/1155=91.4%） | 166→166 | 21→21 | 51→51 | 32→32 |
| unpack_row_fp32 | 3 (4B) | 1155 | 8,437→4,397 | 0.521 | 960/1155（83.1%） | 297→297 | 0→0 | 66→66 | 19→19 |
| unpack_nchw_fp32 | 4 | 1155 | 10,702→10,702 | 1.000 | 0（无快路径） | 297→297 | 0→0 | 297→297 | 19→19 |
| unpack_c48_compact | 3 (6B) | 1155 | 10,213→10,213 | 1.000 | 0（C48 标量 fallback） | 462→462 | 33→33 | 67→67 | 28→28 |
| conv_padding | 2 | 2048 | 8,245→8,245 | 1.000 | 0 | 16→16 | 0→0 | 15→16 | 16→16 |
| case0000_embed_conv0 | 2 | 78,848 | 330,327→330,327 | 1.000 | 0 | 1,270→1,270 | 0→0 | 1,270→1,270 | 616→616 |
| depthwise_31 | 2 | 1024 | 5,540→5,540 | 1.000 | 0 | 4→4 | 0→0 | 4→4 | 8→8 |

mode 0 的源/目标都对齐时覆盖率接近 100%；mode 1 的 25.8% 是相对含零填充的
总元素，按有效元素 `m*n` 计算为 91.4%；mode 3 的 4B 用例为 83.1%，主要损失
在 `n=35` 的行尾不足一拍。6B C48、mode 2/4 按设计为 0。

### 4.2 fast path 覆盖率

- 覆盖率 = `fast_elements / processed_elements`（候选内部计数器，仅观测）。
- mode 0 copy 接近 100%（只差尾部不足一拍的 0~7 个元素）。
- mode 1/3 的覆盖率受 `n` 和 32 列行边界限制；6B C48 与 mode 2/4 为 0
  （按设计走标量）。
- 总覆盖率被官方 case0000（mode 2，78,848 元素）拉低，因此必须分套件/
  分模式看，不能用单一总比例替代。

### 4.3 overfetch 定义

`overfetch_lines = AXI read beats - 独立枚举的“实际消费到的不同 16B 源行数”`。
该最小行数由 `scripts/metrics.py:touched_lines()` 从 descriptor 语义展开，
不来自候选 RTL。正数表示预取/行粒度多读。

## 5. mode 2 预取门控实测

45 个 mode 2 用例，同一输入、同一 BFM，三种策略：

| 策略 | cycles | 读请求 | 读 beat | 读字节 |
|---|---:|---:|---:|---:|
| V0.23 基线（mode2 prefetch 16） | 1,217,617 | 4,846 | 5,529 | 88,464 |
| gate1（默认） | 1,219,647 | 5,316 | 5,316 | 85,056 |
| gate16 | 1,217,617 | 4,846 | 5,529 | 88,464 |

- gate1 在 7/45 例降低读 beat，38/45 持平，0 例升高；合计 -213 beat，
  单例最大 -168（`r2_21`，正是 V0.23 报告中的过读例）；
- 代价是读请求 +470（+9.7%）、cycles +0.17%；单例最大请求增加 +166；
- 因此**不承诺**“预取门控消除全部多读”，也不把它当验收指标；
  `MODE2_PREFETCH=16` 与 V0.23 mode2 流量逐项相同。

## 6. 4 KiB、unaligned、尾 mask、C48 6B

- BFM 对每条 AR/AW 独立检查 `addr[3:0]==0`、`size=4`、`INCR`、`len<=15`、
  `addr[11:0]+(len+1)*16<=4096`；所有通过用例都真实满足。
- `c0_4k_src`、`c0_4k_dst`、`c0_4k_both` 覆盖源/目标跨 4 KiB；快路径在
  跨页 beat 上主动回退，burst 在页尾 flush。
- unaligned 目标：`c0_dst2_b2`、`c0_both_b2`、`p1_n32_m64_dst2`、
  `t3_64_full64_dst2` 等先由标量补齐头部，再整拍搬运，尾部不足一拍回标量。
- 尾 mask：快路径只写完整 16B beat；任何不足 16B 的尾部仍由标量
  `fragment_mask/take` 生成部分 strobe。
- 32 列行边界：mode 1 在 `col==32` 进入 `FAST_ROW` 更新源行并继续；mode 3
  在源 tile 列边界加 `992*bytes` 修正，在目标行尾强制 flush 后跳行。
- C48 6B：`bytes==6` 永不进入快路径；负对照去掉 `NEXT` 的
  `source_part<=0;value_hi<=0;` 后 `copy_tail_6b` 与
  `unpack_c48_compact` 均真实 FATAL，恢复后均 PASS。

## 7. 未完成 / 不能声称

1. 未跑完整 512 维模型/CASE0000 sealed payload；本目录只是 Layout 模块级证据。
2. 未综合/STA，不声称 Fmax、250/300/600 MHz 或板级 DDR 时间。
3. 共享 DMA 多 outstanding/真实仲裁、reset-in-flight、CDC 未在本任务验证。
4. mode 2 没有整拍快路径；门控只降低部分 case 的读 beat，不消除全部多读。
5. 6B C48 固定走标量，因此其 fastpath 覆盖率为 0 是设计选择，不是遗漏。
6. 统一顶层整合属于 `ds_unified_graph`/主 agent，本目录未改其他 worker。

## 8. 复跑

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_layout_wide
bash scripts/run_all.sh
```

`run_all.sh` 串行编译（-j1），依次生成 golden/edge、编译基线/候选/标量/
门控/负对照、跑官方 8+12、gold 32、edge 53、random 152、fuzz 57、标量等价、
mode 2 A/B、C48 负对照、Verilator lint，最后合并 `logs/summary.json`。
机器可读结果：`result.json`、`logs/summary.json`；唯一编译清单：
`filelist_wide.f`（RTL）与 `filelist_sim.f`（逻辑仿真）。
本次端到端 `run_all.sh` 退出码为 0；每个仿真另有外部 timeout 和 TB 内
watchdog，正常完成前必须排空最后的读/B 事务。
