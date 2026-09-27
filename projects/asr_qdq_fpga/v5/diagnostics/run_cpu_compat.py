"""OFFLINE proposed arithmetic audit. No hardware access; never replacement gold."""
import argparse,json,sys,time,shutil
from pathlib import Path
import numpy as np
import onnx
import onnxruntime as ort
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'host'),str(ROOT/'diagnostics'),str(ROOT.parent/'v4/diagnostics')]
from onnx_executor_v5 import OnnxExecutor,Tensor
from compat_cpu import CompatCpuBackend
from compare_encoder_checkpoints import options,compare,sha

class AuditedExecutor(OnnxExecutor):
    def __init__(self,model,backend,teacher):
        self.teacher=teacher;self.comparisons=[];self.sessions={}
        super().__init__(model,backend)
    def _eval(self,node,args,backend):
        candidate=super()._eval(node,args,backend)
        if not getattr(backend,'compat_onnx',False) or node.op_type not in ('Conv','MatMul','LayerNormalization','BatchNormalization','Softmax','Sigmoid'):
            return candidate
        data={k:v.data for k,v in zip(node.input,args) if k and v is not None}
        graph=onnx.helper.make_graph([node],'same-input-audit',
              [onnx.helper.make_tensor_value_info(k,onnx.helper.np_dtype_to_tensor_dtype(v.dtype),v.shape) for k,v in data.items()],
              [onnx.helper.make_tensor_value_info(k,1,None) for k in node.output if k])
        model=onnx.helper.make_model(graph,opset_imports=[onnx.helper.make_opsetid('',21)],ir_version=9)
        session=ort.InferenceSession(model.SerializeToString(),options(4),providers=['CPUExecutionProvider'])
        expected=session.run(None,data)
        values=candidate if isinstance(candidate,list) else [candidate]
        for i,value in enumerate(values):
            comparison=compare(value.data,expected[i])
            comparison.pop('first_numeric_differences',None)
            rec=dict(node=node.name,operator=node.op_type,output=node.output[i],input_shapes=[list(v.shape) for v in data.values()],comparison=comparison)
            self.comparisons.append(rec)
            if comparison['numeric_differing_elements']:
                print(json.dumps(dict(node=node.name,op=node.op_type,different=comparison['numeric_differing_elements'],max_error=comparison['max_abs_error'])),flush=True)
        if self.teacher:
            return [Tensor(v) for v in expected] if isinstance(candidate,list) else Tensor(expected[0])
        return candidate

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--teacher-forcing',action='store_true');p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();args.out.mkdir(parents=True,exist_ok=False)
    model=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_int16_runs\run01\int16_qdq_fix01\encoder.onnx')
    case=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\random200_v1\cases\case_0000')
    srcs=[model,case/'inputs.npz',case/'expected.npz',Path(__file__),ROOT/'diagnostics/compat_cpu.py',ROOT/'host/onnx_executor_v5.py',ROOT/'host/compat_algorithms.py']
    hashes={str(f):sha(f) for f in srcs}
    for f in srcs[3:]:shutil.copy2(f,args.out/f.name)
    with np.load(case/'inputs.npz') as z:feats=z['feats'].copy()
    with np.load(case/'expected.npz') as z:expected=z['encoder_memory'].copy()
    start=time.perf_counter();ex=AuditedExecutor(model,CompatCpuBackend(),args.teacher_forcing)
    result=ex.run({'feats':feats})
    report=dict(scope='OFFLINE ONLY; no CPU backend in physical deployment',hardware_accessed=False,
                teacher_forcing=args.teacher_forcing,numerical_candidate_only=not args.teacher_forcing,
                seconds=time.perf_counter()-start,original_golden_compare=compare(result['memory'],expected),
                same_input_comparisons=ex.comparisons,source_sha256=hashes,sources_unchanged=all(sha(Path(f))==h for f,h in hashes.items()))
    (args.out/'report.json').write_text(json.dumps(report,indent=2))
    np.savez(args.out/'OFFLINE_diagnostic_outputs.npz',**result)
    print(json.dumps(dict(seconds=report['seconds'],golden=report['original_golden_compare'],sources_unchanged=report['sources_unchanged']),indent=2),flush=True)

if __name__=='__main__':main()
