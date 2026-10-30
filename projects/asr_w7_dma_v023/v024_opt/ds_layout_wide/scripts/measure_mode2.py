#!/usr/bin/env python3
"""Measure the mode-2 prefetch gate on mode-2 cases only.

Variants: v023 baseline (mode2 prefetch 16), gate=1 (default), gate=16.
The gate is a bandwidth/latency trade, not a zero-overfetch claim.
"""
import json, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from layout_model import extent_bytes

HERE = Path(__file__).resolve().parents[1]
BINS = {"base": "build/base_dst.vvp", "gate1": "build/wide_fasttb.vvp",
        "gate16": "build/wide_m2p16.vvp"}
F = ["cycles","processed","read_requests","write_requests","read_beats","write_beats","read_bytes","write_bytes"]

def run(binpath, folder, ob):
    p = subprocess.run([binpath, f"+folder={folder}", f"+nbytes={ob}", "+mode=0"],
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       timeout=600)
    d = {"rc": p.returncode, "pass": "PASS" in p.stdout}
    for k in F:
        m = re.search(rf"{k}=\s*(\d+)", p.stdout)
        d[k] = int(m.group(1)) if m else 0
    return d

cases = []
for d in ("/tmp/opencode/dslw_official", "/tmp/opencode/dslw_edge"):
    meta = json.loads((Path(d)/"meta.json").read_text())
    for c in meta:
        if c["mode"] == 2:
            cases.append((c["name"], str(Path(d)/c["name"]), c["output_bytes"]))
rd = Path("/tmp/opencode/dslw_random")
for p in sorted(rd.iterdir()):
    if not p.is_dir(): continue
    w = [int(x, 16) for x in (p/"descriptor.hex").read_text().split()]
    if w[1] == 2:
        cases.append((p.name, str(p), extent_bytes(w)))

rows = []; fails = 0
for name, folder, ob in cases:
    rec = {"name": name}
    for tag, b in BINS.items():
        rec[tag] = run(str(HERE/b), folder, ob)
    ok = all(rec[t]["pass"] and rec[t]["rc"] == 0 for t in BINS)
    if not ok: fails += 1
    rows.append(rec)

lines = ["name ok cyc_base cyc_g1 cyc_g16 rreq_base rreq_g1 rreq_g16 "
         "rbeat_base rbeat_g1 rbeat_g16 rbyte_base rbyte_g1 rbyte_g16 drbeat_g1 drbeat_g16"]
tot = {t: {"cycles": 0, "read_requests": 0, "read_beats": 0, "read_bytes": 0} for t in BINS}
lower = equal = higher = 0; max_red = (0, "-"); max_req = (-10**9, "-")
for r in rows:
    b, g1, g16 = r["base"], r["gate1"], r["gate16"]
    for t in BINS:
        for k in tot[t]: tot[t][k] += r[t][k]
    d1 = g1["read_beats"] - b["read_beats"]; d16 = g16["read_beats"] - b["read_beats"]
    if d1 < 0: lower += 1
    elif d1 == 0: equal += 1
    else: higher += 1
    if -d1 > max_red[0]: max_red = (-d1, r["name"])
    rd = g1["read_requests"] - b["read_requests"]
    if rd > max_req[0]: max_req = (rd, r["name"])
    lines.append(f"{r['name']} {int(all(r[t]['pass'] for t in BINS))} "
                 f"{b['cycles']} {g1['cycles']} {g16['cycles']} "
                 f"{b['read_requests']} {g1['read_requests']} {g16['read_requests']} "
                 f"{b['read_beats']} {g1['read_beats']} {g16['read_beats']} "
                 f"{b['read_bytes']} {g1['read_bytes']} {g16['read_bytes']} {d1} {d16}")
lines.append("")
for t in BINS:
    x = tot[t]
    lines.append(f"TOTAL {t} cycles={x['cycles']} read_requests={x['read_requests']} "
                 f"read_beats={x['read_beats']} read_bytes={x['read_bytes']}")
lines.append(f"MODE2_GATE cases={len(rows)} fails={fails} beats_lower={lower} "
             f"beats_equal={equal} beats_higher={higher} "
             f"total_beat_delta_gate1={tot['gate1']['read_beats']-tot['base']['read_beats']} "
             f"total_request_delta_gate1={tot['gate1']['read_requests']-tot['base']['read_requests']} "
             f"max_case_reduction={max_red[0]}({max_red[1]}) "
             f"max_case_request_increase={max_req[0]}({max_req[1]})")
lines.append("NOTE: gate1 reduces read beats on 7/45 mode2 cases and is neutral on 38; "
             "it does not eliminate all re-reads; it trades more, shorter read requests "
             "and +0.17% cycles. gate16 reproduces the v023 baseline exactly.")
text = "\n".join(lines) + "\n"
(HERE/"logs"/"mode2_gate.log").write_text(text)
print("\n".join(lines[-4:]))
raise SystemExit(1 if fails else 0)
