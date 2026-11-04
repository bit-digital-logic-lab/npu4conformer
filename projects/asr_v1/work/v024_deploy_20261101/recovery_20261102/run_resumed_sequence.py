"""Resume a real optimized platform, review both physical stages, then test the board."""
from pathlib import Path
import datetime as dt, json, os, subprocess, sys

r=Path(__file__).resolve().parent;p=r/'partitioned_shared16';q=p/'reports';v=p/'resume_placement_v1'
name=dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
out=q/('sequence_'+name);out.mkdir()
def now():return dt.datetime.now().astimezone().isoformat()
state={'started':now(),'status':'RUNNING','scope':'Resume physical build and run only verified board gates','runs':[]}
def save():
    tmp=out/'state.tmp';tmp.write_text(json.dumps(state,indent=2));os.replace(tmp,out/'state.json')
def run(stage,script,*args):
    state['stage']=stage;rec={'stage':stage,'started':now(),'arguments':list(map(str,args))};state['runs'].append(rec);save()
    with (out/(stage+'.log')).open('x') as f:
        child=subprocess.Popen([sys.executable,'-I',str(script),*map(str,args)],cwd=r,stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        rec['pid']=child.pid;save();rec['exit_code']=child.wait()
    rec['finished']=now();save()
    if rec['exit_code']!=0:raise RuntimeError(f'{stage} exit {rec["exit_code"]}; see {stage}.log')
print(out/'state.json',flush=True)
try:
    before=set(q.glob('resume_*_process.json'))
    run('placement_and_routing',v/'run_resume.py','run')
    after=set(q.glob('resume_*_process.json'))-before
    if len(after)!=1:raise RuntimeError('Expected exactly one new physical resume receipt')
    receipt=after.pop();state['resume_receipt']=str(receipt);save()
    run('physical_review',r/'review_partitioned_resumed_physical.py','--initial-receipt',q/'implement_20261102_145124_process.json','--resume-receipt',receipt,'--resume-plan',v/'RESUME_PLAN.json')
    state['board_run_name']='resume_board_'+name;save()
    run('board_program_and_verify',r/'run_partitioned_board_once.py','--run-name',state['board_run_name'])
    verification=p/'hardware'/state['board_run_name']/'functional/verification.json';data=json.loads(verification.read_text(encoding='utf-8-sig'))
    if data.get('pass') is not True or data.get('evidence_kind')!='physical_board_jtag_axi' or data.get('dump_words')!=8192:raise RuntimeError('Physical output verification missing')
    state.update(status='BOARD_ACCEPTED',finished=now(),cycles=data['cycles'],words=data['dump_words'],verification=str(verification));save()
except BaseException as exc:
    state.update(status='STOPPED',finished=now(),error=str(exc));save();raise
