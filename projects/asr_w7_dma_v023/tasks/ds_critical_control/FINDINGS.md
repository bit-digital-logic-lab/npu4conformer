# FINDINGS — 关键控制路径（只读仿真，无综合/无板卡）

## 1. 已证实的关键路径不是 PE

`timing_baseline/timing.rpt` 的最差 setup（clk100_raw，125 MHz / 8.000 ns）：

- Source: `.../compute/core/state_reg[3]/C`
- Destination: `.../compute/storage/bad_reg/D`
- Slack +0.055 ns；Data Path Delay 7.745 ns
- Logic 5.057 ns (65.292%) / Route 2.688 ns (34.708%)
- Logic Levels 30：`CARRY8=6 DSP_A_B_DATA=2 DSP_ALU=3 DSP_M_DATA=2 DSP_MULTIPLIER=2 DSP_OUTPUT=3 DSP_PREADD_DATA=2 LUT2=1 LUT5=4 LUT6=5`

路径明细（timing.rpt 4703 行起）可直接看到：

1. `state_reg[3]` 先经过 block_engine 的请求 mux（`expected_address1_i_65/74/22`）；
2. 进入 `storage/expected_address1` 的 DSP48E2：`A2_DATA -> PREADD -> MULTIPLIER -> M_DATA -> ALU -> OUTPUT`；
3. 再串到 `storage/expected_address0` 的第二个 DSP48E2（`MULTIPLIER -> ALU -> PCOUT/PCIN -> ALU -> P`）；
4. 然后 `expected_address[29] -> expected_end[37]`，进入多条 `CARRY8` 边界比较；
5. 最后经 `storage/bad_i_1`、`bad_i_2` 到 `bad_reg/D`。

也就是说，原模块在**同一拍**内完成了：

- `(row*ncols + col) * block_bytes` 的两次宽乘加；
- `base + offset`、`expected_end = expected + block_bytes` 的 64 位加；
- ARENA/PARAM 边界比较、地址相等比较、row/col 边界比较；
- 头部元数据（epoch/layer/matrix/allowed/in_operation/completed）检查；
- 并把结果直接写入 `bad_reg`。

这正是 `block_storage_dma_prefetch.sv` 中组合 `request_bad` / `expected_address` 锥。`state_reg[3]` 只是该锥的起点，不是 PE 计算路径；因此单独优化 PE 不能解决这条 7.745 ns 路径。

PATH 63/66（`cfg_reg[258] -> storage/state_reg[0/2]`）同样经过 `request_bad` 进入 storage 状态寄存器，候选把 `request_bad` 从 IDLE 次态和 bad 采样中移走后，这条依赖也被同时切断。

## 2. Storage 候选：7 级寄存 descriptor 校验

文件：`candidate/rtl/block_storage_dma_wide4_pipe_v1.sv`，模块名仍为 `block_storage_dma_wide4`，端口与位宽不变。

| 阶段 | 组合内容 | 主要位宽/资源 | 与乘法/比较的关系 |
|---|---|---|---|
| V1 | epoch/layer/matrix/allowed/block_valid/读写 ABI/对齐检查；ncols/nrows/block_bytes/base 选择 | 16/32 bit 比较、移位加 | 不乘 |
| V2 | `row * ncols` | 16×32→64，1 个乘法级 | 独立 |
| V3 | `+ col` | 64 bit 加 | 无乘 |
| V4 | `* block_bytes`（2/4/6 KiB） | 64×32→64，1 个乘法级 | 独立 |
| V5 | `base + offset`；`end = base + offset + bytes` | 64 bit 加 | 无乘 |
| V6 | `expected == req_address`；ARENA/PARAM 范围；row/col 边界 | 64 bit 相等/大小比较 + 16/32 bit 比较 | 比较独立，不与乘法同拍 |
| V7 | `v_bad = meta | addr_bad`，置 `v_done` | 1 bit | 只折叠 |

关键点：

- 乘法结果与 64 位边界比较**不再同拍**；`bad` 不再由组合 `request_bad` 直接采样。
- 边界说明：候选把原 7.745 ns 路径的 storage 段终点前移到 accept 寄存器；`block_engine`/`block_address_v020` 的请求 mux 组合锥仍然存在，主 agent 必须在新实现中单独检查，不能把本候选当成整条路径已闭合。
- 读路径：接受请求后先等 `v_done`，好请求才发 DMA；坏请求直接进 HEADER，不发 AXI。
- 写路径：仍按原协议立即进入 `WSCALAR`，1024 个字的数据流与 7 级校验并行；校验结果在 `WVAL` 才用于决定是否发 DMA 写。正常写请求的校验完全隐藏在 1024 字打包期间，只多 1 个 `WVAL` 拍。
- 错误顺序/ACL/数据不变：坏 descriptor 不产生 AXI；读错误先排空再 HEADER；写错误在 WACK 报告；`abort_scalar` 仍只在 HEADER/RPRE/RSCALAR 生效（与原模块一致，VWAIT 不额外引入 abort 语义）。
- `read_wait_cycles`/`write_wait_cycles` 仍只统计原 DMA 等待状态，不把新增校验拍混入原计数器语义。

**延迟代价**：读请求从接受到 header 决策约 +8 拍（7 级校验 + 1 拍状态）；写 DMA 启动 +1 拍（WVAL），且校验通常被 1024 字数据流完全隐藏。该延迟变化必须在集成接口中明确；本任务不声称 0 延迟。

## 3. Layout 候选：地址形成分级

