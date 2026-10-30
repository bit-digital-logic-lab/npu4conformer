#!/usr/bin/env bash
# Prove the metric gate fails non-zero on a real missing metric (no masking).
set -euo pipefail
cd "$(dirname "$0")/.."
T=/tmp/opencode/dslw_badlogs
rm -rf "$T"; mkdir -p "$T"
cp logs/official_suite.json logs/gold_edge_suite.json logs/random_suite.json \
   logs/scalar_fallback.json logs/layout_fuzz.log logs/mode2_gate.log "$T"/
python3 - "$T/random_suite.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["rows"][0]["wide"].pop("cycles")          # inject one missing required metric
json.dump(d, open(p, "w"))
PY
set +e
DSLW_LOG_DIR="$T" python3 scripts/audit_metrics.py > "$T/audit_bad.log" 2>&1
bad_rc=$?
set -e
{
  echo "failure-path self-test: injected missing wide.cycles in random row 0"
  echo "audit_bad_rc=$bad_rc (must be non-zero)"
  grep -m1 "missing" "$T/audit_bad.log" || true
  if [ "$bad_rc" -ne 0 ]; then echo FAILURE_PATH_RC_NONZERO_OK; else echo FAILURE_PATH_RC_ZERO_BUG; fi
} | tee logs/failure_rc_selftest.log
[ "$bad_rc" -ne 0 ]
