# REPORT — V0.24 Matrix C48 写合并 + 地址校验寄存级

日期：2026-10-30  
任务目录：`/home/yang/Desktop/项目/v024_opt/ds_storage_write`  
范围：**仅逻辑仿真**。未综合、未 Vivado/STA/DRC、未 CDC、未上板、未 VNC、未 push；
不承诺频率、Fmax 或整模型秒数。`v023_repair/`、`work/`、ZIP 和其他 worker 目录只读。
执行模型：`opencode-go/deepseek-v4.1-flash`（本 worker 唯一执行模型）。

## 1. 结论与 rc

- `bash scripts/run_all.sh` 本次全新编译/运行：**rc=0，28 个仿真 run 全部 PASS/PASS_FAULT，
  0 个失败步骤**。没有复用任何旧 JSON PASS 或旧日志；脚本启动时删除旧 `run_*.log`。
- 候选：`block_storage_stream_v3` + `block_engine_prefetch_v3` + `matrix_p2_cluster_v3`。
- 同输入、同 BFM、同完成/排空边界下，K32 `long_wait`（LAT=48）：
  - v023 v2：**4428 周期**，65 个写 burst，`c_collect=3777`；
  - v3：**2616 周期**，24 个写请求/burst，`c_collect=260`；
  - **减少 1812 周期，v2/v3 = 1.6927×**（只限该受测小链，不是整机加速比）。
- **只把 B_OUT 加大不能修因**：同一 v2 在 `WR_OUT=64` 下仍是 **4428 周期 / c_collect=3777**，
  与 `WR_OUT=8` 逐周期相同。原因是 DMA 的 request 上下文在 B 排空前不接下一笔；
  真正有效的是把 64 个 96 B 小段合并成 24 个合法大请求。
- v3 的 24 个请求全部 ≤16 beat、不跨 4 KiB；把 C 块放到 `C_BASE+0x80` 的定向测试
  得到 **25 个请求**（在 4 KiB 边界处 16 beat 被切成 8 beat），数据仍 6144 B 全对。
- `cseg` 与首拍 `cval` 同拍接收：同引擎 A/B（SAME_CYCLE_CSEG=1/0）为
  **4721/1560 vs 4785/1688**（总数/c_collect），命令气泡被消掉。
- `ld_expected` 的宽乘加/64-bit 比较拆成 V1..V4 四个寄存器边界；方向测试用连续 4 拍
  接收 4 条合法命令，并逐项拒绝错地址、非 64B 对齐、越界、越 epoch、错编码、64-bit 端跨出。
- 本报告只提交本 worker 的证据；最终验收由主 agent 完成，`rc=0` 不等于主验收自动通过。
- 所有正常 run 的 `cwr_pending=0`；read fault 09、write fault 0a、坏 W parity 09
  都在 `done` 前排空，`cwr_pending=0`。失败会非零：`run_all.sh` 对任何非零 rc 或
  缺少 PASS/PASS_FAULT 的 run 退出 1。

## 2. 复跑

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_storage_write
bash scripts/run_all.sh        # 每个编译/仿真 timeout 600；Verilator 全部 -j 1
# 机器可读结果：
cat result.json
cat logs/metrics.txt
cat reports/long_wait_compare.json
cat reports/cseg_bubble_compare.json
cat reports/storage_angles.json
```

依赖：Verilator 5.x、Icarus Verilog（只作为对照可选项，本报告未使用）、Python 3、
`timeout`。baseline 从只读 `v023_repair/ds_matrix` 现场编译，不使用其旧 `result.json`。

## 3. 参考冻结与独立 gold

- `REFERENCE_SHA256.json` 冻结了 v023 的 18 个参考文件（RTL、TB、BFM、REPORT/INTERFACE/
  progress/result）和 14 个 fixture；`scripts/check_reference.py` 在每次 run 前重算 SHA，
  并检查本目录 9 个“未改动参考副本”与源文件逐字节一致。本次 `REFERENCE_CHECK PASS`。
- fixture 是独立整数模型 `tests/gen_engine_vectors.py` 生成的，不读 RTL。发布前重新生成
  `eng_k1`（seed 77）和 `eng_c1`（seed 222），`init.hex`/`exp_c.txt` 与冻结 fixture
  **逐字节相同**（`cmp_gold_k1`/`cmp_gold_c1` 均 rc=0）。
- 存储定向测试的参考不是 RTL 输出，而是 TB 内独立字节函数 `pat(k)=8'h5a^(k*7)`；
  native/generic/tail/split 都按地址逐字节比对，且 `tail` 检查 24 B 之后不被踩。
