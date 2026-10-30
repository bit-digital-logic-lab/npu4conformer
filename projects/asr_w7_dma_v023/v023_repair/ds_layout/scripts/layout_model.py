#!/usr/bin/env python3
"""Independent golden fixtures for the V0.23 layout engine.

The model below is written from the descriptor contract, not from the RTL:
it expands every mode element by element and produces gold.hex.  The testbench
then compares the RTL-written DDR image byte-for-byte against this gold file and
checks that the 32-byte tail guard is untouched.

Covered: copy, rowmajor->A16tile, im2col (padding/stride/dilation/slice),
tiled->rowmajor transpose, NCHW compact (C48), 4 KiB crossing, partial tails,
non-contiguous destination rows (full_n > n).
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FIX = HERE / "fixtures" / "gold"
FIX.mkdir(parents=True, exist_ok=True)
SRC_OFF = 0x04000000
DST_OFF = 0x04010000
MEM_SIZE = 262144

def build_mem():
    mem = bytearray(MEM_SIZE)
    for i in range(MEM_SIZE):
        mem[i] = (i * 37 + (i >> 7) * 101 + 0x5A) & 0xFF
    return mem

def desc(mode=0, src=SRC_OFF, dst=DST_OFF, total=1024, nbytes=2,
         m=32, n=32, full_n=32, col_start=0, channels=1, ih=16, iw=16,
         kh=1, kw=1, oh=16, ow=16, sh=1, sw=1, dh=1, dw=1, ph=0, pw=0,
         k_offset=0):
    return [0x224C4159, mode, src, dst, total, nbytes, m, n, full_n, col_start,
            channels, ih, iw, kh, kw, oh, ow, sh, sw, dh, dw, ph, pw, k_offset] + [0]*8

def check_legal(w):
    (magic,mode,src,dst,total,nb,m,n,full_n,col_start,ch,ih,iw,kh,kw,oh,ow,
     sh,sw,dh,dw,ph,pw,ko) = w[:24]
    mt, nt = (m+31)//32, (n+31)//32
    assert magic == 0x224C4159
    assert nb in (2,4,6), nb
    assert src % (4 if nb == 4 else 2) == 0 and dst % (4 if nb == 4 else 2) == 0
    if mode == 0:
        assert total == (w[4])
    elif mode == 1:
        assert nb == 2 and full_n and full_n <= 8192
        assert ko <= full_n and ko + n <= full_n
        assert total == mt*nt*1024
    elif mode == 2:
        assert nb == 2 and ch and ch <= 1024 and ih and ih <= 8192 and iw and iw <= 8192
        assert 1 <= kh <= 31 and 1 <= kw <= 31
        assert oh and oh <= 4096 and ow and ow <= 8192
        assert 1 <= sh <= 64 and 1 <= sw <= 64 and 1 <= dh <= 64 and 1 <= dw <= 64
        assert ph <= 255 and pw <= 255 and oh*ow == m
        assert ch*kh*kw <= 8192 and ko <= 8192 and ko + n <= ch*kh*kw
        assert total == mt*nt*1024
    else:
        assert full_n >= n and full_n <= 4096 and col_start <= full_n and col_start + n <= full_n
        assert total == m*n
    # simulate the engine's extent check
    if mode == 0:
        se = total
    elif mode == 1:
        se = m*full_n
    elif mode == 2:
        se = ch*ih
    else:
        se = mt*nt*1024
    src_bytes = se * (iw*2 if mode == 2 else nb)
    if mode == 0 or mode == 1 or mode == 2:
        extent_elems = total
    elif mode == 3:
        extent_elems = (m-1)*full_n + col_start + n
    else:
        extent_elems = (col_start + n)*m
    dst_bytes = extent_elems * nb
    assert src + ((src_bytes + 15) & ~15) <= 0x08000000
    assert dst + ((dst_bytes + 15) & ~15) <= 0x08000000
    assert not (src < dst + ((dst_bytes + 15) & ~15) and dst < src + ((src_bytes + 15) & ~15))
    assert src_bytes < DST_OFF - SRC_OFF, (src_bytes, "source overlaps dst window")
    assert dst == DST_OFF, "testbench compares at 0x04010000"
    assert dst_bytes + 32 <= MEM_SIZE - 65536
    return src_bytes, dst_bytes

def extent_bytes(w):
    (magic,mode,src,dst,total,nb,m,n,full_n,col_start,ch,ih,iw,kh,kw,oh,ow,
     sh,sw,dh,dw,ph,pw,ko) = w[:24]
    if mode in (0,1,2):
        elems = total
    elif mode == 3:
        elems = (m-1)*full_n + col_start + n
    else:
        elems = (col_start + n)*m
    return elems*nb

def model(w, mem):
    (magic,mode,src,dst,total,nb,m,n,full_n,col_start,ch,ih,iw,kh,kw,oh,ow,
     sh,sw,dh,dw,ph,pw,ko) = w[:24]
    mt, nt = (m+31)//32, (n+31)//32
    ob = extent_bytes(w)
    out = bytearray(mem[dst - SRC_OFF : dst - SRC_OFF + ob])  # gaps keep existing bytes
    so = src - SRC_OFF
    def sg(idx):
        a = so + idx*nb
        return mem[a:a+nb]
    if mode == 0:
        for i in range(total):
            out[i*nb:(i+1)*nb] = sg(i)
    elif mode == 1:
        for tr in range(mt):
            for tc in range(nt):
                for r in range(32):
                    for c in range(32):
                        lin = ((tr*nt + tc)*32 + r)*32 + c
                        rr, cc = tr*32 + r, tc*32 + c
                        sidx = rr*full_n + cc + ko
                        val = b"\0"*nb if (rr >= m or cc >= n) else sg(sidx)
                        out[lin*nb:(lin+1)*nb] = val
    elif mode == 2:
        for tr in range(mt):
            for tc in range(nt):
                for r in range(32):
                    for c in range(32):
                        lin = ((tr*nt + tc)*32 + r)*32 + c
                        rr, cc = tr*32 + r, tc*32 + c
                        k = ko + cc
                        kc, rem = divmod(k, kh*kw)
                        ky, kx = divmod(rem, kw)
                        oy, ox = divmod(rr, ow)
                        iy = oy*sh + ky*dh - ph
                        ix = ox*sw + kx*dw - pw
                        zero = (rr >= m or cc >= n or kc >= ch or iy < 0 or ix < 0
                                or iy >= ih or ix >= iw)
                        sidx = (kc*ih + iy)*iw + ix
                        val = b"\0"*nb if zero else sg(sidx)
                        out[lin*nb:(lin+1)*nb] = val
    elif mode == 3:
        for r in range(m):
            for c in range(n):
                sidx = ((r >> 5)*nt + (c >> 5))*1024 + (r & 31)*32 + (c & 31)
                didx = r*full_n + col_start + c
                out[didx*nb:(didx+1)*nb] = sg(sidx)
    else:
        for c in range(n):
            for r in range(m):
                sidx = ((r >> 5)*nt + (c >> 5))*1024 + (r & 31)*32 + (c & 31)
                didx = (col_start + c)*m + r
                out[didx*nb:(didx+1)*nb] = sg(sidx)
    return out


def write_case(outdir, name, w):
    outdir = Path(outdir)
    mem = build_mem()
    check_legal(w)
    out = model(w, mem)
    ob = len(out)
    for j in range(ob, ob + 32):
        mem[65536 + j] = 0xA5
    d = outdir / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "memory.hex").write_text("".join(f"{b:02x}\n" for b in mem), encoding="ascii")
    (d / "descriptor.hex").write_text("".join(f"{v & 0xffffffff:08x}\n" for v in w), encoding="ascii")
    (d / "gold.hex").write_text("".join(f"{b:02x}\n" for b in out), encoding="ascii")
    return ob
