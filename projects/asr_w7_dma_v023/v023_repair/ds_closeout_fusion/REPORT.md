# REPORT — ds_closeout_fusion
## 真实矩阵 C48 → 片上 FMA(scale,bias) → A16 → AXI 写回闭环

日期：2026-10-30  
目录：`/home/yang/Desktop/项目/v023_repair/ds_closeout_fusion`  
范围：**仅本地 Icarus Verilog 逻辑仿真**。未综合、未 Vivado/STA、未上板、未 VNC、未 push。
`work/`、ZIP、`primary_stream_fix`、`ds_matrix` 及其他 worker 目录均只读；本目录只新增代码、
测试、脚本、日志和报告。`candidate/` 是上游交付件的逐字节副本（`diff -rq` 已验证一致）。

---

## 0. 结论

**交付了一个真实可运行的“矩阵 C48 → 片上融合 → A16 → AXI 写回”模块级闭环，并在
同负载、同 BFM、同独立 golden 下与真实“C48 写 DDR 再读回”的未融合基线做了周期和
实际总线字节对照。23 个仿真用例全部通过（rc=0，逐值 golden 0 mismatch）。**

- 融合路径中 **C48 从不写 DDR、也从不从 DDR 读回**：`block_storage_stream_v2` 的
  C48 写端口在 RTL 中结构性 tie-off，监控到的 `c48_ddr_bytes=0`，且所有写地址都在
  A16 窗口内。
- 真实 `block_engine_prefetch_v2` 的 `cval_valid/cval_ready/cval_last` 4-lane C48
  直接进入 `epilogue_stream_engine_v023`（primary 冻结候选），然后 A16 经 2 KiB
  片上重排缓冲和写 DMA 写回。
- 5 种背压模式（无背压、随机、仅写长停顿、仅读长停顿、混合重背压）、odd tail、
  非平凡 scale/bias、负 scale、ReLU、conv-only、scale-only、edge `M17/N19/K33`、
  双 tile `M32/N64/K64` 均逐值一致。
- 数字契约已分离：DUT 与**单次舍入 FMA gold** 逐位一致；与旧 **mul+add 两次舍入
  baseline** 在 8/8 个定向构造用例上不同，且**没有**把“与 mul+add 不同”判成失败。
- FIFO 容量有真实单元测试：1000 beat、最大占用 15（DEPTH-1）、无 overflow、顺序
  无丢失；live matrix 本身有 `cval_ready` 且 stall 时保持数据（monitor 断言）。
- AXI 写响应排空边界有逐周期证据：`done` 只在 `dma_done` 之后，`dma_done` 本身
  由 `b_out==0` 限定；日志记录 `last_w / last_b / dma_done / drain_cycles`。

**这不是整机通过，也不是全模型 WER/CER 或板级时序结论。** 见 §10。

---

## 1. 上游基线（已阅读，未改写）

- `primary_stream_fix/REPORT.md` 与 `INTERFACE.md`：主 agent 修复后的流式引擎在
  5 种背压模式 65 项通过；参数只有 addr0=广播 scale、addr1=广播 bias；无
  per-channel、无 `cfg_spill_fp32`；A16 与 packed 是两个独立输出。
- `primary_acceptance/round2/REPORT.md` 与 `result_primary_fma.json` /
  `result_primary_approx.json`：第二轮主 agent 独立通过 **FMA 8734 零失配**、
  **approx 15168**。旧门禁（primary_acceptance/REPORT 的 FMA/approx 阻断）已过时，
  本报告不把它当作当前失败依据。
- `integrated/REPORT.md`：integrated 是 exact-path 可运行候选，整机仍阻断；本任务
  不引用其局部结果外推全模型。
- 当前模型口径是 **512 维 ASR（Conformer/Transformer）**，不是 KWT；本任务不套用
  旧 KWT 的 64 维/99 元素精度范围。
- `gemini_closeout_fusion/` 是 Gemini 因 429/RESOURCE_EXHAUSTED 退出后留下的只读
  参考。核查结果：其 `matrix_stream_fusion_cluster_v023.sv` **不能 elaborate**
  （对 `block_engine_prefetch_v2`/`block_storage_stream_v2` 使用不存在的端口，7 个
  port error），且没有 build/仿真日志。本任务没有把该 partial RTL 当作完成证据；
  仅参考其文件命名，独立重写了桥接并完成真实编译/仿真。

---

## 2. 实际实现（不是 stub）

### 2.1 融合链

