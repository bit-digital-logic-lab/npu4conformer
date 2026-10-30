# REPORT — ds_matrix V0.23 matrix P2 unified candidate

Date: 2026-10-29  
Task directory: `/home/yang/Desktop/项目/v023_repair/ds_matrix`  
Scope: **logic simulation only**.  No synthesis, Vivado, DRC/STA, board,
VNC, network deployment or push.  All original `work/`, ZIP, old competition
repository and other workers' files were read-only.

## 1. Executive result

The three mature ds_storage_overlap modules were copied and then re-audited,
not blind-copied.  The unified candidate now has:

1. A/W double-stage prefetch and a posted C48 stream (from
   `block_storage_stream_v1` / `operand_banks_dual_v1` /
   `block_engine_prefetch_v1`).
2. A true **II=1** C read-modify-write cache
   (`c_cache_banked4_pipe`): read of group g+1 and write of group g in the same
   cycle, with registered array MUX and final-result bypass.
3. Parametric PE depth 3/4/5/6 from ds_pe_pipeline, with real
   `array_drain_done`; no hard-coded 61/65 and no RUN-exit flush.
4. ds_ddr multi-outstanding DMA with PA-003 (40-bit address / no 4 GiB wrap),
   PA-004 (`write_bytes=popcount(WSTRB)`) and PA-014 (B-credit underflow) fixed.
5. An AXI cluster wrapper and a real AXI128 BFM run, plus
   traffic-ledger and module-activity-waveform output from the same cycle trace.

Same workload, same BFM stalls, same fixtures (M64 N32 K96, C=0, fast BFM):

| implementation | cycles | vs V020 |
|---|---:|---:|
| V020 baseline (`work/rtl/...`) | 11839 | 1.00x |
| ds_storage_overlap V1 (reported) | 5896 | 2.01x |
| **this candidate PIPE=4** | **4552** | **2.60x** |

The gain is not a PE-frequency claim: PE RUN is unchanged in arithmetic and
grows by one cycle per added pipeline stage; the cycle reduction comes from the
C collect and the already-prefetched A/W path.

## 2. What was copied and what was actually changed

### 2.1 Storage side

- `block_storage_stream_v2.sv` is `block_storage_stream_v1` plus:
  - `write_bytes` from actual WSTRB (`pop16`) instead of 16 B/beat;
  - 64-bit end checks (`ld_no_wrap`) and C-segment 32-bit/64-bit overflow
    rejection.
- `operand_banks_dual_v2.sv` is the V1 dual bank.  Its A row/half/chunk and W
  k/column mappings were re-derived and checked against the 32x32 layouts in
  `tb_storage_unit` (2048 A16 + 1024 W7 values).
- The V1 storage still owns the stage release/credit/error-drain contract;
  the engine's stage usage was checked against it.

### 2.2 Engine / C cache

- `block_engine_prefetch_v2.sv` replaces the V1 array with
  `array16_w7_c48_cfg #(.PIPE_STAGES(...))`.
- `RUN` exits on `run_cycle >= k_local+14 && array_drain_done`.
- `flush = reset || state==FAIL` only.  CLEAR uses `clear_sum`; quadrant
  transitions therefore do not discard in-flight products.
- C collect uses `c_cache_banked4_pipe`:
  - synchronous BRAM read, separate write port;
  - group g+1 read while group g is written;
  - 256:4 array MUX captured into `pipe_sums` with the read address;
  - result taken from `collected_values` for both cache write and cval, so the
    final result is not read back from BRAM;
  - same-address read/write bypass (`raw_bypass_pulse`) for cross-K / last-group
    RAW.  Measured `craw=0` in the normal fixtures because the read/write
    groups differ; the directed `tb_cache_pipe` forces the bypass case.
- The first C group of each 16-value segment spends one cycle accepting
  `cseg`; the other three groups are II=1.  This is the measured 1.59
  cycles/group, not a 1.00 estimate.

