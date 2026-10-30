#!/usr/bin/env bash
# Reproduce the ds_closeout_fusion regression: compile (Icarus, serial -j1),
# regenerate fixtures, run every logic simulation under a subprocess timeout,
# compare with the independent golden, and write result.json + logs + SHA.
set -u
cd "$(dirname "$0")/.."
python3 scripts/run_all.py
rc=$?
python3 scripts/finalize.py
exit $rc