```
block_engine_prefetch_v2 (ds_matrix 冻结候选，未改)
  │  cseg_valid/ready, cval_valid/ready, cval_data[191:0] (4×C48), cval_last
  ▼
fusion_c48_framer        段节奏检查、把“段尾”换成“tile 尾”、生成 row-major 目标字索引
  ▼
fusion_c48_fifo          弹性 FIFO，DEPTH=16，保留 1 个 skid，credit/occupancy 遥测
  ▼
epilogue_stream_engine_v023 (primary_stream_fix 冻结候选，未改)
  │  I48→F32 RNE/FTZ，单次舍入 FP32 FMA(scale,bias)，可选 ReLU，F32→I16 RNE+饱和
  ▼  a16_packed[127:0] + word tag + tile_last
fusion_a16_blockbuf      128×128b = 2 KiB 片上重排缓冲（row-major scatter）
  ▼
fusion_a16_writer        128 beat/tile，burst 由 DMA 切到 ≤16 beat/≤4 KiB
  ▼
axi_dma_v020_multi_v2    真实写 DMA；done 前 b_out==0（B 响应排空）
  ▼
AXI4 128-bit 写主口
```

A/W（以及可选 C）加载仍走真实的 `block_storage_stream_v2` + 读 DMA；只有 C48
写端口被 tie-off。`block_storage_stream_v2` 的 `cwr_idle` 仍接回 engine，engine
原有的完成路径没有被绕过。

### 2.2 关键接口事实（容易做错的地方）

1. `cval_last` 是 **segment-last**（`pipe_grp[1:0]==3`，每 4 个 cval beat 一次），
   **不是 tile-last**。直接送给 epilogue 会把每 2 个 packed beat 都标成 last。
   `fusion_c48_framer` 用 beat 计数在 **第 256 个 cval beat** 生成真正的 tile-last。
2. 矩阵的 C48 流顺序是 **quadrant-major**，而逻辑张量是 row-major。framer 按
   `segment = quadrant*16 + row_in_quadrant` 生成目标 128-bit 字号：
   ```
   row      = ((seg>>5)<<4) | (seg & 15)       // 0..31
   col_half = (seg>>4) & 1                     // 0/16
   pair     = beat_in_segment >> 1             // 0/1
   word     = row*4 + col_half*2 + pair        // 0..127
   ```
   epilogue 每个 packed word 的第一半 tag 就是该 `word`；2 KiB 缓冲按此 scatter，
   再顺序 drain，所以 DDR 中是行主序 A16。
3. 每个 32×32 tile 固定 **64 个 cseg、256 个 cval beat、128 个 packed A16 word、
   2048 B**。partial M/N（edge）仍输出完整 32×32（未使用区域为 0），与未融合
   C48 的布局一致，便于逐值对照。
4. 每 tile 的 A16 基址 = `cfg_a16_base + (block_row*ceil(N/32)+block_col)*2048`。
   `n64` 用例验证了 tile 地址递增和第二次 tile-last。

### 2.3 为什么不是“先写 DDR 再读冒充片上融合”

- 融合 top 中 `block_storage_stream_v2` 的 `cseg_valid/cval_valid` 恒 0，
  `wr_req_ready/wr_ready` 恒 0；C48 写 DMA 根本没有实例化。
- 测试台监控所有 AW 地址：融合路径 **只允许** 落在
  `[cfg_a16_base, cfg_a16_base + tiles*2048)`；任何越界立即计错。所有用例
  `out_of_a16=0`。
- 遥测 `stat_c48_ddr_bytes` 由结构固定为 0；真实总线计数只有 A/W 读 + A16 写。
- 未融合基线则**真实**产生 C48 6144 B 写 + 6144 B 读（见 §6），不是估算。

---

## 3. FIFO 容量与反压证明

### 3.1 live matrix 是可暂停的

`block_engine_prefetch_v2` 在 COLLECT 中用
`commit_now = pipe_valid && !seg_needed && (!cval_needed || cval_ready)`，即
`cval_ready=0` 时保持 `pipe_*`/读地址不动。测试台对
`cval_valid && !cval_ready` 做保持断言：下一拍 `cval_valid` 必须仍为 1，且
`cval_data/cval_last` 不变。全部通过（`ASSERT_FAIL cval not held` 未出现）。

### 3.2 FIFO 结构界

`fusion_c48_fifo`：`DEPTH=16`，`in_ready = (count < DEPTH-1)`，保留 1 个 skid
slot。因此：

```
occupancy <= DEPTH-1 = 15           （结构不变量，不是统计值）
credit    = (DEPTH-1) - occupancy   （0..15）
```

