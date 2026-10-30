# V0.23 Layout 整改报告（ds_layout）

## 0. 范围与结论先行
## 0. 主验收整改回应（2026-10-29 USER_UPDATES）

已读取 `../primary_acceptance/REPORT.md`。**整体验收仍是 NOT PASS**，本目录
只提供 Layout 模块级逻辑证据，不沿用任何早期 review 的 PASS，也不把本模块
的通过当成整机/全模型验收。

主验收列出的 6 项中，与 Layout 直接相关的是第 4 项“ds_layout 仍在修 C48
跨缓存行”：

- 本任务定位并修复了该缺陷。根因是去掉原 `ADDRESS` 状态后，逐元素开始
  新值时没有清零 `source_part/value_hi`；当 6 字节 C48 值跨 16 字节 cache
  line（例如源偏移 12→18）时，第二个元素会错误沿用上一元素的第二半行。
- 证据（负对照）：把 `NEXT` 中的 `source_part<=0;value_hi<=0;` 删掉后，
  `unpack_c48_compact` 在 byte 18 失败（got=0x21, expected=0x8e），
  `copy_tail_6b` 在 byte 18 失败（got=0xa4, expected=0xf4）；修复后的最终
  RTL 两例均 byte-exact PASS。日志：
  `logs/c48_known_bad_*.log` / `logs/c48_fixed_*.log`。
- 这不是“用近似除法放宽”能解释的差异；Layout 本身不含浮点除/开根，C48
  跨行是纯字节拼装/清状态问题。

主验收的其余项不属于 Layout，本报告不据其声称任何通过：

1. 融合 FMA 舍入反例（gemini_epilogue）— 不在本目录；
2. approx 档位实现不符（gemini_approx）— 不在本目录；
3. ds_vector 尾包失败 — 不在本目录；
5. ds_graph 仅部分交付 — 不在本目录；
6. ds_integration waiting_modules — 未整合，本目录不能替代。

因此：**字节正确性优先于性能**。下面的周期/请求数都是模块级、同负载实测，
不构成整机 153→12.5s 或 .15s 的验收，也不构成 300/600 MHz 或全模型精度结论。


- 只做**逻辑仿真**：未综合、未 Vivado/STA、未上板、未 VNC、未 push。
- `work/`、原 ZIP、旧竞赛仓库、其他 worker 目录均只读；全部新增源码、
  测试、脚本、日志在本目录 `v023_repair/ds_layout/`。
- 交付两个候选，模块名均为 `ddr_layout_engine`：
  - `rtl/ddr_layout_engine_v023.sv`：**步进正确性阶段**，去掉运行期
    `u16_divmod` 与逐元素地址乘法，仍用 1-beat I/O，用于单独证明步进正确。
  - `rtl/ddr_layout_engine_v023_burst.sv`：**集成候选**，在上一阶段基础上
    增加 16-beat posted 写突发和有界顺序读预取，新增参数
    `MAX_PREFETCH`（默认 16，1=关闭多行预取）。
- 8 个官方 fixture、12 个错误/ACL/lifecycle 模式、57 个描述符 fuzz、
  32 个独立 Python golden、100 个随机合法 shape **全部通过**。
- 官方 8 fixture 合计周期 **671,563 → 397,315（0.592×）**，写请求
  **11,890 → 746（0.063×）**，读/写 beat 与字节数**逐项不变**。
- 读预取在 reuse 较重的 im2col 上会多读连续行：随机 100 例中 9 例多读，
  共 +234 beat，最坏 +168 beat（+38%）。这不是跨 4 KiB/非连续合并，而是
  预取提前量被逐出；`MAX_PREFETCH=1` 可完全消除该额外读（同 11 例采样中
  读 beat 与原版逐项相等），周期仍约 0.60×。**已实测并如实报告，不宣称
  全场景零代价。**
- 没有 STA，因此**不声称任何 Fmax / 250/300/600 MHz 达标**；也没有实现或
  验证 CDC/异步 FIFO。共享 DMA 只给出接口契约，仲裁器未实现。
- 本模块不引入任何主机/PS 运行期控制：descriptor/param_end 由 PL 计划
  控制器提交，读/写 DMA 全部由 PL 发起，没有 CPU 代搬或逐算子回主机。
  “主机启动前一次装载”由上层 superplan 负责；本模块只消费已装载的
  descriptor。该拓扑边界沿用原工程，本任务没有新增 PS 依赖。

