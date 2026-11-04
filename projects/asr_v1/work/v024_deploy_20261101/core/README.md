# V0.24 final export — ASR FPGA logic candidate

This is a cleaned, self-contained export of the V0.24 unified small-graph
candidate plus the focused baseline smoke. It is a **single-clock RTL logic
model**, not a synthesised/placed/board design and not the full 512-dim ASR
model.

- Main top: `rtl/graph/v024_unified_top.sv`
- Unique compile list: `filelist.f` (51 selected sources, one definition per module)
- Entry: `bash scripts/sim/run_export_all.sh` (simulate + judge + summary +
  manifest); `bash scripts/sim/run_export.sh` runs only simulate + judge
- Independent judge: `python3 scripts/analysis/check_export.py`
- Manifest: `python3 scripts/analysis/make_manifest.py`

## Quick start (verified configuration)

Dependencies used for the recorded run:

- Icarus Verilog 14.0 (`iverilog -g2012`, `vvp`)
- Python 3.12 with NumPy
- bash `timeout`, `sha256sum`

```bash
cd final_export
bash scripts/sim/run_export_all.sh
```

The script:

1. regenerates the deterministic small-graph fixtures and independent gold;
2. compiles serially (`-j1` style, one iverilog at a time);
3. runs every simulation with a shell `timeout` and an in-TB watchdog;
4. requires `b_pending=0 quiesced=1` on every normal completion;
5. runs an independent judge that first verifies `sim/fixtures/REFERENCE_FREEZE.json`;
6. runs a focused baseline smoke on `v023_integrated_top`;
7. exits non-zero on any failure.

The recorded run and its rc are in `docs/verification/logs/rc.tsv` and
`docs/verification/RESULTS.md`.

## What is exercised

| Path | Evidence |
|---|---|
| fused MAT (explicit `MATF` + `A16C`) + per-column scale/bias + DIV/SQRT + A16 copy | 512/512 A16 words vs independent gold; layout copy 512/512; C48 DDR = 0 B; A16 = 2,048 B; drained |
| explicit fallback (`queue_count=2`, untagged consumer) | legacy C48; I16 512/512 vs independent gold; `used=0`; drained |
| multi-consumer fallback | legacy completes; `used=0`; drained |
| `MATF` without `FUSION_ALLOW` | terminal `error=0x04`, no fused work |
| held A16 write B | `fault=1,error=0x0E,isolation=1,requires_reset=1,b_pending>0,quiesced=0` |
| directed FMA | 64/64 single-rounding vs gold; 64/64 differ from `mul`+`add` |
| baseline smoke (`FUSION_ALLOW` clear) | normal/multitask/bad-queue/bad-vec/hold-B focused smoke |

Measured small-graph cycles (logic only, not additive): fused 18,724;
fallback 16,973; multi-consumer 19,749; bad flag 383; hold-B 30,720. DIV worst
relative error ~9.102e-4, SQRT ~5.089e-6. See
`docs/performance/MEASURED.md`.

## What is NOT included / not claimed

- **No full model**: the 512-dim ASR / 591-tensor DAG, CASE0000, ONNX input,
  sealed payload re-lowering and complete host executor are missing. The small
  fixtures are not a substitute.
- **No synthesis/STA**: no Vivado, no Fmax, no gate count, no power, no
  CDC/multi-clock proof.
- **No board**: no DDR PHY/MIG/HP topology, no VNC, no bitstream, no push.
- **No frequency or whole-model seconds**: the old ~150 s is an old platform
  number and cannot be transferred. Cycle counts are for the named fixtures.
- **No WER/CER**: the old KWT accuracy range does not apply to this 512-dim
  model.
- **Approximate DIV/SQRT** is intentional; exactness is not claimed.
- **Per-channel table** is a one-time host preload before START, not per-tile
  DMA and not PL autonomous refill.
- **Deferred optimisations** (storage v3, layout wide, W reuse, fusion
  dual-bank, epilogue ping-pong/FP32, graph lookahead, vector op17) are not in
  `rtl/`. See `assets_manifest/UNSELECTED.md` for measured reasons.

## Integration honesty

`ds_adversarial_review` rejected integration at its cutoff (AR-012: fallback
rc=143, no result at that time). The unified stage later froze a final
`result.json` with all six simulations rc=0. This export reruns the frozen
sources rather than relabelling the old snapshot. The main agent still performs
final acceptance; a zero exit here is not automatic acceptance. Details:
`docs/design/INTEGRATION_STATUS.md`, `docs/verification/ADVERSARIAL_FINDINGS.md`.

## Layout

```text
rtl/{matrix,memory,dma,vector,layout,graph,epilogue,common}/
sim/{tb,fixtures}/
scripts/{sim,analysis}/
software/
docs/{design,verification,performance}/
skills/
assets_manifest/
```

`assets_manifest/OLD_TO_NEW.csv` and `SOURCE_SHA256.json` map every exported
file to its read-only origin and SHA-256. No original directory was moved or
deleted.

## Baseline provenance

The unified stage's `unified/rtl` started as a byte copy of
`v023_repair/ds_closeout_safety/rtl`; the modified base files and per-file
hashes are in `docs/design/BASE_SOURCE_SHA256.json`. The selected numeric FMA
is the repaired `ds_repair_fmaflush` core (`3c1114bc…`, AR-001 closed), not the
earlier `b062284a…`.
