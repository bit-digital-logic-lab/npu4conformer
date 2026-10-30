"""Independent exact integer/bit-layout fixtures; never neural CPU fallback."""
import json,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/layout_fixtures';OUT.mkdir(exist_ok=False)
cases=[]
def tile(x):
    m,n=x.shape;p=np.zeros(((m+31)//32*32,(n+31)//32*32),x.dtype);p[:m,:n]=x
    return p.reshape(p.shape[0]//32,32,p.shape[1]//32,32).transpose(0,2,1,3).copy()
def emit(name,config,source,gold):
    folder=OUT/name;folder.mkdir();memory=bytearray(b'\xa5'*(1<<18));memory[:len(source)]=source
    (folder/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in memory),encoding='ascii')
    (folder/'gold.hex').write_text(''.join(f'{v:02x}\n' for v in gold),encoding='ascii')
    (folder/'descriptor.hex').write_text(''.join(f'{v:08x}\n' for v in config),encoding='ascii')
    cases.append(dict(name=name,elements=config[4],output_bytes=len(gold),mode=config[1]))
def desc(mode,count,bytes,m=0,n=0,full=0,start=0):return [0x224c4159,mode,0x04000000,0x04010000,count,bytes,m,n,full,start]+[0]*22
x=(np.arange(1001)*17%65536-32768).astype('<i2');emit('copy_i16',desc(0,x.size,2),x.tobytes(),x.tobytes())
x=(np.arange(33*35)*19%65536-32768).astype('<i2').reshape(33,35);packed=tile(x)
emit('pack_matrix_edges',desc(1,packed.size,2,33,35,35),x.tobytes(),packed.tobytes())
f=np.arange(33*35,dtype='<f4').reshape(33,35);emit('unpack_row_fp32',desc(3,f.size,4,33,35,35),tile(f).tobytes(),f.tobytes())
emit('unpack_nchw_fp32',desc(4,f.size,4,33,35,35),tile(f).tobytes(),f.T.copy().tobytes())
i48=(np.arange(33*35,dtype=np.int64)*123456789-987654321).reshape(33,35);raw=lambda a:b''.join((int(v)&((1<<48)-1)).to_bytes(6,'little') for v in a.ravel())
emit('unpack_c48_compact',desc(3,i48.size,6,33,35,35),raw(tile(i48)),raw(i48))
for name,c,h,w,kh,kw,oh,ow,sh,sw,ph,pw in [('conv_padding',2,7,9,3,3,7,5,1,2,1,1),('case0000_embed_conv0',1,128,80,3,3,63,39,2,2,0,0),('depthwise_31',1,31,1,31,1,31,1,1,1,15,0)]:
    q=(np.arange(c*h*w)*13%65536-32768).astype('<i2').reshape(c,h,w);m=oh*ow;n=c*kh*kw;matrix=np.zeros((m,n),'<i2')
    for row in range(m):
        for col in range(n):
            channel=col//(kh*kw);kernel=col%(kh*kw);iy=(row//ow)*sh+kernel//kw-ph;ix=(row%ow)*sw+kernel%kw-pw
            if 0<=iy<h and 0<=ix<w:matrix[row,col]=q[channel,iy,ix]
    p=tile(matrix);config=desc(2,p.size,2,m,n);config[10:24]=[c,h,w,kh,kw,oh,ow,sh,sw,1,1,ph,pw,0]
    emit(name,config,q.tobytes(),p.tobytes())
(OUT/'meta.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8');print('V022_LAYOUT_FIXTURES',len(cases))