文件：`candidate/rtl/ddr_layout_engine_pipe_v1.sv`，模块名仍为 `ddr_layout_engine`。

原 `CALC` 在同一拍完成：

- `input_y = out_y*sh + kernel_y*dh - ph`
- `input_x = out_x*sw + kernel_x*dw - pw`
- `source_index = (kernel_channel*ih + input_y)*iw + input_x`
- 以及部分 mode 的 destination index。

候选拆成：

| 阶段 | 内容 | 乘法级 |
|---|---|---|
| CALC | `iy/ix` 坐标、`source_zero`、`kc = kernel_channel*ih` | 坐标乘法与 `kc*ih` 并行，各 1 级 |
| ADDR1 | `source_index` / `destination_index` 形成：mode2 的 `(kc+iy)*iw+ix`；mode1 的 `rr*full_n+...`；mode3/4 的 tile/row/col 组合与 destination | 每分支至多 1 个乘法级（mode3/4 source 与 dest 是并行独立乘法） |
| ADDRESS | `src + source_index*bytes`；`dst + destination_index*bytes` | 1 个乘法级；无比较 |
| LOOKUP | 原有 tag 比较/缓存选择 | 与地址乘法分离 |

只增加 1 个状态（CALC→ADDR1→ADDRESS）。本版采用分阶段乘加而非预计算步进，优先保证所有 mode 的地址表达式逐位一致；预计算步进可作为后续进一步摊薄 1 拍的优化，但需单独验证边界/回绕。实测 fixture 周期代价：

| fixture | 原 cycles | 候选 cycles | 增幅 |
|---|---:|---:|---:|
| copy_i16 | 10152 | 11242 | +10.7% |
| pack_matrix_edges | 27343 | 31474 | +15.1% |
| conv_padding | 14152 | 16187 | +14.4% |
| case0000_embed_conv0 | 563652 | 638750 | +13.3% |
| depthwise_31 | 8965 | 9972 | +11.2% |

所以 layout 候选不是“免费”的：在 125 MHz 原频点会多花约 11–15% 的元素循环拍。它只应在 **确实获得更高频点/局部计算域收益** 时集成；若主 agent 仍以 125 MHz 上板为目标，应优先只集成 storage 候选，layout 候选留作频率提升后的备选。该结论是逻辑周期计数，不是板级时间预测。

## 4. 等价性结果

| 测试 | 规模 | 结果 |
|---|---:|---|
| Storage 协议等价 | 71 case | 原/候选 canonical 日志逐字节一致（diff 0） |
| Layout 官方 fixture/错误模式 | 20 case | 20/20 PASS，canonical PASS 行一致 |
| Layout 随机/边界 fuzz | 51 case | 51/51 fault/error/processed/cache/R/W/memhash 一致 |
| Block engine + storage 集成 | 2 配置 | 32³ 与 64×32×64：C hash、result 数、read/write/hit/miss 全一致 |

Storage 71 case 覆盖：A/B/C 合法读写、部分维度、参数窗口 B 读、C 不存在、epoch/layer/matrix/allowed/block_valid/row/col/地址错位/32 位溢出/ARENA 下界/ARENA 上界/param_end 越界/编码 3/读写 ABI 反例、DMA 读错误、读 index 错、DMA 写错误、out_index/out_last 错、header abort、data abort、读/写中途 reset、读/写反压、请求间隔、12 个连续混合事务。

Block 集成中 `c_hash` 一致说明 C48 写回数据逐字节一致；`read/hit/miss` 一致说明 header/缓存/事务顺序未变。

## 5. 不能宣称的内容

- 未综合、未 Vivado、未 STA、未上板；不能宣称 300/600 MHz 或任何 Fmax 已达到。
- 候选只是**按结构切断了乘法/比较同拍依赖**；实际能否收敛取决于综合/布局布线、扇出、时钟和拥塞。
- layout 候选的 +11–15% 周期是实测逻辑周期，不是板级吞吐结论；若主 agent 在 125 MHz 集成，需权衡。
- 929293344 B 聚合流量没有随包提供实测读写拆分；`0.464646672 s` 只是共享半双工串行情景，不是普适下界。详见 `BOUNDS.md`。

## 6. 与 PE/带宽匹配的关系（引用 research，不改本任务数值）

本任务没有改 PE、W7A16C48 或 QDQ；它只处理控制/地址路径。PE 配置仍需按 `research/PE_BANDWIDTH_MATCH.md/json` 的 `P <= B*I/f` 评估：

- 单 HP128@125 MHz 峰值 2 GB/s，不等于 DDR4 物理 12.8 GB/s；6 个 master 汇聚 HP0 不能按 6×2 GB/s 相加。
- 32³ tile、2 GB/s、300 MHz：I=3.5556 MAC/B，等效 PE 上限约 23.70；256 PE 在 300 MHz 需要 I≥38.4 MAC/B，600 MHz 需要 I≥76.8 MAC/B。
- 原 16×16 本地阵列无跨 tile 重用时 I≤5.333；300/600 MHz 分别需要 ≥14.4/28.8 GB/s，单 HP128@125 只有 2 GB/s。因此“加 PE/升频”必须同时提高 tile 驻留/重用，不能只看 PE 数。
- AMD HP 调优推荐 128-bit、16-beat；>16 会切分。16-beat 本身不是缺陷，重点是多个 outstanding 隐藏延迟。
- DS925 PS AXI 标称最大 333 MHz；600 MHz 只能作为局部计算域目标，必须 CDC/异步 FIFO，不能把 PS AXI 直接跑 600 MHz。
