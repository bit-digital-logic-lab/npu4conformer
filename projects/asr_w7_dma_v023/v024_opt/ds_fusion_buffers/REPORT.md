# REPORT — ds_fusion_buffers

## 0. 结论

本任务在只读的 `v023_repair/ds_closeout_fusion` 与 `primary_stream_fix` 之上，
把单块 2 KiB A16 重排缓冲升级为 **2×2 KiB 乒乓双块**，让 tile $t$ 的 A16
DMA 写出与 tile $t+1$ 的矩阵/Epilogue 计算重叠；保留了矩阵可暂停时的 FIFO
信用，并新增了“矩阵不可暂停”时的 stale-credit + 尾帧证明。

回归结果：**39/39 PASS**（`run_all.sh` rc=`0`、独立 exact-rational gold 逐值 0 mismatch；PASS_DUAL_BANK_A16_OVERLAP）。

- 融合路径 C48 DDR 写/读仍为 **0**；每 tile 消除未融合基线的 12288 B C48 往返。
- 双块只增加 **2048 B 片上存储**，不增加 AXI 端口、不增加 DDR 字节。
- 多 tile M/N/K（1/2/3/4 tiles，K=96/64/33/32）全部逐值通过。
- 长 B 延迟（`cfg_b_extra` 最高 3000 拍）下，`done` 严格晚于最后一个 B；
  双块相对单块参考在 n64/B3000 上 engine `task_cycles` 9160→2934，整体
  周期 9165→7857，overlap=1522、`bank_occ_max=2`。

这不是整机/全模型/板级/时序结论。见 §11。

## 1. 上游 exit1 核查与独立复跑

`ds_closeout_fusion/exit.json` 为 `exit_code=1`。核查 `worker.log`：
全文只有 **1 个** `type=error`，是 `provider.transport` 的 `ECONNRESET`
（第 216 行）；同一 session 在该错误后继续运行并写出了 23 个用例、REPORT、
result 和 SHA。原始 `result.json` 是 **23/23 PASS**，所有 case 的 `rc=0`。

因此 exit1 **不是 23 个测试失败**，而是执行工具/提供方传输错误。为独立确认，
本任务把上游源码复制到 `upstream_repro/ds_closeout_fusion`（不修改 v023），
重新编译并完整跑了一遍：

| 项目 | 结果 |
|---|---|
| 原始 exit_code | `1` |
| 原始 result status | `PASS` |
| 原始 totals | `{'cases': 23, 'passed': 23, 'failed': 0, 'elapsed_seconds': 256.44}` |
| 独立复跑 rc | `0` |
| 独立复跑 totals | `{'cases': 23, 'passed': 23, 'failed': 0, 'elapsed_seconds': 266.32}` |

证据：`upstream_repro/ds_closeout_fusion/rerun_console.log`、`rerun_rc.txt`、
`result.json`；上游 50 个源文件 SHA 冻结在 `reference_freeze_v023_fusion.json`。

## 2. 实现

### 2.1 双块 A16 缓冲

`rtl/fusion_a16_blockbuf_dual.sv`：2 × 128 × 128-bit = 4 KiB，每块独立
`EMPTY→FILLING→FULL→DRAINING→EMPTY`。写侧仍是一个 128-bit packed 字/拍，
按 `wr_tag[6:0]` 做 row-major scatter；`wr_last` 必须与 128 个字对齐，否则
置 sticky `err_sequence`。读侧只从 `drain_bank` 顺序 drain。

### 2.2 重叠控制

`rtl/matrix_stream_fusion_top_dual.sv` 的规则：

1. tile-last packed 字写入时锁存该 bank 的 A16 基址，置 `pending_ack[bank]`。
2. 该 bank 满且 **另一块为空** 时，才给 matrix `result_ready`；随后 epilogue
   开始写另一块。这样 tile $t+1$ 的计算与 tile $t$ 的 DMA 写出重叠。
