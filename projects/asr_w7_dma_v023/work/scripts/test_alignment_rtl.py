"""Natural alignment, C48 crossings and byte-preserving output fragments."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'alignment001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False);rows=[]
def hexbytes(p):return bytearray(int(x,16) for x in p.read_text().split())
for kind in ('vector','layout'):
    tb=(ROOT/f'tests/tb_{kind}_axi.sv').read_text()
    if kind=='layout':
        tb=tb.replace('ddr.memory[65536+j]','ddr.memory[desc_words[3]-32\'h04000000+j]')
    path=out/f'tb_{kind}_axi.sv';path.write_text(tb,encoding='utf-8')
    names=('ddr_vector_axi.sv','ddr_vector_engine.sv','asr_fp32_alu.sv','axi_dma_v019.sv') if kind=='vector' else ('ddr_layout_axi.sv','ddr_layout_engine.sv','u16_divmod.sv','axi_dma_v019.sv')
    src=[path,ROOT/'tests/axi128_memory_bfm.sv',*[ROOT/'rtl'/x for x in names]]
    if kind=='vector':src.append(ROOT/'tests/fma_forbidden_stub.sv')
    exe=out/f'{kind}.vvp';cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s',f'tb_{kind}_axi','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
    (out/f'{kind}_compile.log').write_text(cp.stdout+cp.stderr);cp.check_returncode()
    selected=(('add_scalar',4,4,0),('i16_to_float',2,0,0),('i48_to_float',14,0,0),('round_i16',12,0,0)) if kind=='vector' else (('copy_i16',2,0,2),('unpack_c48_compact',14,0,14),('unpack_nchw_fp32',4,0,4),('depthwise_31',2,0,2))
    for name,ashift,bshift,dshift in selected:
        original=ROOT/f'tests/{kind}_fixtures'/name;folder=out/name;folder.mkdir()
        memory=hexbytes(original/'memory.hex');w=[int(x,16) for x in (original/'descriptor.hex').read_text().split()];gold=(original/'gold.hex').read_text();nbytes=len(gold.split())
        if kind=='vector':
            size=6 if w[1]&(1<<13) else 2 if w[1]&(1<<8) else 4;n=w[6]
            at=w[2]-0x04000000;data=memory[at:at+n*size];memory[at+ashift:at+ashift+n*size]=data;w[2]+=ashift
            if bshift:at=w[3]-0x04000000;data=memory[at:at+4];memory[at+bshift:at+bshift+4]=data;w[3]+=bshift
        else:
            # Move all original source data (fixture has A5 padding) and retain
            # source guard sentinel. Gold already represents compact semantics.
            data=memory[:65500];memory[ashift:ashift+len(data)]=data;w[2]+=ashift;w[3]+=dshift
        (folder/'memory.hex').write_text(''.join(f'{x:02x}\n' for x in memory));(folder/'gold.hex').write_text(gold)
        (folder/'descriptor.hex').write_text(''.join(f'{x:08x}\n' for x in w))
        cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),f'+folder={folder.as_posix()}',f'+nbytes={nbytes}','+mode=0'],cwd=out,capture_output=True,text=True,timeout=180)
        (out/f'{name}.log').write_text(cp.stdout+cp.stderr);print(cp.stdout,flush=True)
        passed=cp.returncode==0 and f'V022_{kind.upper()}_AXI_PASS' in cp.stdout;rows.append(dict(name=name,passed=passed,a_shift=ashift,b_shift=bshift,d_shift=dshift))
        if not passed:raise RuntimeError('Alignment failed '+name)
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual RTL/AXI stalled BFM: FP32 +4, scalar +4, I16 +2, packedC48 +14 crossing16byte, compact destinations +2/+4/+14; no FPGA performance claim.',tests=rows),indent=2)+'\n')
print('V022_ALIGNMENT_ALL_PASS',len(rows))
