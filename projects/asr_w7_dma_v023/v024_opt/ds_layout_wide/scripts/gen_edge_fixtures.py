#!/usr/bin/env python3
"""New edge/random-tail fixtures for the V0.24 wide fast path.

All expectations come from scripts/layout_model.py (independent descriptor
model).  Destination may be offset inside the private window so unaligned
destination heads/tails are exercised for real (the testbench compares at the
descriptor destination).
"""
from pathlib import Path
from layout_model import DST_OFF, desc, check_legal, extent_bytes, write_case

FIX = Path(__file__).resolve().parents[1] / "fixtures" / "edge"
FIX.mkdir(parents=True, exist_ok=True)

cases = []
def add(name, w):
    check_legal(w)
    cases.append((name, w, extent_bytes(w)))

D = DST_OFF
# ---- mode 0: unaligned heads/tails, phase mismatch, 4 KiB, short tails ----
add("c0_dst2_b2",   desc(0, total=1001, nbytes=2, dst=D+2))
add("c0_src2_b2",   desc(0, total=1001, nbytes=2, src=0x04000002))
add("c0_both_b2",   desc(0, total=1001, nbytes=2, src=0x04000006, dst=D+0x0E))
add("c0_dst4_b4",   desc(0, total=1003, nbytes=4, src=0x04000004, dst=D+4))
add("c0_dst6_b6",   desc(0, total=683,  nbytes=6, src=0x04000002, dst=D+2))
add("c0_4k_src",    desc(0, total=100,  nbytes=2, src=0x04000FF0, dst=D))
add("c0_4k_dst",    desc(0, total=100,  nbytes=2, src=0x04000000, dst=D+0x0FF0))
add("c0_4k_both",   desc(0, total=300,  nbytes=4, src=0x04000FF4, dst=D+0x0FF4))
add("c0_4k_src_u",  desc(0, total=300,  nbytes=4, src=0x04000FF4, dst=D))

# ---- 4 KiB crossing with mode1/mode3 fast path + row gaps ---------------
add("p1_4k_b2", desc(1, total=2*1*1024, nbytes=2, m=64, n=32, full_n=32, dst=D+0x0FF0))
add("t3_4k_b2", desc(3, total=64*64, nbytes=2, m=64, n=64, full_n=64, dst=D+0x0FF0))
add("t3_4k_b4", desc(3, total=64*40, nbytes=4, m=64, n=40, full_n=40, dst=D+0x0FF4))
add("t3_4k_gap_b4", desc(3, total=64*40, nbytes=4, m=64, n=40, full_n=47,
                         col_start=3, dst=D+0x0FE0))
add("t3_4k_b6", desc(3, total=33*35, nbytes=6, m=33, n=35, full_n=35, dst=D+0x0FFE))
for n in (1, 2, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65):
    add(f"c0_tail_{n}", desc(0, total=n, nbytes=2, dst=D+2))
for n in (1, 3, 4, 5, 8, 9):
    add(f"c0_tail4_{n}", desc(0, total=n, nbytes=4, dst=D+4))

# ---- mode 1: 32-column row boundary, n tails, unaligned destination ------
add("p1_n32_m64", desc(1, total=2*1*1024, nbytes=2, m=64, n=32, full_n=32))
add("p1_n32_m64_dst2", desc(1, total=2*1*1024, nbytes=2, m=64, n=32, full_n=32, dst=D+2))
add("p1_n35_m33_dst4", desc(1, total=2*2*1024, nbytes=2, m=33, n=35, full_n=35, dst=D+4))
add("p1_n64_m64", desc(1, total=2*2*1024, nbytes=2, m=64, n=64, full_n=70, k_offset=2))
add("p1_n8_m32", desc(1, total=1*1*1024, nbytes=2, m=32, n=8, full_n=8))
add("p1_n1_m32", desc(1, total=1*1*1024, nbytes=2, m=32, n=1, full_n=1))
add("p1_n33_m64_ko", desc(1, total=2*2*1024, nbytes=2, m=64, n=33, full_n=40, k_offset=3))

# ---- mode 3: multi tile-column, n tails, unaligned dst, C48 fallback -----
add("t3_64_full64_b2", desc(3, total=64*64, nbytes=2, m=64, n=64, full_n=64))
add("t3_64_full70_b4", desc(3, total=64*40, nbytes=4, m=64, n=40, full_n=70, col_start=3))
add("t3_33_full35_b2", desc(3, total=33*35, nbytes=2, m=33, n=35, full_n=35))
add("t3_33_full40_b6", desc(3, total=33*35, nbytes=6, m=33, n=35, full_n=40, col_start=1))
add("t3_65_full70_b2", desc(3, total=40*65, nbytes=2, m=40, n=65, full_n=70, col_start=1))
add("t3_32_full32_b4", desc(3, total=64*32, nbytes=4, m=64, n=32, full_n=32))
add("t3_9_full9_b2", desc(3, total=9*7, nbytes=2, m=9, n=7, full_n=7))
add("t3_64_full64_dst2", desc(3, total=64*64, nbytes=2, m=64, n=64, full_n=64, dst=D+2))
add("t3_64_full64_dst4", desc(3, total=64*64, nbytes=4, m=64, n=64, full_n=64, dst=D+4))
add("t3_64_full64_dst14_b6", desc(3, total=64*64, nbytes=6, m=64, n=64, full_n=64, dst=D+14))

# ---- mode 2: keep the scalar path honest on a few small shapes -----------
add("m2_pad", desc(2, total=((14*14+31)//32)*((9+31)//32)*1024, nbytes=2, m=14*14, n=9,
                   channels=1, ih=16, iw=16, kh=3, kw=3, oh=14, ow=14,
                   sh=1, sw=1, dh=1, dw=1, ph=1, pw=1))
add("m2_s2", desc(2, total=((7*7+31)//32)*((27+31)//32)*1024, nbytes=2, m=7*7, n=27,
                  channels=3, ih=16, iw=16, kh=3, kw=3, oh=7, ow=7,
                  sh=2, sw=2, dh=1, dw=1, ph=1, pw=1))

for name, w, ob in cases:
    write_case(FIX, name, w)
import json
(FIX / "meta.json").write_text(json.dumps(
    [{"name": n, "mode": w[1], "output_bytes": ob,
      "dst": f"0x{w[3]:08x}", "bytes": w[5]} for n, w, ob in cases], indent=1))
print(f"generated {len(cases)} edge fixtures in {FIX}")