**A real bug found by the old-C regression:** the first draft used
`{slot[0],1'b0}` (2 bits) for the cache group base.  For slot 1 this selected
group 2 instead of 256, so the second output block read/wrote block 0's C.
`run_pipe4_c1` failed with 7135 mismatches.  The fix is
`{slot[0],8'd0}+...`.  This is why the old-C case and multi-block cases were
rerun; the V1 report alone would not have caught it.

### 2.3 DMA side

`axi_dma_v020_multi_v2.sv` is ds_ddr's `axi_dma_v020_multi` with:

- 40-bit internal `next_addr` and full 40-bit AXI address (PA-003);
- `write_bytes += popcount(write_strobe)` (PA-004);
- no `b_out` underflow on a spurious B; error sticky instead (PA-014);
- elaboration checks for `MAX_OUT` power-of-two, `MAX_BURST<=16`,
  `FIFO_BEATS>=MAX_OUT*MAX_BURST`.

The read DMA keeps multi-AR + 128-beat FIFO; the write DMA keeps posted AW/B.
The storage's read/write transaction ports remain separate.

## 3. Measured regression (same fixtures/BFM)

All commands and rc are in `logs/commands.log` (62 commands, 0 nonzero);
per-run output is in `logs/metrics.txt` and `logs/run_*.log`.

| case | result | cycles | notes |
|---|---|---:|---|
| normal K96 C0, PIPE=3 | PASS | 4528 | adrain=19 |
| normal K96 C0, PIPE=4 | PASS | 4552 | adrain=20 |
| normal K96 C0, PIPE=5 | PASS | 4576 | adrain=21 |
| normal K96 C0, PIPE=6 | PASS | 4600 | adrain=22 |
| old C (C=1), PIPE=4 | PASS | 5329 | 2 C loads, 1920 read beats |
| multi-N M32 N64 K64 | PASS | 3468 | 2 output blocks |
| K1 M32 N32 K32 | PASS | 4147 | one K tile, one output block |
| edge M17 N19 K33 | PASS | 5236 | partial 16x16 rows/cols and K tail=1; 512 C groups |
| positions=0xCCCC, clip=1 | PASS | 4147 | P=12 saturation path against independent golden |
| write backpressure `WR_GAP=60,B_DELAY=40` | PASS | 26701 | `cwr_pending=0` |
| read error drain | PASS_FAULT | 137 | code 09, `cwr_pending=0` |
| write error drain | PASS_FAULT | 1384 | code 0a, `cwr_pending=0` |
| bad W parity | PASS_FAULT | 203 | code 09, `cwr_pending=0` |
| seeds 1/2/3 | PASS | 4554/4554/4553 | output stable |
| V020 baseline K96 C0 | PASS | 11839 | read-only work RTL |
| V020 baseline K96 C1 | PASS | 13132 | read-only work RTL |
| V020 baseline backpressure | PASS | 34620 | read-only work RTL |

The 16x16 result payload is bit-identical to the independent integer golden in
every engine case.  The golden generator was rerun from scratch and its
`init.hex`/`exp_c.txt` compare byte-for-byte with the copied fixtures
(`run compare_golden_k1`, `run compare_golden_c1`, both rc=0).

## 4. AXI and multi-outstanding evidence

`tb_dma_multi` (directed, Icarus) covers:

- multi-AR read, FIFO full + same-cycle push/pop;
- early/late RLAST, RRESP error drain, BRESP abort;
- WVALID bubbles and tail strobe;
- zero-length/unaligned rejection;
- 4 GiB crossing (`0xFFFFFFF0`, 2 beats -> `0xFFFFFFF0`, `0x100000000`, not 0);
- W2: last WSTRB `0x0007` -> `write_bytes=51` (old metric said 64).
- Result: `MULTI_TEST_END errors=0`.

`tb_strobe`: `mem=00 01 02 00`, `write_bytes=3`, PASS.

AXI cluster (`matrix_p2_cluster_v2` + two `axi_dma_v020_multi_v2` + shared AXI128
BFM):