- 未把同源 golden 当参考：引擎 C48 用独立 Python 整数模型；存储 C 图像用独立字节模式。

## 4. 实现

### 4.1 地址 validator 寄存级（`block_storage_stream_v3`）

旧式单周期锥：`base + (row*ncols + col)*block_bytes`、`== {0,address}`、
`end` 范围比较。v3 改为：

| 边界 | 寄存内容 |
|---|---|
| V0 | 捕获 `ld_*` |
| V1 | `idx = block_row*ncols + block_col`（16×16） |
| V2 | `off = idx*block_bytes`（32×32→64） |
| V3 | `expected = base + off`，`end = expected + block_bytes` |
| V4 | identity/对齐/arena/param/64-bit wrap/`expected==address` 比较，`bad`，入 lq |

`ld_ready` 只看 lq 空位、stage 预留和 in-flight 计数，不依赖乘法/比较结果；in-flight
计入 lq 空间，防止流水填满队列。`tb_validator_pipe` 连续 4 拍接收 A0/W0/A1/W1，
`stage_a_bvalid/stage_w_bvalid` 全 1，`lq=4`；6 类坏命令都被拒绝。

### 4.2 cseg 元数据 FIFO + 首 cval 同拍

- `cseg_ready` 只受 4-entry metadata FIFO 空间和错误状态影响；`cseg` 的 block/地址检查
  从 FIFO 头寄存后做，不在接收入口维持原组合锥。
- 引擎新增 `SAME_CYCLE_CSEG`（默认 1）：最终 K 的 segment 首 group 允许 `cseg` 与
  该 group 的 `cval` 同拍提交；`commit_now` 同时看 `cseg_ready`/`cval_ready`。
  置 0 可复现 v0.23 的一拍命令气泡，用于 A/B。
- 结果：`c_collect` 在 K96 C0 同引擎 A/B 中从 1688 降到 1560；总周期 4785→4721。
  剩余 `c_collect=260` 是 4 个 quadrant 各 1 个 CREAD 加 64 个 group，不是每段命令气泡。

### 4.3 合法连续 C48 写合并

- 识别 native 布局：`cseg_address == block_base + unit*96`、`unit<64`、`beats==6`、
  `block_base[3:0]==0`、`rel<6144`。native 段写入 **6144 B staging**，按
  `unit*96 + group*24` 落位；非该布局走 **generic** 路径（每段 ≤128 B，按真实
  `WSTRB` 尾拍）。
- native 的两个 3072 B 半行（rows 0..15 / rows 16..31）在对应 32 个 unit 完成后 flush；
  第一半可在 quadrant 2/3 仍在计算时排空。每个请求 `beats = min(16, 剩余, 到 4 KiB 的距离)`。
- 4 KiB 距离按 **当前请求地址** 计算，不是 half 起点。这是 `+split` 定向测试抓到的
  真实问题：初版在 `0x...F80` 仍发 16 beat，靠下游 DMA 才切开；修正后 v3 自己在
  4 KiB 边界发 8 beat，`+split` 从 24 个请求变成 **25 个请求**，数据 6144 B 不变。
- 全部通过严格 AXI128 BFM：该 BFM 对 >16 beat、跨 4 KiB、非 INCR、非 16B 对齐
  直接 `$fatal`。v3 K32 的 `wr_bursts=24`，即 24×16=384 beat，无违规。
- 同一数据通路上，native 定向流：64 个 `cseg` → **24 个写请求 / 384 beat / 6144 B**，
  `maxb=2`；generic 8 段 → 8 请求 / 48 beat / 768 B；tail 24 B → 1 请求 / 2 beat /
  实际 `write_bytes=24`（尾 strobe 0x00ff）。
