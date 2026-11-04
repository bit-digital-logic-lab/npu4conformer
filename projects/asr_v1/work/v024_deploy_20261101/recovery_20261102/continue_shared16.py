"""Continue the saved-parent 50 MHz build through static implementation only.

Each executable still enforces its own input, checkpoint and evidence checks.
Uses exact receipts created by each invocation; any failed stage stops the chain.
"""
import argparse, datetime, json, os, subprocess, sys, time
from pathlib import Path

R=Path(__file__).resolve().parent
P=R/'partitioned_shared16'
V=P/'retry_parent_v2'
VR=V/'reports'
PR=P/'reports'
PC=P/'post_core_review'
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--parent-receipt',type=Path,required=True)
ap.add_argument('--wait-storage',type=Path,help='avoid starting a second Vivado while the small resource comparison runs')
ap.add_argument('--linked-receipt',type=Path,help='resume after a verified, published link')
args=ap.parse_args()
p=args.parent_receipt.resolve()
if not p.is_relative_to(VR) or not p.is_file():
    raise ValueError('Select the parent process receipt from the current build')
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def now():return datetime.datetime.now().astimezone().isoformat(timespec='seconds')
run=PR/('sequence_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
run.mkdir()
state={'scope':'50 MHz shared original 16x16 array; no hardware access','started':now(),
       'parent_receipt':str(p),'supervisor_pid':os.getpid(),'runs':[]}
def save(**fields):
    state.update(fields)
    temp=run/'state.tmp'; temp.write_text(json.dumps(state,indent=2))
    os.replace(temp,run/'state.json')
def call(stage,script,*args):
    rec={'stage':stage,'started':now(),'arguments':[str(v) for v in args]}
    state['runs'].append(rec)
    save(stage=stage,status='RUNNING')
    with (run/(stage+'.log')).open('w') as f:
        child=subprocess.Popen([sys.executable,'-I',str(script),*map(str,args)],cwd=R,stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        rec['launcher_pid']=child.pid;save()
        rec['exit_code']=child.wait()
    rec['finished']=now();save()
    if rec['exit_code']!=0:
        raise RuntimeError(f'{stage} exit {rec["exit_code"]}; inspect {stage}.log')
def new_receipt(directory,pattern,fn):
    before=set(directory.glob(pattern))
    fn()
    delta=set(directory.glob(pattern))-before
    if len(delta)!=1:raise ValueError(f'Expected one new {pattern}, got {delta}')
    return delta.pop()
try:
    save(status='WAITING_FOR_PARENT',stage='parent',state_path=str(run/'state.json'))
    print(run/'state.json',flush=True)
    deadline=time.monotonic()+900
    while time.monotonic()<deadline:
        d=read(p)
        if d.get('status')=='PROCESS_EXITED' and d.get('exit_code')!=0:
            raise RuntimeError('Parent failed; will not start link')
        if (VR/'PARENT_ACCEPTANCE.json').is_file():break
        time.sleep(2)
    else:raise TimeoutError('Parent acceptance did not become available')
    if d.get('status')!='PROCESS_EXITED' or d.get('exit_code')!=0 or d.get('stage')!='parent':
        raise RuntimeError('Parent receipt is not a successful parent run')
    if args.wait_storage:
        s=args.wait_storage.resolve()
        if s.parent!=(R/'fusion_storage_ooc/reports') or read(s).get('stage')!='four_storage_ooc':
            raise ValueError('Invalid resource comparison receipt')
        save(status='WAITING_FOR_RESOURCE_SLOT',stage='before_link',storage_receipt=str(s))
        deadline=time.monotonic()+1200
        while time.monotonic()<deadline:
            try:sd=read(s)
            except json.JSONDecodeError:
                time.sleep(1);continue
            if sd.get('status')=='PROCESS_EXITED' and isinstance(sd.get('exit_code'),int):break
            time.sleep(3)
        else:raise TimeoutError('Resource slot did not become available')
    if args.linked_receipt:
        link=args.linked_receipt.resolve()
        if link.parent!=VR or not (PR/'READY_FOR_IMPLEMENTATION.json').is_file() or read(link).get('stage')!='link' or read(link).get('exit_code')!=0:
            raise ValueError('No accepted, published link to inspect')
    else:
        link=new_receipt(VR,'link_*_process.json',lambda:call('link',V/'run_stage.py','link'))
        call('publish',R/'review_partitioned_v3_publish.py','--parent-receipt',p,'--link-receipt',link)
    save(link_receipt=str(link))
    structural=new_receipt(PR,'postcore_*/PROCESS_RECEIPT.json',lambda:call('inspect',PC/'run_post_core_once.py','--core-receipt',link))
    save(postcore_receipt=str(structural))
    call('review',PC/'review_post_core.py',structural)
    impl=new_receipt(PR,'implement_*_process.json',lambda:call('implementation',R/'run_partitioned_implementation.py','implement','--post-core-receipt',structural))
    save(implementation_receipt=str(impl))
    call('physical_review',R/'review_partitioned_physical.py',impl)
    if not (P/'hardware/BOARD_READY.json').is_file():raise RuntimeError('No BOARD_READY after physical review')
    save(status='STATIC_REVIEW_PASSED',finished=now(),board_tested=False)
except BaseException as exc:
    save(status='STOPPED',finished=now(),error=str(exc))
    raise
