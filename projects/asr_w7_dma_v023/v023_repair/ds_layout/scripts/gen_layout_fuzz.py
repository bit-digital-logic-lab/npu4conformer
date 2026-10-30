#!/usr/bin/env python3
"""Random/edge layout descriptors: original RTL vs candidate RTL.
Both binaries get the same DDR image and descriptor; compare fault/error/
processed/cache/R/W counters and a hash of the 256 KiB private DDR window."""
import json, random, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
WORK = Path("/tmp/opencode/dslayout_fuzz")
WORK.mkdir(parents=True, exist_ok=True)
BIN = {"orig": HERE / "build" / "layout_fuzz_orig.vvp",
       "cand": HERE / "build" / "layout_fuzz_cand.vvp"}
LOG = HERE / "logs" / "layout_fuzz.log"

rng = random.Random(20261029)
mem = bytearray(262144)
for i in range(len(mem)):
    mem[i] = (i * 73 + (i >> 8) * 29 + 0x5A) & 0xFF
(WORK / "memory.hex").write_text("".join(f"{b:02x}\n" for b in mem), encoding="ascii")

def desc(mode=0, src=0x04000000, dst=0x04010000, total=1024, nbytes=2,
         m=32, n=32, full_n=32, col_start=0, channels=1, ih=16, iw=16,
         kh=1, kw=1, oh=16, ow=16, sh=1, sw=1, dh=1, dw=1, ph=0, pw=0,
         k_offset=0, magic=0x224C4159):
    w = [magic, mode, src, dst, total, nbytes, m, n, full_n, col_start,
         channels, ih, iw, kh, kw, oh, ow, sh, sw, dh, dw, ph, pw, k_offset] + [0] * 8
    return w

cases = []
def add(name, w, pe=0x10010000):
    cases.append((name, w, pe))

# legal mode 0
for i, (total, nb) in enumerate([(1, 2), (1001, 2), (64, 4), (37, 6), (2048, 6)]):
    add(f"copy_{i}", desc(0, total=total, nbytes=nb, src=0x04000000, dst=0x04020000))
# legal mode 1
for i, (m, n, full_n, nb) in enumerate([(33, 35, 35, 2), (64, 32, 40, 2), (32, 64, 64, 2)]):
    mt, nt = (m + 31) // 32, (n + 31) // 32
    add(f"pack_{i}", desc(1, src=0x04000000, dst=0x04020000, total=mt * nt * 1024,
                          nbytes=2, m=m, n=n, full_n=full_n, col_start=0))
# legal mode 2 (padding/stride/dilation/k_offset/channels)
for i, (c, ih, iw, kh, kw, oh, ow, sh, sw, dh, dw, ph, pw, ko) in enumerate([
        (1, 16, 16, 3, 3, 14, 14, 1, 1, 1, 1, 1, 1, 0),
        (3, 16, 16, 3, 3, 7, 7, 2, 2, 1, 1, 1, 1, 0),
        (4, 32, 24, 3, 3, 15, 11, 2, 2, 1, 1, 0, 0, 0),
        (2, 8, 8, 1, 1, 8, 8, 1, 1, 1, 1, 0, 0, 0),
        (2, 20, 18, 3, 3, 10, 9, 2, 1, 2, 2, 0, 0, 0),
        (3, 9, 11, 2, 2, 9, 11, 1, 1, 1, 1, 0, 0, 4)]):
    mt = (oh * ow + 31) // 32
    n_used = c * kh * kw - ko
    nt = (n_used + 31) // 32
    add(f"conv_{i}", desc(2, src=0x04000000, dst=0x04020000, total=mt * nt * 1024,
                          nbytes=2, m=oh * ow, n=n_used, channels=c, ih=ih, iw=iw,
                          kh=kh, kw=kw, oh=oh, ow=ow, sh=sh, sw=sw, dh=dh, dw=dw,
                          ph=ph, pw=pw, k_offset=ko))
# legal mode 3/4 (transpose / compact C48, slices).  mode 3/4 total == m*n.
for i, (mode, m, n, full_n, col_start, nb) in enumerate([
        (3, 33, 35, 40, 0, 4), (3, 64, 32, 64, 0, 6), (3, 31, 31, 31, 0, 2),
        (4, 33, 35, 40, 0, 4), (4, 64, 32, 64, 0, 6),
        (3, 32, 33, 35, 2, 6), (4, 35, 33, 40, 3, 2),
        (3, 35, 33, 40, 5, 6), (4, 33, 35, 40, 2, 2)]):
    add(f"unpack_{mode}_{i}", desc(mode, src=0x04000000, dst=0x04020000, total=m*n,
                                   nbytes=nb, m=m, n=n, full_n=full_n, col_start=col_start))
# parameter-window B read
add("param_B", desc(1, src=0x10000000, dst=0x04020000, total=2 * 2 * 1024,
                    nbytes=2, m=64, n=64, full_n=64))