合规 producer 每拍最多 1 beat，ready 低时停；consumer 任意慢。即使 producer 把
ready 决策多寄存一拍，预留的 1 个 slot 仍能吸收，不会覆盖未读数据。FIFO 内部还有
显式 overflow sticky 和 `count>=limit` 写保护。

### 3.3 单元测试

`tb/tb_fifo_unit.sv`：1000 beat，consumer 每 60 拍有 40 拍长停顿 + LFSR 抖动，
producer 合规。结果：

```
FIFO sent=1000 recv=1000 in_beats=1000 out_beats=1000 max_occ=15 high_water=15 credit=15 errors=0
FIFO_PASS
```

即：在真实长背压下 FIFO 填到 15、producer 被反压、1000 beat 顺序无丢失、无 overflow。

### 3.4 若未来 matrix 没有输出 ready

当前接口**有** `cval_ready`，所以不需要“cache 读出桥”来兜底。若换成一个
不可暂停的 C cache 读出源，正确构造是信用门控：只有在 `credit>0` 时才发 BRAM
读地址，并为 BRAM 的 1 拍读延迟预留至少 1 个 slot（本 FIFO 的 credit 已按
`DEPTH-1-occupancy` 计算，正好覆盖 1 个在途读 + 1 个 skid）。不能只把 C48 先写
DDR 再读来“解决”反压；本任务没有走这条路。

---

## 4. 验证矩阵（23/23 PASS）

每项均重新编译真实 RTL、真实 vvp 运行、与独立 Python golden 逐值比较；任一子项
失败 `run_all.py` 退出非零。完整 rc/日志在 `logs/`，汇总在 `logs/regression.tsv`。

| 类别 | 用例 | 关键变化 | 结果 |
|---|---|---|---|
| 融合 5 背压 | `fused_bp0/1/2/3/4` | 无背压；随机 25%；仅写长停顿；仅读长停顿；混合重背压 + ReLU | PASS 0 mismatch |
| 形状/尾块 | `fused_edge` (17/19/33)、`fused_n64` (32/64/64, 2 tiles) | partial M/N + K tail；双 tile 地址/块尾 | PASS |
| 数值模式 | `fused_fma0`、`fused_fma2`、`fused_relu` | conv-only、scale-only、负 scale+ReLU | PASS |
| 未融合基线 | `unfused_bp0/1/2/3/4`、`unfused_edge`、`unfused_n64` | 真实 C48 DDR 写 + 读回 | PASS |
| odd tail | `oddtail_5w_3b`、`1w_1b`、`16w_16b`、`7w_8b` | 末字 WSTRB=0007/0001/FFFF/00FF | PASS |
| FIFO 容量 | `fifo_capacity` | 1000 beat + 长停顿 | PASS |
| 数字契约 | `epilogue_contract` | 8 个定向 FMA vs mul+add | PASS（FMA 0 mismatch，muladd 8/8 不同） |

非平凡 scale/bias 例：`0x3f800001/0x3f7fffff`、`0xbf000000/0x3f000000`、
`0x3f800001/0xbf800000`、`0xbf000000/0x3f000000` 等；不是只测 1.0/0.0。

---

## 5. 同负载周期与总线实际字节

同一 fixture、同一 BFM（同 seed/LAT/长停顿设置）、同一 scale/bias、同一独立
golden。融合与未融合**逐值都等于 golden**；下表的周期是该 testbench 的 start→done
周期，不是板级时间，也不是全模型时间。

| workload | fused cycles | unfused cycles | 未融合/融合 | fused 总线 B | unfused 总线 B | 字节差 |
|---|---:|---:|---:|---:|---:|---:|
| bp0 | 2122 | 4397 | 2.072× | 11264 | 23552 | 12288 |
| bp1 random | 2405 | 6013 | 2.500× | 11264 | 23552 | 12288 |
| bp2 write-long | 2576 | 7274 | 2.824× | 11264 | 23552 | 12288 |
| bp3 read-long | 2807 | 5814 | 2.071× | 11264 | 23552 | 12288 |
| bp4 heavy | 9016 | 21941 | 2.434× | 11264 | 23552 | 12288 |
| edge | 1651 | 5297 | 3.208× | 8192 | 20480 | 12288 |
| n64 (2 tiles) | 3471 | 10138 | 2.921× | 16384 | 40960 | 24576 |

字节拆分（main，1 tile）：

- fused：A/W 读 9216 B（576 beat）+ A16 写 2048 B（128 beat）= **11264 B**；
  C48 写 0、C48 读 0。
- unfused：A/W 读 9216 B + C48 写 6144 B + C48 读 6144 B + A16 写 2048 B
  = **23552 B**。
