# Asset manifest

| File | Purpose |
|---|---|
| `ORIGIN_MAP.json` | new export path -> original read-only path |
| `OLD_TO_NEW.csv` | flat old -> new -> SHA table |
| `SOURCE_SHA256.json` | every export file with SHA-256 and origin |
| `FILE_SHA256.txt` | `sha256sum -c` compatible list |
| `SUMMARY.json` | file/module counts and duplicate check |
| `UNSELECTED.md` | deferred/rejected optimisations and reasons |
| `MISSING_ASSETS.md` | large/missing original model assets |

Regenerate/verify with:

```bash
cd final_export
python3 scripts/analysis/make_manifest.py
sha256sum -c assets_manifest/FILE_SHA256.txt
```

The manifest script also parses `filelist.f`, fails on a missing path or a
module defined twice, and verifies `sim/fixtures/REFERENCE_FREEZE.json`.

## Provenance notes

- RTL/TB/generator files come from
  `v024_opt/ds_unified_graph/unified/` (byte-for-byte).
- `scripts/analysis/gen_matrix_gold.py` is a copy of
  `v023_repair/ds_matrix/tests/gen_engine_vectors.py` (independent integer
  model, no RTL import).
- `scripts/sim/gen_v024_graph.py`, `scripts/analysis/check_export.py`,
  `sim/tb/tb_v024_unified.sv`, `sim/tb/tb_v024_epilogue.sv`,
  `sim/tb/tb_safety_integrated.sv` and
  `sim/fixtures/REFERENCE_FREEZE.json` have **path-only** edits for this
  layout (`HERE` depth, `sim/fixtures`, TB default fixture paths, and the local
  matrix gold path). No numeric constant, seed, tolerance or fixture byte was
  changed.
- `sim/fixtures/mat32/*` is regenerated deterministically by the entry script;
  its `exp_c.txt`/`init.hex` hashes are recorded in its `manifest.json`.
- Skills are copied from the project `skills/` snapshot.
- Docs and `software/` are authored for this export and are not RTL evidence.