## 1. 基线、方法与只读边界

- 原始 RTL：`work/rtl/ddr_layout_engine.sv`（SHA 见
  `SOURCE_BASELINE_SHA.txt`）、`work/rtl/u16_divmod.sv`、
  `work/rtl/axi_dma_v019.sv`、`work/rtl/ddr_layout_axi.sv`。
- 最终交付 SHA256：
  - 阶段 A `rtl/ddr_layout_engine_v023.sv` =
    `dbfd68df4aa2ecbc77582c29ce4d18bc0f49a33b5b42cb904a87c4ebbb823d0e`；
  - 阶段 B `rtl/ddr_layout_engine_v023_burst.sv` =
    `4e45a39dcb07daeefc190d383ede885e57718f9a60c9d23eda61c4dae11eb893`。
  本文所有数字均由最终 SHA 的 `scripts/run_all.sh` 重跑得到。
- 参考候选：`tasks/ds_critical_control/candidate/rtl/ddr_layout_engine_pipe_v1.sv`
  只做 `CALC→ADDR1→ADDRESS` 分级，每元素 +1 拍，fixture 周期 +10.7~15.1%。
  本任务保留其“乘法分级”思想，但改为**增量步进**，目标是减拍而不是加拍。
- 测试方法：同一 descriptor、同一 256 KiB DDR 初值、同一
  `axi128_memory_bfm`、同一 testbench；原版/阶段 A/阶段 B 三方对比。
  BFM 独立检查 AR/AW 的 16 字节对齐、1..16 beat、4 KiB 不跨界，并在
  `done` 时检查所有 AXI 已排空。
- 独立参考：`scripts/layout_model.py` 按 descriptor 语义逐元素展开生成
  `gold.hex`；golden 测试不是“拿候选和原版互比”，而是和 Python 模型逐字节
  比较，并检查输出尾部 32 字节保护。

## 2. 实现细节

### 2.1 增量坐标与 stride 预计算（阶段 A）

- 每个元素只做加法/比较维护：
  - `source_address` / `destination_address`；
  - `out_y/out_x`、`iy/ix`、`kc/ky/kx`、`rr/cc`；
  - 行/瓦片基址 `row_src_address`、`row_dst_address`、
    `col_src_address`、`col_dst_address`、`row_krow_addr`。
- 每 descriptor 在 `INIT` 一次算好字节步长：
  `b_lin`、`b_rowx/b_rowy`、`b_kx/b_ky/b_kc`、mode3/4 的行列步长等。
- 运行期不再调用 `u16_divmod`。mode 2 只在 `INIT` 用两次除法把
  `k_offset` 分解为 `(kc0,ky0,kx0)`；行/瓦片坐标全部递推。
- 地址链 `(kc*ih+iy)*iw+ix` 与 `index*bytes` 不再逐元素串行出现；
  瓦片起始地址在 `PREP0..2` 分 3 拍重算（每 1024 元素一次）。
- 结果：官方 8 fixture 阶段 A 周期 0.734~0.877×，逐字节/计数器与原版一致。

### 2.2 16-beat 写突发

- `PACK` 仍按 16 字节 line 累积 `output_data/output_mask`；
- 完成一行后压入 16 深 × 128-bit 的 posted buffer（含每 beat strobe）；
- 仅在以下条件发一次 1..16 beat 写：
  1. 达到 16 行；
  2. 刚完成的行是 4 KiB 页内最后一行（`line[11:0]==0xFF0`）；
  3. 下一 fragment 的 line 不等于 `当前 line+16`（非连续/有 gap）；
  4. 描述符结束（tail，保留部分 strobe）。
- 写地址始终 16B 对齐、burst 内严格连续；不会把 mode3/4 的
  `full_n>n` gap 或 `col_start` 前缀合并进去。
- 官方 8 fixture 写请求 11,890 → 746，写 beat/字节数完全不变。

### 2.3 有界顺序读预取

- 仅在 cache miss 时进入 `PF_CALC`，计算本次可取连续行数：
  `min(16, 当前源连续段剩余行, 4 KiB 页剩余行, 源 extent 剩余行)`；
