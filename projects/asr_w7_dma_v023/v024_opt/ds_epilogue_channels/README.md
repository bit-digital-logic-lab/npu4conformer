# ds_epilogue_channels — v024 per-column epilogue candidate

Base: read-only `v023_repair/primary_stream_fix` (`primary_stream_fix`,
not the old Gemini biasvalid-bug version).  Only this directory is written.

## What this is

A module-level RTL candidate for the C48 → FP32 → FMA(scale,bias) → optional
ReLU → A16 epilogue with:

- 2 ping-pong banks × 32 columns of 32-bit scale and bias, per-entry valid;
- one 32-bit parameter-DMA write port; inactive-bank preload while the active
  bank streams; active-bank writes only when the engine is drained;
- explicit `cval_bc[15:0]` / `cval_col[4:0]` sideband, with the framer
  word-tag → bc/column mapping in `INTERFACE.md`;
- A16 and packed A16 outputs (primary_stream_fix semantics), plus an optional
  independent 4×FP32 post-ReLU output with its own `valid/ready`;
- scalar compatibility: table miss falls back to legacy broadcast addr 0/1
  preload, then to `cfg_scale/cfg_bias`.

No residual add or reassociation is implemented.  The FP32 output is the exact
post-ReLU value for a downstream IEEE-754 RNE residual add (see
`INTERFACE.md` §6).

## Files

- `rtl/` — 7 RTL files, unique modules; `filelist_v024.f` is the single
  integration filelist.
- `tb/tb_epilogue_channels.sv` — real RTL testbench, command/parameter streams,
  independent output backpressure, stability assertions, cycle watchdog.
- `ref/refmodel.py` — copied independent exact Fraction FP32 reference.
- `scripts/gold_model.py` — independent per-column gold (does not parse RTL).
- `scripts/gen_vectors.py` — deterministic stimulus/scenario generator.
- `scripts/run_suite.py` — serial compile + per-run watchdog + comparison.
- `scripts/negative_control.py` — broken-RTL control that must fail.
- `scripts/freeze_reference.py` — frozen reference metadata write/check.
- `scripts/finalize.py` — builds `result.json` from fresh run artifacts.
- `REFERENCE_LOCK.json` — frozen gold/vector/v023-source hashes.
- `INTERFACE.md`, `REPORT.md`, `USER_UPDATES.md`, `progress.json`.

## Re-run

```bash
bash run_all.sh
```

It regenerates deterministic vectors, verifies the frozen reference, compiles
serially with Icarus, runs every scenario under a wall-clock watchdog, runs the
negative control, and refreshes `result.json`.  Any failure exits non-zero.
A single scenario can be inspected in `logs/<name>.log` and `.out`.

## Scope / not claimed

Only module-level Icarus logic simulation.  No synthesis, Vivado/STA, board,
VNC or push.  No frequency, whole-model seconds, WER/CER or full-graph claim.
This module has no AXI/B channel; the completion boundary tested here is the
last A16/packed/FP32/spill handshake.  `ds_fusion_buffers` was not edited;
integration is via `INTERFACE.md` only.
