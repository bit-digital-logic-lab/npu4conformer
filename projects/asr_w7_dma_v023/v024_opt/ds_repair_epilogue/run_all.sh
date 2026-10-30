#!/usr/bin/env bash
# Full reproducible run for ds_repair_epilogue.
# Serial compile (single iverilog invocation per build), per-sim shell timeout
# and in-TB cycle watchdog.  Writes result.json fresh; never reads an old PASS.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/logs"
RC=0

echo "== [1/6] generate independent vectors =="
python3 "$ROOT/gold/gen_vectors.py" "$ROOT/vectors" > "$ROOT/logs/gen_vectors.log" 2>&1
r=$?; echo "gen_vectors rc=$r"; [ $r -eq 0 ] || RC=1

echo "== [2/6] strict formal gate (new RTL) =="
rm -f "$ROOT/logs/gate_new/summary.json"
bash "$ROOT/scripts/run_gate.sh" gate_new "$ROOT"/rtl/*.sv
r=$?; echo "gate_new rc=$r"; [ $r -eq 0 ] || RC=1

echo "== [3/6] negative control (broken RTL must be rejected) =="
bash "$ROOT/scripts/negative_control.sh" > "$ROOT/logs/negctl_console.txt" 2>&1
r=$?; echo "negctl rc=$r"; [ $r -eq 0 ] || RC=1

echo "== [4/6] original worker 10-case regression with new RTL =="
bash "$ROOT/scripts/run_regress.sh"
r=$?; echo "regress rc=$r"; [ $r -eq 0 ] || RC=1

echo "== [5/6] AR-006/007 reproduction + corrected-ready + old-SHA evidence =="
bash "$ROOT/scripts/evidence.sh" > "$ROOT/logs/evidence_console.txt" 2>&1
r=$?; echo "evidence rc=$r"; [ $r -eq 0 ] || RC=1

echo "== [6/6] finalize result.json / SHA256SUMS.txt =="
python3 "$ROOT/scripts/finalize.py"
r=$?; [ $r -eq 0 ] || RC=1

echo "== SUMMARY =="
grep -E '^(compile rc|EPI_STRICT_GATE|NEGCTL|REGRESS|RESULT overall|OLD_SHA)' \
  "$ROOT/logs/gate_new/rc.txt" "$ROOT/logs/negctl_console.txt" \
  "$ROOT/logs/regress_console.txt" 2>/dev/null | tail -8
echo "RUN_ALL_RC=$RC"
exit "$RC"