| run | engine cycles | rd_bursts / bytes | wr_bursts / bytes | max AR | max B |
|---|---:|---:|---:|---:|---:|
| K32 | 2704 | 12 / 3072 | 65 / 6144 | 8 | 2 |
| K96 C=1 | 8707 | 120 / 30720 | 130 / 12288 | 8 | 2 |

The 65th write burst in K32 is a real 4 KiB split of the 96-byte segment at
`0x3FC0`, not an extra tensor.  `wr_bytes` is exactly 64 x 96 = 6144 B
(K32) and 128 x 96 = 12288 B (K96 C1).

Runtime autonomy in this test: the BFM memory is preloaded once before `start`;
after `start` the engine/storage issue all A/W/C reads and C writes from their
own descriptors, and the testbench only waits for `done`.  It does not issue
per-block host reads/writes.  This is a PL-side DMA control model; the physical
Zynq PS hard DDR controller/SmartConnect topology is unchanged and is not
claimed to be bypassed.

## 5. Traffic ledger and module activity

The project skills were run on the actual `valid&&ready`/FSM trace; no module
activity was estimated.

- `traffic/cluster_k1.jsonl`, `traffic/report_k1/`:
  - window 0..2708 cycles, 100% coverage on all 7 resources;
  - axi_r 3072 B, axi_w 6144 B; ledger-minus-interval = 0 for both;
  - no duplicate candidate (single output block).
- `traffic/cluster_c1_k96.jsonl`, `traffic/report_c1_k96/`:
  - window 0..8711 cycles, 100% coverage;
  - axi_r 30720 B, axi_w 12288 B; ledger-minus-interval = 0 for both;
  - W: 6 transfers / 6144 B total, 3072 B unique, **3072 B repeat candidate**
    because the second output block reloads the same three W blocks.
- `activity/cluster_k1.html` and `activity/cluster_c1_k96.html` are offline
  interactive waveforms with lanes `axi_r, axi_w, ddr_bfm, compute,
  c_cache_rd, c_cache_wr, packer`; each has a `.summary.json`.

The `ddr_bfm` lane is a shared BFM data-channel observation.  Its payload bytes
are the union of the two masters (9216 / 43008 B), so its
`ledger_minus_interval_valid_bytes` is intentionally negative
(-9216 / -43008).  It has no independent tensor identity and is **not added**
to the per-master ledgers.  The on-chip `c_cache_rd/wr` and `packer` lanes show
activity/occupancy but 0 off-chip bytes; they are not presented as DDR traffic.

## 6. Resident-A assessment (optional, not selected)

Resident-A would fix an A row strip on chip and stream W column blocks.  For
this engine:

- A block = 2048 B, W block = 1024 B, C block = 6144 B.
- Current dual-stage bank = 2 x (2048+1024) = 6144 B.
- Reusing A across `bc` requires `nbk` A blocks: K=96 -> 3 x 2048 = 6144 B
  A alone; plus at least two W stages and 2 x 6144 B C cache.  K=4096 ->
  nbk=128, which is not bounded by this bank.
- The 16-row read port count is unchanged, but selecting a resident A stage
  adds a stage mux in front of the array read path.  That is a structural
  trade, and this task has no STA to claim it is free.
- Measured A read is not the current bottleneck: axi_r payload is 7.1% of the
  K32 window and 22.0% of the K96 C1 window.  The K96 C1 ledger shows W, not A,
  as the duplicate candidate (3072 B).

Therefore the unified path keeps A/W double-bank prefetch.  Resident-A (or
resident-W) is left as an optional experiment; no speedup is claimed.

## 7. Limits and unfinished work

- **No full model:** no CASE0000/ONNX/vector/layout integration, no WER or
  accuracy metric in this directory.  The matrix block path is integer only.
  FP32 FTZ/RNE/FMA and QDQ boundaries were not modified or exercised here.
- **No timing:** no synthesis, implementation, STA, DRC or CDC report.  The
  PIPE=4/5/6 split is structural; 300/600 MHz is not claimed.
- **No physical DDR:** the AXI128 BFM models protocol, stalls and multiple
  outstanding requests, not the PS DDR controller/PHY, refresh or board
  topology.  The Zynq PS hard DDR controller is not bypassed.
