#!/usr/bin/env python3
"""Strict per-row metric audit.  Fails non-zero on any missing required field,
non-PASS RTL result, or base/wide functional mismatch.

The only allowed absence is the fast-path observability counters on the v023
baseline side: the baseline RTL has no fast path and its testbench cannot print
those fields.  That absence is reported explicitly (counted, not turned into 0)
and is excluded from the fast-path statistics; every functional metric
(cycles/processed/requests/beats/bytes) must be present on both sides.
"""
import json, os, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
L = Path(os.environ.get("DSLW_LOG_DIR", HERE/"logs"))
REQ = ["cycles", "processed", "read_requests", "write_requests",
       "read_beats", "write_beats", "read_bytes", "write_bytes"]
WREQ = REQ + ["fast_elements", "fast_beats", "fast_groups"]
FAST_KEYS = ["fast_elements", "fast_beats", "fast_groups"]

def missing(d, keys):
    return [k for k in keys if d.get(k) is None]

official = json.loads((L/"official_suite.json").read_text())
gold_edge = json.loads((L/"gold_edge_suite.json").read_text())
random = json.loads((L/"random_suite.json").read_text())
scalar = json.loads((L/"scalar_fallback.json").read_text())

errors = []
allowed_absent = 0
rows = 0

def check_pair(suite, name, a, b, allow_base_fast_absent=True):
    global rows, allowed_absent
    rows += 1
    for tag, d in (("base", a), ("wide", b)):
        if not d.get("pass"):
            errors.append(f"{suite}:{name}:{tag}: not PASS")
        if d.get("rc") != 0:
            errors.append(f"{suite}:{name}:{tag}: rc={d.get('rc')}")
    mb = missing(a, REQ)
    mw = missing(b, WREQ)
    if mb:
        errors.append(f"{suite}:{name}:base: missing {mb}")
    if mw:
        errors.append(f"{suite}:{name}:wide: missing {mw}")
    if allow_base_fast_absent:
        absent = [k for k in FAST_KEYS if a.get(k) is None]
        if absent:
            if absent != FAST_KEYS:
                errors.append(f"{suite}:{name}:base: partial fast counters {absent}")
            else:
                allowed_absent += 1
    for k in ("processed", "write_beats", "write_bytes"):
        if a.get(k) != b.get(k):
            errors.append(f"{suite}:{name}: {k} base={a.get(k)} wide={b.get(k)}")

for r in official["rows"]:
    check_pair("official", r["name"], r["base"], r["wide"])
for r in gold_edge["rows"]:
    check_pair(r["suite"], r["name"], r["base"], r["wide"])
for r in random["rows"]:
    check_pair("random", r["name"], r["base"], r["wide"])

if official["fails"] != 0:
    errors.append(f"official fails={official['fails']}")
if not all(e["ok"] for e in official["errors"]):
    errors.append("official error-mode mismatch")
if not all(official["model_matches_preserved_gold"].values()):
    errors.append("official preserved gold differs from independent model")
if gold_edge["fails"] != 0:
    errors.append(f"gold/edge fails={gold_edge['fails']}")
if random["fails"] != 0:
    errors.append(f"random fails={random['fails']}")
if random["overfetch_cases"] != 0:
    errors.append(f"random extra read beats cases={random['overfetch_cases']}")
if scalar["fails"] != 0:
    errors.append(f"scalar fallback fails={scalar['fails']}")
for r in scalar["rows"]:
    if not r.get("ok"):
        errors.append(f"scalar:{r['name']}: not ok")

fuzz_txt = (L/"layout_fuzz.log").read_text()
m = re.search(r"SUMMARY cases=(\d+) fails=(\d+)", fuzz_txt)
fuzz = (int(m.group(1)), int(m.group(2))) if m else (0, -1)
if fuzz != (57, 0):
    errors.append(f"fuzz cases/fails={fuzz}")
m2_txt = (L/"mode2_gate.log").read_text()
m = re.search(r"MODE2_GATE cases=(\d+) fails=(\d+)", m2_txt)
m2 = (int(m.group(1)), int(m.group(2))) if m else (0, -1)
if m2 != (45, 0):
    errors.append(f"mode2 cases/fails={m2}")

out = {
    "ok": not errors,
    "normal_rows": rows,
    "allowed_absent_baseline_fast_counters": allowed_absent,
    "allowed_absence_reason": "v023 baseline RTL has no fast path; its TB cannot print fast_* fields",
    "errors": errors,
    "fuzz_cases": fuzz[0], "fuzz_fails": fuzz[1],
    "mode2_cases": m2[0], "mode2_fails": m2[1],
    "scalar_cases": scalar["cases"], "scalar_fails": scalar["fails"],
}
(L/"metric_audit.json").write_text(json.dumps(out, indent=1) + "\n")
lines = [f"rows={rows} ok={out['ok']} errors={len(errors)}",
         f"allowed_absent_baseline_fast_counters={allowed_absent} (explicit, not zero-filled)",
         f"fuzz={fuzz[0]}/{fuzz[1]} mode2={m2[0]}/{m2[1]} scalar={scalar['cases']}/{scalar['fails']}"]
lines += errors
text = "\n".join(lines) + "\n"
(L/"metric_audit.log").write_text(text)
print(text, end="")
raise SystemExit(0 if out["ok"] else 1)
