#!/usr/bin/env bash
# Re-run the complete ds_epilogue_channels v024 regression.
# Real Icarus RTL simulation, serial compile, per-run watchdog, independent gold.
set -euo pipefail
cd "$(dirname "$0")"

rm -f RUN_RESULT.json result.json NEGATIVE_CONTROL.json

python3 scripts/gen_vectors.py
python3 scripts/freeze_reference.py --check
python3 scripts/run_suite.py
python3 scripts/negative_control.py
python3 scripts/finalize.py

echo "PASS: RUN_RESULT.json, NEGATIVE_CONTROL.json and result.json refreshed"