- 没有把 `B_OUT` 加大当修因：v2 `WR_OUT=64` 与 8 的 long_wait 周期、burst 数、
  `c_collect` 完全相同（见 §5.1）。

### 4.4 metadata 对齐、背压、fault/abort

- staging 写入按 `unit*96+group*24`，`cval_last` 完成 unit；半行完成用 64-bit
  `unit_done` 和 done0/done1 计数，重复 unit 不会重复置位。
- generic 用 2×128 B ping-pong；buffer 忙时 `cval_ready=0`，不丢数（`+generic`
  `cvalstall=47` 是真实背压，最终 768 B 全对）。
- `cwr_idle` 要求：metadata/segment、staged half、generic、cq、current burst、
  `b_out` 全空。abort/error 丢弃未 post 命令，已接受的 burst 用零 strobe 补齐到
  原 beat 数，再置 sticky error；`done` 前 `cwr_pending=0`。

## 5. 实测结果

### 5.1 long_wait：同 BFM、同输入、同排空边界

K32，PIPE=4，`axi128_ddr_bfm_v2`，`LAT_MIN=LAT_MAX=48`，`BP_PCT=0`，seed=7；
两边都用 `eng_k1` 的 `init.hex`/`exp_c.txt`，C 内存逐字节核对，`done` 后 5 拍采样。

| 实现 | cycles | c_collect | 写请求/burst | wr_bytes | 备注 |
|---|---:|---:|---:|---:|---|
| v023 v2 `WR_OUT=8` | 4428 | 3777 | 65 | 6144 | 64×96 B + 1 个 4 KiB split |
| v023 v2 `WR_OUT=64` | **4428** | **3777** | **65** | 6144 | 加大 B_OUT 无变化 |
| v3 coalescer | **2616** | **260** | **24** | 6144 | 24×16 beat |
| 差额 | **-1812** | -3517 | -41 | 0 | v2/v3=1.6927× |

fast（LAT=0）同 BFM：v2 1399，v3 1365；v3 略快，说明合并没有牺牲正常路径。
long_wait 相对 fast 的退化本身也被复现并缩小：v2 从 1399 涨到 4428
（**+3029 拍，3.165×**），v3 从 1365 涨到 2616（**+1251 拍，1.917×**）。
v3 的 `maxb=1`（DMA request 上下文串行），不是靠堆 B credit。

### 5.2 cseg 首 cval 同拍 A/B（K96 C0，txn BFM）

| 引擎配置 | cycles | c_collect | 结论 |
|---|---:|---:|---|
| `SAME_CYCLE_CSEG=0`（旧气泡） | 4785 | 1688 | 每段多一拍 |
| `SAME_CYCLE_CSEG=1`（v3） | **4721** | **1560** | 本次候选 |

### 5.3 存储定向（独立字节 gold）

| mode | cseg | 写请求 | beats | write_bytes | 结果 |
|---|---:|---:|---:|---:|---|
| native | 64 | 24 | 384 | 6144 | PASS，64→24 合并 |
| split (`C_BASE+0x80`) | 64 | **25** | 384 | 6144 | PASS，4 KiB 处 8 beat 切分 |
| generic 128 B stride | 8 | 8 | 48 | 768 | PASS，generic 路径 |
| tail 24 B | 1 | 1 | 2 | 24 | PASS，尾 strobe |
| bad (跨 block 端) | 1 | 0 | 0 | 0 | PASS，sticky fault、无写 |
| abort 半段 | 1 | 0 | 0 | 0 | PASS，排空/错误 |

### 5.4 引擎回归（候选 v3，txn BFM）

| 用例 | cycles | c_collect | 结果 |
|---|---:|---:|---|
| K96 C0 | 4721 | 1560 | PASS |
| K96 C1（旧 C） | 5493 | 1560 | PASS |
| seeds 1/2/3 | 4720/4719/4718 | 1560 | PASS |
| M32 N64 K64 | 3630 | 1040 | PASS |
| M32 N32 K32 | 4102 | 260 | PASS |
| M17 N19 K33 | 5190 | 520 | PASS |
| P12 clip | 4102 | 260 | PASS |
| 写背压 `WR_GAP=60,B_DELAY=40` | 26470 | 1560 | PASS |
| read fault | 141 | 0 | PASS_FAULT code 09 |
| write fault | 1635 | 655 | PASS_FAULT code 0a |
| 坏 W parity | 207 | 0 | PASS_FAULT code 09 |

