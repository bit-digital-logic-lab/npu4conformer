"""中文说明：离线验证脚本，与纯传输的实物推理客户端分开。"""
import argparse,json,struct,hashlib
from pathlib import Path
import torch
from .integer_reference import reference
ROOT=Path(__file__).resolve().parents[1]
def compare(folder,input_folder=None):
    folder=Path(folder);fixtures=Path(input_folder) if input_folder else ROOT/"fixtures"
    raw=(folder/"fpga_output.bin").read_bytes()
    expected,_=reference((fixtures/"input.bin").read_bytes())
    if raw!=expected:raise AssertionError("FPGA output not bit-exact against independent integer model")
    r=torch.load(fixtures/"reference.pt",weights_only=True,map_location="cpu")
    t=r["x"].shape[1]
    values=torch.tensor(struct.unpack("<"+str((len(raw)-12)//4)+"f",raw[12:]))
    offset=0;metrics={}
    for name,n,original in (
        ("context",t*64,r["original"]["context"]),
        ("contribution",t*512,r["original"]["contribution"]),
        ("with_output_bias",t*512,r["original"]["contribution"]+r["shared_bias"]),
        ("probability",t*t,r["original"]["probability"])):
        actual=values[offset:offset+n].reshape(original.shape);offset+=n
        delta=(actual-original).double()
        relative=float(delta.norm())/max(float(original.double().norm()),1e-12)
        metrics[name]={"max_abs":float(delta.abs().max()),"mean_abs":float(delta.abs().mean()),"relative_l2":relative}
        if name!="probability" and (metrics[name]["max_abs"]>.1 or relative>.005):
            raise AssertionError(f"accuracy failed: {name}: {metrics[name]}")
    report={"status":"PASS","all_fpga_outputs_bit_exact":True,"output_values":len(values),
            "metrics":metrics,"input_sha256":hashlib.sha256((fixtures/"input.bin").read_bytes()).hexdigest(),
            "output_sha256":hashlib.sha256(raw).hexdigest(),"max_abs_threshold":.1,"relative_l2_threshold":.005}
    (folder/"verification.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print(json.dumps(report,indent=2))
    return report
if __name__=="__main__":
    torch.set_num_threads(1)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",type=Path,default=ROOT/"artifacts/hardware")
    p.add_argument("--fixtures",type=Path,default=ROOT/"fixtures")
    a=p.parse_args();compare(a.output,a.fixtures)
