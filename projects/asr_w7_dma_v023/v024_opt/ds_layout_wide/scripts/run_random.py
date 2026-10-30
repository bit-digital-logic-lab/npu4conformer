#!/usr/bin/env python3
"""100 preserved deterministic random cases + 40 new random/short-tail cases.

Reference = scripts/layout_model.py (independent Python expansion).
Baseline = frozen v023 burst RTL; candidate = wide RTL.  Candidate must match
the independent gold byte-for-byte and match baseline on processed/write beats/
write bytes.  Read beats may differ (overfetch is recorded, never assumed).
"""
import json, random, re, subprocess, sys
from pathlib import Path
from layout_model import (DST_OFF, build_mem, desc, check_legal, extent_bytes,
                          model, write_case)
from metrics import source_bytes, REQUIRED, WIDE_REQUIRED, missing_fields

HERE = Path(__file__).resolve().parents[1]
FIX = HERE / "fixtures" / "random"
FIX.mkdir(parents=True, exist_ok=True)
TMP = Path("/tmp/opencode/dslw_random")
if TMP.is_symlink() or TMP.exists():
    try: TMP.unlink()
    except IsADirectoryError: pass
TMP.symlink_to(FIX)
BINS = {"base": HERE/"build/base_dst.vvp", "wide": HERE/"build/wide_fasttb.vvp"}
FIELDS = ["cycles","processed","read_beats","write_beats","read_bytes","write_bytes",
          "read_requests","write_requests","fast_elements","fast_beats","fast_groups"]

def parse(t):
    d = {"pass": "PASS" in t}
    for k in FIELDS:
        m = re.search(rf"{k}=\s*(\d+)", t)
        d[k] = int(m.group(1)) if m else None
    return d

def gen_original():
    rng = random.Random(20261029)
    cases = []
    def try_add(name, w):
        try:
            check_legal(w); ob = extent_bytes(w)
            if ob <= 40000:
                cases.append((name, w)); return True
        except AssertionError:
            pass
        return False
    for i in range(20):
        nb = rng.choice([2,4,6]); total = rng.randint(1,4000)
        try_add(f"r0_{i}", desc(0, total=total, nbytes=nb))
    for i in range(20):
        m = rng.randint(1,96); n = rng.randint(1,96); full_n = n + rng.randint(0,16)
        ko = rng.randint(0, min(full_n-n,8))
        mt,nt = (m+31)//32,(n+31)//32
        try_add(f"r1_{i}", desc(1, total=mt*nt*1024, nbytes=2, m=m, n=n,
                               full_n=full_n, k_offset=ko))
    for i in range(40):
        ch = rng.randint(1,4); ih = rng.randint(4,40); iw = rng.randint(4,40)
        kh = rng.randint(1,4); kw = rng.randint(1,4)
        oh = rng.randint(1,20); ow = rng.randint(1,20)
        if oh*ow > 400: continue
        K = ch*kh*kw
        if K > 64: continue
        ko = rng.randint(0, min(8,K-1)); n = K-ko
        sh = rng.randint(1,4); sw = rng.randint(1,5); dh = rng.randint(1,9); dw = rng.randint(1,9)
        ph = rng.randint(0,3); pw = rng.randint(0,3)
        m = oh*ow; mt,nt = (m+31)//32,(n+31)//32
        try_add(f"r2_{i}", desc(2, total=mt*nt*1024, nbytes=2, m=m, n=n, channels=ch,
                               ih=ih, iw=iw, kh=kh, kw=kw, oh=oh, ow=ow, sh=sh, sw=sw,
                               dh=dh, dw=dw, ph=ph, pw=pw, k_offset=ko))
    for i in range(20):
        mode = rng.choice([3,4]); m = rng.randint(1,96); n = rng.randint(1,96)
        full_n = n + rng.randint(0,16); cs = rng.randint(0, full_n-n); nb = rng.choice([2,4,6])
        try_add(f"r{mode}_{i}", desc(mode, total=m*n, nbytes=nb, m=m, n=n,
                                    full_n=full_n, col_start=cs))
    return cases

