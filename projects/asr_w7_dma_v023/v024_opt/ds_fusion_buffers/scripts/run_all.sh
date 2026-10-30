#!/usr/bin/env bash
# Reproduce ds_fusion_buffers: serial Icarus compile (-j1), fixtures, gold,
# every simulation under a watchdog, independent comparison, ledger, REPORT, SHA.
# Any required failure returns non-zero.
set -u
cd "$(dirname "$0")/.."
python3 scripts/run_all.py
rc=$?
python3 scripts/finalize.py
frc=$?
python3 scripts/make_report.py
mrc=$?
# Refresh SHA256SUMS.txt now that REPORT.md has been rendered.
python3 scripts/finalize.py
frc2=$?
if [ "$rc" -ne 0 ]; then exit "$rc"; fi
if [ "$frc" -ne 0 ]; then exit "$frc"; fi
if [ "$mrc" -ne 0 ]; then exit "$mrc"; fi
exit "$frc2"
