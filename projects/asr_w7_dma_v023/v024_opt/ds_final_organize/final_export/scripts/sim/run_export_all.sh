#!/usr/bin/env bash
# Full export entry: simulate -> independent judge -> summary -> manifest.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
bash scripts/sim/run_export.sh || exit $?
python3 scripts/analysis/summarize_export.py || exit $?
python3 scripts/analysis/make_manifest.py || exit $?
echo "EXPORT_ALL_PASS"
