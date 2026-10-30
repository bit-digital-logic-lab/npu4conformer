"""One START, real PL plan/3AXIDMAs/numeric chain; matrix stub explicitly scoped."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'plan_rtl001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
src=[ROOT/'tests/tb_plan_cluster.sv',ROOT/'tests/axi128_memory_bfm.sv',ROOT/'tests/fma_forbidden_stub.sv',*[ROOT/'rtl'/x for x in ('ddr_execution_cluster.sv','pl_execution_plan.sv','ddr_vector_axi.sv','ddr_vector_engine.sv','asr_fp32_alu.sv','axi_dma_v019.sv')]]
exe=out/'plan.vvp';cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_plan_cluster','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode();rows=[]
for mode in range(15):
    cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),'+folder='+str(ROOT/'tests/plan_fixture').replace('\\','/'),f'+mode={mode}'],cwd=out,capture_output=True,text=True,timeout=90)
    (out/f'mode{mode}.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');print(cp.stdout,flush=True)
    passed=cp.returncode==0 and 'V022_PLAN_CLUSTER_PASS' in cp.stdout;rows.append(dict(mode=mode,passed=passed))
    if not passed:raise RuntimeError('Plan failed mode'+str(mode))
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Real PL planfetch +3actual AXI DMAs +actual unchanged FP32 RTL, chainedAdd+Q with DDR-only intermediate, oneexternalSTART.15control/error/generation/dependency/watchdog cases. Matrix modes12..14 use completionstub: no matrixarithmetic evidence in this bench. FMA forbiddenstub unused; separate officialvendor test.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n',encoding='utf-8');print('V022_PLAN_RTL_PASS',len(rows))
