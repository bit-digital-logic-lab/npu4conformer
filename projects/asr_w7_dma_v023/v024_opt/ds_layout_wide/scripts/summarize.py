#!/usr/bin/env python3
"""Merge suite evidence into logs/summary.json and print the gate verdict."""
import json, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from metrics import touched_lines

HERE = Path(__file__).resolve().parents[1]
L = HERE / "logs"
FIX = {"official": HERE/"fixtures"/"official", "gold": HERE/"fixtures"/"gold",
       "edge": HERE/"fixtures"/"edge", "random": HERE/"fixtures"/"random"}

official = json.loads((L/"official_suite.json").read_text())
gold_edge = json.loads((L/"gold_edge_suite.json").read_text())
random = json.loads((L/"random_suite.json").read_text())
scalar = json.loads((L/"scalar_fallback.json").read_text())
audit = json.loads((L/"metric_audit.json").read_text())
fuzz_txt = (L/"layout_fuzz.log").read_text()
m2_txt = (L/"mode2_gate.log").read_text()
neg_txt = (L/"c48_negative_control.log").read_text() if (L/"c48_negative_control.log").exists() else ""
fr_txt = (L/"failure_rc_selftest.log").read_text() if (L/"failure_rc_selftest.log").exists() else ""
fuzz_m = re.search(r"SUMMARY cases=(\d+) fails=(\d+)", fuzz_txt)
fuzz_cases, fuzz_fails = (int(fuzz_m.group(1)), int(fuzz_m.group(2))) if fuzz_m else (0, -1)
m2_m = re.search(r"MODE2_GATE cases=(\d+) fails=(\d+)", m2_txt)
m2_cases, m2_fails = (int(m2_m.group(1)), int(m2_m.group(2))) if m2_m else (0, -1)

def annotate(rows, suite):
    """Add independently-computed minimum source lines and line overfetch."""
    ofb = ofw = 0
    for r in rows:
        w = [int(x, 16) for x in (FIX[suite]/r["name"]/"descriptor.hex").read_text().split()]
        ml = touched_lines(w)
        r["min_source_lines"] = ml
        r["overfetch_base_lines"] = r["base"]["read_beats"] - ml
        r["overfetch_wide_lines"] = r["wide"]["read_beats"] - ml
        ofb += r["overfetch_base_lines"]; ofw += r["overfetch_wide_lines"]
    return ofb, ofw

suite_totals = {}
ofb, ofw = annotate(official["rows"], "official")
t = dict(official["totals"]); t["overfetch_base_lines"] = ofb; t["overfetch_wide_lines"] = ofw
t["cases"] = len(official["rows"]); t["fails"] = official["fails"]
suite_totals["official"] = t
for label in ("gold", "edge"):
    rows = [r for r in gold_edge["rows"] if r["suite"] == label]
    ofb, ofw = annotate(rows, label)
    t = dict(gold_edge["totals"][label]); t["overfetch_base_lines"] = ofb
    t["overfetch_wide_lines"] = ofw
    suite_totals[label] = t
ofb, ofw = annotate(random["rows"], "random")
KEYS = ("cycles","processed","read_requests","write_requests","read_beats",
        "write_beats","read_bytes","write_bytes","fast_elements")
t = {b: {} for b in ("base","wide")}
for b in ("base","wide"):
    for k in KEYS:
        vals = [r[b][k] for r in random["rows"]]
        if k == "fast_elements" and b == "base":
            # The v023 baseline has no fast-path counter; keep it absent
            # instead of silently converting None to 0.
            assert all(v is None for v in vals), "unexpected baseline fast counter"
            t[b][k] = None
        else:
            assert all(isinstance(v, int) for v in vals), f"missing random metric {b}.{k}"
            t[b][k] = sum(vals)
t["processed"] = t["wide"]["processed"]
t["effective_bytes"] = sum(r["effective_bytes"] for r in random["rows"])
t["coverage"] = t["wide"]["fast_elements"]/t["processed"] if t["processed"] else 0
t["overfetch_base_lines"] = ofb; t["overfetch_wide_lines"] = ofw
t["cases"] = random["cases"]; t["fails"] = random["fails"]
suite_totals["random"] = t

grand = {b: {k: 0 for k in ("cycles","processed","read_requests","write_requests",
                            "read_beats","write_beats","read_bytes","write_bytes",
                            "fast_elements")} for b in ("base","wide")}
ge = 0; gob = gow = 0
for b in ("base","wide"):
    for k in grand[b]:
        if k == "fast_elements" and b == "base":
            grand[b][k] = None   # not measured by v023 baseline
            continue
        grand[b][k] = sum(t[b][k] for t in suite_totals.values())
for t in suite_totals.values():
    ge += t.get("effective_bytes", 0)
    gob += t["overfetch_base_lines"]; gow += t["overfetch_wide_lines"]
grand["effective_bytes"] = ge
grand["overfetch_base_lines"] = gob
grand["overfetch_wide_lines"] = gow
grand["coverage"] = (grand["wide"]["fast_elements"]/grand["wide"]["processed"]
                     if grand["wide"]["processed"] else 0)

checks = {
    "official_normal_8_pass": official["fails"] == 0,
    "official_error_modes_12_match": all(e["ok"] for e in official["errors"]),
    "official_preserved_gold_matches_independent_model":
        all(official["model_matches_preserved_gold"].values()),
    "gold_32_pass": suite_totals["gold"]["fails"] == 0,
    "edge_53_pass": suite_totals["edge"]["cases"] == 53 and suite_totals["edge"]["fails"] == 0,
    "random_152_pass": random["fails"] == 0,
    "random_no_extra_read_beats_vs_v023": random["overfetch_cases"] == 0,
    "descriptor_fuzz_57_pass": fuzz_cases == 57 and fuzz_fails == 0,
    "scalar_fallback_identical": scalar["fails"] == 0,
    "mode2_gate_measured": m2_cases == 45 and m2_fails == 0,
    "c48_negative_control_fails_and_fixed_passes":
        ("KNOWN_BAD_FAILED" in neg_txt and "FIXED_PASSED" in neg_txt),
    "metrics_complete_no_masking":
        audit["ok"] and audit["normal_rows"] == 245 and not audit["errors"],
    "failure_path_exits_nonzero": "FAILURE_PATH_RC_NONZERO_OK" in fr_txt,
}
verdict = "PASS_LOCAL_LOGIC" if all(checks.values()) else "FAIL"
summary = {
    "task": "ds_layout_wide",
    "verdict": verdict,
    "checks": checks,
    "suites": suite_totals,
    "grand_totals": grand,
    "metric_audit": audit,
    "fuzz": {"cases": fuzz_cases, "fails": fuzz_fails},
    "mode2_gate": {"cases": m2_cases, "fails": m2_fails},
    "notes": [
        "Cycles are testbench cycles with a deterministic single-clock BFM; not board time.",
        "Effective bytes = processed_elements * descriptor element size.",
        "Overfetch_lines = AXI read beats - independently enumerated distinct 16B source lines actually consumed.",
        "Mode-2 gate reduces read beats on 7/45 cases and is neutral on 38; it does not remove all re-reads.",
        "No synthesis/Vivado/STA/board/VNC/push; no frequency or full-model seconds claim."
    ],
}
(L/"summary.json").write_text(json.dumps(summary, indent=1))
print(json.dumps({"verdict": verdict, "checks": checks,
                  "grand_totals": grand}, indent=1))
raise SystemExit(0 if verdict == "PASS_LOCAL_LOGIC" else 1)
