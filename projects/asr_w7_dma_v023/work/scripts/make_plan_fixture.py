"""Static two-operator plan: Add then Q cast, intermediates stay in DDR."""
import json,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'tests/plan_fixture';out.mkdir(exist_ok=False)
n=1001;x=(np.arange(n)%65-32).astype('<f4');memory=bytearray(b'\xa5'*(1<<18))
memory[:x.nbytes]=x.tobytes();gold=np.float32(x+2);q=gold.astype('<i2')
def put(address,words):
    offset=196608+address-0x10000000;data=struct.pack('<16I',*words);memory[offset:offset+64]=data
put(0x10000000,[0x22504c4e,2,1,0xffffffff,0x10001000,64]+[0]*10)
put(0x10000040,[0x22504c4e,2,2,0,0x10001100,64]+[0]*10)
put(0x10001000,[0x22564543,1<<10,0x04000000,0x10002000,0,0x04010000,n]+[0]*9)
put(0x10001100,[0x22564543,15|(1<<9),0x04010000,0,0,0x04020000,n]+[0]*9)
memory[196608+0x2000:196608+0x2004]=struct.pack('<f',2)
(out/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in memory),encoding='ascii')
for name,data in [('gold_float.hex',gold.tobytes()),('gold_q.hex',q.tobytes())]:
    (out/name).write_text(''.join(f'{v:02x}\n' for v in data),encoding='ascii')
(out/'meta.json').write_text(json.dumps(dict(count=n,scope='Static fixture only; real PL plan/DMA/numeric operations tested separately'),indent=2)+'\n',encoding='utf-8')
print('V022_PLAN_FIXTURE_CREATED')