# illegal descriptors
add("bad_magic", desc(0, magic=0x224C4158))
add("bad_mode", desc(5))
add("bad_total0", desc(0, total=0))
add("bad_total_big", desc(0, total=16777217))
add("bad_bytes3", desc(0, nbytes=3))
add("bad_src_align", desc(0, src=0x04000001))
add("bad_dst_align", desc(0, dst=0x04010001))
add("bad_m0", desc(1, m=0))
add("bad_m_big", desc(1, m=4097))
add("bad_n0", desc(1, n=0))
add("bad_n_big", desc(1, n=4097))
add("bad_full0", desc(1, full_n=0))
add("bad_full_big", desc(1, full_n=8193))
add("bad_koff", desc(1, n=32, full_n=32, k_offset=33))
add("bad_ch0", desc(2, channels=0))
add("bad_ch_big", desc(2, channels=1025))
add("bad_ih0", desc(2, ih=0))
add("bad_iw0", desc(2, iw=0))
add("bad_kh0", desc(2, kh=0))
add("bad_kw32", desc(2, kw=32))
add("bad_oh0", desc(2, oh=0))
add("bad_ow0", desc(2, ow=0))
add("bad_sh0", desc(2, sh=0))
add("bad_sw0", desc(2, sw=0))
add("bad_dh0", desc(2, dh=0))
add("bad_dw0", desc(2, dw=0))
add("bad_ph", desc(2, ph=256))
add("bad_total_mismatch", desc(1, total=1234, m=33, n=35, full_n=35))
add("bad_src_overflow", desc(0, total=2048, nbytes=6, src=0x02FFF000, dst=0x04020000))
add("bad_dst_overflow", desc(0, total=2048, nbytes=6, src=0x04000000, dst=0x07FFF000))
add("bad_overlap", desc(0, total=2048, nbytes=6, src=0x04000000, dst=0x04000010))
add("bad_param_end", desc(1, src=0x10000000, dst=0x04020000, total=4096, m=64, n=64,
                          full_n=64), pe=0x40001000)
add("bad_param_mode2", desc(2, src=0x10000000, dst=0x04020000, total=64, channels=1,
                            ih=8, iw=8, oh=8, ow=8, kh=1, kw=1))

def parse(txt):
    d={}
    for kv in txt.split():
        if '=' in kv:
            k,v=kv.split('=',1)
            d[k]=v
    return d

def run(binpath, dfile, pe):
    outf = WORK / "out.log"
    if outf.exists(): outf.unlink()
    p = subprocess.run([str(binpath), f"+mem={WORK/'memory.hex'}", f"+desc={dfile}",
                        f"+pe={pe}", f"+log={outf}"], text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT)
    txt = outf.read_text().strip() if outf.exists() else ""
    return p.returncode, txt

FUNC=("fault","err","processed","memhash")
lines=[]; fails=0; rows=[]
for idx,(name,w,pe) in enumerate(cases):
    dfile=WORK/f"d{idx}.hex"
    dfile.write_text("".join(f"{v & 0xffffffff:08x}\n" for v in w),encoding="ascii")
    a=run(BIN["orig"],dfile,pe); b=run(BIN["cand"],dfile,pe)
    da,db=parse(a[1]),parse(b[1])
    ok=a[0]==b[0] and all(da.get(k)==db.get(k) for k in FUNC)
    fails+=0 if ok else 1
    def num(d,k):
        try: return int(d.get(k,"0"))
        except ValueError: return 0
    cyc_o,cyc_c=num(da,"cycles"),num(db,"cycles")
    rbo,rbc=num(da,"rbeat"),num(db,"rbeat")
    wbo,wbc=num(da,"wbeat"),num(db,"wbeat")
    rows.append((name,ok,cyc_o,cyc_c,rbo,rbc,wbo,wbc,num(da,"rb"),num(db,"rb"),num(da,"wb"),num(db,"wb")))
    lines.append(f"{'PASS' if ok else 'FAIL'} {name}")
    lines.append(f"  orig rc={a[0]} {a[1]}")
    lines.append(f"  cand rc={b[0]} {b[1]}")

lines.append("")
lines.append("name ok cyc_orig cyc_cand ratio rbeat_o rbeat_c wbeat_o wbeat_c rb_o rb_c wb_o wb_c")
for r in rows:
    ratio=(r[3]/r[2]) if r[2] else 0
    lines.append(f"{r[0]} {int(r[1])} {r[2]} {r[3]} {ratio:.3f} {r[4]} {r[5]} {r[6]} {r[7]} {r[8]} {r[9]} {r[10]} {r[11]}")
tot_o=sum(r[2] for r in rows); tot_c=sum(r[3] for r in rows)
legal=[r for r in rows if r[1]]
lines.append(f"CYCLES_TOTAL orig={tot_o} cand={tot_c} ratio={tot_c/tot_o if tot_o else 0:.3f}")
lines.append(f"SUMMARY cases={len(cases)} fails={fails}")
LOG.write_text("\n".join(lines)+"\n")
print("\n".join(lines[-8:]))
raise SystemExit(1 if fails else 0)
