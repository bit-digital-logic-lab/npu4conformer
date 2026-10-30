# 关键控制路径优化报告（ds_critical_control）

## 0. 范围与边界

- 只做逻辑仿真：**未综合、未 Vivado、未 STA、未上板、未 push**。
- `work/`、ZIP、其他任务目录保持只读；所有候选/脚本/测试/日志写在 `tasks/ds_critical_control/`。
- 不改变 `W7A16C48`、QDQ、FP32 FTZ/RNE/FMA 顺序、ONNX 容差、ACL 区间、DDR 预装/主机一次装载约束。
- 不声称任何频率已达到；本文的“分级”是组合依赖结构，不是物理 Fmax 结论。

## 1. 结论摘要

1. 已确认真实关键路径是 `block_engine state_reg[3] -> storage/bad_reg`，7.745 ns / 30 levels，包含 **两个串联 DSP48E2 宽乘加 + 64 位 expected_end + 多条 CARRY8 边界比较**，不是 PE 乘法链。
2. Storage 候选 `block_storage_dma_wide4_pipe_v1.sv` 把 descriptor 校验拆成 **7 个寄存阶段**（V1..V7）：元数据/几何、row×ncols、+col、×block_bytes、base/end、地址/范围/row/col 比较、verdict。乘法与 64 位比较不再同拍。
3. Layout 候选 `ddr_layout_engine_pipe_v1.sv` 把 `(kc*ih+iy)*iw+ix` 与 `src+index*bytes` 拆成 `CALC -> ADDR1 -> ADDRESS`；只多 1 拍/元素。
   注意：storage 候选把原路径终点从 `bad_reg` 前移到 storage 的 accept 寄存器；block_engine/`block_address_v020` 自身的组合锥仍存在，必须由主 agent 在新实现中单独检查，不能把本候选当成整条路径已闭合。
4. 等价性：storage 71/71 case canonical 日志逐字节一致；layout 官方 20/20 + fuzz 51/51 一致；真实 block engine 集成 2/2 配置 C hash 一致。
5. 代价：71-case 协议仿真结束时间 storage 约 +1.3%（校验等待）；layout 元素循环约 +10.7%…+15.1%。因此 **优先集成 storage**；layout 只在更高频点/局部域收益能覆盖周期代价时集成。
6. 理论下界已按读写拆分和 DAG 依赖修正：`929293344 B/16B/125MHz=0.46465 s` 只是共享读写串行情景，不是普适全模型下界。

## 2. 基线证据（timing.rpt）

`timing_baseline/timing.rpt` 第 4703 行起：

- Source: `ps_system/ps_gateway_i/accelerator/inst/core/compute/core/state_reg[3]/C`
- Destination: `ps_system/ps_gateway_i/accelerator/inst/core/compute/storage/bad_reg/D`
- Requirement 8.000 ns；Data 7.745 ns；Slack +0.055 ns
- Logic 5.057 ns (65.292%)；Route 2.688 ns (34.708%)
- 30 levels：`CARRY8=6 DSP_A_B_DATA=2 DSP_ALU=3 DSP_M_DATA=2 DSP_MULTIPLIER=2 DSP_OUTPUT=3 DSP_PREADD_DATA=2 LUT2=1 LUT5=4 LUT6=5`

路径上可直接读到：

- block_engine 请求 mux（`expected_address1_i_65/74/22`）；
- `storage/expected_address1` DSP48E2（MULTIPLIER/ALU/OUTPUT）；
- 串到 `storage/expected_address0` 第二个 DSP48E2；
- `expected_address[29] -> expected_end[37]`；
- 多条 CARRY8；
- `bad_i_1/bad_i_2 -> bad_reg/D`。

对应 RTL 就是 `block_storage_dma_prefetch.sv` 的组合 `expected_address = base + (row*ncols+col)*block_bytes`、`expected_end`、ARENA/PARAM 比较、metadata 检查全部汇入 `bad`。`state_reg[3]` 只是起点，不是计算单元。

## 3. Storage 候选

文件：`candidate/rtl/block_storage_dma_wide4_pipe_v1.sv`（模块名不变，端口不变）。

### 3.1 分级

