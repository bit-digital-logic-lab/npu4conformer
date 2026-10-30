"""Actual two frozen AXI DMAs + actual FP32 RTL, shared-memory stalled AXI BFM."""
import hashlib,json,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'vector_axi001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
src=[ROOT/'tests/tb_vector_axi.sv',ROOT/'tests/axi128_memory_bfm.sv',ROOT/'tests/fma_forbidden_stub.sv',*[ROOT/'rtl'/x for x in ('ddr_vector_axi.sv','ddr_vector_engine.sv','asr_fp32_alu.sv','axi_dma_v019.sv')]]
exe=out/'vector.vvp';cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_vector_axi','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode()
rows=[]
for case in json.loads((ROOT/'tests/vector_fixtures/meta.json').read_text()):
    for mode in (range(10) if case['name']=='add_scalar' else [0]):
        f=ROOT/'tests/vector_fixtures'/case['name'];t=time.perf_counter()
        cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),f'+folder={f.as_posix()}',f'+nbytes={case["output_bytes"]}',f'+mode={mode}'],cwd=out,capture_output=True,text=True,timeout=90)
        (out/f'{case["name"]}_{mode}.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');print(cp.stdout,flush=True)
        passed=cp.returncode==0 and 'V022_VECTOR_AXI_PASS' in cp.stdout;rows.append(dict(fixture=case['name'],mode=mode,passed=passed,host_simulation_seconds=time.perf_counter()-t))
        if not passed:raise RuntimeError('ActualAXI test failed '+case['name']+'/'+str(mode))
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual two axi_dma_v019 RTLs + unchanged FP32 RTL + vectorDDRcontroller, shared-memory independent AXI BFMs with stalls/4KiB rules/errors/tails. Not FPGA or real DDR bandwidth. FMA not covered; forbidden stub.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n',encoding='utf-8');print('V022_VECTOR_REAL_AXI_ALL_PASS',len(rows))
