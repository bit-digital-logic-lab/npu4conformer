#!/usr/bin/env python3
"""Generate random/e dge layout descriptors and run original vs candidate."""
import json, random, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
WORK = Path("/tmp/opencode/dscc_layout_fuzz")
WORK.mkdir(parents=True, exist_ok=True)
BIN = {"orig": HERE / "build" / "layout_fuzz_orig.vvp",
       "cand": HERE / "build" / "layout_fuzz_cand.vvp"}
LOG = HERE / "logs" / "layout_fuzz.log"

# 256 KiB deterministic DDR image.
rng = random.Random(20261029)
mem = bytearray(262144)
for i in range(len(mem)):
    mem[i] = (i * 73 + (i >> 8) * 29 + 0x5A) & 0xFF
(WORK / "memory.hex").write_text("".join(f"{b:02x}\n" for b in mem), encoding="ascii")

def desc(mode=0, src=0x04000000, dst=0x04010000, total=1024, nbytes=2,
         m=32, n=32, full_n=32, col_start=0, channels=1, ih=16, iw=16,
         kh=1, kw=1, oh=16, ow=16, sh=1, sw=1, dh=1, dw=1, ph=0, pw=0,
         k_offset=0, magic=0x224C4159, param_end=0x10010000):
    w = [magic, mode, src, dst, total, nbytes, m, n, full_n, col_start,
         channels, ih, iw, kh, kw, oh, ow, sh, sw, dh, dw, ph, pw, k_offset] + [0] * 8
    return w, param_end

cases = []
def add(name, w, pe=0x10010000):
    cases.append((name, w, pe))

# Legal mode 0 (copy).
for i, (total, nb) in enumerate([(1, 2), (1001, 2), (64, 4), (37, 6), (2048, 6)]):
    add(f"copy_{i}", *desc(0, total=total, nbytes=nb, src=0x04000000, dst=0x04020000))
# Legal mode 1 (rowmajor -> tiled).
for i, (m, n, full_n, nb) in enumerate([(33, 35, 35, 2), (64, 32, 40, 2), (32, 64, 64, 2)]):
    mt, nt = (m + 31) // 32, (n + 31) // 32
    total = mt * nt * 1024
    add(f"pack_{i}", *desc(1, src=0x04000000, dst=0x04020000, total=total,
                          nbytes=2, m=m, n=n, full_n=full_n, col_start=0))
# Legal mode 2 (conv im2col), including padding.
for i, (c, ih, iw, kh, kw, oh, ow, sh, sw, ph, pw) in enumerate([
        (1, 16, 16, 3, 3, 14, 14, 1, 1, 1, 1),
        (3, 16, 16, 3, 3, 7, 7, 2, 2, 1, 1),
        (4, 32, 24, 3, 3, 15, 11, 2, 2, 0, 0),
        (2, 8, 8, 1, 1, 8, 8, 1, 1, 0, 0)]):
    mt = (oh * ow + 31) // 32
    nt = (c * kh * kw + 31) // 32
    add(f"conv_{i}", *desc(2, src=0x04000000, dst=0x04020000, total=mt * nt * 1024,
                          nbytes=2, m=oh * ow, n=c * kh * kw, channels=c, ih=ih, iw=iw,
                          kh=kh, kw=kw, oh=oh, ow=ow, sh=sh, sw=sw, ph=ph, pw=pw,
                          dh=1, dw=1, k_offset=0))
# Legal mode 3/4 (tiled -> rowmajor / NCHW compact).
for i, (mode, m, n, full_n, col_start, nb) in enumerate([
        (3, 33, 35, 40, 0, 4), (3, 64, 32, 64, 0, 6), (3, 31, 31, 31, 0, 2),
        (4, 33, 35, 40, 0, 4), (4, 64, 32, 64, 0, 6)]):
    mt, nt = (m + 31) // 32, (n + 31) // 32
    total = mt * nt * 1024
    add(f"unpack_{mode}_{i}", *desc(mode, src=0x04000000, dst=0x04020000, total=total,
                                     nbytes=nb, m=m, n=n, full_n=full_n, col_start=col_start))
