#!/usr/bin/env python3
"""Prove FASTPATH=0 + MODE2_PREFETCH=16 reproduces the v023 burst baseline.

Exact equality is required for rc/pass/cycles/processed/requests/beats/bytes.
Covered: 8 official normal, 32 gold, first 30 random fixtures.
"""
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from layout_model import extent_bytes
from metrics import parse_log

HERE = Path(__file__).resolve().parents[1]
BASE = HERE/"build/base_dst.vvp"; SCALAR = HERE/"build/wide_scalar.vvp"
FIELDS = ("cycles","processed","read_requests","write_requests","read_beats",
          "write_beats","read_bytes","write_bytes")

def run(binpath, folder, ob):
    p = subprocess.run([str(binpath), f"+folder={folder}", f"+nbytes={ob}", "+mode=0"],
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       timeout=600)
    d = parse_log(p.stdout); d["rc"] = p.returncode
    return d

cases = []
for label, d in (("official", "/tmp/opencode/dslw_official"),
                 ("gold", "/tmp/opencode/dslw_gold")):
    meta = json.loads((Path(d)/"meta.json").read_text())
    for c in meta:
        cases.append((f"{label}:{c['name']}", str(Path(d)/c["name"]), c["output_bytes"]))
rd = Path("/tmp/opencode/dslw_random")
for p in sorted(x for x in rd.iterdir() if x.is_dir())[:30]:
    w = [int(x, 16) for x in (p/"descriptor.hex").read_text().split()]
    cases.append((f"random:{p.name}", str(p), extent_bytes(w)))

rows = []; fails = 0
for name, folder, ob in cases:
    a = run(BASE, folder, ob); b = run(SCALAR, folder, ob)
    ok = (a["rc"] == b["rc"] == 0 and a["pass"] and b["pass"]
          and all(a[k] == b[k] for k in FIELDS))
    fails += 0 if ok else 1
    rows.append({"name": name, "ok": ok, "base": a, "scalar": b})

lines = ["name ok cyc_base cyc_scalar"]
for r in rows:
    lines.append(f"{r['name']} {int(r['ok'])} {r['base']['cycles']} {r['scalar']['cycles']}")
lines.append(f"SCALAR_FALLBACK cases={len(rows)} fails={fails} "
             f"(FASTPATH=0 MODE2_PREFETCH=16 vs frozen v023 burst)")
(HERE/"logs"/"scalar_fallback.log").write_text("\n".join(lines)+"\n")
(HERE/"logs"/"scalar_fallback.json").write_text(json.dumps(
    {"cases": len(rows), "fails": fails, "rows": rows}, indent=1))
print(lines[-1])
raise SystemExit(1 if fails else 0)
