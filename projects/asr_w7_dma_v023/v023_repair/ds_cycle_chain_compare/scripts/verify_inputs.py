#!/usr/bin/env python3
"""Independently verify the frozen input fixture and golden.

Checks:
  * mat32/exp_c.txt matches the generator manifest SHA;
  * gold_i16.hex agrees with a fresh numpy float32 computation from exp_c;
  * mem_integrated.hex contains the plan blob whose SHA matches integrated_meta.
No RTL is used here.
"""
import hashlib, json, struct, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parents[1]
INP = HERE / 'inputs'

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def win_index(addr):
    base = None; off = None
    if 0x03000000 <= addr < 0x03040000: base, off = 0x03000000, 0x00000
    elif 0x04000000 <= addr < 0x04040000: base, off = 0x04000000, 0x40000
    elif 0x08000000 <= addr < 0x08040000: base, off = 0x08000000, 0x80000
    elif 0x10000000 <= addr < 0x10040000: base, off = 0x10000000, 0xC0000
    else: raise ValueError(hex(addr))
    return (off + (addr - base)) // 4

def main():
    exp = [int(x, 16) for x in (INP/'mat32'/'exp_c.txt').read_text().split()]
    gold = [int(x, 16) for x in (INP/'gold_i16.hex').read_text().split()]
    manifest = json.loads((INP/'mat32'/'manifest.json').read_text())
    meta = json.loads((INP/'integrated_meta.json').read_text())

    exp_sha = sha(INP/'mat32'/'exp_c.txt')
    init_sha = sha(INP/'mat32'/'init.hex')
    out = {
        'exp_sha_match': exp_sha == manifest['sha256_exp'],
        'init_sha_match': init_sha == manifest['sha256_init'],
        'exp_values': len(exp),
        'gold_words': len(gold),
        'gold_sha256': sha(INP/'gold_i16.hex'),
        'mem_sha256': sha(INP/'mem_integrated.hex'),
    }

    # Fresh float32 golden: C48 signed -> f32 -> *2^-10 -> +0.5 -> RNE -> clip i16
    vals = [v - (1 << 48) if (v & (1 << 47)) else v for v in exp]
    x = np.array(vals, dtype=np.int64).astype(np.float32)
    y = (x * np.float32(2.0**-10)).astype(np.float32)
    z = (y + np.float32(0.5)).astype(np.float32)
    r = np.clip(np.rint(z.astype(np.float64)).astype(np.int64), -32768, 32767).astype(np.int16)
    gw = []
    for i in range(0, 1024, 2):
        gw.append((int(r[i]) & 0xffff) | ((int(r[i+1]) & 0xffff) << 16))
    out['gold_recomputed_match'] = gw == gold

    # Reconstruct plan bytes from the BFM image and compare its SHA.
    mem = [int(x, 16) for x in (INP/'mem_integrated.hex').read_text().split()]
    pb = meta['plan_base']; plen = meta['plan_bytes']
    blob = bytearray()
    for a in range(pb, pb + plen, 4):
        w = mem[win_index(a)]
        blob += w.to_bytes(4, 'little')
    out['plan_sha_recomputed'] = hashlib.sha256(bytes(blob)).hexdigest()
    out['plan_sha_match'] = out['plan_sha_recomputed'] == meta['plan_sha256']

    out['pass'] = all([out['exp_sha_match'], out['init_sha_match'],
                       out['gold_recomputed_match'], out['plan_sha_match']])
    (HERE/'reports').mkdir(exist_ok=True)
    (HERE/'reports'/'input_check.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps(out, indent=2))
    sys.exit(0 if out['pass'] else 1)

if __name__ == '__main__':
    main()