- 源连续段按 mode 精确给出：
  - mode0：到源 extent；
  - mode1：到当前 32 列片段的 `cc` 末尾（不是整行，避免预取下一片段）；
  - mode2：到当前 kernel-x 行末尾，且 `dw*bytes>16` 时强制 1 行；
  - mode3：到当前 32 列 tile 行末尾；
  - mode4：强制 1 行（行内步长 32，跨行不连续）。
- 预取行装入原有 64 行 cache（direct-mapped；mode4 仍是全相联单行替换）。
- 4 KiB、extent、非连续三者都在结构上截断；不依赖“DMA 会帮我拆”。

### 2.4 新增参数

```verilog
parameter integer MAX_PREFETCH = 16;  // 1 = 关闭多行预取
```

默认 16；集成时可按带宽目标改 1。参数只影响预取行数，不影响
descriptor/端口/数值合同。

## 3. 正确性证据

### 3.1 官方 8 fixture（与原版同一负载）

| fixture | 元素 | orig 周期 | 阶段 A | 阶段 B | B/orig | 读beat O/B | 写beat O/B |
|---|---:|---:|---:|---:|---:|---:|---:|
| copy_i16 | 1001 | 10,152 | 8,147 | 6,538 | 0.644 | 126/126 | 126/126 |
| pack_matrix_edges | 4096 | 27,343 | 22,313 | 17,313 | 0.633 | 166/166 | 512/512 |
| unpack_row_fp32 | 1155 | 14,183 | 11,790 | 8,437 | 0.595 | 297/297 | 289/289 |
| unpack_nchw_fp32 | 1155 | 15,313 | 13,042 | 10,702 | 0.699 | 297/297 | 289/289 |
| unpack_c48_compact | 1155 | 17,803 | 15,605 | 10,213 | 0.574 | 462/462 | 434/434 |
| conv_padding | 2048 | 14,152 | 10,498 | 8,245 | 0.583 | 16/16 | 256/256 |
| case0000_embed_conv0 | 78848 | 563,652 | 413,653 | 330,327 | 0.586 | 1270/1270 | 9856/9856 |
| depthwise_31 | 1024 | 8,965 | 6,618 | 5,540 | 0.618 | 4/4 | 128/128 |
| **合计** | | **671,563** | **501,666 (0.747)** | **397,315 (0.592)** | | 2,638/2,638 | 11,890/11,890 |

阶段 A/阶段 B 的 `processed_elements`、输出字节、写字节、读字节均与原版
一致；阶段 A 的 cache 命中/未命中计数也一致。阶段 B 的 `cache_misses`
语义变为“取数请求次数”，已在 INTERFACE 说明。

### 3.2 12 个错误/ACL/lifecycle 模式

对 `copy_i16` 注入：dst 越界、src 越界、total 错、src=dst、descriptor
高位非零、mode=9、读写 DMA 错误、重复 START、bytes=3、src 非对齐、
mode1 维度错。原版/阶段 A/阶段 B 的 rc、fault/error、是否产生 AXI
副作用全部一致，12/12 通过。

### 3.3 描述符 fuzz（原版 vs 候选）

57 例：合法 copy/pack/conv/transpose/compact/slice + 30 个非法边界
（magic/mode/total/bytes/alignment/m/n/full_n/channels/ih/iw/kernel/
stride/padding/overflow/overlap/param_end 等）。
比较 `fault`、`error_code`、`processed_elements`、256 KiB 内存 hash：
**57/57 通过**；周期合计 559,524 → 352,545（0.630×）。

### 3.4 独立 Python golden（32 例）

覆盖 copy 尾部、4 KiB 正好/跨界、16-beat 边界、pack 多瓦片/切片、
im2col padding/stride/dilation/大 dilation/大 stride/多通道/多瓦片、
transpose 的 `full_n>n` gap 与 `col_start` 切片、compact C48（bytes=6）。
原版、阶段 A、阶段 B 都 **32/32 与 Python gold 逐字节一致**，尾部守卫
未被覆盖。周期合计 824,648 → 651,191（A, 0.790×）→ 515,789（B, 0.625×）。

### 3.5 随机合法 shape（100 例，独立 golden）

