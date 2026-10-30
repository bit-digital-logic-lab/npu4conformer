# Verification plan (this export)

## 1. Method

- Real RTL logic simulation with Icarus Verilog 14.0 (`-g2012`).
- One iverilog compile at a time (`-j1` style; no parallel compiles).
- Every `vvp` run has a shell `timeout` and an in-TB cycle watchdog.
- Independent gold: `scripts/sim/gen_v024_graph.py` computes the matrix C48
  result from an independent integer model, then numpy float32 single-rounding
  FMA/ReLU/RNE, without reading RTL output. DIV/SQRT gold is computed from the
  input arrays in Python float64/float32 under the declared tolerance.
- `scripts/analysis/gen_matrix_gold.py` is the independent A16×W7 integer
  model used to produce the 32×32×32 block expectation.
- `REFERENCE_FREEZE.json` is checked before judging; a mutated fixture is a
  hard failure.
- Any mismatch, watchdog, missing PASS marker, missing final B drain on a
  normal run, or non-zero exit makes `run_export.sh` non-zero.
- No old `result.json` PASS and no stub is used as evidence.

## 2. Main tests

| # | Test | Input | Pass criteria |
|---|---|---|---|
| 1 | fused small graph | `mem_v024_fused.hex` mode 0 | `done=1,fault=0,error=0`; A16 512/512 vs `gold_a16.hex`; layout copy 512/512; DIV/SQRT within tolerance; `used=1,c48_ddr_bytes=0`; `b_pending=0,quiesced=1` |
| 2 | explicit fallback | `mem_v024_fallback.hex` mode 1 | `used=0`; legacy C48; I16 512/512 vs `gold_fallback_i16.hex`; drained |
| 3 | multi-consumer fallback | `mem_v024_multicons.hex` mode 4 | `used=0`; legacy completes; drained |
| 4 | bad flag | `mem_v024_badflag.hex` mode 3 | terminal `error=0x04`; no fusion |
| 5 | hold B | `mem_v024_fused.hex` mode 2 + held B | `fault=1,error=0x0E,isolation=1,requires_reset=1,b_pending>0,quiesced=0`; no new AR/AW/W |
| 6 | directed FMA | `lane_vectors.hex` | 64/64 vs single-rounding `lane_gold.hex`; ≥16/64 differ from `mul`+`add` |

## 3. Focused baseline smoke

`sim/tb/tb_safety_integrated.sv` on `v023_integrated_top` (default header,
`FUSION_ALLOW` clear):

| Test | Mode | Expected |
|---|---|---|
| normal | 0 | `SAFETY_RESULT PASS`, drained |
| multitask | 5 | `SAFETY_RESULT PASS`, drained |
| bad queue magic | — | `error=0x03` |
| bad vector op | — | `error=0x07` |
| hold B | — | `error=0x0E`, isolation, requires_reset |

This is a focused smoke, **not** the full V0.23 26-test closeout.

## 4. What is not covered

- full 591-tensor DAG, CASE0000, ONNX/WER/CER;
- sealed payload re-lowering and host executor;
- synthesis, Vivado, STA, Fmax, CDC/multi-clock;
- board DDR/HP topology, MIG/PHY, VNC, push;
- per-tile per-channel table DMA (the table is a one-time preload);
- 4-lane op17 FMA; this export uses the single-lane unified vector numeric path.
