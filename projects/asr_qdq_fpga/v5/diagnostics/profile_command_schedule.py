"""OFFLINE count of V5 command work by original graph node; no hardware access."""
from pathlib import Path
import sys,json,time
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'diagnostics'))
from host_pipeline_emulation import EmulatedLink,CompatEthernetBackend,OnnxExecutor
class CountingLink(EmulatedLink):
    def __init__(self):super().__init__();self.fmas=0;self.upload_words=0;self.download_words=0
    def request(self,op,payload=b'',flags=0,allow_arithmetic=False):
        import struct
        if op==0x46:
            a,b,d,m,n,k,acc=struct.unpack('<7H',payload);self.fmas+=m*n*k
        elif op==0x47:self.fmas+=struct.unpack_from('<H',payload,8)[0]
        elif op==0x41:self.upload_words+=struct.unpack_from('<H',payload,2)[0]
        elif op==0x42:self.download_words+=struct.unpack_from('<H',payload,2)[0]
        return super().request(op,payload,flags,allow_arithmetic)
def main():
    out=ROOT/'reports/offline_work_profile_001';out.mkdir(parents=True,exist_ok=False)
    link=CountingLink();backend=CompatEthernetBackend(link);backend.hardware_executed=False
    model=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_int16_runs\run01\int16_qdq_fix01\encoder.onnx')
    case=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\random200_v1\cases\case_0000')
    executor=OnnxExecutor(model,backend);nodes=[];last=(0,0,0)
    def progress(i,total,name,op):
        nonlocal last
        now=(link.fmas,link.upload_words,link.download_words);delta=tuple(a-b for a,b in zip(now,last));last=now
        nodes.append(dict(dynamic_node=i,name=name,op=op,fma_count=delta[0],upload_words=delta[1],download_words=delta[2],cumulative_fmas=now[0]))
    result=executor.run({'feats':np.load(case/'inputs.npz')['feats']},progress=progress)
    eq=np.array_equal(result['memory'].view(np.uint32),np.load(case/'expected.npz')['encoder_memory'].view(np.uint32))
    report=dict(OFFLINE_ONLY=True,hardware_accessed=False,bit_exact_original_encoder=bool(eq),total_fmas=link.fmas,upload_words=link.upload_words,download_words=link.download_words,nodes=nodes)
    (out/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='nodes'}));print(json.dumps(sorted(nodes,key=lambda n:n['fma_count'],reverse=True)[:5],indent=2))
if __name__=='__main__':main()
