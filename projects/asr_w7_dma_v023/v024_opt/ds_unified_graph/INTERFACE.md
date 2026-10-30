# INTERFACE — ds_unified_graph (v024 unified candidate)

Status (final): **logic-simulation candidate; unified regression PASS in this directory**.
Acceptance is still by the main agent, not by `exit.json` rc alone.
Single clock, no CDC / async FIFO. No synthesis, Vivado/STA, board, VNC or push.
This file is published early so `ds_adversarial_review` and `ds_final_organize`
can test/consume the stage without waiting for `exit.json`.

## 0. Boundary

- Writable: this directory only.
- Read-only: `v023_repair/**`, `work/**`, ZIPs, every other `v024_opt/ds_*`
  worker directory (read their `INTERFACE.md`/`result.json`; never patch their
  sources).
- Only execution model: `opencode-go/deepseek-v4.1-flash`.
- Unique entry: `filelist_v024_unified.f` (created when the build stabilises).
- Fallback: the reliable base is `v023_repair/ds_closeout_safety` (safety top,
  26-test closeout) — copied byte-for-byte into `unified/rtl` before edits.

## 1. Base snapshot and provenance

`unified/rtl` initially equals `ds_closeout_safety/rtl`. Provenance SHA-256 of
every base file is recorded in `SOURCE_SHA256.json`. Reference metadata
(fixtures, gold, plan ABI) is frozen; the V0.24 additions are new modules or
explicitly marked edits, never silent rewrites of the base.

## 2. Explicit fused-MAT descriptor (no automatic swallowing)

Fusion is **opt-in per node** and is never inferred by looking at successors.

- Header word 3 (`flags`) bit 16 (`0x00010000`) = `FUSION_ALLOW`.
  If clear, node words 14/15 must be zero exactly as in V0.23 and fusion is
  impossible.
- A fused MAT node (type `T_MAT=1`) sets word 14 = magic `0x4D415446`
  (`'MATF'`) and word 15 = per-channel parameter block base (or 0 when
  broadcast parameters are used).
- Word 14 layout:
  - `[31:16]` magic `0x4D41`
  - `[15:14]` output kind: 0 = A16 (fused), others reserved/rejected
  - `[13]` per-channel scale/bias table enable
  - `[12]` ReLU enable
  - `[11:10]` FMA mode: 0 conv-only, 1 scale+bias, 2 scale-only
  - `[9:0]` reserved, must be 0
- Validation is conservative; any of the following makes the controller
  **fall back to the legacy MAT path** (C48 output, no fusion):
  - header `FUSION_ALLOW` clear, or word 14/15 non-zero without it;
  - queue count != 1 (dynamic/multi-task parameter lists are not fused);
  - any predecessor of a downstream node also feeds that node (multi-producer
    ambiguity), or more than one consumer of the MAT node is not explicitly
    tagged as an A16 consumer (word 14 magic `0x41313643` `'A16C'` in the
    consumer node, only legal when `FUSION_ALLOW` is set).
- A node that is not fused keeps the V0.23 byte-for-byte semantics.

## 3. Per-channel epilogue

`epilogue_stream_engine_v024` (new copy; base module untouched):

- 32-entry scale table + 32-entry bias table, indexed by column within the
  current 32-column tile (`col = (beat_in_row % 8)*4 + lane`).
- Table preload uses the existing 8-bit `param_wr_addr`: `0..31` = scale,
  `32..63` = bias. Preload only while drained; a broadcast pair remains the
  fallback when `perchannel_en=0`.
- Numeric contract is unchanged: I48->F32 RNE, **single-rounding FP32 FMA**
  (`round(a*b+c)`), optional ReLU, F32->I16 RNE. It is not `mul` then `add`:
  the two differ on directed vectors and the TB records both.

## 4. Vector DIV/SQRT

`ddr_vector_engine_pipe` is compiled with `USE_APPROX_DIV_SQRT=1` and the
`optional/approx` core for the numeric branch. Exactness is **not** claimed:
DIV tolerance ~0.112 %, SQRT ~5.8e-6 (from the independent V0.23 audit).
The TB checks the result against an independent float64/float32 Python gold
under that tolerance and checks the `FLAG_APPROX` marker.

## 5. Safety / drain contract (inherited and not weakened)

- every simulation has a `timeout` and TB cycle watchdog;
- normal completion requires the final A16/C48 B response drained
  (`b_pending==0`, `quiesced==1`);
- fault/drain injection must end with `fault=1`, non-zero exit if the expected
  terminal state is not reached;
- `requires_reset=1` is sticky; START is rejected until reset;
- no old `result.json` PASS and no stub/同源 golden is used as evidence.

## 6. Files (stable names, created during the task)

```
unified/filelist_v024_unified.f     unique compile list
unified/rtl/v024_*.sv               unified additions
unified/rtl/epilogue_stream_engine_v024.sv
unified/scripts/gen_v024_graph.py   independent plan/fixture + gold generator
unified/scripts/run_v024.sh         compile(-j1)/run/watchdog/judge
unified/scripts/check_v024.py       independent judge (non-zero on failure)
unified/tb/tb_v024_unified.sv       small-graph system TB
unified/tb/tb_v024_epilogue.sv      per-channel + FMA vs mul+add TB
```

## 7. Merge policy and final decisions

Select by `exit_code==0` **and** measured evidence SHA; an optimisation that
does not survive the unified regression is not forced in. All patches are
merged only in this directory; no worker source is edited. See `MERGE_TABLE.md`.

Consumed:

- `ds_repair_fmaflush` repaired 7-stage 129-bit FMA core
  (`fp32_fma_pipe.sv` `3c1114bc…`, AR-001 closed).
Deferred with reasons: storage v3 (two-descriptor legacy queue hit the MAT
watchdog in the unified plan), layout-wide (in this plan it exceeded the MAT
watchdog and roughly doubled Icarus wall time), W-reuse (ABI adds `cfg_w_reuse`
and split stage release), fusion dual-bank (broadcast-only top), epilogue
ping-pong/FP32 spill (open AR-006/7 and a wider port list), graph lookahead
(own result rc 1, no MATF descriptor), vector op17 (adds `abort`/`aborted`).
