"""Offline integer/exact-FP fixtures only, not CPU fallback during inference."""
import json,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/vector_fixtures'
if OUT.exists():raise RuntimeError('Fresh fixture directory')
OUT.mkdir();n=1001
x=(np.arange(n)%65-32).astype('<f4');b=(np.arange(n)%17-8).astype('<f4')
q=(np.arange(n)*67%65536-32768).astype('<i2');ties=np.resize(np.array([-32768.5,-1.5,-.5,0,.5,1.5,32767.5],np.float32),n)
i48=np.resize(np.array([0,1,-1,2**24+1,2**24+3,-2**24-3,2**39+12345,-2**39-12345],np.int64),n)
memory=bytearray(b'\xa5'*(1<<18))
def put(at,a):memory[at:at+len(a)]=a
put(0,x.tobytes());put(0x1000,struct.pack('<f',2));put(0x2000,b.tobytes());put(0x4000,q.tobytes())
put(0x6000,b''.join((int(v)&((1<<48)-1)).to_bytes(6,'little') for v in i48));put(0x8000,ties.tobytes())
cases=[('add_scalar',0|(1<<10),0x04000000,0x04001000,np.float32(x+2)),
 ('mul_vector',2,0x04000000,0x04002000,np.float32(x*b)),
 ('i16_to_float',7|(1<<8),0x04004000,0,q.astype('<f4')),
 ('round_i16',15|(1<<9),0x04008000,0,np.clip(np.rint(ties),-32768,32767).astype('<i2')),
 ('i48_to_float',14|(1<<13),0x04006000,0,i48.astype('<f4'))]
meta=[]
for ident,(name,opcode,aa,bb,expected) in enumerate(cases):
    folder=OUT/name;folder.mkdir()
    (folder/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in memory),encoding='ascii')
    golden=expected.tobytes();(folder/'gold.hex').write_text(''.join(f'{v:02x}\n' for v in golden),encoding='ascii')
    words=[0x22564543,opcode,aa,bb,0,0x04010000,n]+[0]*9
    (folder/'descriptor.hex').write_text(''.join(f'{v:08x}\n' for v in words),encoding='ascii')
    meta.append(dict(name=name,id=ident,count=n,output_bytes=len(golden),numerical_oracle='Independent numpy FP32/integer conversion, finite exact inputs; actual RTL FP32 core under test'))
(OUT/'meta.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
print('V022_VECTOR_FIXTURES_CREATED',len(cases))