确定性随机 seed，mode0..4、bytes 2/4/6、stride 1..5、dilation 1..9、
padding、slice、gap、多瓦片。**100/100 逐字节通过**；周期
3,149,865 → 1,913,759（0.608×）。

## 4. 性能与 II

### 4.1 每元素周期（II 的实测代理）

| fixture | orig | 阶段 A | 阶段 B |
|---|---:|---:|---:|
| copy_i16 | 10.142 | 8.139 | 6.531 |
| pack_matrix_edges | 6.676 | 5.448 | 4.227 |
| unpack_row_fp32 | 12.280 | 10.208 | 7.305 |
| unpack_nchw_fp32 | 13.258 | 11.292 | 9.266 |
| unpack_c48_compact | 15.414 | 13.511 | 8.842 |
| conv_padding | 6.910 | 5.126 | 4.026 |
| case0000_embed_conv0 | 7.149 | 5.246 | 4.189 |
| depthwise_31 | 8.755 | 6.463 | 5.410 |

这是状态级 cycle/element，不是“每元素固定 II=1”的流水线吞吐承诺；但可以
明确：**没有为了提频而每元素加 1 拍**，相反去掉了 runtime 除法等待、
`CALC/ADDRESS` 复合乘加和逐元素 `index*bytes`。

### 4.2 写/读请求压缩

官方合计：

| 指标 | orig | 阶段 B | 比值 |
|---|---:|---:|---:|
| 写请求 | 11,890 | 746 | 0.063 |
| 读请求 | 2,638 | 1,778 | 0.674 |
| 写 beat | 11,890 | 11,890 | 1.000 |
| 读 beat | 2,638 | 2,638 | 1.000 |
| 写字节 | 190,204 | 190,204 | 1.000 |
| 读字节 | 42,208 | 42,208 | 1.000 |

单个 case0000：写请求 9,856 → 616（约 16 beat/次），写 beat 9,856 不变。

### 4.3 预取策略实测（含反例）

`logs/prefetch_policy.log`：同一源码用 `MAX_PREFETCH=16` 与 `=1` 两版，
跑官方 8 例 + 3 个过读随机例：

| 指标 | orig | pf16 | pf1 |
|---|---:|---:|---:|
| 周期合计 | 800,079 | 476,048 (0.595) | 482,271 (0.603) |
| r2_21 读 beat | 440 | 608 (+168) | 440 |
| r1_18 读 beat | 428 | 448 (+20) | 428 |
| 写 beat | — | 全等 | 全等 |

结论：预取主要降低顺序 copy/pack/transpose 的读延迟；在 reuse-heavy
im2col 上可能因提前量被逐出而增加读流量。默认 16 是吞吐优先；若共享 DDR
带宽是约束，建议集成时 `MAX_PREFETCH=1`，或按 mode 关闭 mode2 的预取
（参数可扩展，但本任务未加运行时 CSR）。

## 5. 4 KiB、非连续、边界与错误

- BFM 对每条 AR/AW 独立检查：`addr[3:0]==0`、`size=4`、`burst=INCR`、
  `len<=15`、`addr[11:0]+(len+1)*16<=4096`。所有 golden/fuzz 通过，说明
  4 KiB 拆分真实发生，而不是靠“数据刚好没跨”。
- `copy_4k_exact`（2048×2B，恰好到 0x04011000）、`copy_4k_cross`
  （2049×2B，跨页）、`copy_4k_cross6`（700×6B）均逐字节通过；跨页版本
  只比不跨页多 24 周期，说明切分开销很小。
- mode3/4 的 `full_n>n` gap、`col_start` 前缀不会被写；golden 从原 DDR
  内容出发，若误合并 gap 会立刻逐字节失败。
- mode2 `dw*bytes>16` 强制单行取数；`conv_dil_big`/`conv_stride_big`
  专门覆盖。
- tail：`copy_tail_*`、`pack_tail` 等覆盖最后一行/最后 burst 不满 16 beat
  的部分 strobe；尾部 32B 守卫由 testbench 检查。
- 读/写 DMA 错误、非法 descriptor、重复 START 与 DRAIN 行为见 3.2；
  testbench 在每个正常用例 `done` 时检查无未完成 AXI（“DONE before drain”）。

