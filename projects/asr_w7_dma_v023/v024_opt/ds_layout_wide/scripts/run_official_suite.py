#!/usr/bin/env python3
"""Official 8 normal + 12 error/ACL/lifecycle modes, baseline vs wide."""
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from layout_model import model
from metrics import parse_log, source_bytes, REQUIRED, missing_fields

HERE = Path(__file__).resolve().parents[1]
FX = Path("/tmp/opencode/dslw_official")
BINS = {"base": HERE/"build/base_official.vvp", "wide": HERE/"build/wide_fasttb.vvp"}
NORMAL = ["copy_i16","pack_matrix_edges","unpack_row_fp32","unpack_nchw_fp32",
          "unpack_c48_compact","conv_padding","case0000_embed_conv0","depthwise_31"]
meta = {c["name"]: c for c in json.loads((FX/"meta.json").read_text())}

def desc_of(name):
    return [int(x, 16) for x in (FX/name/"descriptor.hex").read_text().split()]

def run(binpath, name, ob, mode):
    p = subprocess.run([str(binpath), f"+folder={FX/name}", f"+nbytes={ob}",
                        f"+mode={mode}"], text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=600)
    return p.returncode, parse_log(p.stdout), p.stdout

rows = []; fails = 0; model_ok = {}
for name in NORMAL:
    c = meta[name]
    w = desc_of(name)
    # independent-model consistency of the preserved official gold
    mem = bytearray(int(x, 16) for x in (FX/name/"memory.hex").read_text().split())
    gold = bytes(int(x, 16) for x in (FX/name/"gold.hex").read_text().split())
    model_ok[name] = bytes(model(w, mem)) == gold
    rec = {"name": name, "bytes": w[5], "output_bytes": c["output_bytes"],
           "src_bytes": source_bytes(w), "model_matches_preserved_gold": model_ok[name]}
    for tag, b in BINS.items():
        rc, d, txt = run(b, name, c["output_bytes"], 0)
        (HERE/"logs"/f"off_{tag}_{name}.log").write_text(txt)
        rec[tag] = d; rec[tag]["rc"] = rc
        rec[tag]["missing"] = missing_fields(d, REQUIRED)
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
    rec["coverage"] = wd["fast_elements"] / wd["processed"] if wd["processed"] else 0.0
    fails += 0 if ok else 1
    rows.append(rec)

err_rows = []
for mode in range(1, 13):
    rec = {"mode": mode}
    for tag, b in BINS.items():
        rc, d, txt = run(b, "copy_i16", 2002, mode)
        rec[tag] = {"rc": rc, "pass": d["pass"], "fault_checked": "Expected" in txt}
    ok = rec["base"] == rec["wide"]
    rec["ok"] = ok; fails += 0 if ok else 1
    err_rows.append(rec)

tot = {t: {} for t in BINS}
for t in BINS:
    for k in ("cycles","processed","read_requests","write_requests","read_beats","write_beats",
              "read_bytes","write_bytes","fast_elements"):
        if k == "fast_elements" and t == "base":
            tot[t][k] = None   # v023 baseline has no fast counter
        else:
            tot[t][k] = sum(r[t][k] for r in rows)
tot["effective_bytes"] = sum(r["effective_bytes"] for r in rows)
tot["src_bytes"] = sum(r["src_bytes"] for r in rows)
tot["overfetch_base"] = sum(r["overfetch_base"] for r in rows)
tot["overfetch_wide"] = sum(r["overfetch_wide"] for r in rows)
tot["coverage"] = tot["wide"]["fast_elements"] / tot["wide"]["processed"] if tot["wide"]["processed"] else 0
tot["processed"] = tot["wide"]["processed"]

lines = ["name ok cyc_base cyc_wide ratio rreq_b rreq_w wreq_b wreq_w rbeat_b rbeat_w "
         "wbeat_b wbeat_w rbyte_b rbyte_w eff_bytes of_b of_w fast/processed"]
for r in rows:
    o, w = r["base"], r["wide"]
    lines.append(f"{r['name']} {int(r['ok'])} {o['cycles']} {w['cycles']} "
                 f"{w['cycles']/o['cycles']:.3f} {o['read_requests']} {w['read_requests']} "
                 f"{o['write_requests']} {w['write_requests']} {o['read_beats']} {w['read_beats']} "
                 f"{o['write_beats']} {w['write_beats']} {o['read_bytes']} {w['read_bytes']} "
                 f"{r['effective_bytes']} {r['overfetch_base']} {r['overfetch_wide']} "
                 f"{w['fast_elements']}/{w['processed']}")
lines.append(f"TOTAL cyc_base={tot['base']['cycles']} cyc_wide={tot['wide']['cycles']} "
             f"ratio={tot['wide']['cycles']/tot['base']['cycles']:.3f} "
             f"rreq={tot['base']['read_requests']}->{tot['wide']['read_requests']} "
             f"wreq={tot['base']['write_requests']}->{tot['wide']['write_requests']} "
             f"rbeat={tot['base']['read_beats']}->{tot['wide']['read_beats']} "
             f"wbeat={tot['base']['write_beats']}->{tot['wide']['write_beats']} "
             f"rbyte={tot['base']['read_bytes']}->{tot['wide']['read_bytes']} "
             f"eff_bytes={tot['effective_bytes']} of={tot['overfetch_base']}->{tot['overfetch_wide']} "
             f"coverage={tot['coverage']:.3f}")
lines.append(f"OFFICIAL_SUMMARY normal={len(rows)} error={len(err_rows)} fails={fails} "
             f"model_matches_preserved_gold={sum(model_ok.values())}/{len(model_ok)}")
text = "\n".join(lines) + "\n"
(HERE/"logs"/"official_table.log").write_text(text)
(HERE/"logs"/"official_suite.json").write_text(json.dumps(
    {"rows": rows, "errors": err_rows, "totals": tot, "fails": fails,
     "model_matches_preserved_gold": model_ok}, indent=1))
print("\n".join(lines[-2:]))
raise SystemExit(1 if fails or not all(model_ok.values()) else 0)
