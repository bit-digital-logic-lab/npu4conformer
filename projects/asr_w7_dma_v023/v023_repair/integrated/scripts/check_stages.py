#!/usr/bin/env python3
"""Check the integrated matrix C48 and each vector stage against independent math."""
import json, struct
from pathlib import Path
import numpy as np
H = Path(__file__).resolve().parents[1]
exp = [int(x, 16) for x in (H/'fixtures/mat32/exp_c.txt').read_text().split()]
def words(p): return [int(x, 16) for x in (H/'logs'/p).read_text().split()]
def f32(w): return np.array([struct.unpack('<f', struct.pack('<I', x))[0] for x in w], dtype=np.float32)
c = words('stage_c48.hex'); cb = b''.join(x.to_bytes(4, 'little') for x in c)
cv = [int.from_bytes(cb[i*6:i*6+6], 'little') for i in range(1024)]
cs = [v - (1 << 48) if v & (1 << 47) else v for v in cv]
d0 = f32(words('stage_d0.hex')); d1 = f32(words('stage_d1.hex')); d2 = f32(words('stage_d2.hex'))
i16w = words('stage_i16.hex')
got = np.empty(1024, dtype=np.int16)
got[0::2] = [struct.unpack('<h', struct.pack('<H', w & 0xffff))[0] for w in i16w]
got[1::2] = [struct.unpack('<h', struct.pack('<H', (w >> 16) & 0xffff))[0] for w in i16w]
x = np.array(cs, dtype=np.int64).astype(np.float32)
y = (x * np.float32(2**-10)).astype(np.float32)
z = (y + np.float32(0.5)).astype(np.float32)
r = np.clip(np.rint(z.astype(np.float64)), -32768, 32767).astype(np.int16)
res = {
 'matrix_c48_vs_integer_golden_mismatches': sum(1 for a,b in zip(exp,cs) if (a & ((1<<48)-1)) != (b & ((1<<48)-1))),
 'i48_to_f32_mismatches': int(np.sum(d0 != x)),
 'mul_scale_mismatches': int(np.sum(d1 != y)),
 'add_bias_mismatches': int(np.sum(d2 != z)),
 'f32_to_i16_mismatches': int(np.sum(got != r)),
 'words': 1024,
 'parameters': {'scale': 2**-10, 'bias': 0.5, 'rounding': 'RNE', 'clip': [-32768, 32767]},
}
res['pass'] = all(res[k] == 0 for k in list(res)[:5])
(H/'reports'/'stage_check.json').write_text(json.dumps(res, indent=2))
print(json.dumps(res, indent=2))
raise SystemExit(0 if res['pass'] else 1)