def gen_new():
    rng = random.Random(20261030)
    cases = []
    def doff(nb):
        step = 4 if nb == 4 else 2
        return DST_OFF + rng.randrange(0, 16//step)*step
    def try_add(name, w):
        try:
            check_legal(w); ob = extent_bytes(w)
            if ob <= 40000:
                cases.append((name, w)); return True
        except AssertionError:
            pass
        return False
    # short copy tails with unaligned destinations
    for i in range(24):
        nb = rng.choice([2,4,6]); total = rng.randint(1,40)
        d = doff(nb)
        try_add(f"n_c0_{i}", desc(0, total=total, nbytes=nb, dst=d,
                                  src=0x04000000 + rng.randrange(0,16//(2 if nb!=4 else 4))*(2 if nb!=4 else 4)))
    # mode 1 short rows / n tails
    for i in range(12):
        m = rng.randint(1,80); n = rng.randint(1,40); full_n = n + rng.randint(0,12)
        ko = rng.randint(0, min(full_n-n,4))
        mt,nt = (m+31)//32,(n+31)//32
        try_add(f"n_p1_{i}", desc(1, total=mt*nt*1024, nbytes=2, m=m, n=n,
                                  full_n=full_n, k_offset=ko, dst=doff(2)))
    # mode 3/4 short rows / multi tile columns / unaligned dst
    for i in range(16):
        mode = rng.choice([3,4]); m = rng.randint(1,80); n = rng.randint(1,80)
        full_n = n + rng.randint(0,10); cs = rng.randint(0, full_n-n)
        nb = rng.choice([2,4,6])
        try_add(f"n_m{mode}_{i}", desc(mode, total=m*n, nbytes=nb, m=m, n=n,
                                       full_n=full_n, col_start=cs, dst=doff(nb)))
    return cases

cases = gen_original() + gen_new()
rows = []; fails = 0
for name, w in cases:
    ob = write_case(FIX, name, w)
    rec = {"name": name, "mode": w[1], "bytes": w[5], "elems": w[4], "ob": ob,
           "src_bytes": source_bytes(w)}
    for tag, b in BINS.items():
        log = HERE/"logs"/f"rand_{tag}_{name}.log"
        p = subprocess.run([str(b), f"+folder={TMP/name}", f"+nbytes={ob}", "+mode=0"],
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=300)
        log.write_text(p.stdout)
        rec[tag] = parse(p.stdout); rec[tag]["rc"] = p.returncode
    rec["base"]["missing"] = missing_fields(rec["base"], REQUIRED)
    rec["wide"]["missing"] = missing_fields(rec["wide"], WIDE_REQUIRED)
    if rec["base"].get("fast_elements") is None:
        rec["base"]["fast_elements_note"] = "v023 baseline TB has no fast counter"
    o, b = rec["base"], rec["wide"]
    ok = (o["pass"] and b["pass"] and o["rc"] == 0 and b["rc"] == 0
          and not o["missing"] and not b["missing"]
          and b["processed"] == o["processed"]
          and b["write_beats"] == o["write_beats"]
          and b["write_bytes"] == o["write_bytes"])
    rec["ok"] = ok
    rec["effective_bytes"] = rec["wide"]["processed"] * w[5]
    rec["overfetch_base"] = rec["base"]["read_bytes"] - rec["src_bytes"]
    rec["overfetch_wide"] = rec["wide"]["read_bytes"] - rec["src_bytes"]
    rows.append(rec)
    if not ok:
        fails += 1
        print("FAILCASE", name, "missing_base", o.get("missing"), "missing_wide", b.get("missing"), o, b)

lines = ["name mode bytes elems ok cyc_o cyc_w ratio rbeat_o rbeat_w drbeat wbeat_o wbeat_w fast_w"]
tot_o = tot_w = 0; over = 0; sum_over = 0; max_over = 0
for r in rows:
    o, b = r["base"], r["wide"]
    oc = o["cycles"] or 0; wc = b["cycles"] or 0
    ratio = wc/oc if oc else 0
    dro = (b["read_beats"] or 0) - (o["read_beats"] or 0)
    if dro > 0: over += 1; sum_over += dro; max_over = max(max_over, dro)
    tot_o += oc; tot_w += wc
    lines.append(f"{r['name']} {r['mode']} {r['bytes']} {r['elems']} {int(r['ok'])} "
                 f"{o['cycles']} {b['cycles']} {ratio:.3f} {o['read_beats']} {b['read_beats']} "
                 f"{dro} {o['write_beats']} {b['write_beats']} {b['fast_elements']}")
lines.append(f"TOTAL cases={len(rows)} fails={fails} cyc_base={tot_o} cyc_wide={tot_w} "
             f"ratio={tot_w/tot_o if tot_o else 0:.3f}")
lines.append(f"READ_OVERFETCH cases={over}/{len(rows)} extra_beats={sum_over} max={max_over}")
text = "\n".join(lines) + "\n"
(HERE/"logs"/"random_fuzz.log").write_text(text)
import json as _json
(HERE/"logs"/"random_suite.json").write_text(_json.dumps(
    {"rows": rows, "cases": len(rows), "fails": fails,
     "cycles_base": tot_o, "cycles_wide": tot_w,
     "overfetch_cases": over, "extra_beats": sum_over, "max_extra": max_over}, indent=1))
print("\n".join(lines[-4:]))
raise SystemExit(1 if fails else 0)