| 阶段 | 组合逻辑 | 位宽/资源 | 说明 |
|---|---|---|---|
| V1 | epoch/layer/matrix/allowed/block_valid/读写 ABI/对齐；ncols/nrows/bytes/base | 16/32 bit 比较、移位加 | 不乘 |
| V2 | `row*ncols` | 16×32→64 | 1 乘法级 |
| V3 | `+col` | 64 bit 加 | 无乘 |
| V4 | `*block_bytes` | 64×32→64 | 1 乘法级 |
| V5 | `base+off`、`end=base+off+bytes` | 64 bit 加 | 无乘 |
| V6 | `expected==req_address`、ARENA/PARAM、row/col | 64/32/16 bit 比较 | 比较独立 |
| V7 | `meta | addr_bad`，`v_done` | 1 bit | 只折叠 |

V2 与 V4 被 V3 的寄存器隔开；V5 的 expected/end 又被 V6 的寄存器采样；`bad` 不再由组合 `request_bad` 直接写入。

### 3.2 数据流/错误顺序

- 读：接受后等 validator；坏 descriptor 直接 HEADER（无 AXI）；好 descriptor 才 RREQ/RDMA，读错误排空后 HEADER。
- 写：接受后立即 WSCALAR，1024 字打包与 validator 并行；WVAL 等 verdict，再 WREQ/WDMA/WACK。
- 合法/非法判定表达式与原 `request_bad` 逐项一致（包括 `req_in_operation` 的读写极性、`param_end<=PARAM_END`、`req_address[5:0]==0`、expected 相等、row/col 边界）。
- 增减延迟：读 header 约 +8 拍；写 DMA 启动 +1 拍。`read_wait_cycles`/`write_wait_cycles` 仍只统计原 DMA 等待状态。

### 3.3 等价性

`logs/storage_equiv_orig.log` vs `logs/storage_equiv_cand.log`：71 case，`diff` 0 字节。覆盖：

- A/B/C 合法读写、部分维度、参数窗口 B 读、C 不存在；
- epoch/layer/matrix/allowed/block_valid/row/col/地址错位/32 位溢出/ARENA 下界/ARENA 上界/param_end 越界/encoding=3/读写 ABI 反例；
- DMA 读错误、读 index 错、DMA 写错误、out_index/out_last 错；
- header abort、data abort、读/写中途 reset、读/写反压、请求间隔；
- 12 个连续混合事务。

比较字段：header 元组、256 个读数据 hash、DMA 地址/beats/read hash/write hash、ACK/错误、`error_transactions`、idle。候选日志中写 hash 已用真实 16 字节 beat 计算（非 X）。

## 4. Layout 候选

文件：`candidate/rtl/ddr_layout_engine_pipe_v1.sv`（模块名/端口不变）。

原 `CALC` 同拍完成 `input_y/input_x`、`source_index=(kc*ih+iy)*iw+ix`、部分 destination index；`ADDRESS` 再做 `src+index*bytes`。候选：

| 阶段 | 内容 | 乘法级 |
|---|---|---|
| CALC | iy/ix、source_zero、`kc=kernel_channel*ih` | 坐标乘法与 kc*ih 并行，各 1 级 |
| ADDR1 | source_index/destination_index：mode2 的 `(kc+iy)*iw+ix`；mode1 的 `rr*full_n+...`；mode3/4 的 tile/row/col 与 destination | 每分支至多 1 个乘法级；mode3/4 source/dest 是并行独立乘法 |
| ADDRESS | `src+index*bytes`、`dst+index*bytes` | 1 乘法级，无比较 |
| LOOKUP | 原 tag compare/cache | 与地址乘法分离 |

实现只增加 1 个状态。这里采用“分阶段乘加”而不是“预计算步进”：前者保持与所有 mode 的原地址表达式逐位一致，风险更低；若后续要进一步摊薄这 1 拍，可在保持同一逻辑切片的前提下改为增量地址累加，但需要单独验证边界/回绕。实测周期代价：

| fixture | 原 | 候选 | 增幅 |
|---|---:|---:|---:|
| copy_i16 | 10152 | 11242 | +10.7% |
| pack_matrix_edges | 27343 | 31474 | +15.1% |
| conv_padding | 14152 | 16187 | +14.4% |
| case0000_embed_conv0 | 563652 | 638750 | +13.3% |
| depthwise_31 | 8965 | 9972 | +11.2% |

### 4.1 等价性

