#!/usr/bin/env python3
"""Randomised legal descriptors checked against the independent Python model.

Each case is generated deterministically, written as a gold fixture, and run on
the original RTL and the burst candidate through the same testbench.  PASS means
the RTL-written DDR image is byte-identical to the model and the tail guard is
intact.  We also record read/write beats and cycles.
"""
import json, random, re, subprocess
from pathlib import Path
from layout_model import (DST_OFF, build_mem, desc, check_legal, extent_bytes,
                          model, write_case)

HERE = Path(__file__).resolve().parents[1]
FIX = HERE / "fixtures" / "random"
FIX.mkdir(parents=True, exist_ok=True)
TMPFIX = Path("/tmp/opencode/ds_layout_random")
if TMPFIX.is_symlink() or TMPFIX.exists():
    if TMPFIX.is_symlink() or TMPFIX.is_dir():
        try: TMPFIX.unlink()
        except IsADirectoryError: pass
TMPFIX.symlink_to(FIX)
BINS = {"orig": HERE/"build/layout_orig.vvp", "burst": HERE/"build/layout_burst.vvp"}
FIELDS = ["cycles","processed","read_beats","write_beats","read_bytes","write_bytes"]

def parse(t):
    d={"pass":"PASS" in t}
    for k in FIELDS:
        m=re.search(rf"{k}=\s*(\d+)",t); d[k]=int(m.group(1)) if m else None
    return d

rng=random.Random(20261029)
cases=[]
def try_add(name,w):
    try:
        check_legal(w)
        ob=extent_bytes(w)
        if ob<=40000:
            cases.append((name,w)); return True
    except AssertionError:
        pass
    return False

# mode 0
for i in range(20):
    nb=rng.choice([2,4,6]); total=rng.randint(1,4000)
    try_add(f"r0_{i}", desc(0,total=total,nbytes=nb))
# mode 1
for i in range(20):
    m=rng.randint(1,96); n=rng.randint(1,96); full_n=n+rng.randint(0,16)
    ko=rng.randint(0,min(full_n-n,8))
    mt,nt=(m+31)//32,(n+31)//32
    try_add(f"r1_{i}", desc(1,total=mt*nt*1024,nbytes=2,m=m,n=n,full_n=full_n,k_offset=ko))
# mode 2
for i in range(40):
    ch=rng.randint(1,4); ih=rng.randint(4,40); iw=rng.randint(4,40)
    kh=rng.randint(1,4); kw=rng.randint(1,4)
    oh=rng.randint(1,20); ow=rng.randint(1,20)
    if oh*ow>400: continue
    K=ch*kh*kw
    if K>64: continue
    ko=rng.randint(0,min(8,K-1)); n=K-ko
    sh=rng.randint(1,4); sw=rng.randint(1,5); dh=rng.randint(1,9); dw=rng.randint(1,9)
    ph=rng.randint(0,3); pw=rng.randint(0,3)
    m=oh*ow; mt,nt=(m+31)//32,(n+31)//32
    try_add(f"r2_{i}", desc(2,total=mt*nt*1024,nbytes=2,m=m,n=n,channels=ch,
                           ih=ih,iw=iw,kh=kh,kw=kw,oh=oh,ow=ow,sh=sh,sw=sw,dh=dh,dw=dw,
                           ph=ph,pw=pw,k_offset=ko))
# mode 3/4
for i in range(20):
    mode=rng.choice([3,4]); m=rng.randint(1,96); n=rng.randint(1,96)
    full_n=n+rng.randint(0,16); cs=rng.randint(0,full_n-n); nb=rng.choice([2,4,6])
    try_add(f"r{mode}_{i}", desc(mode,total=m*n,nbytes=nb,m=m,n=n,full_n=full_n,col_start=cs))

rows=[]; fails=0
for name,w in cases:
    ob=write_case(FIX,name,w)
    rec={"name":name,"mode":w[1],"bytes":w[5],"elems":w[4],"ob":ob}
    for tag,b in BINS.items():
        log=HERE/"logs"/f"rand_{tag}_{name}.log"
        p=subprocess.run([str(b),f"+folder={TMPFIX/name}",f"+nbytes={ob}","+mode=0"],
                         text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        log.write_text(p.stdout)
        rec[tag]=parse(p.stdout); rec[tag]["rc"]=p.returncode
    ok=(rec["orig"]["pass"] and rec["burst"]["pass"]
        and rec["burst"]["rc"]==0 and rec["orig"]["rc"]==0
        and rec["burst"]["processed"]==rec["orig"]["processed"]
        and rec["burst"]["write_beats"]==rec["orig"]["write_beats"]
        and rec["burst"]["write_bytes"]==rec["orig"]["write_bytes"])
    rec["ok"]=ok
    if not ok: fails+=1
    rows.append(rec)

lines=["name mode bytes elems ok cyc_o cyc_b ratio rbeat_o rbeat_b drbeat wbeat_o wbeat_b"]
tot_o=tot_b=0; over=0; max_over=0; sum_over=0
for r in rows:
    o,b=r["orig"],r["burst"]
    oc=o["cycles"] or 0; bc=b["cycles"] or 0
    ratio=bc/oc if oc else 0
    if not r["ok"]:
        print("FAILCASE", r["name"], "orig", o, "burst", b)
    dro=(b["read_beats"] or 0)-(o["read_beats"] or 0)
    if dro>0: over+=1; sum_over+=dro; max_over=max(max_over,dro)
    tot_o+=oc; tot_b+=bc
    lines.append(f"{r['name']} {r['mode']} {r['bytes']} {r['elems']} {int(r['ok'])} "
                 f"{o['cycles']} {b['cycles']} {ratio:.3f} "
                 f"{o['read_beats']} {b['read_beats']} {dro} {o['write_beats']} {b['write_beats']}")
lines.append(f"TOTAL cases={len(rows)} fails={fails} cyc_orig={tot_o} cyc_burst={tot_b} "
             f"ratio={tot_b/tot_o if tot_o else 0:.3f}")
lines.append(f"READ_OVERFETCH cases={over}/{len(rows)} extra_beats={sum_over} "
             f"max_extra_beats_per_case={max_over}")
text="\n".join(lines)+"\n"
(HERE/"logs"/"random_fuzz.log").write_text(text)
print("\n".join(lines[-4:]))
raise SystemExit(1 if fails else 0)
