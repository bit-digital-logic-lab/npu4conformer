"""中文说明：离线生成原始 PyTorch 基准，只供测试；实物推理不调用本文件。"""
import argparse,struct
from pathlib import Path
import torch
from .source_model import ROOT,load_source,original_classes,source_reference
from .export_image import build_image

@torch.no_grad()
def make_reference(folder,head=0):
    folder=Path(folder)
    raw=(folder/"input.bin").read_bytes()
    magic,t,*rows=struct.unpack_from("<10I",raw)
    if magic!=0x48454144 or not 1<=t<=8:raise ValueError("invalid input image")
    x=torch.tensor(struct.unpack_from("<"+str(t*512)+"f",raw,40),dtype=torch.float32).reshape(1,t,512)
    mask=torch.tensor([[[bool(rows[i]>>j&1) for j in range(t)] for i in range(t)]])
    model,_,metadata=load_source()
    # 验证原始权重切片及序列化次序；防止拿另一个 head 的权重生成错误的浮点基准。
    if build_image(model,x,mask,head)!=raw:
        raise ValueError("image differs from the selected pretrained head; check --head")
    _,pe_cls=original_classes()
    pe=pe_cls(512,0.1,max_len=t).eval()
    _,pos=pe(torch.zeros_like(x))
    original=source_reference(model,x,pos,mask,head)
    torch.save(dict(x=x,pos=pos,mask=mask,original=original,
                    shared_bias=model.linear_out.bias.detach().clone(),
                    head=head,checkpoint=metadata),folder/"reference.pt")
    print("OFFLINE_PYTORCH_REFERENCE_READY",str(folder/"reference.pt"))

if __name__=="__main__":
    torch.set_num_threads(1)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--fixtures",type=Path,default=ROOT/"fixtures/custom")
    p.add_argument("--head",type=int,default=0)
    a=p.parse_args();make_reference(a.fixtures,a.head)