3. 单个 writer/DMA 串行 drain 两个块；若 tile $t+1$ 已满而 writer 尚未完成，
   matrix 等待（`stat_bank_stall_cycles`），**不清 pending、不丢 tile**。
4. `done` 仍要求：engine done、writer idle、所有 bank 为空、
   `tiles_acked == ceil(M/32)*ceil(N/32)`、且 writer 的 `dma_done`（含
   `b_out==0`）已发生。

没有“把 pending 清零”的捷径；`pending_ack` 只由真实的 engine result 握手清除。

## 3. 新增 2 KiB / 端口实际代价

| 项目 | 实际值 |
|---|---|
| 新增片上存储 | **2048 B**（第二块 128×128b） |
| 总 A16 重排存储 | 4096 B |
| 新增顶层 AXI 端口 | **0** |
| 内部 bank 数 | 2，每块 1 写 + 1 读（128-bit） |
| 新增 DDR 字节 | **0** |
| 新增 C48 DDR 字节 | **0** |
| 新增逻辑 | 1-bit bank index, write/read bank mux, per-bank empty/full/draining state |

说明：没有综合，所以不声称 BRAM 原语个数/Fmax；128-bit 宽的 bank 在 FPGA
上通常由多个 BRAM 原语拼宽，不能把 2 KiB 简单说成“1 个 BRAM”。

## 4. FIFO 信用 / 尾帧（矩阵不可暂停时）

`fusion_c48_fifo` 未改：DEPTH=16、`in_ready=(count<DEPTH-1)`、
`occupancy<=15`、`credit=DEPTH-1-occupancy`，保留 1 个 skid。

新增 `tb/tb_fifo_credit.sv` 模拟未来 **无 `cval_ready` 的 C-cache 读出源**：
使用 **上一拍寄存的 stale credit**，只在 credit>0 时发 beat，且不撤销 valid；
consumer 有 320 拍长停顿。结果：

```
CREDIT sent=512 recv=512 max_occ=15 credit=15 overflow=0 last_seen=1 errs=0
```

即 512 beat 全部按序到达，尾帧 `last` 只出现一次，occupancy 达到 15 且从未
超过 15，overflow=0。原 1000-beat FIFO 单元测试也保留：

```
FIFO sent=1000 recv=1000 in_beats=1000 out_beats=1000 max_occ=15 high_water=15 credit=15 errors=0
```

## 5. 验证矩阵

所有 case 均重新编译真实 RTL、真实 vvp 运行，并与独立 Python exact-rational
gold 逐值比较；任一失败 `run_all.py` 返回非零。`-j1` 串行编译；每个仿真有
subprocess timeout + TB 内 watchdog。

