#!/usr/bin/env python3
"""Prefetch policy trade-off: original vs burst(MAX_PREFETCH=16) vs
burst(MAX_PREFETCH=1).  Same fixtures, same BFM.  Shows that disabling
multi-line prefetch restores the original read-beat count exactly while the
write aggregation and incremental stepping still reduce cycles."""
import json, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from layout_model import extent_bytes

HERE=Path(__file__).resolve().parents[1]
FX=Path("/tmp/opencode/ds_layout_fixtures")
meta={c["name"]:c for c in json.loads((FX/"meta.json").read_text())}
BINS={"orig":HERE/"build/layout_orig.vvp",
      "pf16":HERE/"build/layout_burst.vvp",
      "pf1":HERE/"build/layout_nopf.vvp"}
FIELDS=["cycles","read_beats","write_beats","write_bytes"]

def run(tag,b,folder,ob):
    p=subprocess.run([str(b),f"+folder={folder}",f"+nbytes={ob}","+mode=0"],
                     text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    d={"pass":"PASS" in p.stdout}
    for k in FIELDS:
        m=re.search(rf"{k}=\s*(\d+)",p.stdout); d[k]=int(m.group(1)) if m else None
    return d

cases=[(n,str(FX/n),meta[n]["output_bytes"]) for n in
       ["copy_i16","pack_matrix_edges","unpack_row_fp32","unpack_nchw_fp32",
        "unpack_c48_compact","conv_padding","case0000_embed_conv0","depthwise_31"]]
# over-read examples from the random suite
for n in ["r2_21","r1_18","r2_14"]:
    d=HERE/"fixtures"/"random"/n
    if d.exists():
        w=[int(x,16) for x in (d/"descriptor.hex").read_text().split()]
        cases.append((n,f"/tmp/opencode/ds_layout_random/{n}",extent_bytes(w)))

lines=["case cyc_o cyc_pf16 cyc_pf1 r16 r1 rbeat_o rbeat_pf16 rbeat_pf1 wbeat_o wbeat_pf16 wbeat_pf1 ok"]
fails=0; to=t16=t1=0
for name,folder,ob in cases:
    r={t:run(t,b,folder,ob) for t,b in BINS.items()}
    ok=all(r[t]["pass"] for t in BINS)
    ok=ok and r["pf1"]["read_beats"]==r["orig"]["read_beats"]
    ok=ok and r["pf16"]["write_beats"]==r["orig"]["write_beats"]==r["pf1"]["write_beats"]
    fails+=0 if ok else 1
    o,a,b=r["orig"],r["pf16"],r["pf1"]
    to+=o["cycles"]; t16+=a["cycles"]; t1+=b["cycles"]
    lines.append(f"{name} {o['cycles']} {a['cycles']} {b['cycles']} "
                 f"{a['cycles']/o['cycles']:.3f} {b['cycles']/o['cycles']:.3f} "
                 f"{o['read_beats']} {a['read_beats']} {b['read_beats']} "
                 f"{o['write_beats']} {a['write_beats']} {b['write_beats']} {int(ok)}")
lines.append(f"TOTAL cyc_orig={to} cyc_pf16={t16} ({t16/to:.3f}) cyc_pf1={t1} ({t1/to:.3f})")
lines.append(f"SUMMARY cases={len(cases)} fails={fails}")
text="\n".join(lines)+"\n"
(HERE/"logs"/"prefetch_policy.log").write_text(text)
print(text)
raise SystemExit(1 if fails else 0)
