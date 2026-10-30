#!/usr/bin/env bash
# Re-run only the evidence merge / freeze / result step (no simulation).
# Useful when run_all.sh has already produced the suite logs.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/audit_metrics.py > logs/metric_audit.log 2>&1 || true
bash scripts/selftest_failure_rc.sh > logs/selftest_stdout.log 2>&1
python3 scripts/summarize.py > logs/summary_stdout.log 2>&1
rc=$?
python3 scripts/freeze_refs.py > logs/freeze_stdout.log 2>&1
python3 scripts/make_result.py "$rc" > logs/result_stdout.log 2>&1 || true
sha256sum rtl/*.sv tests/*.sv scripts/*.py fixtures/official/meta.json \
  fixtures/gold/meta.json fixtures/edge/meta.json INTERFACE.md REPORT.md README.md \
  result.json REFERENCE_FREEZE.json progress.json > SHA256SUMS.txt
sha256sum $(ls logs/*.log | grep -v LOGS_SHA256) > logs/LOGS_SHA256.txt
python3 scripts/progress.py 10 complete "suite logs merged; see logs/summary.json and REPORT.md"
echo "FINALIZE rc=$rc"
exit $rc
