import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'csr001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False);src=[ROOT/'tests/tb_plan_csr.sv',ROOT/'rtl/plan_submit_csr.sv'];exe=out/'csr.vvp'
cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_plan_csr','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr);cp.check_returncode()
cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe',str(exe)],cwd=out,capture_output=True,text=True,timeout=90);(out/'simulation.log').write_text(cp.stdout+cp.stderr);print(cp.stdout,flush=True)
assert cp.returncode==0 and 'V022_PLAN_CSR_PASS' in cp.stdout
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual AXIL CSR RTL only: independent AW/W order and stalls, stickyDONE, BUSY/unready/unaligned/highaddress/bytewrite rejection, one-shot accumulation of a level-held matrixDONE. No numerical or DDR performance claim.',source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n')
