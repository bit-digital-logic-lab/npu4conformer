"""中文说明：加载压缩包原始 ESPnet 注意力作为基准，不用自写公式冒充原始模型。"""
from __future__ import annotations
import ast
import hashlib
import importlib
import json
import math
from pathlib import Path
import sys
import torch
import torch.nn.functional as F

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT/"vendor"
FULL_SHA256 = "8e94fe626aefaec3662a101cba7e112fd108de4871602c34852c27b09384b21b"

def sha256(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()

def original_classes():
    # 原始 attention.py 仅需 torch 与其自带 LayerNorm；保留原文件和版权注释。
    if str(VENDOR) not in sys.path:
        sys.path.insert(0,str(VENDOR))
    mod = importlib.import_module("espnet2.legacy.nets.pytorch_backend.transformer.attention")
    # embedding.py 其它类依赖完整 ESPnet；只编译独立的原始相对位置类，类体不修改。
    path = VENDOR/"espnet2/legacy/nets/pytorch_backend/transformer/embedding.py"
    tree = ast.parse(path.read_text(encoding="utf-8"))
    node = next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=="RelPositionalEncoding")
    env = {"torch":torch,"math":math}
    exec(compile(ast.Module(body=[node],type_ignores=[]),str(path),"exec"),env)
    return mod.RelPositionMultiHeadedAttention, env["RelPositionalEncoding"]

def load_source(layer=0, checkpoint=None):
    if type(layer) is not int or not 0 <= layer < 12:
        raise ValueError("Model A 层号为 0～11")
    path = Path(checkpoint) if checkpoint else ROOT/f"weights/layer_{layer}.pth"
    data = torch.load(path,map_location="cpu",weights_only=True)
    prefix = f"encoder.encoders.{layer}."
    attention = {k[len(prefix+"self_attn."):]:v for k,v in data.items()
                 if k.startswith(prefix+"self_attn.")}
    if not attention:
        raise ValueError(f"checkpoint 中缺少第 {layer} 层的完整注意力")
    cls,_ = original_classes()
    model = cls(8,512,0.1,zero_triu=False).eval()
    model.load_state_dict(attention,strict=True)
    model.requires_grad_(False)
    norm = (data[prefix+"norm_mha.weight"],data[prefix+"norm_mha.bias"])
    return model,norm,{"layer":layer,"checkpoint":path.name,"sha256":sha256(path),
                       "full_checkpoint_sha256":FULL_SHA256 if checkpoint is None else None,
                       "custom_checkpoint":checkpoint is not None}

@torch.no_grad()
def make_fixture(norm, seq_len=4, batch=1, seed=2026):
    if seq_len < 1 or batch < 1:
        raise ValueError("序列长度和 batch 必须为正")
    gen = torch.Generator().manual_seed(seed)
    # 输入边界：Macaron FFN 之后、norm_mha 之后的 [B,T,512]。
    # 本测试使用固定随机残差及真实训练好的 norm 参数，不声称来自语音数据集。
    residual = torch.randn(batch,seq_len,512,generator=gen)
    x = F.layer_norm(residual,(512,),*norm,eps=1e-12)
    _,pe_cls = original_classes()
    pe = pe_cls(512,0.1,max_len=seq_len).eval()
    _,pos = pe(torch.zeros_like(x))
    return x,pos,residual

@torch.no_grad()
def source_reference(model,x,pos,mask,head):
    captures = []
    handle = model.linear_out.register_forward_pre_hook(
        lambda module,args: captures.append(args[0].detach().clone()))
    try:
        full = model(x,x,x,pos,mask)
    finally:
        handle.remove()
    concat = captures[0]
    start = head*64
    context = concat[:,:,start:start+64]
    contribution = F.linear(context,model.linear_out.weight[:,start:start+64],None)
    # 一个 head 的输出投影贡献不含共享偏置；8 个贡献求和后只加一次偏置。
    reconstructed = sum(F.linear(concat[:,:,i*64:(i+1)*64],
                                 model.linear_out.weight[:,i*64:(i+1)*64],None)
                        for i in range(8)) + model.linear_out.bias
    torch.testing.assert_close(reconstructed,full,atol=1e-4,rtol=1e-5)
    return {"context":context,"contribution":contribution,
            "probability":model.attn[:,head].clone(),"full_attention_output":full,
            "head_sum_max_abs":float((reconstructed-full).abs().max())}