- 官方 fixture + 错误/ACL/lifecycle 模式：`logs/layout_equiv_run.log` 20/20 PASS（8 个 fixture modes 0..4 + 12 个错误/边界/重放模式）。
- 随机/边界 fuzz：`logs/layout_fuzz_run.log` 51/51 PASS（18 合法 copy/pack/conv/unpack/param + 33 非法 magic/mode/total/bytes/alignment/m/n/full_n/channels/ih/iw/kernel/stride/padding/overflow/overlap/param_end 等）。
- 比较字段：`fault/error/processed/cache_hits/cache_misses/read bursts/write bursts/read beats/write beats/256 KiB memhash`。

## 5. 真实 block engine 集成

`tests/tb_block_integration.sv` 用真实 `block_engine_banked_v020` + 原/候选 storage + 确定性 DDR BFM：

| 配置 | 结果 | result_count | read | write | hit | miss | C hash |
|---|---|---:|---:|---:|---:|---:|---|
| 32×32×32 | 原=候选，fault=0 | 1 | 3 | 1 | 0 | 1 | `fefd48c480f5f324` |
| 64×32×64 | 原=候选，fault=0 | 2 | 10 | 2 | 2 | 2 | `ee7e0905446bd2e8` |

日志：`logs/block_integration.log`。集成中 C48 写回数据逐字节一致，说明 storage 候选没有改变 header/data/writeback 顺序。

> 说明：Icarus 对原 block_engine 的“先使用后声明”报错，集成测试使用 `tests/block_engine_simfix_v020.sv`，仅把已有 `beat/quadrant/transfer_slot/sums` 声明移到首次使用之前；无逻辑改动。原 `work/rtl/block_engine_l1bank_v020.sv` 未改。

## 6. 理论最快/带宽修正

详见 `BOUNDS.md` / `BOUNDS.json`。核心：

### 6.1 已知 vector/layout 读写拆分

`BOARD_RESULT.json`：vector/layout 真实读 452,330,768 B，写 355,555,088 B（不含矩阵 DMA）。

| AXI MHz | 读 LB (s) | 写 LB (s) | 共享 R+W (s) | 独立 max (s) |
|---:|---:|---:|---:|---:|
| 125 | 0.226165 | 0.177778 | 0.403943 | 0.226165 |
| 200 | 0.141353 | 0.111111 | 0.252464 | 0.141353 |
| 250 | 0.113083 | 0.088889 | 0.201971 | 0.113083 |
| 300 | 0.094236 | 0.074074 | 0.168310 | 0.094236 |
| 333 | 0.084897 | 0.066733 | 0.151630 | 0.084897 |

“独立 max”是乐观值：假设 R/W 完全并行、无 DDR 读写切换/仲裁/依赖；真实应在两者之间。

### 6.2 929,293,344 B 聚合

该数在随包资料中没有实测读写拆分：

- 共享串行模型：`929293344/(16*125e6)=0.464646672 s`。
- 若读写独立但拆分未知：条件范围 `[0.232323336, 0.464646672] s`（125 MHz，理想平衡下限到全串行上限）。
- 因此 `0.46465 s` 只能作为“共享读写串行”情景，不能作为普适全模型下界。

### 6.3 依赖校正

68 个 plan 是 DAG，不是一块可全局 max 的连续流。有效下界应按段：

```
T >= Σ_s max( C_s/(256 f), R_s/BW_r_eff, W_s/BW_w_eff )   （串行段）
或按可重叠段的临界路径取 max/累加，不能全图直接套一个 max 或一个 sum。
```

缺少逐段 `C_s/R_s/W_s` 时，只能给出条件界：

- `T >= max(R_total/BW_r, W_total/BW_w)`：乐观，忽略依赖和 DDR 切换；
- `T >= (R_total+W_total)/BW_shared`：悲观共享串行；
- 真实值在两者之间，需按 DAG 段/读写切换建模。

### 6.4 矩阵计算下界（不含 vector/layout）

| MHz | useful (ms) | padded (ms) |
|---:|---:|---:|
| 125 | 108.157 | 124.731 |
| 150 | 90.131 | 103.943 |
| 300 | 45.065 | 51.971 |
| 600 | 22.533 | 25.986 |

这些只是矩阵 MAC 下界，不含 vector/layout/QDQ/padding/DAG 等待，不能当整模型时间。

### 6.5 PE/带宽匹配（引用 research，不改本任务算术）

`P_eq <= B*I/f`；256 PE 在 300 MHz 需 I≥38.4 MAC/B，600 MHz 需 I≥76.8 MAC/B。

