"""OFFLINE board-command emulation: validate the physical host scheduler.
This is not hardware execution and is never imported by deployment scripts.
"""
from pathlib import Path
import sys,struct,json,time
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'host'),str(ROOT/'diagnostics')]
from frozen_imports import require_frozen_modules
require_frozen_modules()
from compat_ethernet import CompatEthernetBackend
from onnx_executor_v5 import OnnxExecutor
from compat_cpu import fma32,gemm_fma
from collections import Counter

class EmulatedLink:
    def __init__(self):
        self.mem=np.zeros(32768,np.uint32);self.commands=Counter();self.stream=self
    def request_many(self,commands):return [self.request(*c) for c in commands]
    def close(self):pass
    def report(self):return {'OFFLINE_ONLY':True,'hardware_executed':False}
    def request(self,op,payload=b'',flags=0,allow_arithmetic=False):
        self.commands[op]+=1;m=self.mem;f=m.view(np.float32)
        if op in (0x40,0x4f):return struct.pack('<4sII',b'ASR2' if op==0x40 else b'ASR5',2 if op==0x40 else 5,32768)
        if op in (0x41,0x42):
            base,count=struct.unpack_from('<HH',payload)
            if op==0x41:m[base:base+count]=np.frombuffer(payload[4:],np.uint32);return b''
            return m[base:base+count].tobytes()
        if op==0x46:
            a,b,d,nr,nc,k,acc=struct.unpack('<7H',payload);v=gemm_fma(f[a:a+nr*k].reshape(nr,k),f[b:b+nc*k].reshape(nc,k),k).ravel()
            if acc:v=np.add(f[d:d+nr*nc],v,dtype=np.float32)
            f[d:d+nr*nc]=v
        elif op==0x47:
            a,b,c,d,n,mode=struct.unpack('<5HB',payload)
            f[d:d+n]=fma32(*[f[base:base+(1 if mode&(1<<i) else n)] for i,base in enumerate((a,b,c))])
        elif op==0x48:
            a,d,n=struct.unpack('<3H',payload);f[d]=np.float32(np.mean(f[a:a+n],dtype=np.float64))
        elif op==0x44:
            kind,mode,a,d,n=struct.unpack('<BBHHH',payload);v=f[a]
            for value in f[a+1:a+n]:v=np.float32(v+value) if kind==0 else np.maximum(v,value)
            f[d]=v
        elif op==0x43:
            kind,mode,a,b,d,n=struct.unpack('<BBHHHH',payload)
            x=f[a:a+(1 if mode&1 else n)].copy();y=f[b:b+(1 if mode&2 else n)].copy()
            if kind==0:z=x+y
            elif kind==1:z=x-y
            elif kind==2:z=x*y
            elif kind==3:z=x/y
            elif kind==4:z=np.sqrt(x)
            elif kind==7:z=x.view(np.int32).astype(np.float32)
            elif kind==8:z=np.rint(x).astype(np.int32).view(np.float32)
            elif kind==9:z=np.maximum(x,y)
            elif kind==10:z=(x<y).astype(np.uint32).view(np.float32)
            elif kind==11:z=(x==y).astype(np.uint32).view(np.float32)
            elif kind==12:z=np.abs(x)
            elif kind==13:z=-x
            elif kind==15:z=np.clip(np.rint(x),-32768,32767).astype(np.int32).view(np.float32)
            elif kind==16:
                z=np.ldexp(x,y.view(np.int32));z=np.where((z.view(np.uint32)&0x7f800000)==0,np.float32(0),z)
            else:raise NotImplementedError(kind)
            f[d:d+n]=z
        else:raise NotImplementedError(hex(op))
        return struct.pack('<BI',0,0)

def main():
    out=ROOT/'reports/offline_host_pipeline_001';out.mkdir(exist_ok=False,parents=True)
    case=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\random200_v1\cases\case_0000')
    model=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_int16_runs\run01\int16_qdq_fix01\encoder.onnx')
    inp=np.load(case/'inputs.npz');gold=np.load(case/'expected.npz');link=EmulatedLink();backend=CompatEthernetBackend(link);backend.hardware_executed=False
    executor=OnnxExecutor(model,backend);started=time.perf_counter()
    def progress(i,total,name,op):
        if i%100==0:print(i,total,op,round(time.perf_counter()-started,1),flush=True)
    result=executor.run({'feats':inp['feats']},progress=progress)
    diff=result['memory']-gold['encoder_memory'];eq=np.array_equal(result['memory'].view(np.uint32),gold['encoder_memory'].view(np.uint32))
    report=dict(OFFLINE_ONLY=True,physical_fpga_executed=False,bit_exact_original_encoder=bool(eq),max_abs=float(np.max(np.abs(diff))),elapsed_seconds=time.perf_counter()-started,commands=dict(link.commands))
    (out/'report.json').write_text(json.dumps(report,indent=2));np.savez(out/'OFFLINE_outputs.npz',**result);print(json.dumps(report,indent=2))
    return 0 if eq else 1
if __name__=='__main__':raise SystemExit(main())
