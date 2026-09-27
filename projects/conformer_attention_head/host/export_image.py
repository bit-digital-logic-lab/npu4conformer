"""中文说明：只打包原始 FP32 模型参数与输入；不量化，不计算 head 中间结果。"""
import argparse,struct
from pathlib import Path
import torch
from .source_model import ROOT,load_source,make_fixture
def build_image(model,x,mask,head=0):
    if x.dtype!=torch.float32 or x.device.type!="cpu" or x.ndim!=3 or x.shape[0]!=1 or x.shape[2]!=512:
        raise ValueError("x must be CPU FP32 [1,T,512]")
    t=x.shape[1]
    if not 1<=t<=8 or not 0<=head<8:raise ValueError("T=1..8, head=0..7")
    if mask.shape not in ((1,1,t),(1,t,t)):raise ValueError("mask shape")
    if not bool(((mask==0)|(mask==1)).all()):raise ValueError("mask must be binary")
    mask=mask.expand(1,t,t)
    rows=[sum(int(mask[0,i,j])*2**j for j in range(t)) for i in range(t)]+[0]*(8-t)
    image=bytearray(struct.pack("<10I",0x48454144,t,*rows))
    image.extend(struct.pack("<"+str(x.numel())+"f",*x.flatten().tolist()))
    sl=slice(head*64,(head+1)*64)
    for stage,name in enumerate(("q","k","v","pos","out")):
        m=getattr(model,"linear_"+name)
        w=m.weight[sl,:] if stage<4 else m.weight[:,sl]
        bias=m.bias[sl] if stage<4 and m.bias is not None else m.bias
        for col in range(w.shape[0]):
            image.extend(struct.pack("<"+str(w.shape[1])+"f",*w[col].tolist()))
            image.extend(struct.pack("<f",float(bias[col]) if bias is not None else 0.))
            if stage==0:image.extend(struct.pack("<2f",float(model.pos_bias_u[head,col]),float(model.pos_bias_v[head,col])))
    return bytes(image)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--head",type=int,default=0);p.add_argument("--seq-len",type=int,default=4)
    p.add_argument("--x",type=Path,help="tensor-only .pt with x/mask")
    p.add_argument("--mask-last-key",action="store_true")
    p.add_argument("--all-masked-row",type=int)
    p.add_argument("--output",type=Path,default=ROOT/"fixtures/custom")
    a=p.parse_args();model,norm,_=load_source()
    if a.x:
        d=torch.load(a.x,map_location="cpu",weights_only=True);x,mask=d["x"],d["mask"]
    else:
        x,pos,_=make_fixture(norm,a.seq_len);mask=torch.ones(1,1,a.seq_len,dtype=torch.bool)
    if a.mask_last_key or a.all_masked_row is not None:
        t=x.shape[1];mask=mask.expand(1,t,t).clone()
        if a.mask_last_key:mask[:,:,-1]=False
        if a.all_masked_row is not None:
            if not 0<=a.all_masked_row<t:raise ValueError("all-masked-row outside T")
            mask[:,a.all_masked_row,:]=False
    a.output.mkdir(parents=True,exist_ok=True)
    image=build_image(model,x,mask,a.head)
    (a.output/"input.bin").write_bytes(image)
    print("RAW_FP32_IMAGE",len(image),"bytes")
if __name__=="__main__":main()
