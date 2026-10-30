"""Actual layout/AXI RTL: nonzeroK offset, splitK4096, dilation and crop."""
import hashlib,json,subprocess,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'im2col_slice001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False);src=[ROOT/'tests/tb_layout_axi.sv',ROOT/'tests/axi128_memory_bfm.sv',*[ROOT/'rtl'/x for x in ('ddr_layout_axi.sv','ddr_layout_engine.sv','u16_divmod.sv','axi_dma_v019.sv')]]
exe=out/'layout.vvp';cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_layout_axi','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90);(out/'compile.log').write_text(cp.stdout+cp.stderr);cp.check_returncode();rows=[]
for name,c,h,wi,kh,kw,oh,ow,sh,sw,dh,dw,ph,pw,koff,depth,shift in [
 ('split_K4096_tail512',512,7,9,3,3,3,5,2,2,1,1,1,1,4096,512,0),
 ('cross_kernel_slice97',17,7,9,3,3,3,5,2,2,1,1,1,1,97,56,2),
 ('dilation_slice11',4,7,9,3,3,7,5,1,2,2,3,2,3,11,17,14)]:
    m=oh*ow;q=(np.arange(c*h*wi)*13%65536-32768).astype('<i2').reshape(c,h,wi);matrix=np.zeros((m,depth),'<i2')
    for row in range(m):
        for col in range(depth):
            channel,kernel=divmod(koff+col,kh*kw);iy=(row//ow)*sh+kernel//kw*dh-ph;ix=(row%ow)*sw+kernel%kw*dw-pw
            if 0<=iy<h and 0<=ix<wi:matrix[row,col]=q[channel,iy,ix]
    pad=np.zeros(((m+31)//32*32,(depth+31)//32*32),'<i2');pad[:m,:depth]=matrix
    gold=pad.reshape(pad.shape[0]//32,32,pad.shape[1]//32,32).transpose(0,2,1,3).copy().tobytes()
    memory=bytearray(b'\xa5'*(1<<18));memory[shift:shift+q.nbytes]=q.tobytes();folder=out/name;folder.mkdir()
    words=[0x224c4159,2,0x04000000+shift,0x04010000,len(gold)//2,2,m,depth,0,0,c,h,wi,kh,kw,oh,ow,sh,sw,dh,dw,ph,pw,koff]+[0]*8
    (folder/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in memory));(folder/'gold.hex').write_text(''.join(f'{v:02x}\n' for v in gold));(folder/'descriptor.hex').write_text(''.join(f'{v:08x}\n' for v in words))
    cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),f'+folder={folder.as_posix()}',f'+nbytes={len(gold)}','+mode=0'],cwd=out,capture_output=True,text=True,timeout=180);(out/f'{name}.log').write_text(cp.stdout+cp.stderr);print(cp.stdout,flush=True)
    passed=cp.returncode==0 and 'V022_LAYOUT_AXI_PASS' in cp.stdout;rows.append(dict(name=name,passed=passed,k_offset=koff,depth=depth))
    if not passed:raise RuntimeError('Im2col slice failed '+name)
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual layout engine with bothrealAXIDMAs and stalledAXI BFM, splitKoffset4096, crosskerneloffset97, dilation2/3, boundarypadding/croppedoutrows; no fullCASE/FPGA speedclaim.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n')
print('V022_IM2COL_SLICE_ALL_PASS',len(rows))
