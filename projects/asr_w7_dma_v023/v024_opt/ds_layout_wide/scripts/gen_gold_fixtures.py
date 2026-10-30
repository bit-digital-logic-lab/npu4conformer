#!/usr/bin/env python3
"""Deterministic golden fixtures (see scripts/layout_model.py for the model)."""
import json
from pathlib import Path
from layout_model import (FIX, DST_OFF, build_mem, desc, check_legal,
                          extent_bytes, model, write_case)

cases = []
def add(name, w):
    check_legal(w)
    cases.append((name, w))

# --- copy: tails, 4 KiB crossings ------------------------------------------
add("copy_tail_2b", desc(0, total=1001, nbytes=2))
add("copy_tail_4b", desc(0, total=1023, nbytes=4))
add("copy_tail_6b", desc(0, total=683, nbytes=6))
add("copy_4k_exact", desc(0, total=2048, nbytes=2))          # ends at 0x04011000
add("copy_4k_cross", desc(0, total=2049, nbytes=2))          # crosses 4 KiB
add("copy_4k_cross6", desc(0, total=700, nbytes=6))          # 4200 B, 16B lines
add("copy_32b", desc(0, total=32, nbytes=2))                 # two 16-beat bursts
# --- pack: multi-tile, gaps, slice ----------------------------------------
add("pack_mt", desc(1, total=((70+31)//32)*((70+31)//32)*1024, nbytes=2,
                    m=70, n=70, full_n=72, k_offset=0))
add("pack_slice", desc(1, total=((40+31)//32)*((64+31)//32)*1024, nbytes=2,
                       m=40, n=64, full_n=80, k_offset=12))
add("pack_tail", desc(1, total=((33+31)//32)*((35+31)//32)*1024, nbytes=2,
                      m=33, n=35, full_n=35))
add("pack_slice_end", desc(1, total=((32+31)//32)*((1+31)//32)*1024, nbytes=2,
                           m=32, n=1, full_n=32, k_offset=31))
# --- im2col: padding/stride/dilation/slice, multi-tile --------------------
def conv(name, c, ih, iw, kh, kw, oh, ow, sh, sw, dh, dw, ph, pw, ko=0, n_used=None):
    m = oh*ow
    kfull = c*kh*kw
    n = kfull - ko if n_used is None else n_used
    mt, nt = (m+31)//32, (n+31)//32
    add(name, desc(2, total=mt*nt*1024, nbytes=2, m=m, n=n, channels=c, ih=ih, iw=iw,
                   kh=kh, kw=kw, oh=oh, ow=ow, sh=sh, sw=sw, dh=dh, dw=dw,
                   ph=ph, pw=pw, k_offset=ko))
conv("conv_pad1", 1, 16, 16, 3, 3, 14, 14, 1, 1, 1, 1, 1, 1)
conv("conv_s2", 3, 16, 16, 3, 3, 7, 7, 2, 2, 1, 1, 1, 1)
conv("conv_dil2", 2, 20, 18, 3, 3, 10, 9, 1, 1, 2, 2, 0, 0)
conv("conv_dil2_s2", 2, 20, 18, 3, 3, 5, 4, 2, 2, 2, 2, 0, 0)
conv("conv_multitile", 4, 32, 24, 3, 3, 15, 11, 2, 2, 1, 1, 0, 0)
conv("conv_widesrc", 2, 40, 40, 3, 3, 20, 20, 1, 1, 1, 1, 1, 1)
conv("conv_slice", 3, 9, 11, 2, 2, 9, 11, 1, 1, 1, 1, 0, 0, ko=4, n_used=8)
conv("conv_slice_end", 2, 8, 8, 2, 2, 8, 8, 1, 1, 1, 1, 0, 0, ko=7, n_used=1)
conv("conv_padbig", 1, 8, 9, 3, 3, 9, 10, 1, 1, 1, 1, 3, 4)
# dilation/stride large enough that consecutive needed lines are NOT adjacent;
# the engine must fall back to single-line fetches and never merge them.
conv("conv_dil_big", 1, 40, 60, 2, 3, 10, 10, 1, 1, 1, 9, 0, 0)
conv("conv_stride_big", 2, 60, 80, 3, 3, 8, 8, 1, 7, 1, 1, 0, 0)
# --- transpose / compact C48 (mode 3/4), gaps and slices ------------------
for i, (m, n, fn, cs, nb) in enumerate([
        (33, 35, 40, 0, 4), (64, 32, 64, 0, 6), (31, 31, 31, 0, 2),
        (35, 33, 40, 2, 6), (32, 33, 35, 1, 4)]):
    add(f"transpose_{i}", desc(3, total=m*n, nbytes=nb, m=m, n=n, full_n=fn, col_start=cs))
for i, (m, n, fn, cs, nb) in enumerate([
        (33, 35, 40, 0, 4), (64, 32, 64, 0, 6), (31, 31, 31, 0, 2),
        (35, 33, 40, 3, 6), (32, 33, 35, 2, 2)]):
    add(f"compactc48_{i}", desc(4, total=m*n, nbytes=nb, m=m, n=n, full_n=fn, col_start=cs))

for name, w in cases:
    write_case(FIX, name, w)

meta = [{"name": n, "output_bytes": extent_bytes(w), "mode": w[1]} for n, w in cases]
(FIX / "meta.json").write_text(json.dumps(meta, indent=1))
print(f"generated {len(cases)} golden fixtures in {FIX}")
