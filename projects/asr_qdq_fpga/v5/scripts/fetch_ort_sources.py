"""Download pinned public Microsoft ORT source for inspection, never execute it."""
import hashlib,json,urllib.request
from pathlib import Path
PIN='f2c39fe'
ROOT=Path(__file__).resolve().parents[1]/'reference/ort_f2c39fe'
FILES=['LICENSE','cmake/onnxruntime_mlas.cmake','onnxruntime/core/mlas/lib/platform.cpp',
       'onnxruntime/core/providers/cpu/nn/layer_norm_impl.cc',
       'onnxruntime/core/mlas/lib/layernorm.cpp','onnxruntime/core/mlas/lib/mlasi.h',
       'onnxruntime/core/mlas/lib/sgemm.cpp','onnxruntime/core/mlas/lib/activate.cpp',
       'onnxruntime/core/mlas/lib/logistic.cpp','onnxruntime/core/mlas/lib/softmax.h',
       'onnxruntime/core/mlas/lib/layernorm_kernel_avx2.cpp',
       'onnxruntime/core/mlas/lib/amd64/SgemmKernelFma3.asm',
       'onnxruntime/core/mlas/lib/amd64/SgemmKernelAvx512F.asm',
       'onnxruntime/core/mlas/lib/amd64/SgemmKernelM1Avx.asm',
       'onnxruntime/core/mlas/lib/amd64/LogisticKernelFma3.asm',
       'onnxruntime/core/mlas/lib/amd64/TransKernelFma3.asm',
       'onnxruntime/core/mlas/lib/amd64/TransKernelAvx512F.asm',
       'onnxruntime/core/mlas/lib/amd64/SoftmaxKernelAvx.asm',
       'onnxruntime/core/mlas/lib/amd64/SoftmaxKernelAvx512F.asm',
       'onnxruntime/core/mlas/lib/compute.cpp',
       'onnxruntime/core/providers/cpu/nn/batch_norm.cc',
       'onnxruntime/core/providers/cpu/nn/batch_norm.h',
       'onnxruntime/core/mlas/lib/amd64/SgemmKernelCommon.inc']
ROOT.mkdir(parents=True,exist_ok=True)
records=[]
for name in FILES:
    url=f'https://raw.githubusercontent.com/microsoft/onnxruntime/{PIN}/{name}'
    dest=ROOT/name
    if dest.exists():
        records.append(dict(file=name,url=url,sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),cached=True));continue
    try:
        data=urllib.request.urlopen(url,timeout=15).read()
        dest.parent.mkdir(parents=True,exist_ok=True)
        with dest.open('xb') as stream:stream.write(data)
        records.append(dict(file=name,url=url,sha256=hashlib.sha256(data).hexdigest()))
        print('OK',name,len(data),flush=True)
    except Exception as e:
        records.append(dict(file=name,url=url,error=str(e)));print('UNAVAILABLE',name,str(e),flush=True)
(ROOT/'SOURCE_MANIFEST.json').write_text(json.dumps(records,indent=2))
