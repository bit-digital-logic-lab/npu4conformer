# ds_layout_wide — V0.24 Layout 128-bit beat fast path

Logic simulation only. No synthesis, Vivado/STA, board, VNC or push.
No frequency or whole-model seconds claim.

## What this is

Baseline: V0.23 `ds_layout/rtl/ddr_layout_engine_v023_burst.sv`
(SHA256 `4e45a39d…eb893`), which is also the layout engine selected by
`ds_closeout_safety/filelist_safety.f`. The baseline is frozen in
`rtl/ddr_layout_engine_baseline_burst.sv`.

Candidate: `rtl/ddr_layout_engine_wide.sv`, same module name/ports/descriptor.
It adds a 16-byte (one beat) fast path:

- mode 0 linear copy, `bytes` 2/4, destination beat aligned, source phase free;
- mode 1 / mode 3 in-row beats for `bytes` 2/4, grouped inside one 32-column
  row/tile row and inside `n`;
- scalar fallback for unaligned heads/tails, zero-fill, 6-byte C48 values,
  mode 2/4, row/tile transitions and any ineligible group;
- mode-2 prefetch gate `MODE2_PREFETCH` (default 1) measured separately.

`FASTPATH=0` disables the beat path and reproduces the frozen baseline exactly
(70-case exact counter check).

## Files

| path | purpose |
|---|---|
| `rtl/ddr_layout_engine_wide.sv` | candidate (unique RTL definition) |
| `rtl/ddr_layout_engine_baseline_burst.sv` | frozen V0.23 baseline |
| `filelist_wide.f` | unique RTL compile list |
| `filelist_sim.f` | unique logic-sim compile list |
| `scripts/run_all.sh` | sequential (`-j1`) re-run of every suite |
| `scripts/layout_model.py` | independent Python descriptor model (gold) |
| `scripts/gen_gold_fixtures.py` | 32 original independent-gold cases |
| `scripts/gen_edge_fixtures.py` | 53 new unaligned/tail/4 KiB/row-edge cases |
| `scripts/run_random.py` | 100 preserved + 52 new random/short-tail cases |
| `scripts/run_official_suite.py` | 8 official normal + 12 error/lifecycle |
| `scripts/run_fuzz.py` | 57 descriptor fuzz cases |
| `scripts/measure_mode2.py` | mode-2 gate A/B (gate1 / gate16 / baseline) |
| `scripts/check_scalar.py` | FASTPATH=0 vs frozen baseline, exact equality |
| `logs/summary.json` | machine-readable verdict + totals |
| `REPORT.md`, `result.json` | final report / machine-readable result |

## Re-run

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_layout_wide
bash scripts/run_all.sh
```

The script compiles one binary at a time, gives every simulation an external
timeout in its Python driver plus the in-testbench cycle watchdog, and requires
each normal run to drain all AXI read/write/B activity before `done`.

Independent reference: `scripts/layout_model.py` expands the descriptor
contract element by element. It is not generated from the candidate RTL. The
preserved official fixtures are additionally checked against this model.
