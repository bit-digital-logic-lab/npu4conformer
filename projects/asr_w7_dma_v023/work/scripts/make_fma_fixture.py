"""Finite exact FMA cases, including a*b+c differing from rounded mul+add."""
import json,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'tests/fma_fixture';out.mkdir(exist_ok=False)
n=1001;a=(np.arange(n)%65-32).astype('<f4');b=(np.arange(n)%17-8).astype('<f4');c=(np.arange(n)%7-3).astype('<f4')
a[::17]=np.float32(1+2**-23);b[::17]=np.float32(1-2**-23);c[::17]=np.float32(-1)
expected=(a.astype(np.float64)*b.astype(np.float64)+c.astype(np.float64)).astype('<f4')
assert np.all(expected[::17]==np.float32(-2**-46))
memory=bytearray(b'\xa5'*(1<<18))
for address,data in [(0,a),(0x1000,b),(0x2000,c)]:memory[address:address+data.nbytes]=data.tobytes()
(out/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in memory),encoding='ascii')
(out/'gold.hex').write_text(''.join(f'{v:02x}\n' for v in expected.tobytes()),encoding='ascii')
words=[0x22564543,17,0x04000000,0x04001000,0x04002000,0x04010000,n]+[0]*9
(out/'descriptor.hex').write_text(''.join(f'{v:08x}\n' for v in words),encoding='ascii')
(out/'meta.json').write_text(json.dumps(dict(count=n,output_bytes=expected.nbytes,scope='Exact finite FMA oracle: integer triplets and (1+2^-23)*(1-2^-23)-1=-2^-46, correctly fused result differs from roundedmul+add'),indent=2)+'\n',encoding='utf-8')
print('V022_FMA_FIXTURE_CREATED',n)
