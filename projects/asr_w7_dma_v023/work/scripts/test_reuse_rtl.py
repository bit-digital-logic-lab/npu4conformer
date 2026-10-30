"""Actual AXI/FP32 coefficient reuse, independent expected output bytes."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'reuse_rtl001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
src=[ROOT/'tests/tb_vector_axi.sv',ROOT/'tests/axi128_memory_bfm.sv',ROOT/'tests/fma_forbidden_stub.sv',*[ROOT/'rtl'/x for x in ('ddr_vector_axi.sv','ddr_vector_engine.sv','asr_fp32_alu.sv','axi_dma_v019.sv')]]
text=(ROOT/'tests/tb_vector_axi.sv').read_text().replace('gold[0:4095]','gold[0:16383]').replace('completed_elements!=1001','completed_elements!=desc_words[6]')
(out/'tb.sv').write_text(text,encoding='utf-8');src[0]=out/'tb.sv';exe=out/'reuse.vvp'
cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_vector_axi','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode();rows=[]
for case in json.loads((ROOT/'tests/reuse_fixtures/meta.json').read_text()):
    f=ROOT/'tests/reuse_fixtures'/case['name'];cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),f'+folder={f.as_posix()}',f'+nbytes={case["output_bytes"]}','+mode=0'],cwd=out,capture_output=True,text=True,timeout=90)
    (out/(case['name']+'.log')).write_text(cp.stdout+cp.stderr,encoding='utf-8');print(case['name'],cp.stdout,flush=True)
    passed=cp.returncode==0 and 'V022_VECTOR_AXI_PASS' in cp.stdout;rows.append(dict(name=case['name'],passed=passed))
    if not passed:raise RuntimeError('Reuse failed '+case['name'])
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual twoAXIDMAs/FP32RTL, repeatedperiod1/32/128/256/512 and tiled40cols with padding; exact outputbytes and overlap. Not whole ASR or FPGA.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n',encoding='utf-8');print('V022_COEFFICIENT_REUSE_PASS',len(rows))
