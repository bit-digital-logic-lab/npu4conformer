"""One-shot continuation of an identified static build, using the existing board gates."""
from pathlib import Path
import datetime, hashlib, json, subprocess, sys, time

r=Path(__file__).resolve().parent
p=r/'partitioned_shared16'
s=Path(sys.argv[1]).resolve()
if s.parent.parent!=p/'reports' or not s.parent.name.startswith('sequence_') or s.name!='state.json':
    raise ValueError('Expected an identified local static build')
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
name='board_'+s.parent.name.removeprefix('sequence_')
output=s.parent/'board_state.json'
def put(**fields):
    tmp=output.with_suffix('.tmp')
    tmp.write_text(json.dumps({'updated':datetime.datetime.now().astimezone().isoformat(),'sequence':str(s),**fields},indent=2))
    tmp.replace(output)
if output.exists():raise FileExistsError(output)
put(status='WAITING_STATIC_BUILD',board_run_name=name)
try:
    deadline=time.monotonic()+12*3600
    while time.monotonic()<deadline:
        current=read(s)
        if current.get('status')=='STATIC_REVIEW_PASSED':break
        if current.get('status')=='STOPPED':raise RuntimeError('Static build stopped: '+str(current.get('error')))
        time.sleep(5)
    else:raise TimeoutError('Static build result not received')
    good=current.get('runs',[])
    if not good or good[-1].get('stage')!='physical_review' or good[-1].get('exit_code')!=0:
        raise RuntimeError('No successful independent physical review')
    phys=read(p/'reports/PHYSICAL_IMPLEMENTATION_REVIEW.json')
    board_gate=read(p/'hardware/BOARD_READY.json')
    if phys.get('status')!='PASS' or board_gate.get('physical_review_sha256')!=digest(p/'reports/PHYSICAL_IMPLEMENTATION_REVIEW.json'):
        raise RuntimeError('Board gate and physical review do not match')
    put(status='STARTED_GATED_BOARD_CHECK',board_run_name=name)
    with (s.parent/'board_run.log').open('x') as f:
        rc=subprocess.run([sys.executable,'-I',str(r/'run_partitioned_board_once.py'),'--run-name',name],cwd=r,
                          stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW).returncode
    if rc:raise RuntimeError(f'Board verifier exited {rc}')
    verified=read(p/'hardware'/name/'functional/verification.json')
    if verified.get('pass') is not True or verified.get('evidence_kind')!='physical_board_jtag_axi':raise RuntimeError('Missing physical numerical acceptance')
    put(status='BOARD_ACCEPTED',board_run_name=name,words=verified['dump_words'],cycles=verified['cycles'],verification=str(p/'hardware'/name/'functional/verification.json'))
except BaseException as exc:
    put(status='STOPPED',board_run_name=name,error=str(exc))
    raise
