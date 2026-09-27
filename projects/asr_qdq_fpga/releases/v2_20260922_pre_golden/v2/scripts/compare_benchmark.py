"""Identical physical operator fixtures for measured V1/V2 comparison."""
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import time
import numpy as np
import onnx
from host.transport import open_link,SerialBackend
from host.onnx_executor import OnnxExecutor as V1Executor,SoftwareBackend,Tensor
from host.smoke import compare


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--generation',choices=('v1','v2'),required=True)
    p.add_argument('--port',required=True)
    p.add_argument('--baud',type=int,required=True)
    p.add_argument('--report',type=Path,required=True)
    a=p.parse_args()
    r=dict(generation=a.generation,timestamp_utc=datetime.now(timezone.utc).isoformat(),
           physical_fpga_executed=False,port=a.port,baud=a.baud,pass_all=False,tests=[])
    b=None
    try:
        if a.generation=='v2':
            from v2.host.transport import BufferedBackend
            from v2.host.onnx_executor import OnnxExecutor
            b=BufferedBackend(open_link(a.port,a.baud,30))
        else:
            OnnxExecutor=V1Executor
            b=SerialBackend(open_link(a.port,a.baud,30))
        r['physical_fpga_executed']=True
        model=onnx.helper.make_model(onnx.helper.make_graph([],'bench',[],[]),opset_imports=[onnx.helper.make_opsetid('',21)])
        engine=OnnxExecutor(model,b,fold_constants=False)
        ref=SoftwareBackend()
        reference_engine=V1Executor(model,ref,fold_constants=False)
        def measure(name,run,reference,atol=0,rtol=0):
            expected=reference()
            sent,received=b.link.bytes_sent,b.link.bytes_received
            start=time.perf_counter()
            actual=run()
            elapsed=time.perf_counter()-start
            item=compare(name,actual,expected,atol=atol,rtol=rtol)
            item.update(elapsed_seconds=elapsed,sent_bytes=b.link.bytes_sent-sent,
                        received_bytes=b.link.bytes_received-received)
            r['tests'].append(item)
            print(json.dumps(item),flush=True)
            if not item['pass']: raise AssertionError(name+' numeric mismatch')
        rng=np.random.default_rng(20260922)
        qa=rng.integers(-32768,32768,(8,256),dtype=np.int16)
        qb=rng.integers(-32768,32768,(256,32),dtype=np.int16)
        def matrix():
            if a.generation=='v2': return b.matmul_i16(qa,qb)
            out=np.empty((8,32),np.int64)
            for i in range(8):
                for j in range(32): out[i,j]=b.dot_i16(qa[i],qb[:,j])
            return out
        measure('matmul_8x256x32',matrix,lambda:ref.matmul_i16(qa,qb))
        x=(rng.standard_normal(512)*2).astype(np.float32)
        measure('quantize512',lambda:b.quantize(x,np.float32(.125)),lambda:ref.quantize(x,np.float32(.125)))
        def evaluate(e,backend,op,values,**attrs):
            node=onnx.helper.make_node(op,[f'x{i}' for i in range(len(values))],['y'],**attrs)
            value=e._eval(node,[Tensor(v) for v in values],backend)
            if isinstance(value,(list,tuple)): value=value[0]
            return value.data
        values=[x.reshape(1,512),np.linspace(.5,1.5,512,dtype=np.float32),np.linspace(-.2,.3,512,dtype=np.float32)]
        measure('layernorm512',lambda:evaluate(engine,b,'LayerNormalization',values,axis=-1,epsilon=1e-12),
                lambda:evaluate(reference_engine,ref,'LayerNormalization',values,axis=-1,epsilon=1e-12),1e-5,1e-5)
        soft=rng.standard_normal((4,31)).astype(np.float32)
        measure('softmax_4x31',lambda:evaluate(engine,b,'Softmax',[soft],axis=-1),
                lambda:evaluate(reference_engine,ref,'Softmax',[soft],axis=-1),3e-6,2e-5)
        r['pass_all']=True
    except Exception as exc:
        r['error']=f'{type(exc).__name__}: {exc}'
    finally:
        if b is not None:
            r['backend']=b.report()
            b.close()
        a.report.parent.mkdir(parents=True,exist_ok=True)
        a.report.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    print(f"pass={r['pass_all']}",flush=True)
    return 0 if r['pass_all'] else 1


if __name__=='__main__': raise SystemExit(main())
