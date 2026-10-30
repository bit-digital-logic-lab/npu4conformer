#!/usr/bin/env python3
"""Official layout fixtures (8 normal + 12 error/ACL/lifecycle modes) for
original, stepping-only candidate (v1) and burst candidate.

Normal cases compare the testbench PASS (byte-exact vs the fixture's own
gold.hex) and report cycles/traffic.  Error modes only require the same
fault/no-side-effect outcome as the original.
"""
import json, re, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FX = Path("/tmp/opencode/ds_layout_fixtures")
BINS = {"orig": HERE/"build/layout_orig.vvp",
        "v1": HERE/"build/layout_v1.vvp",
        "burst": HERE/"build/layout_burst.vvp"}
OUT = HERE/"logs"
meta = {c["name"]: c for c in json.loads((FX/"meta.json").read_text())}
NORMAL = ["copy_i16","pack_matrix_edges","unpack_row_fp32","unpack_nchw_fp32",
          "unpack_c48_compact","conv_padding","case0000_embed_conv0","depthwise_31"]
FIELDS = ["cycles","processed","cache_hits","cache_misses","read_requests",
          "write_requests","read_beats","write_beats","read_bytes","write_bytes"]

def parse(text):
    d = {"pass": "PASS" in text}
    for k in FIELDS:
        m = re.search(rf"{k}=\s*(\d+)", text)
        d[k] = int(m.group(1)) if m else None
    return d

def run(binpath, folder, nbytes, mode, tag):
    log = OUT/f"{tag}.log"
    p = subprocess.run([str(binpath), f"+folder={folder}", f"+nbytes={nbytes}",
                        f"+mode={mode}"], text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT)
    log.write_text(p.stdout)
    return p.returncode, parse(p.stdout), p.stdout

rows=[]; err_rows=[]; fails=0
for name in NORMAL:
    c = meta[name]
    rec = {"name": name, "nbytes": c["output_bytes"]}
    for tag, b in BINS.items():
        rc, d, txt = run(b, str(FX/name), c["output_bytes"], 0, f"off_{tag}_{name}")
        rec[tag] = d
        if not d["pass"] or rc != 0:
            fails += 1
    rows.append(rec)

for mode in range(1, 13):
    rec = {"mode": mode}
    for tag, b in BINS.items():
        rc, d, txt = run(b, str(FX/"copy_i16"), 2002, mode, f"err_{tag}_{mode}")
        # same externally visible outcome: rc and PASS/fault behaviour
        rec[tag] = (rc, d["pass"], "fault" if "Expected layout error" in txt else
                    ("fault" if "Expected" in txt else "other"))
    # require rc and pass flag equality between orig and both candidates
    base = rec["orig"][:2]
    ok = all(rec[t][:2] == base for t in ("v1","burst"))
    rec["ok"] = ok
    if not ok: fails += 1
    err_rows.append(rec)

lines=[]
lines.append("OFFICIAL NORMAL FIXTURES")
lines.append("name nbytes pass_o pass_v1 pass_b cyc_o cyc_v1 cyc_b ratio_v1 ratio_b "
             "rbeat_o rbeat_v1 rbeat_b wbeat_o wbeat_v1 wbeat_b wb_o wb_v1 wb_b")
for r in rows:
    o,v,b = r["orig"],r["v1"],r["burst"]
    lines.append(f"{r['name']} {r['nbytes']} {int(o['pass'])} {int(v['pass'])} {int(b['pass'])} "
                 f"{o['cycles']} {v['cycles']} {b['cycles']} "
                 f"{v['cycles']/o['cycles']:.3f} {b['cycles']/o['cycles']:.3f} "
                 f"{o['read_beats']} {v['read_beats']} {b['read_beats']} "
                 f"{o['write_beats']} {v['write_beats']} {b['write_beats']} "
                 f"{o['write_bytes']} {v['write_bytes']} {b['write_bytes']}")
tot={t:sum(r[t]["cycles"] for r in rows) for t in BINS}
lines.append(f"TOTAL cycles orig={tot['orig']} v1={tot['v1']} burst={tot['burst']} "
             f"ratio_v1={tot['v1']/tot['orig']:.3f} ratio_burst={tot['burst']/tot['orig']:.3f}")
lines.append("")
lines.append("ERROR / ACL / LIFECYCLE MODES (copy_i16)")
for r in err_rows:
    lines.append(f"mode={r['mode']} ok={int(r['ok'])} orig={r['orig'][:2]} v1={r['v1'][:2]} burst={r['burst'][:2]}")
lines.append(f"SUMMARY normal={len(rows)} error={len(err_rows)} fails={fails}")
text="\n".join(lines)+"\n"
(OUT/"official_table.log").write_text(text)
print(text)
raise SystemExit(1 if fails else 0)