| label | kind | fixture | tiles | rc | check | cycles | C48w B | C48r B | A16 B | B count | last B |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| d_bp0_main | dual | main | 1 | 0 | 0 | 2120 | 0 | 0 | 2048 | 8 | 2118 |
| d_bp1_main | dual | main | 1 | 0 | 0 | 2403 | 0 | 0 | 2048 | 8 | 2401 |
| d_bp2_main | dual | main | 1 | 0 | 0 | 2570 | 0 | 0 | 2048 | 8 | 2568 |
| d_bp3_main | dual | main | 1 | 0 | 0 | 2789 | 0 | 0 | 2048 | 8 | 2787 |
| d_bp4_main | dual | main | 1 | 0 | 0 | 9014 | 0 | 0 | 2048 | 8 | 9012 |
| d_bextra_main | dual | main | 1 | 0 | 0 | 2240 | 0 | 0 | 2048 | 8 | 2238 |
| d_bextra_n64 | dual | n64 | 2 | 0 | 0 | 7857 | 0 | 0 | 4096 | 16 | 7855 |
| d_b0_n64 | dual | n64 | 2 | 0 | 0 | 3108 | 0 | 0 | 4096 | 16 | 3106 |
| d_n96 | dual | n96 | 3 | 0 | 0 | 3412 | 0 | 0 | 6144 | 24 | 3410 |
| d_m64 | dual | m64 | 4 | 0 | 0 | 4393 | 0 | 0 | 8192 | 32 | 4391 |
| d_edge | dual | edge | 1 | 0 | 0 | 1685 | 0 | 0 | 2048 | 8 | 1683 |
| d_b0_n96 | dual | n96 | 3 | 0 | 0 | 3012 | 0 | 0 | 6144 | 24 | 3010 |
| d_b0_m64 | dual | m64 | 4 | 0 | 0 | 3993 | 0 | 0 | 8192 | 32 | 3991 |
| d_b0_edge | dual | edge | 1 | 0 | 0 | 1517 | 0 | 0 | 2048 | 8 | 1515 |
| d_fma0_main | dual | main | 1 | 0 | 0 | 2120 | 0 | 0 | 2048 | 8 | 2118 |
| d_fma2_main | dual | main | 1 | 0 | 0 | 2120 | 0 | 0 | 2048 | 8 | 2118 |
| d_relu_main | dual | main | 1 | 0 | 0 | 2120 | 0 | 0 | 2048 | 8 | 2118 |
| s_bp0_main | single | main | 1 | 0 | 0 | 2122 | 0 | 0 | 2048 | 8 | 2118 |
| s_b120_main | single | main | 1 | 0 | 0 | 2242 | 0 | 0 | 2048 | 8 | 2238 |
| s_n64_b3000 | single | n64 | 2 | 0 | 0 | 9165 | 0 | 0 | 4096 | 16 | 9161 |
| s_n96_b400 | single | n96 | 3 | 0 | 0 | 4337 | 0 | 0 | 6144 | 24 | 4333 |
| s_m64_b400 | single | m64 | 4 | 0 | 0 | 5789 | 0 | 0 | 8192 | 32 | 5785 |
| s_b0_n64 | single | n64 | 2 | 0 | 0 | 3163 | 0 | 0 | 4096 | 16 | 3159 |
| s_b0_n96 | single | n96 | 3 | 0 | 0 | 3120 | 0 | 0 | 6144 | 24 | 3116 |
| s_b0_m64 | single | m64 | 4 | 0 | 0 | 4168 | 0 | 0 | 8192 | 32 | 4164 |
| s_b0_edge | single | edge | 1 | 0 | 0 | 1519 | 0 | 0 | 2048 | 8 | 1515 |
| u_bp0_main | unfused | main | 1 | 0 | 0 | 4397 | 6144 | 6144 | 2048 | 8 | 4393 |
| u_n64 | unfused | n64 | 2 | 0 | 0 | 7638 | 12288 | 12288 | 4096 | 16 | 7634 |
| u_n96 | unfused | n96 | 3 | 0 | 0 | 9751 | 18432 | 18432 | 6144 | 24 | 9747 |
| u_m64 | unfused | m64 | 4 | 0 | 0 | 13005 | 24576 | 24576 | 8192 | 32 | 13001 |
| u_edge | unfused | edge | 1 | 0 | 0 | 3527 | 6144 | 6144 | 2048 | 8 | 3523 |
| u_b1_main | unfused | main | 1 | 0 | 0 | 4480 | 6144 | 6144 | 2048 | 8 | 4476 |
| oddtail_5w_3b | oddtail | - | - | 0 | - | - | 0 | 0 | - | - | - |
| oddtail_1w_1b | oddtail | - | - | 0 | - | - | 0 | 0 | - | - | - |
| oddtail_16w_16b | oddtail | - | - | 0 | - | - | 0 | 0 | - | - | - |
| oddtail_7w_8b | oddtail | - | - | 0 | - | - | 0 | 0 | - | - | - |
| fifo_unit | fifo | - | - | 0 | - | - | 0 | 0 | - | - | - |
| fifo_credit | fifo | - | - | 0 | - | - | 0 | 0 | - | - | - |
| epilogue_contract | contract | - | - | 0 | - | - | 0 | 0 | - | - | - |

