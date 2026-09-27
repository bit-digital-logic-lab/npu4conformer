"""Independent random/edge stimuli and exact response checking, simulation only."""
from pathlib import Path
import sys,json,struct,argparse,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
sys.path.insert(0,str(ROOT/'diagnostics'))
from frozen_imports import require_frozen_modules
require_frozen_modules()
from compat_cpu import fma32,gemm_fma
from ethernet_transport import encode_inner,crc16
OUT=ROOT/'build/numeric_sim_001'

def generate():
    OUT.mkdir(parents=True,exist_ok=True);frames=[];expected=[];seq=0
    def command(op,data=b'',payload=None,status=0,label=''):
        nonlocal seq
        frames.append(encode_inner(seq,op,data));expected.append(dict(seq=seq,op=op,status=status,payload=None if payload is None else payload.hex(),label=label));seq+=1
    def write(base,data):
        raw=np.ascontiguousarray(data).view(np.uint32).reshape(-1)
        for start in range(0,len(raw),255):
            v=raw[start:start+255];command(0x41,struct.pack('<HH',base+start,len(v))+v.tobytes(),b'')
    def read(base,data,label):
        raw=np.ascontiguousarray(data).view(np.uint32).reshape(-1)
        for start in range(0,len(raw),256):
            v=raw[start:start+256];command(0x42,struct.pack('<HH',base+start,len(v)),v.tobytes(),label=label)
    rng=np.random.default_rng(5271)
    command(0x4f,payload=struct.pack('<4sII',b'ASR5',5,32768),label='V5 capability')
    for mode in range(8):
        n=513;a=(rng.normal(size=n)*3).astype(np.float32);b=(rng.normal(size=n)*.3).astype(np.float32);c=rng.normal(size=n).astype(np.float32)
        a[:3]=[1+2**-23,2**-12,1e-12];b[:3]=[1-2**-23,2**-13,1e-12];c[:3]=[-1,1,1]
        values=[v[:1] if mode&(1<<i) else v for i,v in enumerate((a,b,c))]
        for i,v in enumerate(values):write(i*n,v)
        command(0x47,struct.pack('<5HB',0,n,2*n,3*n,n,mode))
        read(3*n,fma32(*values),'FMA random/cancellation/broadcast '+str(mode))
    n=513;write(0,a);write(n,b);write(2*n,c);command(0x47,struct.pack('<5HB',0,n,2*n,0,n,0));read(0,fma32(a,b,c),'FMA exact A alias')
    command(0x47,struct.pack('<5HB',0,n,2*n,1,n,0),b'',2,'reject partial alias')
    command(0x47,struct.pack('<5HB',0,n,2*n,0,n,1),b'',2,'reject broadcast alias')
    for m,n,k,block in [(3,7,257,128),(2,3,521,512),(4,5,9,128)]:
        aa=rng.normal(size=(m,k)).astype(np.float32);bb=rng.normal(size=(n,k)).astype(np.float32)
        for d in range(0,k,block):
            kc=min(block,k-d);write(0,aa[:,d:d+kc]);write(5000,bb[:,d:d+kc])
            command(0x46,struct.pack('<7H',0,5000,10000,m,n,kc,int(d!=0)))
        read(10000,gemm_fma(aa,bb,block),f'FMA GEMM K blocks {m}x{n}x{k}/{block}')
    rows=(rng.integers(-32767,32768,(24,512),dtype=np.int16).astype(np.float32)*np.float32(.0001173))
    rows[0]=0;rows[1]=1;rows[2,:256]=1;rows[2,256:]=-1
    rows[3,::2]=1;rows[3,1::2]=-1;rows[3,-1]=np.float32(-1+2**-20)
    for i,row in enumerate(rows):
        write(0,row);command(0x48,struct.pack('<3H',0,1000,512));read(1000,np.asarray(np.mean(row,dtype=np.float64),np.float32),f'FP64-equivalent QDQ mean {i}')
    write(0,np.r_[np.float32(2**25),np.ones(511,np.float32)].astype(np.float32));command(0x48,struct.pack('<3H',0,1000,512),status=4,label='reject exponent span >20')
    p=np.array([.75,1,1.2,1.9]*32,np.float32);power=np.arange(0,-128,-1,dtype=np.int32)
    write(0,p);write(128,power);command(0x43,struct.pack('<BBHHHH',16,0,0,128,0,128))
    scaled=np.ldexp(p,power).astype(np.float32);scaled[scaled.view(np.uint32)&0x7f800000==0]=0
    read(0,scaled,'Scale pow2 FTZ')
    # Legacy arithmetic commands still work after new resident operations.
    command(0x22,struct.pack('<ff',3.5,-2),struct.pack('<fB',-7,0),label='legacy Mul')
    (OUT/'input.hex').write_text(''.join(f'{v:02x}\n' for f in frames for v in f),encoding='ascii')
    (OUT/'expected.json').write_text(json.dumps(expected,indent=2),encoding='utf-8')
    print('GENERATED',len(expected),'commands')

def check():
    expected=json.loads((OUT/'expected.json').read_text());raw=bytes(int(v,16) for v in (OUT/'output.hex').read_text().split());pos=0;fail=[];checked=0
    for e in expected:
        if pos+10>len(raw):fail.append(dict(expected=e,error='missing reply'));break
        seq,op,status,n=struct.unpack_from('<HBBH',raw,pos+2);frame=raw[pos:pos+n+10];pos+=len(frame)
        if len(frame)!=n+10 or frame[:2]!=b'\x5a\xa5' or crc16(frame[2:-2])!=struct.unpack('<H',frame[-2:])[0]:raise AssertionError('framing/CRC')
        data=frame[8:-2];error=[]
        if (seq,op,status)!=(e['seq'],e['op'],e['status']):error.append('identity/status')
        if e['payload'] is not None and data.hex()!=e['payload']:error.append('bit mismatch')
        if e['payload'] is None and status==0 and (len(data)!=5 or data[0]&7):error.append('arithmetic status')
        if error:fail.append(dict(seq=seq,label=e['label'],error=error,actual=data.hex(),expected=e['payload'],status=status))
        else:checked+=1
    result=dict(pass_all=not fail and pos==len(raw) and checked==len(expected),checked=checked,total=len(expected),failures=fail,hardware_executed=False,simulation='Vivado XSIM + generated AMD floating_point FMA IP')
    (OUT/'report.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='failures'},indent=2));print('First failures:',fail[:3]);return 0 if result['pass_all'] else 1
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
    if args.check:raise SystemExit(check())
    generate()
