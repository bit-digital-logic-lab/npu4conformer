"""Independent random FP32 GEMM order probes. No hardware/golden data access."""
import json
from pathlib import Path
import numpy as np
import onnx
import onnxruntime as ort
from numba import njit

@njit(fastmath={'contract'})
def sample_fma(a,b,positions,block):
    out = np.empty(len(positions), np.float32)
    for t in range(len(positions)):
        i,j=positions[t]
        total=np.float32(0)
        for start in range(0,a.shape[1],block):
            acc=np.float32(0)
            for k in range(start,min(start+block,a.shape[1])):
                acc=acc+a[i,k]*b[k,j]
            total=total+acc
        out[t]=total
    return out

def main():
    root=Path(__file__).resolve().parents[1]
    out=root/'reports/matrix_order_001'
    out.mkdir(parents=True,exist_ok=False)
    rng=np.random.default_rng(971)
    reports=[]
    for m,n,k in [(31,512,512),(31,2048,512),(31,512,2048),(31,31,64),
                  (512,2457,9),(512,589,4608),(1,31,15),(16,512,512),(1,5000,512)]:
        a=rng.normal(size=(m,k)).astype(np.float32)
        b=rng.normal(size=(k,n)).astype(np.float32)
        graph=onnx.helper.make_graph([onnx.helper.make_node('MatMul',['a','b'],['y'])],
               'probe',[onnx.helper.make_tensor_value_info('a',1,[m,k]),onnx.helper.make_tensor_value_info('b',1,[k,n])],
               [onnx.helper.make_tensor_value_info('y',1,[m,n])])
        model=onnx.helper.make_model(graph,opset_imports=[onnx.helper.make_opsetid('',21)],ir_version=9)
        opt=ort.SessionOptions();opt.intra_op_num_threads=4;opt.inter_op_num_threads=1
        opt.graph_optimization_level=ort.GraphOptimizationLevel.ORT_DISABLE_ALL
        ref=ort.InferenceSession(model.SerializeToString(),opt,providers=['CPUExecutionProvider']).run(None,{'a':a,'b':b})[0]
        pos=np.asarray([(i,j) for i in sorted(set([0,m//2,m-1])) for j in sorted(set([0,1,min(n-1,7),n//4,n//2,n-1]))],np.int64)
        want=np.asarray([ref[i,j] for i,j in pos])
        modes=[]
        for block in sorted(set([64,128,256,512,1024,2048,4096,k])):
            got=sample_fma(a,b,pos,block)
            modes.append(dict(block=block,different=int(np.count_nonzero(got.view(np.uint32)!=want.view(np.uint32))),
                              max_abs=float(np.max(np.abs(got-want)))))
        report=dict(shape=[m,n,k],samples=len(pos),modes=modes)
        reports.append(report);print(json.dumps(report),flush=True)
    asm='\n'.join(sample_fma.inspect_asm().values())
    report=dict(scope='random scalar native-FMA order probes, not FPGA verification',numba_emits_fma='vfmadd' in asm,
                ort_build=ort.get_build_info(),cases=reports)
    (out/'report.json').write_text(json.dumps(report,indent=2))

if __name__=='__main__':main()