- 单 HP128@125 MHz = 2 GB/s，不等于 DDR4 物理 12.8 GB/s；6 master 汇聚 HP0 不能 6×2。
- 32³ tile、2 GB/s、300 MHz：I=3.5556，P_eq≈23.70；600 MHz≈11.85。
- 64×128×256 tile、2 GB/s、300 MHz：I=18.286，P_eq≈121.90；600 MHz≈60.95。
- 原 16×16 本地阵列无跨 tile 重用时 I≤5.333；300/600 MHz 分别需要 ≥14.4/28.8 GB/s，而单 HP128@125 只有 2 GB/s。
- AMD HP 推荐 128-bit/16-beat；>16 会切分。16-beat 不是缺陷，关键是在途 outstanding 隐藏延迟。
- DS925 PS AXI 标称最大 333 MHz；600 MHz 只能是局部计算域，必须 CDC/异步 FIFO。

### 6.6 板卡/链路边界

- 器件已确认 `XCZU15EG-2FFVB1156I`；ALINX AXU15EG 因 `AL8/AL7` 差分时钟和 RGMII 引脚与原工程 `board_pins.xdc` 高度一致，是**最高优先级候选板卡**，但工程内没有板名/原理图锚点，不能直接断定用户实物板。
- 原 ZIP 的 `ps_properties`：DDR4、64-bit 物理总线、4×16-bit 8Gb、`CONFIG.PSU__ACT_DDR_FREQ_MHZ≈799.992`（DDR4-1600 MT/s），物理理论 12.8 GB/s；`DDR4_2400P` 是颗粒 speed bin，不是当前运行 2400。
- PL 侧 6 个 master 经一个 SmartConnect 汇聚到单一 `S_AXI_HP0_FPD`，128-bit @125 MHz，接口峰值 2.0 GB/s；不是 6×2 GB/s。
- AXU15EG 若确认，可能有 PL 端 2 GB DDR4（32-bit），但原工程 `board_pins.xdc` 未约束 PL DDR4 引脚、未例化 MIG；因此“完全绕过 PS 硬 DDR 控制器”只是板级适配可能性，本轮不能许诺，也不能在逻辑模型中当作已实现。

## 7. Traffic-ledger 接入建议

本任务未实现完整 ledger，也未改功能 ready/valid。按 `/home/yang/.codex/skills/traffic-ledger/SKILL.md`，建议主 agent 在独立 monitor/wrapper 中接入：

- storage：descriptor/tensor/version/slice/reason；`VWAIT` 标 `DESCRIPTOR_CHECK`，`WVAL` 标 `WRITE_VERDICT`，不要归到 DDR wait/idle；记录 request/first-data/last-data/completion；R/W 按真实握手和 `dma_write_strobe` 计字节。
- layout：descriptor/tensor/version/format/slice/reason；`ADDR1/ADDRESS` 标地址形成，不归 `wait_memory`；cache hit/miss、R/W 请求/首拍/末拍/完成分开。
- 未知原因保留 `unknown`；不能用 busy/prefetch 名称替代真实握手。
- 82→? 的首接数据（analysis/traffic_first_use）只是 BFM 微基准，不是整模型；本任务不引用其 62.36%→95.17% 作为本候选的性能结论。

## 8. 结论与建议

- **建议主 agent 先集成 storage 候选**：它直接切断 7.745 ns 路径的核心乘法+比较锥，且 71-case 协议仿真结束时间只增加约 1.3%。
- Layout 候选默认作为备选：它把地址链切成 3 段，但每个元素多 1 拍，fixture 周期 +10.7…+15.1%；只有在更高频点/局部计算域收益能覆盖时才替换。
- 任何“达到 300/600 MHz”或“整模型加速”结论都必须等新的综合/STA/板测；本任务没有、也不能提供该证据。

## 9. 复跑

```bash
cd /home/yang/Desktop/项目/tasks/ds_critical_control
./scripts/run_all_tests.sh
```

产物：

- `BOUNDS.md`, `BOUNDS.json`
- `FINDINGS.md`, `INTERFACE.md`, `REPORT.md`, `result.json`, `progress.json`
- `SHA256SUMS.txt`, `SOURCE_BASELINE_SHA.txt`
- `logs/`：storage 71-case 原/候选日志与 diff、layout 20+51 case、block 集成、编译/Verilator lint、复跑总日志
