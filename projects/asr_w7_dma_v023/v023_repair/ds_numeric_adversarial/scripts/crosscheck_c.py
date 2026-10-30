"""Cross-check the Python reference against independent C libc behaviour.

- i48 -> f32: C cast from int64_t to float (RNE).
- f32 -> i16: C lrintf (current rounding mode = RNE) + saturation.
- FMA: C fmaf for normal-input, finite, non-zero results.

Writes ref_c_crosscheck.json.  A non-zero mismatch count means the Python
reference itself is suspect; it does NOT test the DUT.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ref"))
import refmodel as R  # noqa: E402

VEC = os.path.join(ROOT, "vectors")
BUILD = os.path.join(ROOT, "build")
os.makedirs(BUILD, exist_ok=True)


def build():
    exe = os.path.join(BUILD, "c_ref")
    subprocess.run(["gcc", "-O2", "-o", exe, os.path.join(ROOT, "ref/c_ref.c"), "-lm"],
                   check=True)
    fma = os.path.join(BUILD, "c_fma_ref")
    src = os.path.join(BUILD, "c_fma_ref.c")
    with open(src, "w") as f:
        f.write(r'''
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
int main(void){
  unsigned x,s,b;
  while(scanf("%x %x %x",&x,&s,&b)==3){
    float fx,fs,fb,r; memcpy(&fx,&x,4); memcpy(&fs,&s,4); memcpy(&fb,&b,4);
    r=fmaf(fx,fs,fb); uint32_t rb; memcpy(&rb,&r,4);
    if(((rb>>23)&0xff)==0 && (rb&0x7fffff)) rb &= 0x80000000u;
    printf("%08x\n",rb);
  }
  return 0;
}
''')
    subprocess.run(["gcc", "-O2", "-o", fma, src, "-lm"], check=True)
    return exe, fma


def main():
    exe, fma_exe = build()
    out = {}
    # i48
    vecs = [l.split() for l in open(os.path.join(VEC, "i48.vec")) if l.split()]
    inp = "".join(v[0] + "\n" for v in vecs)
    got = subprocess.run([exe, "0"], input=inp, text=True, capture_output=True).stdout.split()
    bad = 0
    for v, c in zip(vecs, got):
        raw = int(v[0], 16)
        val = raw if raw < (1 << 47) else raw - (1 << 48)
        if R.i48_to_f32_bits(val) != int(c, 16):
            bad += 1
    out["i48"] = {"vectors": len(vecs), "mismatches": bad}
    # f32 -> i16
    vecs = [l.split() for l in open(os.path.join(VEC, "f32_i16.vec")) if l.split()]
    inp = "".join(v[0] + "\n" for v in vecs)
    got = subprocess.run([exe, "1"], input=inp, text=True, capture_output=True).stdout.split()
    bad = 0
    for v, c in zip(vecs, got):
        b = int(v[0], 16)
        g = int(c, 16)
        g = g - 65536 if g & 0x8000 else g
        if R.f32_to_i16(b) != g:
            bad += 1
    out["f32_i16"] = {"vectors": len(vecs), "mismatches": bad}
    # FMA on normal-input, finite, non-zero results
    vecs = [l.split() for l in open(os.path.join(VEC, "fma.vec")) if l.split()]

    def norm_or_zero(bits):
        e = (bits >> 23) & 0xFF
        return e != 0 or (bits & 0x7FFFFF) == 0

    sel = []
    for v in vecs:
        if int(v[0], 16) == 0:
            continue
        x, s, b = int(v[3], 16), int(v[1], 16), int(v[2], 16)
        if norm_or_zero(x) and norm_or_zero(s) and norm_or_zero(b):
            sel.append(v)
    lines = []
    for v in sel:
        b = "00000000" if int(v[0], 16) == 2 else v[2]
        lines.append(f"{v[3]} {v[1]} {b}\n")
    got = subprocess.run([fma_exe], input="".join(lines), text=True,
                         capture_output=True).stdout.split()
    bad = 0
    checked = 0
    for v, c in zip(sel, got):
        x, s, b, mode = int(v[3], 16), int(v[1], 16), int(v[2], 16), int(v[0], 16)
        exp = R.fma_bits(x, s, 0) if mode == 2 else R.fma_bits(x, s, b)
        g = int(c, 16)
        if R.is_nan(exp) or R.is_inf(exp) or R.is_nan(g) or R.is_inf(g):
            continue
        if R.is_zero(exp) and R.is_zero(g):
            continue
        checked += 1
        if exp != g:
            bad += 1
    out["fma_normal_finite_nonzero"] = {"vectors": checked, "mismatches": bad}
    out["pass"] = all(v["mismatches"] == 0 for v in out.values() if isinstance(v, dict))
    with open(os.path.join(ROOT, "ref_c_crosscheck.json"), "w") as f:
        json.dump(out, f, indent=2)
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