覆盖：main M32/N32/K96；n64 M32/N64/K64（2 tiles）；n96 M32/N96/K32（3 tiles）；
m64 M64/N64/K32（4 tiles）；edge M17/N19/K33；5 种 AXI 背压；conv-only/
scale-only/负 scale/ReLU；长 B 延迟 120/400/3000 拍；真实未融合基线；
odd-tail 1/3/8/16 B；FIFO 容量与 credit/tail；FMA vs mul+add 定向契约。

## 6. 同负载周期与总线字节

同一 fixture、同一 v5 BFM、同一 scale/bias、同一独立 gold。未融合基线是真实
store-then-reload（C48 写 DDR 再读回），不是估算。

| workload | tiles | dual cycles | single cycles | unfused cycles | dual task cycles | single task cycles | fused B | unfused B | C48 消除 B | both gold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| main | 1 | 2120 | 2122 | 4397 | 1953 | 2117 | 11264 | 23552 | 12288 | True |
| n64 | 2 | 3108 | 3163 | 7638 | 2934 | 3158 | 16384 | 40960 | 24576 | True |
| n96 | 3 | 3012 | 3120 | 9751 | 2835 | 3115 | 15360 | 52224 | 36864 | True |
| m64 | 4 | 3993 | 4168 | 13005 | 3824 | 4163 | 20480 | 69632 | 49152 | True |
| edge | 1 | 1517 | 1519 | 3527 | 1335 | 1514 | 8192 | 20480 | 12288 | True |

字节差正好等于每 tile 的 C48 往返 12288 B（2×6144）；融合/双块路径没有
任何额外 DDR 搬运（`fused_extra_ddr_bytes=0`），额外只有片上 2048 B。

### 6.1 长 B 延迟 / 双块重叠

| workload | dual cycles | single cycles | dual task cycles | single task cycles | overlap | bank_occ_max | last B | dma_done | B count |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| n64_long_B_3000 | 7857 | 9165 | 2934 | 9160 | 1522 | 2 | 7855 | 7857 | 16 |
| main_long_B_120 | 2240 | 2242 | 1953 | 2237 | 0 | 1 | 2238 | 2240 | 8 |

n64 `cfg_b_extra=3000`：双块 engine `task_cycles` 2934，单块 9160；
双块 `overlap=1522`、`bank_occ_max=2`，即 tile 1 计算期间 tile 0 的 A16 DMA
仍在写出。整体 cycles 7857 vs 9165 受长 B 限制，不能当作板级加速承诺。

## 7. 完成 / B 排空边界

融合 TB 逐拍统计真实 AW/B 握手：每个 tile 128 字 = 8 个 16-beat burst，
`b_count` 必须等于 `8*tiles`；`done` 必须晚于 `last_b` 和 writer 的
`dma_done`。所有 case 的断言均通过。示例：

| label | cycles | last W | last B | dma_done | B count | bank_occ_max |
|---|---:|---:|---:|---:|---:|---:|
| d_bp0_main | 2120 | 2106 | 2118 | 2120 | 8 | 1 |
| d_bextra_n64 | 7857 | 4825 | 7855 | 7857 | 16 | 2 |
| d_n96 | 3412 | 2988 | 3410 | 3412 | 24 | 2 |
| d_m64 | 4393 | 3975 | 4391 | 4393 | 32 | 2 |
| d_edge | 1685 | 1603 | 1683 | 1685 | 8 | 1 |

`done` 的产生条件包含 `!writer_busy && !(|bank_busy)`，writer 的 done 又由
`axi_dma_v020_multi_v2` 的 `b_out==0` 限定；不存在“最后 B 未回就 done”的路径。

## 8. 数字契约（独立 gold）

- DUT 必须匹配单次舍入 FMA gold；与 mul+add 两次舍入的差异只报告、不判失败。
- 定向契约：`CONTRACT cases=8 fma_mismatch=0 fma_vs_muladd_diff=8; CONTRACT_PASS`
- 契约 TB 在 vector 文件打不开、读到 0 个 case 时 `$fatal`；driver 还要求
  `CONTRACT cases>=8 && fma_mismatch==0 && fma_vs_muladd_diff>=1`，避免
  “0 case 也 PASS”的假通过。
