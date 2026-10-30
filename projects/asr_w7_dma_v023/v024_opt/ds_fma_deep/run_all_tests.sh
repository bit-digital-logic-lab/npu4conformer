#!/usr/bin/env bash
# Sequential (-j1) rebuild + full regression for ds_fma_deep.
# Every simulation has a SystemVerilog cycle watchdog and a Python wall-clock
# watchdog.  Any mismatch, watchdog hit or count error -> non-zero exit.
set -u
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

mkdir -p sim logs vectors
echo "==============================================================="
echo " ds_fma_deep regression  $(date -Iseconds)"
echo " model: opencode-go/deepseek-v4.1-flash  (logic simulation only)"
echo "==============================================================="

python3 scripts/run_regression.py
rc=$?
echo "run_regression.py rc=$rc"
exit $rc