- **C48 overflow rule:** the PE INT48 accumulation wraps naturally; the engine
  still reports the V020 C-accumulation overflow as fault 8.  That was retained,
  not changed to saturation.
- **Resident-A/W:** assessed, not implemented/measured.
- **CDC:** not implemented; ready/credit paths need boundary registers and an
  async FIFO before any high-frequency claim.
- **Full plan integration:** the wrapper exposes the same config/result shape
  as the block engine, but `pl_execution_plan_v022` / `queued_v020_monitored`
  wiring and a whole-plan run are outside this task.

## 8. Reproduction

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_matrix
bash scripts/run_all.sh          # 62 commands, all rc=0; Verilator -j 1
python3 scripts/collect_metrics.py
```

Individual highlights:

```bash
# C cache II=1 / bypass
vvp /tmp/opencode/mx_build/tb_cache_pipe.vvp
# multi DMA / WSTRB / 4 GiB
vvp /tmp/opencode/mx_build/tb_dma_multi.vvp
vvp /tmp/opencode/mx_build/tb_strobe.vvp
# engine PIPE=4, K96
/tmp/opencode/mx_build/tb_p4 +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
# AXI cluster + trace
/tmp/opencode/mx_build/tb_cluster96 +cvalid=1 \
  +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt \
  +trace=traffic/raw/cluster_c1_k96.csv
python3 scripts/make_trace.py traffic/raw/cluster_c1_k96.csv --out /tmp/t.jsonl
python3 ../skills/traffic-ledger/scripts/analyze.py /tmp/t.jsonl --out /tmp/tr
python3 ../skills/module-activity-waveform/scripts/render.py /tmp/t.jsonl --out /tmp/a.html
```


## 9. 对主验收整改通知的回应（2026-10-29 追加）

已读取 `../primary_acceptance/REPORT.md` 和本目录随后追加的
`USER_UPDATES.md`。 本报告没有沿用任何早期 review/V1 的 PASS：

- 本目录的 27 个 RTL run 都是本次重新编译、重新仿真得到的；V020 baseline
  也是本次只读重跑（11839/13132/34620 cycles）。
- 老 C 用例首次重跑就暴露了 C cache slot base 的真实功能 bug（7135 个
  mismatch），修复后才 PASS；这正是“不得沿用早期 PASS”的具体执行。
- 主验收指出的 **ds_vector 尾包失败**（add_tail5/add_tail7/a48_tail3/
  f16_tail7）不在本任务目录内，本报告不声称它已修复。矩阵侧本任务检查的是
  C48 的 64 个 segment/1024 个输出值；矩阵尾包由 `cseg` 完成计数、
  `cwr_idle`、`write_bytes=6144` 和独立 golden 对照，不能拿来抵消 vector
  尾包问题。
- 主验收指出的 **融合 FMA 非单次舍入** 和 **approx 档位实现不符** 属于
  gemini_epilogue/gemini_approx，本任务没有修改、没有复跑、没有为它们背书。
  本任务只保留整数 A16×W7(S/J/M)→C48 路径，不涉及 FP32 FMA/QDQ。
- 本报告不声明整体验收通过、不声明完整 CASE0000/全图纯 PL；只声明
  `ds_matrix` 矩阵 P2 模块级逻辑仿真的本目录证据。
- 仍无综合/STA/板卡/DDR 物理时序证据；300/600 MHz、CDC、整机性能均未声称。

## 10. Files

- `candidate/rtl/` — the unified candidate and unmodified reference copies.
- `tests/` — BFM, directed tests, cluster AXI test, golden generator.
- `fixtures/` — deterministic integer vectors (regenerated and compared).
- `logs/commands.log`, `logs/metrics.txt`, `logs/run_*.log` — rc and evidence.
- `traffic/`, `activity/` — ledger JSONL/reports and waveforms.
- `INTERFACE.md` — integration contract.
- `FINDINGS.md`, `FINDINGS.jsonl` — findings and limits.
- `progress.json`, `result.json`, `logs/source_sha256.txt` — status/SHA.
