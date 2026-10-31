#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
python3 skill/traffic_ledger/scripts/selftest.py
python3 skill/traffic_ledger/scripts/roofline_selftest.py
python3 skill/module_activity_waveform/scripts/selftest.py
python3 skill/traffic_ledger/scripts/roofline.py data/roofline_spec.json --out data/roofline_recomputed.json
python3 skill/traffic_ledger/scripts/analyze.py data/integrated_trace.jsonl --out sim/ledger_fixed
python3 skill/module_activity_waveform/scripts/render.py data/integrated_trace.jsonl --out report/activity_fixed.html
if [ -f sim/ledger_fixed/REPORT.md ]; then mv sim/ledger_fixed/REPORT.md sim/ledger_fixed/report.md; fi
python3 sim/verify_metrics.py
python3 sim/plot_roofline.py
