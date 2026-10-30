#!/usr/bin/env python3
"""Run the deterministic independent-golden fixtures (fixtures/gold)."""
import json, re, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FIX = Path("/tmp/opencode/ds_layout_gold")
BINS = {"orig": HERE/"build/layout_orig.vvp",
        "v1": HERE/"build/layout_v1.vvp",
        "burst": HERE/"build/layout_burst.vvp"}
FIELDS = ["cycles","processed","read_beats","write_beats","read_bytes","write_bytes"]

def parse(t):
    d={"pass":"PASS" in t}
    for k in FIELDS:
        m=re.search(rf"{k}=\s*(\d+)",t); d[k]=int(m.group(1)) if m else None
    return d

meta=json.loads((FIX/"meta.json").read_text())
rows=[]; fails=0
for c in meta:
    name=c["name"]; ob=c["output_bytes"]
    rec={"name":name,"mode":c["mode"],"ob":ob}
    for tag,b in BINS.items():
        log=HERE/"logs"/f"gold_{tag}_{name}.log"
        p=subprocess.run([str(b),f"+folder={FIX/name}",f"+nbytes={ob}","+mode=0"],
                         text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        log.write_text(p.stdout)
        rec[tag]=parse(p.stdout); rec[tag]["rc"]=p.returncode
    ok=all(rec[t]["pass"] and rec[t]["rc"]==0 for t in BINS)
    ok=ok and rec["burst"]["processed"]==rec["orig"]["processed"]
    ok=ok and (rec["burst"]["write_beats"] or 0)==(rec["orig"]["write_beats"] or 0)
    ok=ok and (rec["burst"]["write_bytes"] or 0)==(rec["orig"]["write_bytes"] or 0)
    rec["ok"]=ok; fails+=0 if ok else 1
    rows.append(rec)

lines=["name mode bytes ok cyc_o cyc_v1 cyc_b ratio_v1 ratio_b rbeat_o rbeat_v1 rbeat_b wbeat_o wbeat_v1 wbeat_b"]
tot={t:0 for t in BINS}; over=[]
for r in rows:
    o,v,b=r["orig"],r["v1"],r["burst"]
    oc=o["cycles"] or 0
    for t in BINS: tot[t]+=r[t]["cycles"] or 0
    dro=(b["read_beats"] or 0)-(o["read_beats"] or 0)
    if dro>0: over.append((r["name"],dro))
    lines.append(f"{r['name']} {r['mode']} {r['ob']} {int(r['ok'])} {o['cycles']} {v['cycles']} {b['cycles']} "
                 f"{(v['cycles'] or 0)/oc if oc else 0:.3f} {(b['cycles'] or 0)/oc if oc else 0:.3f} "
                 f"{o['read_beats']} {v['read_beats']} {b['read_beats']} "
                 f"{o['write_beats']} {v['write_beats']} {b['write_beats']}")
lines.append(f"TOTAL cycles orig={tot['orig']} v1={tot['v1']} burst={tot['burst']} "
             f"ratio_v1={tot['v1']/tot['orig']:.3f} ratio_burst={tot['burst']/tot['orig']:.3f}")
lines.append(f"SUMMARY cases={len(rows)} fails={fails} read_overfetch_cases={len(over)} "
             f"extra_beats={sum(d for _,d in over)}")
text="\n".join(lines)+"\n"
(HERE/"logs"/"gold_table.log").write_text(text)
print(text)
raise SystemExit(1 if fails else 0)
