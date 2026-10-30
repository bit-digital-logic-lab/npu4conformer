#!/usr/bin/env bash
# Reproduce the module-level stream cycle comparison.
# Logic simulation only. No synthesis, no Vivado, no board, no VNC, no push.
set -euo pipefail
cd "$(dirname "$0")"

progress() {
  python3 - "$1" "$2" <<'PY'
import json, sys, time
stage, status = sys.argv[1], sys.argv[2]
data = {
    "stage": stage,
    "status": status,
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "details": {},
}
open("progress.json", "w").write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
with open("progress_history.jsonl", "a") as f:
    f.write(json.dumps(data, ensure_ascii=False) + "\n")
PY
}

progress "VECTORS" "RUNNING"
python3 scripts/gen_vectors.py
progress "VECTORS" "DONE"

python3 scripts/run_bench.py
python3 scripts/make_report.py

python3 - <<'PY'
import json, time
r = json.load(open("result.json"))
p = {
    "stage": "STAGE_FINAL_DELIVERY_COMPLETE",
    "status": "COMPLETED" if r["summary"]["required_checks_pass"] else "FAILED",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "details": {
        "task": r["task"],
        "module_compare_pass": r["summary"]["required_checks_pass"],
        "system_pass": False,
        "comparison_cases": r["summary"]["comparison_cases"],
        "both_correct": r["summary"]["both_correct"],
        "invalid_no_speedup_claim": r["summary"]["invalid_no_speedup_claim"],
        "bias_only_expected_negative_control": r["summary"]["bias_only_expected_negative_control"],
        "scope": r["scope"],
        "deliverables": ["REPORT.md", "result.json", "SOURCE_SHA256.json",
                         "vectors/VECTOR_SHA256.json", "scripts/", "logs/"],
        "limits": ["no_full_system", "no_full_model", "no_synthesis", "no_sta",
                   "no_board", "module_level_only"],
    },
    "next_stage": "NONE",
}
open("progress.json", "w").write(json.dumps(p, indent=2, ensure_ascii=False) + "\n")
with open("progress_history.jsonl", "a") as f:
    f.write(json.dumps(p, ensure_ascii=False) + "\n")
print(json.dumps({"stage": p["stage"], "status": p["status"]}, indent=2))
PY

echo "DONE: REPORT.md / result.json / logs/ / progress.json"
