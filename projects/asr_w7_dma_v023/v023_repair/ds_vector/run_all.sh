#!/bin/sh
# Serial by design: one iverilog/vvp process at a time (no -j parallel jobs).
set -e
python3 scripts/gen_fixtures.py
python3 scripts/run_regression.py
python3 scripts/run_axi.py
python3 scripts/run_approx.py
python3 scripts/finalize_result.py