- 差值正好是每 tile 的 C48 往返 12288 B；n64 为 24576 B。所有字节来自真实
  `valid&&ready` 握手和写 `WSTRB` popcount，不是按张量大小估算。

**口径限制**：未融合基线是“先全部写完 C48，再串行读回 + epilogue + 写 A16”的
真实 store-then-reload 调度；如果做一个更好的重叠式未融合调度，周期差距可能缩小。
因此 2.07–3.21× 是**该基线的实测**，不是融合方案的下界或板级加速承诺。

---

## 6. FMA 单次舍入 gold 与旧 mul+add baseline 的分离

- 整数 C48 阶段的独立交叉检查：`scripts/gold_fusion.py` 从 `init.hex` 重新解码
  A/W 并按契约累加，结果与 `ds_matrix` 的 `exp_c.txt` 在 `main/edge/n64/k32`
  四个 fixture 上 **逐值 0 mismatch**（`result.json.numeric_contract.matrix_integer_crosscheck`）。
  这证明 A16 FMA 之前的整数矩阵阶段不是 RTL 自证。
- `scripts/gold_fusion.py` 用精确有理数实现：
  - I48→binary32：RNE，subnormal FTZ；
  - FMA：`x*scale+bias` 的精确值只做 **一次** RNE/FTZ pack；
  - mul+add baseline：先 `round(x*scale)`，再 `round(+bias)`（两次舍入）；
  - F32→I16：RNE + `[-32768,32767]` 饱和。
- 定向契约测试 `tb/tb_epilogue_contract.sv` 用 8 个构造用例（例如
  `x=3, scale=0x43aaaaab, bias=0xc47fe000`，FMA→1，muladd→0）：

```
CONTRACT cases=8 fma_mismatch=0 fma_vs_muladd_diff=8
CONTRACT_PASS
```

即 DUT **匹配 FMA 单次舍入 gold 8/8**，同时与 mul+add baseline **不同 8/8**。
- 全链 A16 输出在本次矩阵 fixture 的非平凡 scale/bias 下，FMA gold 与 muladd gold
  的 **I16 结果差为 0**：因为最终量化到 I16 会把 sub-ulp 的 FP32 差异掩盖掉。这不是
  “两个契约相同”，而是“这个负载的 I16 量化不敏感”；报告不强迫两者逐位相同，也
  不以 muladd 作为 DUT 的通过标准。
- 本任务复用 primary_stream_fix 的冻结 epilogue/FMA；第二轮 8734/15168 门禁由主
  agent 独立通过，本任务不替换、不重跑、不把局部结果外推为全模型精度。

---

## 7. 块尾、列尾与 odd tail

- 矩阵每个 32×32 tile 的 64 个 segment（16 个 quadrant×4 行段×2 列半）在
  framer 中逐一检查 cseg 节奏和 segment-last；第 64 个 segment 的第 4 个 beat
  产生 tile-last。
- 列半映射 `col_half=(seg>>4)&1`，行 `row=((seg>>5)<<4)|(seg&15)`；`n64` 的
  第二个 tile 验证了 `block_col` 的地址递增。
- partial M/N（17×19）不改变 32×32 输出块大小；未使用行列的乘积被 engine 的
  `av/wv` 门控为 0，gold 同样按 0 处理，逐值一致。
- odd-tail 写口用 4 个定向用例覆盖末字 1/3/8/16 字节：
  `strobe=0001/0007/00FF/FFFF`，`bytes=1/67/104/256`，末字之后的 poison 字节
  未被改写，`last_w < dma_done`。
- `cfg_spill_fp32`/per-channel **没有实现**，本报告不声称。

---

## 8. AXI 写响应排空边界（真实记录）

`fusion_a16_writer` 的 `done` 只在 `axi_dma_v020_multi_v2.done` 后产生；DMA 的
`done` 条件包含 `remaining==0 && beats==0 && b_out==0`，即所有 AW 的 B 响应已收到。
顶层 `done` 还要等 writer idle 和 buffer drain。日志中的边界示例：

| 用例 | last W | last B | dma_done | drain cycles |
|---|---:|---:|---:|---:|
| fused_bp0 | 2106 | 2118 | 2120 | 14 |
| fused_bp2_wrlong | 2543 | 2572 | 2574 | 31 |
| fused_bp4_heavy | 8856 | 9012 | 9014 | 158 |
| unfused_bp0 | C48:3767/3783；A16:4384/4393 | — | — | — |
| unfused_bp4_heavy | C48:17285/17433；A16:21844/21937 | — | — | — |

