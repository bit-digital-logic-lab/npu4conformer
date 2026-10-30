"""CPU-only independent plan-layout/numeric oracle, NEVER FPGA speed evidence.

Executes the serialized instructions, not compiler helpers; compares to the
sealed serialized VM reference with exact native fmaf for its frozen sigmoid.
"""
import ctypes,hashlib,json,struct,sys,time
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1'
sys.path[:0]=[str(BASE/'host'),str(ROOT.parent/'model_a_v0_21/host'),str(ROOT.parent/'model_a_lowbit_v13/host')]
from parameters import ParameterImage,LoadState
from vm_reference import FusionReference
from lowbit_executor import Tensor
tag=sys.argv[1] if len(sys.argv)>1 else 'plan_oracle001';all_programs='--all' in sys.argv[2:]
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False);image=ParameterImage(ROOT/'assets/parameters002')
state=LoadState();state.begin(image.meta)
for at in range(0,len(image.data),1<<20):state.verify(at,image.data[at:at+(1<<20)])
state.commit();oracle=FusionReference(image,state)
lib=ctypes.CDLL(str(BASE/'reports/native_execution002/vm_execute.dll'));lib.test_fma.argtypes=[ctypes.c_void_p]*3+[ctypes.c_uint]
def ftz(x):
    x=np.asarray(x,np.float32).copy();bits=x.view('u4');bits[(bits&0x7f800000)==0]&=0x80000000;return x
def fused(a,b,c):
    a=ftz(a);b=np.ascontiguousarray(np.broadcast_to(ftz(b),a.shape),np.float32);c=np.ascontiguousarray(np.broadcast_to(ftz(c),a.shape),np.float32)
    lib.test_fma(a.ctypes.data,b.ctypes.data,c.ctypes.data,a.size);return ftz(a)
coeff=np.frombuffer(image.data,'<f4',count=15,offset=image.meta['v211_algorithm_constants_address']-0x10000000)
def sigmoid(x):
    x=np.minimum(np.maximum(x,coeff[0]),coeff[1]);xx=ftz(x*x);p=fused(np.full(x.shape,coeff[4],np.float32),xx,coeff[5])
    for ci in coeff[6:9]:p=fused(p,xx,ci)
    q=fused(np.full(x.shape,coeff[9],np.float32),xx,coeff[10])
    for ci in coeff[11:15]:q=fused(q,xx,ci)
    return np.maximum(ftz(ftz(ftz(p*x)/q)+coeff[2]),coeff[3])
old_unary=oracle.unary;oracle.unary=lambda op,x:sigmoid(x) if op=='Sigmoid' else old_unary(op,x)
memory=bytearray(0x05000000);SB=0x03000000;PB=0x10000000
def read(address,n):
    if PB<=address and address+n<=PB+len(image.data):return image.data[address-PB:address-PB+n]
    if SB<=address and address+n<=0x08000000:return memory[address-SB:address-SB+n]
    raise ValueError(f'Read ACL {address:08x}+{n}')
def write(address,data):
    if not SB<=address or address+len(data)>0x08000000:raise ValueError('Write ACL')
    memory[address-SB:address-SB+len(data)]=data
def array(address,count,dtype):return np.frombuffer(read(address,count*np.dtype(dtype).itemsize),dtype).copy()
def i48(address,count):
    p=array(address,count*3,'<u2').reshape(-1,3).astype(np.int64);v=p[:,0]|p[:,1]<<16|p[:,2]<<32;return np.where(v&(1<<47),v-(1<<48),v)
