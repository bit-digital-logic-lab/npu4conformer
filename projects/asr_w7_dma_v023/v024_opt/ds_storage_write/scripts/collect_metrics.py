#!/usr/bin/env python3
"""Collect the run_all logs into metrics.json / metrics.txt and the two
comparison reports.  It does not invent numbers: every value is parsed from a
run log produced in this invocation."""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS = os.path.join(ROOT, "logs")
REPORTS = os.path.join(ROOT, "reports")

KEYS = [
    "cycles", "compute", "ccyc", "cgrp", "cseg", "wrcmd", "wrbeat", "coal",
    "gen", "flush", "maxb", "cvalstall", "csegstall", "wr_bytes", "wr_bursts",
    "bfm_wbeats", "rv", "code", "cwr_pending", "armax", "bmax", "wrblk",
]


def parse_run(name):
    path = os.path.join(LOGS, name + ".log")
    if not os.path.isfile(path):
        return {"name": name, "status": "MISSING", "values": {}}
    text = open(path, errors="replace").read()
    status = "FAIL"
    if "PASS_FAULT" in text:
        status = "PASS_FAULT"
    elif "PASS" in text:
        status = "PASS"
    values = {}
    for key in KEYS:
        m = re.search(rf"\b{key}=([0-9a-fA-F]+)", text)
        if m:
            try:
                values[key] = int(m.group(1), 0)
            except ValueError:
                values[key] = m.group(1)
    return {"name": name, "status": status, "values": values}


def main():
    commands = {}
    if os.path.isfile(os.path.join(LOGS, "commands.log")):
        for line in open(os.path.join(LOGS, "commands.log"), errors="replace"):
            m = re.match(r"(\S+) rc=(\d+)", line.strip())
            if m:
                commands[m.group(1)] = int(m.group(2))
    runs = []
    for fn in sorted(os.listdir(LOGS)):
        if fn.startswith("run_") and fn.endswith(".log"):
            runs.append(parse_run(fn[:-4]))
    out = {"commands": commands, "runs": {r["name"]: r for r in runs}}
    json.dump(out, open(os.path.join(LOGS, "metrics.json"), "w"), indent=2, sort_keys=True)
    with open(os.path.join(LOGS, "metrics.txt"), "w") as f:
        for name in sorted(out["runs"]):
            r = out["runs"][name]
            vals = " ".join(f"{k}={v}" for k, v in sorted(r["values"].items()))
            f.write(f"{name:24s} {r['status']:11s} rc={commands.get(name, '?')} {vals}\n")
    print(open(os.path.join(LOGS, "metrics.txt")).read())

    # key comparisons (only if both sides exist)
    def val(name, key):
        return out["runs"].get(name, {}).get("values", {}).get(key)

    lw = {
        "note": "K32 PIPE=4, same strict AXI128 BFM, LAT_MIN=LAT_MAX=48, same input/gold; cycles are start-to-done after the last B drains.",
        "ref_v2": {"cycles": val("run_ref_cl_lw", "cycles"),
                   "c_collect": val("run_ref_cl_lw", "ccyc"),
                   "write_bursts": val("run_ref_cl_lw", "wr_bursts"),
                   "wr_bytes": val("run_ref_cl_lw", "wr_bytes")},
        "ref_v2_wrout64": {"cycles": val("run_ref_cl_wr64", "cycles"),
                           "c_collect": val("run_ref_cl_wr64", "ccyc"),
                           "write_bursts": val("run_ref_cl_wr64", "wr_bursts")},
        "v3": {"cycles": val("run_cl_lw", "cycles"),
               "c_collect": val("run_cl_lw", "ccyc"),
               "cseg": val("run_cl_lw", "cseg"),
               "wr_cmds": val("run_cl_lw", "wrcmd"),
               "write_bursts": val("run_cl_lw", "wr_bursts"),
               "wr_bytes": val("run_cl_lw", "wr_bytes"),
               "max_b_credit": val("run_cl_lw", "maxb")},
        "fast": {"ref_cycles": val("run_ref_cl_fast", "cycles"),
                 "v3_cycles": val("run_cl_fast", "cycles"),
                 "ref_c_collect": val("run_ref_cl_fast", "ccyc"),
                 "v3_c_collect": val("run_cl_fast", "ccyc")},
    }
    a, b = lw["ref_v2"]["cycles"], lw["v3"]["cycles"]
    if a and b:
        lw["ref_over_v3"] = round(a / b, 4)
        lw["cycle_reduction"] = a - b
    rf, vf = lw["fast"]["ref_cycles"], lw["fast"]["v3_cycles"]
    if a and rf and b and vf:
        lw["degradation"] = {
            "ref_fast_to_long_wait_cycles": a - rf,
            "ref_long_wait_over_fast": round(a / rf, 4),
            "v3_fast_to_long_wait_cycles": b - vf,
            "v3_long_wait_over_fast": round(b / vf, 4),
        }
    json.dump(lw, open(os.path.join(REPORTS, "long_wait_compare.json"), "w"), indent=2, sort_keys=True)

    bubble = {
        "note": "same-engine A/B: SAME_CYCLE_CSEG=1 accepts cseg+first cval in one cycle; =0 keeps the v0.23 one-cycle cseg bubble.",
        "same_cycle": {"cycles": val("run_eng_fast_c0", "cycles"),
                       "c_collect": val("run_eng_fast_c0", "ccyc")},
        "old_bubble": {"cycles": val("run_eng_nosame_c0", "cycles"),
                       "c_collect": val("run_eng_nosame_c0", "ccyc")},
    }
    json.dump(bubble, open(os.path.join(REPORTS, "cseg_bubble_compare.json"), "w"), indent=2, sort_keys=True)

    storage = {}
    for m in ["native", "generic", "tail", "bad", "abortm", "split"]:
        n = "run_coal_" + m
        storage[m] = {"status": out["runs"].get(n, {}).get("status"),
                      **out["runs"].get(n, {}).get("values", {})}
    json.dump(storage, open(os.path.join(REPORTS, "storage_angles.json"), "w"), indent=2, sort_keys=True)
    bad = [n for n, r in out["runs"].items() if r["status"] not in ("PASS", "PASS_FAULT")]
    if bad:
        print("NON-PASS RUNS:", bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
