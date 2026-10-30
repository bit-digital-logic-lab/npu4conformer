"""Exact independent coefficient-period and tiled-column-reuse vector tests."""
import json,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/reuse_fixtures';OUT.mkdir(exist_ok=False);cases=[]
def emit(name,flags,period,a,b,expected):
    folder=OUT/name;folder.mkdir();mem=bytearray(b'\xa5'*(1<<18));mem[:a.nbytes]=a.tobytes();mem[0x6000:0x6000+b.nbytes]=b.tobytes()
    (folder/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in mem),encoding='ascii')
    (folder/'gold.hex').write_text(''.join(f'{v:02x}\n' for v in expected.tobytes()),encoding='ascii')
    desc=[0x22564543,2|flags,0x04000000,0x04006000,0,0x04010000,a.size,period]+[0]*8
    (folder/'descriptor.hex').write_text(''.join(f'{v:08x}\n' for v in desc),encoding='ascii');cases.append(dict(name=name,elements=a.size,output_bytes=expected.nbytes))
a=(np.arange(1001)%65-32).astype('<f4');b=(np.arange(512)%17-8).astype('<f4')
for p in [1,32,128,256,512]:emit('period'+str(p),0,p,a,b[:p],np.float32(a*np.resize(b[:p],a.size)))
a=(np.arange(2048)%17-8).astype('<f4').reshape(2,32,32);a[1,:,8:]=0;b=np.arange(1,65,dtype='<f4');b[40:]=0
e=np.float32(a*b.reshape(2,1,32));emit('tiled40cols',1<<14,40,a.ravel(),b,e.ravel())
(OUT/'meta.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8');print('V022_COEFFICIENT_REUSE_FIXTURES',len(cases))
