# INTERFACE — ds_closeout_fusion

Status: **module/cluster-level logic candidate, verified by local simulation**.
Whole-model / synthesis / STA / board acceptance is not claimed. See `REPORT.md`.

所有 RTL 单时钟 `clk`、同步高有效 `reset`（顶层），内部 storage 用 `rst_n=!reset`。
没有 CDC/异步 FIFO。只新增本目录文件；`candidate/` 是上游冻结交付件的逐字节副本。

---

## 1. 融合顶层 `matrix_stream_fusion_top`

文件：`rtl/matrix_stream_fusion_top.sv`。

### 1.1 参数

```systemverilog
SLOTS=2, MAX_DIM=4096, PIPE_STAGES=4, ACCUM_MODE=0, CPA_PIPE=1,
MAX_OUT=8, FIFO_BEATS=128, ARENA_BASE=0x03000000, ARENA_END=0x08000000,
WR_OUT=8, BRIDGE_FIFO=16, A16_WORDS=128
```

`BRIDGE_FIFO` 必须是 ≥4 的 2 的幂；`A16_WORDS=128` 对应 32×32 A16 tile。

### 1.2 端口

矩阵配置（与 `ds_matrix/matrix_p2_cluster_v2` 同形）：

```
cfg_a_base, cfg_b_base, cfg_a16_base, cfg_epoch[31:0],
cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,
cfg_target_high,cfg_allowed_ops,cfg_requested_op,cfg_positions,cfg_clip,
cfg_c_valid,cfg_c_completed,param_end
```

- `cfg_a16_base`：A16 输出基址，也是 engine 的逻辑 C base（本路径不产生 C 流量）。
  必须与 A/B 的实际范围不重叠，16 B 对齐。
- `cfg_c_valid=0` 是本次所有回归的用法；C 加载路径仍保留真实连接，但未做
  c_valid=1 的融合回归（见 §7）。
- `param_end` 传给 storage 的 PARAM 边界，默认 `0x40000000`。

Epilogue 配置：

```
cfg_fma_mode[1:0]   0=conv-only, 1=scale+bias, 2=scale-only
cfg_relu_en
cfg_scale[31:0], cfg_bias[31:0]   // 广播到全部 lane/通道
param_wr_valid/ready, param_wr_addr[7:0], param_wr_data[31:0]
```

- `param_wr_addr=0` 写广播 scale，`=1` 写广播 bias；`>=2` 不 ready。
- 预装值覆盖 `cfg_scale/cfg_bias`，直到 reset/abort 或再次预装。
- **没有 per-channel**；没有 `cfg_spill_fp32`。spill C48 端口在本 top 内 tie 0。

状态 / 遥测：

```
busy, done, fault, error_code[7:0], task_cycles[63:0], compute_cycles[31:0],
read_blocks, write_blocks, c_collect_groups, c_collect_cycles,
c_raw_bypass_cycles, pe_drain_cycles[7:0], array_drain_cycles[7:0],
stat_c48_beats, stat_a16_words, stat_a16_bytes, stat_fifo_high,
stat_fifo_stalls, stat_c48_ddr_bytes (=0), stat_drain_cycles,
stat_last_w_cycle, stat_dma_done_cycle, stat_tiles[15:0]
```

AXI：

```
// 读主口：A/W（以及可选 C）加载；40-bit 地址，AXI4 INCR，128-bit
rd_m_axi_araddr[39:0], arlen[7:0], arsize=4, arburst=INCR,
arvalid/arready, rdata[127:0], rresp, rlast, rvalid, rready

// 写主口：只有 A16；40-bit 地址
wr_m_axi_awaddr[39:0], awlen, awsize=4, awburst=INCR,
awvalid/awready, wdata[127:0], wstrb[15:0], wlast, wvalid, wready,
bresp, bvalid, bready
```

DMA 遥测：`rd_read_bytes/rd_read_bursts/wr_write_bytes/wr_write_bursts/
rd_ar_outstanding_max/wr_b_outstanding_max`。

### 1.3 完成 / 错误语义

