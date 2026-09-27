"""Generate independent NumPy references and check the scalar RTL simulation.

This is a test utility, not a replacement for FPGA computation. EXP/LOG accept
up to 4 ULP against libm; the other operations require exact output bits after
the documented input/output FTZ and canonical-NaN transformations.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import random
import struct
import subprocess
import numpy as np

def bits(x):
    with np.errstate(all="ignore"):
        return struct.unpack("<I", struct.pack("<f", np.float32(x)))[0]

def number(u):
    return struct.unpack("<f", struct.pack("<I", u & 0xffffffff))[0]

def ftz(u):
    return u & 0x80000000 if not (u & 0x7f800000) else u

def canon(u):
    return 0x7fc00000 if math.isnan(number(u)) else ftz(u)

def signed(u, width):
    return u - (1 << width) if u & (1 << (width-1)) else u

def reference(op, a, b):
    if op == 7:
        return bits(signed(a, 32))
    if op == 14:
        return bits(signed(((b & 0xffff) << 32) | a, 48))
    x, y = np.float32(number(ftz(a))), np.float32(number(ftz(b)))
    with np.errstate(all="ignore"):
        if op == 0: z = x+y
        elif op == 1: z = x-y
        elif op == 2: z = x*y
        elif op == 3: z = x/y
        elif op == 4: z = np.sqrt(x)
        elif op == 5: z = np.float32(np.exp(np.float64(x)))
        elif op == 6: z = np.float32(np.log(np.float64(x)))
        elif op in (8,15):
            lo,hi = (-2**31,2**31-1) if op == 8 else (-32768,32767)
            z = 0 if math.isnan(x) else lo if x <= lo else hi if x >= hi else round(float(x))
            return int(z)&0xffffffff
        elif op == 9:
            if math.isnan(x): z=y
            elif math.isnan(y): z=x
            elif x == 0 and y == 0: return ftz(a)&ftz(b)
            else: z=max(x,y)
        elif op == 10: return int(x<y)
        elif op == 11: return int(x==y)
        elif op == 12: return ftz(a)&0x7fffffff
        elif op == 13: return ftz(a)^0x80000000
        else: return 0x7fc00000
    return canon(bits(z))

def reference_flags(op, raw_a, raw_b, out):
    """Documented public status, deliberately not the five IEEE754 exceptions."""
    sub_a = (raw_a&0x7f800000)==0 and (raw_a&0x7fffff)!=0
    sub_b = (raw_b&0x7f800000)==0 and (raw_b&0x7fffff)!=0
    status=8 if ((op not in (7,14) and sub_a) or (op in (0,1,2,3,9,10,11) and sub_b)) else 0
    x,y,z=number(ftz(raw_a)),number(ftz(raw_b)),number(out)
    if op in (0,1,2,3):
        if math.isnan(z):status|=1
        elif op==3 and y==0 and math.isfinite(x):status|=2
        elif math.isinf(z) and math.isfinite(x) and math.isfinite(y):status|=4
        elif z==0 and x!=0 and y!=0:
            if op in (0,1) and abs(x)!=abs(y):status|=8
            elif op in (2,3) and math.isfinite(y):status|=8
    elif op==4:
        if math.isnan(x) or x<0:status|=1
    elif op==5:
        if math.isnan(x):status|=1
        elif math.isfinite(x):
            status|=16
            if math.isinf(z):status|=4
            if z==0:status|=8
    elif op==6:
        if math.isnan(x) or x<0:status|=1
        elif x==0:status|=2
        elif math.isfinite(x):status|=16
    elif op==8:
        if math.isnan(x) or not (-2**31<=x<2**31):status|=1
    elif op==9:
        if math.isnan(x) and math.isnan(y):status|=1
    elif op==10:
        if math.isnan(x) or math.isnan(y):status|=1
    elif op==15:
        if math.isnan(x):status|=1
    return status

def make_vectors(count):
    rng=random.Random(160048)
    special=[0,0x80000000,1,0x80000001,0x7fffff,0x800000,0x80800000,
             0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7fc00000,
             bits(1),bits(-1),bits(0.5),bits(1.5),bits(2.5),bits(-0.5),
             bits(-1.5),bits(-2.5),bits(32767.5),bits(-32768.5),bits(2**31),
             bits(-2**31),bits(1e-12)]
    vec=[]
    for op in range(16):
        for a in special:
            for b in (special if op in (0,1,2,3,9,10,11) else [0]):
                vec.append((op,a,b))
        for _ in range(count):
            if op==5:
                a=bits(rng.uniform(-90,90));b=0
            elif op==6:
                a=rng.randrange(0x00800000,0x7f800000);b=0
                if rng.random()<0.25:a=bits(rng.uniform(0.7,1.4))
            elif op==4:a=rng.randrange(0x00800000,0x7f800000);b=0
            elif op in (7,14):a=rng.getrandbits(32);b=rng.getrandbits(16)
            elif op in (8,15):
                a=bits(rng.uniform(-65536,65536)) if rng.random()<0.5 else rng.getrandbits(32);b=0
            else:a=rng.getrandbits(32);b=rng.getrandbits(32)
            vec.append((op,a,b))
    # Exact cancellation, halfway rounding, large-exponent reductions, and boundaries.
    for value in [0.5,1.5,2.5,-0.5,-1.5,-2.5,32767.5,-32768.5,2**24+1]:
        vec.extend([(8,bits(value),0),(15,bits(value),0),(7,int(value)&0xffffffff,0)])
    for u in range(bits(-87.33654475)-8,bits(-87.33654475)+9):vec.append((5,u,0))
    for u in range(bits(88.722839)-8,bits(88.722839)+9):vec.append((5,u,0))
    for u in range(bits(1.0)-32,bits(1.0)+33):vec.append((6,u,0))
    return vec

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument("--work",type=Path);ap.add_argument("--count",type=int,default=2000)
    ap.add_argument("--iverilog",default=r"D:\app\iverilog\iverilog\bin\iverilog.exe")
    ap.add_argument("--vvp",default=r"D:\app\iverilog\iverilog\bin\vvp.exe");args=ap.parse_args()
    work=args.work or args.root/"sim"/"scalar_work";work.mkdir(parents=True,exist_ok=True)
    vectors=make_vectors(args.count);vf=work/"scalar_vectors.txt";rf=work/"scalar_results.txt"
    vf.write_text("".join(f"{op} {a:08x} {b:08x}\n" for op,a,b in vectors))
    exe=work/"scalar.vvp"
    subprocess.run([args.iverilog,"-g2012","-s","tb_asr_fp32_alu","-o",str(exe),
                    str(args.root/"rtl/asr_fp32_alu.sv"),str(args.root/"sim/tb_asr_fp32_alu.sv")],check=True)
    subprocess.run([args.vvp,str(exe),f"+VECTORS={vf.as_posix()}",f"+RESULTS={rf.as_posix()}"],check=True)
    errors=[];max_ulp={5:0,6:0};worst={};counts={i:0 for i in range(16)}
    lines=rf.read_text().splitlines()
    if len(lines)!=len(vectors):raise AssertionError("Output count mismatch")
    for i,line in enumerate(lines):
        fields=line.split();op=int(fields[0]);a,b,out,flags=[int(x,16) for x in fields[1:]]
        if (op,a,b)!=vectors[i]:raise AssertionError("Transaction mismatch")
        expected=reference(op,a,b);counts[op]+=1
        if op in (5,6) and (out&0x7f800000)!=0x7f800000 and (expected&0x7f800000)!=0x7f800000:
            ulp=abs(out-expected)
            if ulp>max_ulp[op]:max_ulp[op]=ulp;worst[op]=[f"{a:08x}",f"{out:08x}",f"{expected:08x}"]
            ok=ulp<=4
        else:ok=out==expected
        if not ok:errors.append(dict(op=op,a=f"{a:08x}",b=f"{b:08x}",actual=f"{out:08x}",expected=f"{expected:08x}",flags=f"{flags:02x}"))
        expected_flags=reference_flags(op,a,b,out)
        if flags!=expected_flags:errors.append(dict(op=op,a=f"{a:08x}",b=f"{b:08x}",flags=f"{flags:02x}",expected_flags=f"{expected_flags:02x}"))
    report=dict(total=len(vectors),per_opcode=counts,max_ulp=max_ulp,worst=worst,failures=len(errors),first_errors=errors[:30])
    (work/"scalar_report.json").write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))
    if errors:raise SystemExit(1)

if __name__=="__main__":main()