def raw48(v):return np.stack([(v>>(16*i))&65535 for i in range(3)],axis=-1).astype('<u2').tobytes()
def tiled(x):
    m,n=x.shape;p=np.zeros(((m+31)//32*32,(n+31)//32*32),x.dtype);p[:m,:n]=x
    return p.reshape(p.shape[0]//32,32,p.shape[1]//32,32).transpose(0,2,1,3).copy()
def untile(v,m,n):return v.reshape((m+31)//32,(n+31)//32,32,32).transpose(0,2,1,3).reshape((m+31)//32*32,(n+31)//32*32)[:m,:n]
def execute_layout(w):
    magic,mode,a,d,count,size,m,n,full,start=w[:10];assert magic==0x224c4159 and w[24:]==(0,)*8
    if mode==0:write(d,read(a,count*size));return
    if mode==1:x=array(a,m*full,'<i2').reshape(m,full)[:,w[23]:w[23]+n];write(d,tiled(x).tobytes());return
    if mode==2:
        ch,h,wi,kh,kw,oh,ow,sh,sw,dh,dw,ph,pw,koff=w[10:24];q=array(a,ch*h*wi,'<i2').reshape(ch,h,wi)
        row=np.arange(m)[:,None];col=np.arange(koff,koff+n)[None,:];iy=(row//ow)*sh+((col%(kh*kw))//kw)*dh-ph;ix=(row%ow)*sw+(col%kw)*dw-pw
        valid=(iy>=0)&(iy<h)&(ix>=0)&(ix<wi);x=np.where(valid,q[col//(kh*kw),np.clip(iy,0,h-1),np.clip(ix,0,wi-1)],0).astype('<i2')
        write(d,tiled(x).tobytes());return
    physical=((m+31)//32)*((n+31)//32)*1024
    x=untile(i48(a,physical) if size==6 else array(a,physical,'<u4' if size==4 else '<u2'),m,n)
    for row in range(m):
        if mode==3:write(d+(row*full+start)*size,raw48(x[row]) if size==6 else x[row].tobytes())
    if mode==4:
        for col in range(n):write(d+(start+col)*m*size,raw48(x[:,col]) if size==6 else np.ascontiguousarray(x[:,col]).tobytes())
def execute_matrix(pointer,count):
    for index in range(count):
        w=struct.unpack('<16I',read(pointer+index*64,64));assert w[0]==0x51415352 and w[1]==0x150001 and w[2]==index+1
        a,b,c,m,n,k=w[4:10];mt,nt,kt=(m+31)//32,(n+31)//32,(k+31)//32
        aa=untile(array(a,mt*kt*1024,'<i2'),m,k).astype(np.int64);raw=untile(array(b,kt*nt*1024,'u1'),k,n)
        parity=np.zeros(raw.shape,np.uint8)
        for bit in range(8):parity^=(raw>>bit)&1
        assert not np.any(parity)
        table=np.asarray([(w[13]>>(4*i))&15 for i in range(4)],np.int64);mag=(raw&15).astype(np.int64)<<table[(raw>>4)&3]
        if w[13]&(1<<16):mag=np.minimum(mag,32767)
        bb=np.where(raw&64,-mag,mag);cc=aa@bb
        if w[15]&1:cc+=untile(i48(c,mt*nt*1024),m,n);assert w[3]==index-1
        assert np.all((cc>=-(1<<47))&(cc<(1<<47)));write(c,raw48(tiled(cc)))
def execute_vector(w):
    magic,flags,a,b,c,d,n,period=w[:8];assert magic==0x22564543 and w[8:]==(0,)*8
    op=flags&255;as_=bool(flags&(1<<11));bs=bool(flags&(1<<10));cs=bool(flags&(1<<12));count=1 if as_ else n
    av=i48(a,count) if flags&(1<<13) else array(a,count,'<i2' if flags&(1<<8) else '<f4')
    if as_:av=np.full(n,av[0],av.dtype)
    needb=op<=3 or op in (9,10,11,14,17)
    bv=None
    if needb and not flags&(1<<13):
        size=1 if bs else ((period+31)//32)*32 if flags&(1<<14) else period or n;bv=array(b,size,'<f4')
        if bs:bv=np.full(n,bv[0],np.float32)
        elif flags&(1<<14):bv=np.broadcast_to(bv.reshape(1,-1,1,32),(n//(len(bv)*32),len(bv)//32,32,32)).copy().ravel()
        elif period:bv=np.resize(bv,n)
    if op in (7,14):result=ftz(av.astype(np.float32))
    elif op==15:result=np.clip(np.rint(av),-32768,32767).astype('<i2')
    elif op==13:result=ftz(-av)
    elif op==17:
        cv=array(c,1 if cs else n,'<f4');result=fused(av,bv,cv)
    elif op==9:result=ftz(np.maximum(ftz(av),ftz(bv)))
    else:
        av=ftz(av);bv=ftz(bv);result=ftz({0:np.add,1:np.subtract,2:np.multiply,3:np.divide}[op](av,bv))
    assert np.all(np.isfinite(result));write(d,result.astype('<i2' if flags&(1<<9) else '<f4').tobytes())
rng=np.random.default_rng(2201);checks=[];selected_kinds=set()
for key,p in image.meta['v022_programs'].items():
    orig=image.meta['v211_programs'][key]
    label='DEPTHWISE' if 'depthwise' in key else ('DECODER_FFN' if p['part']=='decoder' else p['kind'])
    if not all_programs and label in selected_kinds:continue
    selected_kinds.add(label);iv=orig['values'][orig['input_id']]['words'];ov=orig['values'][orig['output_id']]['words'];shape=tuple(iv[6:6+iv[5]])
    q=rng.integers(-127,128,shape,dtype=np.int16);scale=array(iv[2],1,'<f4')[0];feed=Tensor(np.float32(q.astype(np.float32)*scale),q,np.asarray(scale,np.float32))
    begin=time.perf_counter();expected=oracle.fuse_plan(image,key,feed);memory[:]=b'\xa5'*len(memory);write(iv[1],q.astype('<i2').tobytes())
    for index in range(p['plan_count']):
        ins=struct.unpack('<16I',read(p['plan_address']+index*64,64));assert ins[0]==0x22504c4e and ins[2]==index+1 and ins[3]==(index-1 if index else 0xffffffff) and not any(ins[6:])
        if ins[1]==1:execute_matrix(ins[4],ins[5])
        else:
            w=struct.unpack('<'+str(ins[5]//4)+'I',read(ins[4],ins[5]));(execute_vector if ins[1]==2 else execute_layout)(w)
    actual=array(ov[0],ov[3],'<f4').reshape(expected.data.shape)
    if not np.array_equal(actual.view('<u4'),expected.data.view('<u4')):
        delta=np.flatnonzero(actual.view('<u4').ravel()!=expected.data.view('<u4').ravel());raise AssertionError((key,len(delta),delta[:10].tolist(),float(np.max(np.abs(actual-expected.data)))))
    if expected.q is not None:assert np.array_equal(array(ov[1],ov[3],'<i2').reshape(expected.q.shape),expected.q)
    checks.append(dict(key=key,bit_exact=True,instructions=p['plan_count'],elements=ov[3],host_oracle_seconds=time.perf_counter()-begin));print('V022_PLAN_ORACLE_PASS',key,flush=True)
result=dict(passed=True,hardware_accessed=False,scope='CPU independent serialized plan emulator vs sealed VM oracle. Validates shape/layout/broadcast/numerical order; native fmaf is a test substitute, NOT vendor RTL/FPGA or performance evidence.',all68_programs=all_programs,checks=checks,image_sha256=image.meta['image_sha256'],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('V022_PLAN_ORACLE_ALL_PASS',len(checks))