# Legal parameter-window B read (mode 1).
mt, nt = 2, 2
add("param_B", *desc(1, src=0x10000000, dst=0x04020000, total=mt * nt * 1024,
                     nbytes=2, m=64, n=64, full_n=64, param_end=0x10010000))

# Illegal descriptors.
add("bad_magic", *desc(0, magic=0x224C4158))
add("bad_mode", *desc(5))
add("bad_total0", *desc(0, total=0))
add("bad_total_big", *desc(0, total=16777217))
add("bad_bytes3", *desc(0, nbytes=3))
add("bad_src_align", *desc(0, src=0x04000001))
add("bad_dst_align", *desc(0, dst=0x04010002))
add("bad_m0", *desc(1, m=0))
add("bad_m_big", *desc(1, m=4097))
add("bad_n0", *desc(1, n=0))
add("bad_n_big", *desc(1, n=4097))
add("bad_full0", *desc(1, full_n=0))
add("bad_full_big", *desc(1, full_n=8193))
add("bad_koff", *desc(1, n=32, full_n=32, k_offset=33))
add("bad_ch0", *desc(2, channels=0))
add("bad_ch_big", *desc(2, channels=1025))
add("bad_ih0", *desc(2, ih=0))
add("bad_iw0", *desc(2, iw=0))
add("bad_kh0", *desc(2, kh=0))
add("bad_kw32", *desc(2, kw=32))
add("bad_oh0", *desc(2, oh=0))
add("bad_ow0", *desc(2, ow=0))
add("bad_sh0", *desc(2, sh=0))
add("bad_sw0", *desc(2, sw=0))
add("bad_dh0", *desc(2, dh=0))
add("bad_dw0", *desc(2, dw=0))
add("bad_ph", *desc(2, ph=256))
add("bad_total_mismatch", *desc(1, total=1234, m=33, n=35, full_n=35))
add("bad_src_overflow", *desc(0, total=2048, nbytes=6, src=0x02FFF000, dst=0x04020000))
add("bad_dst_overflow", *desc(0, total=2048, nbytes=6, src=0x04000000, dst=0x07FFF000))
add("bad_overlap", *desc(0, total=2048, nbytes=6, src=0x04000000, dst=0x04000010))
add("bad_param_end", *desc(1, src=0x10000000, dst=0x04020000, total=4096, m=64, n=64,
                           full_n=64, param_end=0x40001000))
add("bad_param_mode2", *desc(2, src=0x10000000, dst=0x04020000, total=64, channels=1,
                             ih=8, iw=8, oh=8, ow=8, kh=1, kw=1, param_end=0x10010000))

def run(binpath, dfile, pe):
    p = subprocess.run([str(binpath), f"+mem={WORK/'memory.hex'}", f"+desc={dfile}",
                        f"+pe={pe}", f"+log={WORK/'out.log'}"], text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT)
    txt = (WORK / "out.log").read_text().strip() if (WORK / "out.log").exists() else ""
    return p.returncode, txt

lines = []
fails = 0
for idx, (name, w, pe) in enumerate(cases):
    dfile = WORK / f"d{idx}.hex"
    dfile.write_text("".join(f"{v & 0xffffffff:08x}\n" for v in w), encoding="ascii")
    # param_end is not in the descriptor; the harness uses a fixed 0x10010000.
    a = run(BIN["orig"], dfile, pe)
    b = run(BIN["cand"], dfile, pe)
    ok = a == b
    fails += 0 if ok else 1
    lines.append(f"{'PASS' if ok else 'FAIL'} {name}")
    lines.append(f"  orig rc={a[0]} {a[1]}")
    lines.append(f"  cand rc={b[0]} {b[1]}")

text = "\n".join(lines) + f"\nSUMMARY cases={len(cases)} fails={fails}\n"
LOG.write_text(text)
print(text)
raise SystemExit(1 if fails else 0)