- `done = engine_done && !fault && !writer_busy && !buffer_busy && !tile_written`。
  engine 的 `result_ready` 被本 top 延迟到该 tile 的 A16 写 **B 响应排空**之后；
  因此 engine 不会提前覆盖 2 KiB 重排缓冲。
- `fault = engine_fault || frame_err || buffer_dup_err || fifo_overflow ||
  writer_fault`。
- `error_code` 选择顺序：engine code → framer `0x51/0x52/0x53` → buffer
  `0x61/0x62` → FIFO `0x54` → writer `0x71/0x72`。
- **没有 abort/drain 输入**：matrix engine / storage 交付件本身没有 abort/drain
  端口。本 top 遇到桥接侧错误时用 `flush` 停止数据并置 fault，但不声称已 drain；
  reset 是唯一完整清理。整机若需要 abort/drain，需要在 engine/storage 增加端口，
  这不是本任务改写的范围。

### 1.4 A16 输出契约

- 每个 32×32 tile：1024 个 signed int16，**row-major**，2048 B。
- tile 基址：`cfg_a16_base + (block_row*ceil(cfg_n/32) + block_col)*2048`。
- 写 burst：DMA 自动切成 ≤16 beat、≤4 KiB；本负载 main 为 8 burst × 16 beat，
  n64 为 16 burst。
- 最后字默认 16 B 全有效；odd-tail 支持 1..16 B，WSTRB=`(1<<n)-1`。
- 未使用 M/N 区域为 0（engine 的 av/wv 门控），与未融合 C48 布局一致。
- **不是** per-channel 反量化后的语义；只是 C48 → F32 → FMA(scale,bias) →
  （可选 ReLU）→ I16 的广播融合。

### 1.5 与共享 AXI xbar 的接入

- 读主口只发 AR/R；写主口只发 AW/W/B。可以直接接 integrated 的
  `v023_axi_shared`（5 read / 3 write）中的一个 read owner + 一个 write owner。
- 本 top 的地址是 40-bit；`ARENA_END=0x08000000` 只是 storage 的 ACL，AXI 地址
  不做 32-bit 截断。
- 读/写并发由 xbar 负责；本 top 内部没有共享总线仲裁，也不声称 DDR/HP 拓扑。

---

## 2. 桥接子模块

| 模块 | 作用 | 关键契约 |
|---|---|---|
| `fusion_c48_framer` | cseg/cval 节奏检查、tile-last、row-major 字号 | `TILE_BEATS=256, SEG_BEATS=4, SEG_PER_TILE=64`；cval_last 必须是每 4 beat 一次；第 256 beat 生成 tile_last；`out_tag[6:0]` = 0..127 |
| `fusion_c48_fifo` | 弹性 FIFO + credit/occupancy | `DEPTH` 2 的幂；`in_ready=(count<DEPTH-1)`；`credit=DEPTH-1-count`；overflow sticky；flush 清指针不清 sticky |
| `fusion_a16_blockbuf` | 128×128b row-major scatter/drain | `addr_mode=0` 用 tag 地址（融合）；`=1` 线性（未融合/odd-tail）；`cfg_words=128`；重复写地址置 `err_duplicate`；drain 完清空 |
| `fusion_a16_writer` | tile → 写 DMA + B 排空 | `words` 1..128，`last_bytes` 1..16；`done` 只在 `dma_done` 后；`cyc_last_w/cyc_dma_done` 遥测 |
| `fusion_c48_gearbox` | 未融合 C48 读回 16B→24B 重组 | 3 个 128-bit beat → 2 个 192-bit group；`GROUPS=256`；`out_last` 第 256 组；只在未融合 top 使用 |

---

## 3. 未融合基线顶层 `matrix_stream_unfused_top`

文件：`rtl/matrix_stream_unfused_top.sv`。

- 内部实例化 **未修改的** `matrix_p2_cluster_v2`（真实 engine+storage+读 DMA+
  C48 写 DMA）。
- matrix done 后，按 tile 串行：
  `read DMA (384×16B) → gearbox (256 group) → epilogue → blockbuf(linear) →
   writer → A16 write DMA`。
