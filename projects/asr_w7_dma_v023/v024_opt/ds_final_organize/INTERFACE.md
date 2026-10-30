# INTERFACE — ds_final_organize（最终整理 / 清洁导出）

Status: **complete (logic-simulation export)**. Writable scope: this directory
only. All other `v024_opt/ds_*`, `v023_repair/**`, `work/**` and ZIPs are
read-only inputs.

Final observed export entry: `EXPORT_ALL_PASS`, rc=0; 6 unified simulations +
5 focused base-smoke runs all rc=0; independent judge `V024_CHECK PASS`;
`sha256sum -c` 150 files OK. Main-agent acceptance is still separate.

## 1. Inputs (frozen before copying)

- `v024_opt/REVIEW_DECISIONS.md`, `REVIEW_INPUT.txt`, `v024_opt/README.md`,
  `PRIMARY_PROGRESS_REVIEW*.md`, `REPAIR_FOLLOWUPS.json`
- `/home/yang/Desktop/项目/README.md`
- `v023_repair/{integrated,ds_closeout_safety,ds_closeout_numeric,
  ds_closeout_fusion,ds_matrix,ds_vector,ds_layout,ds_graph,
  primary_stream_fix}` REPORT/INTERFACE (latest)
- `v024_opt/ds_unified_graph/{REPORT,INTERFACE,MERGE_TABLE,result,exit}`
- `v024_opt/ds_adversarial_review/{REPORT,FINDINGS,result,exit}`
- Every V0.24 worker `result.json` / `exit.json` / `USER_UPDATES.md`

Integration status used for selection: `ds_unified_graph` final
`result.json` rc=0 with fused/fallback/multicons/badflag/hold/lane all rc=0;
the earlier AR-012 review rejection is a pre-freeze snapshot. This task
**re-runs** the unified entry before exporting and records the observed rc.
Main-agent acceptance is still separate; exit 0 alone is not acceptance.

## 2. Export layout

```
final_export/
  rtl/{matrix,memory,dma,vector,layout,graph,epilogue,common}/  one selected .sv per module
  sim/{tb,fixtures}/                                            TB + frozen fixtures
  scripts/{sim,analysis}/                                       isolated rerun + checks
  software/                                                     host/CSR notes & helpers
  docs/{design,verification,performance}/                       design, evidence, limits
  skills/                                                       reusable transfer-ledger skill
  assets_manifest/                                              SHA-256, old->new map, asset gaps
```

Rules applied:

1. **One selected source per module.** 4x4 / duplicate worker trees and
   deferred candidates are not copied into `rtl/`; they stay in their original
   directories and are listed with reasons in `assets_manifest/UNSELECTED.md`.
2. `final_export/filelist.f` is rewritten to the exported relative paths; the
   old absolute-path filelists are not reused.
3. `scripts/sim/run_export.sh` compiles `-j1`, runs every simulation with a
   shell `timeout` and TB watchdog, requires the final B drain on normal
   completion, and exits non-zero on any mismatch.
4. `scripts/analysis/check_export.py` is an independent judge; it verifies
   `REFERENCE_FREEZE.json` and the exported SHA manifest first.
5. No original directory is moved, deleted or pushed. No synthesis / Vivado /
   STA / board / VNC / push. No frequency or whole-model-seconds claim.

## 3. Honest status labels

- `BASELINE-INTEGRATED`: the small-graph unified candidate
  (`v024_unified_top`) after this task's rerun. It is **not** the full 591
  tensor DAG and not a board build.
- `MODULE-PASS-LOCAL`: a V0.24 module/cluster that passed its own and/or the
  independent review, but is not in the unified top. Exported only as a
  documented candidate, never as integrated.
- `DEFERRED`: measured failure or ABI conflict in the unified plan; not copied
  to `rtl/`.

## 4. Non-claims

No synthesis/STA/Fmax, no board DDR/HP topology, no CDC/multi-clock, no
591-tensor sealed payload, no ONNX/host executor, no WER/CER, no whole-model
seconds.