`last_b <= dma_done`、`last_w < dma_done` 在所有用例中成立；没有“done 先于 B”的
提前完成。融合路径的写 burst 数：main 8（128 beat / 16），n64 16；bmax 在重背压
下到 4–5，未超过 DMA 的 8 个 B 信用。

---

## 9. 证据、SHA 与复跑

- 入口：`bash scripts/run_all.sh`。串行编译（Icarus `-g2012`，无并行）、每个仿真
  有 Python subprocess 超时（默认 900 s，unfused 1200 s），另有 TB 内 watchdog。
- 结果：`result.json`（status=PASS，23/23，含 comparison/SHA/limits）、
  `logs/regression.tsv`、每用例 `logs/<label>.log` 和 `.hex`。
- 源清单：`SHA256SUMS.txt`（68 个文件），`result.json.sha256.key_files`；
  上游副本 SHA 另见 `logs/upstream_sha256.txt`，`candidate/` 与上游 `diff -rq` 一致。
- 唯一 filelist：`filelist_fused.f`（25 个文件/25 个 module，无重名）、
  `filelist_unfused.f`（28/28，无重名）。
- 编译 log 全为空（无 warning/error）：`logs/compile_tb_*.log`；各用例 rc=0 见
  `result.json.cases[].rc`。

关键 SHAs（完整见 result.json）：

| 文件 | SHA-256 |
|---|---|
| rtl/matrix_stream_fusion_top.sv | `b9d21cb0996c4ae08d50514973b4b6bdbd33fd0a5eb53d0fa107156c93b6486b` |
| rtl/matrix_stream_unfused_top.sv | `3ab97f01da78bcfa3f44785364c4a8bfa638cee53807ed298d1849d1eb4d1761` |
| rtl/fusion_c48_fifo.sv | `63bbb01f70165ebbf6ea6cae37f2390865dffcc63be213770ad72f2ee9b8bd56` |
| rtl/fusion_c48_framer.sv | `3aee775515daa65699f687f3d910b838daaf820fa58aad48ffd995b33f581042` |
| tb/tb_fusion_cluster.sv | `fb2f015e7f18a9750ff457d6c37cc4474604567124ce066b4b6effccf8df27d9` |
| scripts/gold_fusion.py | `605b16318e029940bc071c094e49b74689c04ec1adf752c6756cce0ce12dd88a` |

---

## 10. 明确未完成 / 不声称

1. **不是整机/全模型结果**：没有原版 ONNX、591 真 tensor DAG、profiled_backend/
   lowbit_executor/vm_abi，也没有 WER/CER。不能把小链周期外推为全模型秒数。
2. **没有综合/STA/CDC/板卡**：不声称 300/600 MHz、ns 裕量、DDR PHY 或 PS HP 拓扑。
   所有 RTL 单时钟；组合 ready/credit 路径未做 STA 清理。
3. **per-channel scale/bias 未实现**：当前只有 addr0 广播 scale、addr1 广播 bias；
   addr>=2 不接受。`cfg_spill_fp32` 也未实现。
4. **融合成本**：行主序重排需要 2 KiB/tile 片上缓冲；这是真实代价，已计入周期，
   不是零成本。
5. **未融合基线是真实的 store-then-reload**，但不是最优重叠调度；周期比不能当作
   融合方案的理论上界/下界。
6. **上游 FMA/approx 门禁**：本任务只消费 primary_stream_fix 冻结候选；第二轮
   8734/15168 由主 agent 独立通过，本任务没有重跑完整集合，也不把本链的局部
   A16 一致性当成 FMA/approx 全量验收。
7. **没有修改 primary_stream_fix**；没有修改 ds_matrix/Gemini/其他 worker 目录；
   Gemini 的 partial fusion top 不能 elaborate，未作为完成证据。

---

## 11. 复跑命令

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_closeout_fusion
bash scripts/run_all.sh          # 编译 + fixtures + 23 cases + golden + result.json/SHA
```

单独复跑某例（示例）：

```bash
iverilog -g2012 -s tb_fusion_cluster -o build/tb_fused.vvp \
  -f filelist_fused.f tb/axi128_ddr_bfm_v4.sv tb/tb_fusion_cluster.sv
python3 scripts/gold_fusion.py --dir vectors/main \
  --scale 0x3f000000 --bias 0x3f800000 --fma 1
vvp build/tb_fused.vvp +init=vectors/main/init.hex +out=logs/x.hex \
  +m=32 +n=32 +k=96 +positions=76543210 +scale=3f000000 +bias=3f800000 +fma=1
python3 scripts/check_a16.py logs/x.hex vectors/main/gold_a16.hex
```
