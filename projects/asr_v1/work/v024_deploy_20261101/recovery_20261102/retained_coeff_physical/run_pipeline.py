"""Finite, fail-closed 2492 pipeline; no stage is treated as passed without its real evidence."""
from pathlib import Path
import ctypes,datetime,json,os,subprocess,sys,time,traceback
D=Path(__file__).resolve().parent;R=D.parent;PY=Path(sys.executable);state=D/'PIPELINE_STATE.json'; lock=D/'PIPELINE.lock'
resume = sys.argv[1:] == ['--resume-postcore-review']
if sys.argv[1:] and not resume:
 raise SystemExit('Unsupported pipeline arguments')
if resume:
 recovery = D/'recovery_postcore_20261102_1732'
 previous = json.loads(state.read_text())
 if (previous.get('stage') != 'STOPPED' or not previous.get('error','').startswith('bind_postcore exit=1;')
     or state.read_bytes() != (recovery/'PIPELINE_STATE.json').read_bytes()
     or (D/'physical/PLAN.json').exists() or any((D/'physical/build').iterdir())):
  raise SystemExit('Resume requires the archived bind_postcore stop and an unstarted physical stage')
 lock = recovery/'resume.lock'
try:
 fd=os.open(lock,os.O_WRONLY|os.O_CREAT|os.O_EXCL)
except FileExistsError:
 print('Pipeline lock exists; duplicate invocation refused',file=sys.stderr);raise SystemExit(2)
with os.fdopen(fd,'w') as f: json.dump({'pid':os.getpid(),'created':datetime.datetime.now().astimezone().isoformat()},f)
if state.exists() and not resume:
 print('Existing pipeline state; refusing to alter it',file=sys.stderr);raise SystemExit(2)
logdir=(recovery/'logs' if resume else D/'pipeline_logs');logdir.mkdir(exist_ok=True)
def now():return datetime.datetime.now().astimezone().isoformat()
def update(stage,**extra):
 v={'stage':stage,'updated':now(),**extra};tmp=state.with_suffix('.tmp');tmp.write_text(json.dumps(v,indent=2)+'\n');tmp.replace(state);print(stage,extra,flush=True)
class MEM(ctypes.Structure):
 _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong)]+[(x,ctypes.c_ulonglong) for x in ('totalphys','availphys','totalpage','availpage','totalvirtual','availvirtual','extended')]
def headroom():
 m=MEM();m.length=ctypes.sizeof(m);assert ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m));return m.availphys/2**30,m.availpage/2**30
def wait_resource(deadline):
 while time.time()<deadline:
  p=subprocess.run(['tasklist.exe','/fo','csv','/nh'],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW);s=p.stdout.lower();busy=[x for x in ('vivado.exe','xsim.exe','xelab.exe','xvlog.exe','vsim.exe','parallel_synth_helper.exe') if x in s];a,b=headroom()
  if p.returncode==0 and not busy and a>=4 and b>=8:return
  update('WAITING_RESOURCE',free_physical_gib=round(a,2),free_commit_gib=round(b,2),busy=busy);time.sleep(15)
 raise RuntimeError('resource deadline reached')
def run(stage,args):
 update(stage,command=[str(x) for x in args]);f=logdir/(stage+'.log')
 with f.open('x',encoding='utf8') as stream:
  p=subprocess.Popen([str(PY),'-I',*[str(x) for x in args]],cwd=D,stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW);c=p.wait()
 if c:raise RuntimeError(f'{stage} exit={c}; see {f}')
def only(pattern):
 a=list(D.glob(pattern));
 if len(a)!=1:raise RuntimeError(f'expected one {pattern}, found {len(a)}')
 return a[0]
def through_postcore(deadline):
 while time.time()<deadline:
  gate=R/'retained_coeff_fix/reports/ACCEPTANCE.json';unit=R/'retained_coeff_fix/UNIT_STATE.json';xsim=R/'fusion_storage_integrated/guarded_pair_outputfix_state.json'
  try: good=json.loads(gate.read_text()).get('status')=='PASS' and json.loads(xsim.read_text()).get('status') in ('PASS','FAILED','RESOURCE_STOP','TIMEOUT')
  except (OSError,ValueError):good=False
  if good:break
  update('WAITING_FIX_AND_PRIOR_XSIM',fix_gate_present=gate.exists());time.sleep(15)
 else:raise RuntimeError('repair acceptance deadline reached')
 wait_resource(deadline);run('freeze_regression',[D/'regression/freeze_regression.py']);run('run_regression',[D/'regression/run_regression.py']);run('publish_functional',[D/'publish_functional.py']);run('prepare_synth',[D/'prepare_synth.py'])
 wait_resource(deadline);run('parent',[D/'synth/run_stage.py','parent']);wait_resource(deadline);run('link',[D/'synth/run_stage.py','link'])
 parent=only('synth/reports/parent_*_process.json');link=only('synth/reports/link_*_process.json');run('review_synth',[D/'review_synth.py','--parent-receipt',parent,'--link-receipt',link])
 wait_resource(deadline);run('postcore',[D/'post_core_review/run_post_core_once.py','--core-receipt',link])
try:
 deadline=time.time()+6*3600
 if not resume:
  through_postcore(deadline)
 post=only('reports/postcore_*/PROCESS_RECEIPT.json')
 run('review_postcore',[D/'post_core_review/review_post_core.py',post])
 run('bind_postcore',[D/'bind_postcore.py',post])
 run('prepare_physical',[D/'physical/run.py','prepare'])
 wait_resource(deadline);run('physical',[D/'physical/run.py','run']);physical=only('physical/reports/implement_*_process.json');run('review_physical',[D/'review_physical.py','--receipt',physical])
 wait_resource(deadline);run('board',[D/'hardware/run_board.py']);update('BOARD_COLD_FIRST_GRAPH_NUMERIC_PASS')
except Exception as e:
 update('STOPPED',error=str(e),traceback=traceback.format_exc());raise


