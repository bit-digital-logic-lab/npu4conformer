"""Real RTL numerical core + transactional DMA BFM. Not FPGA/AXI performance."""
import hashlib,json,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'vector_rtl001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
src=[ROOT/'tests/tb_vector.sv',ROOT/'tests/fma_forbidden_stub.sv',ROOT/'rtl/ddr_vector_engine.sv',ROOT/'rtl/asr_fp32_alu.sv']
exe=out/'vector.vvp';iver=r'D:\app\iverilog\iverilog\bin\iverilog.exe';vvp=r'D:\app\iverilog\iverilog\bin\vvp.exe'
cmd=[iver,'-g2012','-Wall','-s','tb_vector','-o',str(exe),*map(str,src)]
cp=subprocess.run(cmd,cwd=out,capture_output=True,text=True,timeout=90);(out/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode()
cases=json.loads((ROOT/'tests/vector_fixtures/meta.json').read_text());rows=[]
for case in cases:
    modes=range(10) if case['name']=='add_scalar' else [0]
    for mode in modes:
        f=ROOT/'tests/vector_fixtures'/case['name'];cmd=[vvp,'-i',str(exe),f'+folder={f.as_posix()}',f'+nbytes={case["output_bytes"]}',f'+mode={mode}']
        t=time.perf_counter();cp=subprocess.run(cmd,cwd=out,capture_output=True,text=True,timeout=90)
        (out/f'{case["name"]}_{mode}.log').write_text(cp.stdout+cp.stderr,encoding='utf-8')
        print(cp.stdout,flush=True);passed=cp.returncode==0 and 'V022_VECTOR_PASS' in cp.stdout
        rows.append(dict(fixture=case['name'],mode=mode,passed=passed,host_simulation_seconds=time.perf_counter()-t))
        if not passed:raise RuntimeError('RTL failed '+case['name']+'/'+str(mode))
result=dict(passed=True,hardware_accessed=False,hardware_executed=False,scope='Actual unchanged FP32 RTL, finite exact independent numerical fixtures; real ping-pong/load-compute-store controller with transactional DMA BFM/backpressure/errors, not actual AXI/DRAM bandwidth. FMA stub aborts if invoked; FMA not covered.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src})
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('V022_VECTOR_RTL_ALL_PASS',len(rows))