## 5.1 C48 跨 cache line 的回归与负对照

- 修复点：`NEXT` 进入下一元素前清 `source_part`/`value_hi`；`START` 也清，
  保证 descriptor 首元素干净。`LOOKUP` 的第二次半行读取仍保留
  `source_part=1`，不会被误清。
- 覆盖：`unpack_c48_compact`（官方，bytes=6）、`copy_tail_6b`、
  `compactc48_0..4`、`transpose_*`（bytes=6）以及 100 例随机中的 bytes=6
  用例，全部 byte-exact。
- 目的端同样会跨行：`PACK` 用 `take` 把 6 字节 fragment 拆到相邻两行，
  每行保留独立 strobe；`copy_tail_6b`、`compactc48_*`、`transpose_1/3`
  都覆盖了目的端跨行和尾部部分行。
- 负对照日志：`logs/c48_known_bad_compile.log`、
  `logs/c48_known_bad_unpack_c48_compact.log`、
  `logs/c48_known_bad_copy_tail_6b.log`；修复后：
  `logs/c48_fixed_unpack_c48_compact.log`、`logs/c48_fixed_copy_tail_6b.log`。
- 该负对照只用于证明修复有效，不进入最终交付 RTL。

## 6. 关键路径/频率边界（不做无证据声明）

- 原 V0.22 STA #2 路径是 Layout `CALC` 单拍
  `input_y/input_x` + `(kc*ih+iy)*iw+ix` + `src+index*bytes` 级联。候选把
  逐元素乘加全部移出热路径，改为增量加法；瓦片起始重算只在每 1024 元素
  一次，且分 `PREP0..2` 三拍。
- 仍存在的乘法：`INIT` 一次性 stride 预计算、`PREP0..2` 每瓦片乘法、
  miss 路径的 `mode3 remaining*bytes`。它们没有被 STA 验证；**不能**据此
  声称某频点收敛。
- 没有综合/实现，**不声称 250/300/600 MHz**；600 MHz 局部域还需要
  CDC/异步 FIFO 与约束，本任务未实现、未验证。
- 设计保持单时钟；没有引入 CDC。若主 agent 把 Layout 放进局部高频域，
  必须另做 CDC 接口契约和独立逻辑验证，不能假定异步 FIFO 已存在。

## 7. 未完成与风险

1. 整体联仿不在本任务；主 agent 需按 `INTERFACE.md` 整合后重跑。共享 DMA
   仲裁器未实现/未联仿；只给了 `INTERFACE.md` 的信号级契约。
   Layout 单方向单在途、读写不同时，适配器可行，但需要主 agent 用真实
   仲裁器重跑背压/错误测试。
2. 在途 16-beat burst 中途 reset 未单独测试；正常排空、DMA 错误排空已测。
3. `MAX_PREFETCH` 是编译期参数，不是运行期 CSR；若需按 shape 动态策略，
   要另加寄存器/描述符位。
4. 未跑完整 CASE0000/全模型；本任务只提供 Layout 模块级逻辑证据，不宣称
   端到端时间或模型精度。
5. Layout 不含浮点除/开根；用户“除法开根允许近似”的授权对本模块不改变
   任何算术。W7p8/A16/C48 位置、QDQ、clip 均未改。

## 8. 复跑

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_layout
./scripts/run_all.sh
```

顺序执行（-j1 风格，不与其他 worker 抢资源）：

1. 生成 32 个独立 golden fixture；
2. 依次编译原版、阶段 A、阶段 B、两个 fuzz testbench；
3. 官方 8 + 12 错误模式；
4. 57 例描述符 fuzz；
5. 32 例 golden + 100 例随机 golden；
6. `MAX_PREFETCH=1` 变体策略对比；
7. Verilator lint + SHA256。

关键产物：

- `logs/official_table.log`、`logs/gold_table.log`、
  `logs/layout_fuzz.log`、`logs/random_fuzz.log`、
  `logs/prefetch_policy.log`、`logs/FINAL_SUMMARY.txt`
- `logs/run_all.log`（每步 rc）
- `SHA256SUMS.txt`、`SOURCE_BASELINE_SHA.txt`
- `FINDINGS.md`、`INTERFACE.md`、`result.json`、`progress.json`
