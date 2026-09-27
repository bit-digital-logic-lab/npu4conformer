"""中文说明：独立整数参考，仅供测试；实物推理客户端不导入本文件。"""
from pathlib import Path
import math,struct,json
import torch
ROOT=Path(__file__).resolve().parents[1]
def round_shift(a,s):
    if s<=0:return a<<(-s)
    if s>=64:return 0
    sign=-1 if a<0 else 1;v=abs(a);q,r=divmod(v,1<<s);half=1<<(s-1)
    return sign*(q+int(r>half or (r==half and q%2==1)))
def select_shift(m):
    s=max(0,m.bit_length()-1-14)
    return s+int(round_shift(m,s)>32767)
def from_bits(w,limit):
    e=(w>>23)&255
    if e==255:raise ValueError("NaN/Inf")
    if e==0:return 0
    m=(1<<23)|(w&0x7fffff);s=e-130
    if s>32:raise ValueError("input range")
    a=round_shift(m,-s)
    if a>limit*(1<<20):raise ValueError("input range")
    return -a if w>>31 else a
def to_bits(a,frac=20):
    if not a:return 0
    v=abs(a);top=v.bit_length()-1
    m=round_shift(v,top-23);e=top-frac+127
    if m>>24:m>>=1;e+=1
    return ((a<0)<<31)|(e<<23)|(m&0x7fffff)
def quant_rows(a):
    s=[select_shift(max(map(abs,row))) for row in a]
    return [[round_shift(v,s[i]) for v in row] for i,row in enumerate(a)],s
def matmul(a,b): # 独立 INT64 整矩阵计算，不复用 HLS 分块/流水线。
    return (torch.tensor(a,dtype=torch.int64)@torch.tensor(b,dtype=torch.int64).t()).tolist()
def reference(binary):
    words=iter(struct.unpack("<"+str(len(binary)//4)+"I",binary))
    assert next(words)==0x48454144;t=next(words);assert 1<=t<=8
    masks=[next(words) for _ in range(8)]
    x,sx=quant_rows([[from_bits(next(words),64) for _ in range(512)] for _ in range(t)])
    pos=[[round((math.sin(o*math.exp(-(d//2*2)*math.log(10000.)/512)) if d%2==0 else
                 math.cos(o*math.exp(-(d//2*2)*math.log(10000.)/512)))*16384)
          for d in range(512)] for o in range(t-1,-t,-1)]
    exp=[round(math.exp(-i/256)*(1<<30)) for i in range(4097)]
    traces={}
    for stage in range(5):
        if stage==4:
            ac=matmul(qu,k)
            bd=matmul(qv,p)
            scores=[[round_shift(ac[i][j],23-su[i]-sk[j])+
                     round_shift(bd[i][t-1-i+j],23-sqv[i]-sp[t-1-i+j])
                     for j in range(t)] for i in range(t)]
            probabilities=[];probq=[]
            for i in range(t):
                valid=[scores[i][j] for j in range(t) if masks[i]>>j&1]
                maximum=max(valid) if valid else -(1<<62)
                ex=[]
                for j in range(t):
                    delta=maximum-scores[i][j]
                    if not (masks[i]>>j&1) or delta>=16*(1<<20):vexp=0
                    else:
                        index,rem=divmod(delta,4096)
                        vexp=exp[index]-(((exp[index]-exp[index+1])*rem+2048)>>12)
                    ex.append(vexp)
                total=sum(ex);pq30=[]
                for a in ex:
                    if not total:q=0
                    else:
                        q,r=divmod(a<<30,total);q+=int(2*r>total or (2*r==total and q%2))
                    pq30.append(q)
                probabilities.append(pq30)
                probq.append([min(32767,round_shift(q,15)) for q in pq30])
            context=[[sum(round_shift(probq[i][j]*v[j][d],15-sv[j]) for j in range(t))
                      for d in range(64)] for i in range(t)]
            c,sc=quant_rows(context)
            traces.update(scores=scores,probability_q30=probabilities,context_fixed20=context)
        cols=512 if stage==4 else 64;inner=64 if stage==4 else 512
        weights=[];shifts=[];bias=[];bu=[];bv=[]
        for col in range(cols):
            raw=[from_bits(next(words),16) for _ in range(inner)]
            shift=select_shift(max(map(abs,raw)))
            weights.append([round_shift(v,shift) for v in raw]);shifts.append(shift)
            bias.append(from_bits(next(words),4096))
            if stage==0:
                bu.append(from_bits(next(words),4096));bv.append(from_bits(next(words),4096))
        left,ls=(x,sx) if stage<3 else ((pos,[6]*len(pos)) if stage==3 else (c,sc))
        acc=matmul(left,weights)
        work=[[round_shift(acc[r][col],20-ls[r]-shifts[col])+(bias[col] if stage<4 else 0)
               for col in range(cols)] for r in range(len(left))]
        traces["stage"+str(stage)]=work
        if stage==0:
            qu,su=quant_rows([[a+bu[d] for d,a in enumerate(row)] for row in work])
            qv,sqv=quant_rows([[a+bv[d] for d,a in enumerate(row)] for row in work])
        elif stage==1:k,sk=quant_rows(work)
        elif stage==2:v,sv=quant_rows(work)
        elif stage==3:p,sp=quant_rows(work)
        else:
            output=work;biased=[[a+bias[d] for d,a in enumerate(row)] for row in output]
    if next(words,None) is not None:raise ValueError("extra words")
    result=[0x46504741,0,t*64+2*t*512+t*t]
    for values,frac in ((context,20),(output,20),(biased,20),(probabilities,30)):
        result.extend(to_bits(a,frac) for row in values for a in row)
    return struct.pack("<"+str(len(result))+"I",*result),traces

def main():
    torch.set_num_threads(1)
    output,traces=reference((ROOT/"fixtures/input.bin").read_bytes())
    expected=(ROOT/"artifacts/csim_output.bin").read_bytes()
    if output!=expected:
        a=struct.unpack("<"+str(len(output)//4)+"I",output);b=struct.unpack("<"+str(len(expected)//4)+"I",expected)
        mismatch=[(i,hex(x),hex(y)) for i,(x,y) in enumerate(zip(a,b)) if x!=y]
        raise AssertionError(mismatch[:10])
    (ROOT/"artifacts/integer_reference.bin").write_bytes(output)
    (ROOT/"artifacts/integer_reference.json").write_text(json.dumps(
        {"status":"PASS","words_exact":len(output)//4,"int16_range":[-32767,32767],
         "work_fractional_bits":20,"softmax_fractional_bits":30},indent=2),encoding="utf-8")
    print("INTEGER_REFERENCE_PASS words=",len(output)//4)
if __name__=="__main__":main()
