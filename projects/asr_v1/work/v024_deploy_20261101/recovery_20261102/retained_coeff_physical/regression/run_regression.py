from pathlib import Path
import json,hashlib,datetime,subprocess,sys
O=Path(__file__).resolve().parent; R=O.parent.parent; S=R/'shared16_candidate'; F=R/'retained_coeff_fix/reports/ACCEPTANCE.json'; P=O/'REGRESSION_PLAN.json'; py=Path('C:/Users/liuka/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'); viv=Path('C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def now():return datetime.datetime.now().astimezone().isoformat()
def check(x,m):
 if not x:raise RuntimeError(m)
plan=json.loads(P.read_text()); fix=json.loads(F.read_text()); check(fix.get('status')=='PASS' and sha(F)==plan['fix_acceptance_sha256'],'repair acceptance changed')
for f,h in plan['inputs'].items():check(sha(Path(f))==h,'changed input '+f)
check(not any((O/'logs').iterdir()) and not any((O/'reports').iterdir()),'existing outputs must not be overwritten')
steps=[('regression','vivado',O/'scripts/sim_combined_all.tcl'),('generation_fault','vivado',O/'scripts/sim_combined_genfault.tcl'),('check17','python',O/'scripts/check_combined_strict.py'),('check2','python',O/'scripts/check_combined_genfault.py')]
for name,kind,script in steps:
 rec=O/'reports'/(name+'_process.json'); log=O/'logs'/(name+'_process.log'); start=now();cmd=([str(py),'-I',str(script)] if kind=='python' else ['cmd.exe','/d','/c',str(viv),'-mode','batch','-nojournal','-log',str(O/'logs'/(name+'_vivado.log')),'-source',str(script)])
 with log.open('x',encoding='utf8') as f:
  proc=subprocess.Popen(cmd,cwd=O,stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW); r={'status':'RUNNING','stage':name,'started':start,'pid':proc.pid,'script_sha256':sha(script),'plan_sha256':sha(P)};rec.write_text(json.dumps(r,indent=2));code=proc.wait()
 r.update(status='PROCESS_EXITED',finished=now(),exit_code=code,log_sha256=sha(log));rec.write_text(json.dumps(r,indent=2));print(name,'exit',code,flush=True);check(code==0,name+' process failed')
 for f,h in plan['inputs'].items():check(sha(Path(f))==h,'input changed during regression '+f)
for name in ('REGRESSION_COMBINED.json','GENERATION_INVALIDATION_CHECKS.json'):check((O/'reports'/name).is_file(),name+' missing')
print('ALL_STAGES_EXITED_ZERO_REVIEW_REQUIRED',flush=True)