- 整数 C48 阶段由 `gold_fusion.py` 从 `init.hex` 重算，与 `gen_engine_vectors.py`
  的 `exp_c.txt` 独立交叉核对：`{'edge': {'values': 1024, 'mismatch_vs_exp_c': 0}, 'm64': {'values': 4096, 'mismatch_vs_exp_c': 0}, 'main': {'values': 1024, 'mismatch_vs_exp_c': 0}, 'n64': {'values': 2048, 'mismatch_vs_exp_c': 0}, 'n96': {'values': 3072, 'mismatch_vs_exp_c': 0}}`

## 9. 可选 per-channel / FP32 接口（已发布，未实现）

`INTERFACE.md` §4 给出了 2×32 通道 scale/bias 参数表与 `cfg_spill_fp32`
4×FP32 旁路的端口/契约。本任务 **没有** 实现或验证它们，也没有把广播
scale/bias 说成 per-channel。

## 10. SHA 与复跑

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_fusion_buffers
bash scripts/run_all.sh
```

`run_all.sh` 串行编译、生成 fixture、跑全部 case、调用 `finalize.py` 写
`result.json` 与 `SHA256SUMS.txt`。关键 SHA：

| 文件 | SHA-256 |
|---|---|
| rtl/matrix_stream_fusion_top_dual.sv | `911b89993560cb839d515c41e8a289d03c687a2af0fca94559fa7294b4135bf5` |
| rtl/fusion_a16_blockbuf_dual.sv | `74230ef85493eac4e296e9763baf38e6354ac270aef049115ea1dccc17f6ba43` |
| rtl/matrix_stream_fusion_top.sv | `b9d21cb0996c4ae08d50514973b4b6bdbd33fd0a5eb53d0fa107156c93b6486b` |
| rtl/fusion_a16_blockbuf.sv | `0ef9aa9520673aef4157fb0ab9164971415f6f7f5fbcd4d4005210fd0c2b4f89` |
| tb/tb_fusion_dual.sv | `01426c14b90d24e9c9f66b992fb4f8358171b913af92365039957015e21b8db4` |
| tb/axi128_ddr_bfm_v5.sv | `49b27354dabfa141b254f04ca5442608a1f7c90a36dd89a95a8f8977e027634e` |
| scripts/gold_fusion.py | `605b16318e029940bc071c094e49b74689c04ec1adf752c6756cce0ce12dd88a` |
| filelist_fused_dual.f | `73b39d0e01b87811bf5416883824d298e7bca6a7ba5d67e75e0dd06942c3463e` |
| INTERFACE.md | `6d4100b25f1caf7e0de18d28a23bdf4767003b11b70658069ed43b278b537d87` |

唯一 filelist：

- `filelist_fused_dual.f`：25 文件 / 28 module / 28 unique，duplicates=`[]`
- `filelist_fused_single.f`：25 文件 / 27 module / 27 unique，duplicates=`[]`
- `filelist_unfused.f`：28 文件 / 31 module / 31 unique，duplicates=`[]`

## 11. 明确未完成 / 不声称

- module/cluster-level logic simulation; not a whole-model or board result
- no synthesis/STA/CDC; no frequency claim
- broadcast scale/bias only; per-channel scale/bias and cfg_spill_fp32 are interface-only
- one A16 write DMA: compute/writeout overlap, not two simultaneous writes
- partial M/N still emits a full 32x32 tile with zeros in the unused region
- the unfused baseline is frozen store-then-reload; a better overlapped unfused schedule could narrow the cycle gap
- the frozen unfused baseline does not complete in this simulation environment for cfg_b_extra>1; accepted baseline uses b_extra=0 (v4-equivalent) plus one b_extra=1 smoke
- long-B and dual-bank overlap are exercised on the fused single vs dual tops with the same v5 BFM and same gold
- no full 591 DAG/executor, approx integration, WER/CER

