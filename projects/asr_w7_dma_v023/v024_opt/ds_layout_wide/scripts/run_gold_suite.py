#!/usr/bin/env python3
"""Independent-golden suites: 32 original gold + 47 new edge fixtures."""
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from layout_model import extent_bytes
from metrics import parse_log, source_bytes, REQUIRED, missing_fields

HERE = Path(__file__).resolve().parents[1]
BINS = {"base": HERE/"build/base_dst.vvp", "wide": HERE/"build/wide_fasttb.vvp"}
SUITES = [("gold", Path("/tmp/opencode/dslw_gold")),
          ("edge", Path("/tmp/opencode/dslw_edge"))]

all_tot = {}; all_rows = []; total_fails = 0
for label, FX in SUITES:
    meta = json.loads((FX/"meta.json").read_text())
    rows = []; fails = 0
    for c in meta:
        w = [int(x, 16) for x in (FX/c["name"]/"descriptor.hex").read_text().split()]
        rec = {"suite": label, "name": c["name"], "mode": w[1], "bytes": w[5],
               "output_bytes": c["output_bytes"], "src_bytes": source_bytes(w)}
        for tag, b in BINS.items():
            p = subprocess.run([str(b), f"+folder={FX/c['name']}",
                                f"+nbytes={c['output_bytes']}", "+mode=0"],
                               text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=600)
            (HERE/"logs"/f"{label}_{tag}_{c['name']}.log").write_text(p.stdout)
            d = parse_log(p.stdout); d["rc"] = p.returncode
            d["missing"] = missing_fields(d, REQUIRED)
            rec[tag] = d
        o, wd = rec["base"], rec["wide"]
        ok = (o["pass"] and wd["pass"] and o["rc"] == 0 and wd["rc"] == 0
              and not o["missing"] and not wd["missing"]
              and wd["processed"] == o["processed"]
              and wd["write_beats"] == o["write_beats"]
              and wd["write_bytes"] == o["write_bytes"])
        rec["ok"] = ok
        rec["effective_bytes"] = wd["processed"] * rec["bytes"]
        rec["overfetch_base"] = o["read_bytes"] - rec["src_bytes"]
        rec["overfetch_wide"] = wd["read_bytes"] - rec["src_bytes"]
        rec["coverage"] = wd["fast_elements"]/wd["processed"] if wd["processed"] else 0.0
        fails += 0 if ok else 1
        rows.append(rec)
    tot = {t: {} for t in BINS}
    for t in BINS:
        for k in ("cycles","processed","read_requests","write_requests","read_beats","write_beats",
                "read_bytes","write_bytes","fast_elements"):
            if k == "fast_elements" and t == "base":
                tot[t][k] = None   # v023 baseline has no fast counter
            else:
                tot[t][k] = sum(r[t][k] for r in rows)
    tot["processed"] = tot["wide"]["processed"]
    tot["effective_bytes"] = sum(r["effective_bytes"] for r in rows)
    tot["src_bytes"] = sum(r["src_bytes"] for r in rows)
    tot["overfetch_base"] = sum(r["overfetch_base"] for r in rows)
    tot["overfetch_wide"] = sum(r["overfetch_wide"] for r in rows)
    tot["coverage"] = tot["wide"]["fast_elements"]/tot["processed"] if tot["processed"] else 0
    tot["fails"] = fails; tot["cases"] = len(rows)
    all_tot[label] = tot; all_rows += rows; total_fails += fails

    lines = [f"{label.upper()} INDEPENDENT GOLDEN"]
    lines.append("name mode bytes ok cyc_base cyc_wide ratio rbeat_b rbeat_w "
                 "drbeat wbeat_b wbeat_w fast/processed")
    for r in rows:
        o, wd = r["base"], r["wide"]
        lines.append(f"{r['name']} {r['mode']} {r['bytes']} {int(r['ok'])} "
                     f"{o['cycles']} {wd['cycles']} {wd['cycles']/o['cycles']:.3f} "
                     f"{o['read_beats']} {wd['read_beats']} "
                     f"{wd['read_beats']-o['read_beats']} {o['write_beats']} {wd['write_beats']} "
                     f"{wd['fast_elements']}/{wd['processed']}")
    lines.append(f"TOTAL cases={len(rows)} fails={fails} "
                 f"cyc_base={tot['base']['cycles']} cyc_wide={tot['wide']['cycles']} "
                 f"ratio={tot['wide']['cycles']/tot['base']['cycles']:.3f} "
                 f"rbeat={tot['base']['read_beats']}->{tot['wide']['read_beats']} "
                 f"rreq={tot['base']['read_requests']}->{tot['wide']['read_requests']} "
                 f"wreq={tot['base']['write_requests']}->{tot['wide']['write_requests']} "
                 f"eff_bytes={tot['effective_bytes']} of={tot['overfetch_base']}->{tot['overfetch_wide']} "
                 f"coverage={tot['coverage']:.3f}")
    (HERE/"logs"/f"{label}_table.log").write_text("\n".join(lines)+"\n")

(HERE/"logs"/"gold_edge_suite.json").write_text(json.dumps(
    {"totals": all_tot, "rows": all_rows, "fails": total_fails}, indent=1))
for label in all_tot:
    t = all_tot[label]
    print(f"{label}: cases={t['cases']} fails={t['fails']} "
          f"cyc={t['base']['cycles']}->{t['wide']['cycles']} "
          f"coverage={t['coverage']:.3f} of={t['overfetch_base']}->{t['overfetch_wide']}")
raise SystemExit(1 if total_fails else 0)