所有正常/fault run `cwr_pending=0`；C48 内存与 `exp_c.txt` 逐字节一致；P12/edge
也逐字节一致。v023 v2 同 BFM fast/背压为 4552/26701，作为参考现场重跑。

### 5.5 诚实的 fast 路径差异

在 txn BFM 的 K96 fast 用例里，v3 是 4721，v2 是 4552（+169 拍，约 +3.7%）：
staging/半行 flush 增加了固定延迟。严格 AXI cluster 的 K32 fast 反而是 v3 1365
对 v2 1399。重要的是 long_wait 下 v3 明显更低；不能把 fast 的 +3.7% 隐去，也不能
把 long_wait 的 1.69× 当整机收益。

## 6. 测了什么、没测什么

**测了**

- v023 参考 SHA 冻结；独立整数 gold 重生成并与 fixture 逐字节比较。
- 存储级：native 合并、4 KiB split、generic stride、24 B 尾 mask、坏 segment、
  abort 排空；每模式独立字节 gold。
- 地址 validator：连续 4 拍接收、6 类拒绝、lq 深度、stage bvalid/fault。
- 引擎：C0/C1、3 seeds、多 N、K32、edge partial、P12 clip、随机写背压、
  read/write fault、坏 parity；C 内存和 result payload 对照独立 gold。
- 新旧 RTL 在同一严格 AXI128 BFM、同一输入、同一 `done`/B 排空边界下的 fast 与
  long_wait；v2 `WR_OUT=64` 对照。
- 所有编译 `-j 1`，每个仿真 `timeout 600`，TB 内部另有 `$fatal` watchdog。

**没测 / 不能声称**

- 完整 512 维 ASR、CASE0000、ONNX、host executor、WER/CER、量化精度。
- 综合、STA、Fmax、CDC、多时钟、板级 DDR/PHY、Xilinx HP/SmartConnect 物理拓扑。
- staging 6144 B 的 BRAM/端口数/功耗；本任务只给逻辑模型，不作资源或频率结论。
- generic 路径单段 >128 B；本任务契约是 ≤128 B。
- 整模型秒数、频率目标、长期稳定性/压力测试。

## 7. 文件与接口

- 候选唯一编译 filelist：`filelist.txt`（9 个 RTL 文件；测试/BFM 由
  `scripts/run_all.sh` 按 top 选择）。
- 接口契约：`INTERFACE.md`（native/generic 规则、16 beat/4 KiB、telemetry、
  abort/error、`SAME_CYCLE_CSEG`）。
- 机器可读：`result.json`（run_all_rc、failed_steps、逐文件 SHA、28 个 run、
  long_wait/bubble/storage 报告），`logs/metrics.json`、`logs/commands.log`。
- 参考冻结：`REFERENCE_SHA256.json`；本次检查日志 `logs/check_reference.log`。
- 逐文件 SHA：`SHA256SUMS.txt`（生成于本报告之后，见该文件）。

## 8. 关键限制

1. 这是逻辑仿真，不是时序/资源/板级验收；地址校验拆寄存级是结构改动，不是 STA 结果。
2. 1.6927× 只对应 K32/C48 写回受测小链，不能外推整模型；fast 路径还有 +3.7%
   （txn BFM）的诚实退化。
3. staging 6144 B 是双访问逻辑数组（写 24 B/cycle、读 16 B/beat）；没有做综合，
   不声称它能直接映射成某个 BRAM 配置。
4. `c_collect` 的定义包含每 quadrant 1 个 CREAD 和 64 个 group；260 不是“256 以下”
   的魔法数，报告按实测解释。
5. v023 基线仍使用其原有 6-beat `cseg` 和单 request 上下文 DMA；本任务没有改 DMA
   的 request 流水，只改了上游合并与存储接收。