- 端口比融合 top 多两个 AXI 主口：
  - `m_rd_*`：matrix A/W 读；
  - `m_wr_*`：C48 写；
  - `rb_*`：C48 读回（只 AR/R）；
  - `a16_*`：A16 写。
- 地址：`cfg_c48_base`（每 tile 6144 B）与 `cfg_a16_base`（每 tile 2048 B）
  必须彼此不重叠、也不与 A/B 重叠；本次用 `0x03010000/0x03020000`。
- 完成语义：`cluster_done`（含 `cwr_idle`/B 排空）→ 每 tile 读回 → A16 写 B 排空
  → 下一 tile / `state==S_FIN`。`fault` 包括 cluster fault、readback error、
  buffer dup、writer fault。
- 该 top 是**对照基线**，不是推荐的系统顶层；它的 store-then-reload 调度比融合
  多 12288 B/tile 的 C48 往返，周期也更长（见 REPORT §5）。

---

## 4. 唯一 filelist

- `filelist_fused.f`：25 个文件 / 25 个 module，无重名。包含 ds_matrix 12 个
  candidate RTL、primary 8 个 candidate RTL、5 个本目录 rtl。
- `filelist_unfused.f`：28 个文件 / 28 个 module，无重名。额外包含
  `matrix_p2_cluster_v2.sv` 和 `fusion_c48_gearbox.sv`。
- 默认不要加入 `integrated/optional/approx/*`；本链不使用 approx。
- `asr_fma_ip.sv` 是 primary 候选里原有的 compile-only 文件；本链不使用 op17。

---

## 5. 定时/复位/背压

- 所有逻辑单时钟；FIFO/BRAM/重排缓冲都是同步读或组合读的寄存器阵列。
- `fault` 后桥接侧 `flush` 停止接收；没有异步 abort。
- 5 种背压模式由 TB 的 AXI slave 产生：
  - `BP_PCT` 每拍随机 gap（读/写）；
  - `LONG_MODE` bit0=读、bit1=写；窗口内 ARREADY/AWREADY 拉低，且下一次完成后
    插入 `LONG_LEN` 拍数据 gap；
  - AW/AR 命令本身始终有约 12.5% 的 `lfsr[7:5]==3` 背压。
- 写 B 响应没有被 TB 反压（DMA 的 `bready=1`）；B 排空边界通过 `b_out==0`
  和 `last_b/dma_done` 记录，不声称测试了 BREADY=0。

---

## 6. 已验证 / 未验证

**已验证**：M32/N32/K96、M17/N19/K33、M32/N64/K64（2 tile）；5 种 AXI 背压；
广播 scale/bias（含负 scale、非平凡值）、conv-only、scale-only、ReLU；odd-tail
1/3/8/16 B；FIFO 1000 beat 长停顿；FMA 单次舍入 vs mul+add 定向契约；真实 C48
DDR 往返的未融合基线；A16 写 B 排空；写地址窗口。

**未验证/未实现**：per-channel scale/bias；`cfg_spill_fp32`；C-valid=1 的融合回归；
mixed SEQ + direct 并发；abort/drain；完整 591 DAG/executor；approx 集成；CDC；
综合/STA/板卡；全模型 WER/CER。旧 KWT 的精度范围不适用。

---

## 7. 快速接入检查清单

1. 把 `candidate/` 与 `rtl/` 一起编译，保持 `filelist_fused.f` 的唯一 module 集合。
2. 确认 A/B/A16 三个区间不重叠，A16 16 B 对齐，地址在 40-bit 内。
3. 确认 epilogue 配置在 `start` 后、第一批 cval 前完成握手（本 top 自动处理）。
4. 若只用 A16 输出，确认 packed 消费者 ready（本 top 内部已接重排缓冲）。
5. 若接共享 xbar，给本 top 一个 read owner + 一个 write owner；不要把 C48 写
   路径再接回来（融合路径已 tie-off）。
6. 需要 odd-tail 时，用 `fusion_a16_writer` 的 `last_bytes`；需要 per-channel 时，
   必须新增参数存储/索引，当前接口明确不支持。
