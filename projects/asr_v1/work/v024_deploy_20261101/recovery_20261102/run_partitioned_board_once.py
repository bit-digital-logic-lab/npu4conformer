"""After a reviewed BOARD_READY only: ensure local services and run existing board verifier once.

This helper does not implement numerical checks; it reuses host/verify_v024.py.
It never starts on import, and creates no separate report.
"""
from pathlib import Path
import argparse,atexit,hashlib,importlib.util,json,os,re,socket,subprocess,sys,time
OWNED_SERVER_LAUNCHERS=[]
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'partitioned_shared16';H=OUT/'hardware';P=OUT/'reports';SHARED=ROOT/'shared16_candidate';DEPLOY=ROOT.parent; BIN=Path('C:/Academic_Application/Vivado/2025.2/Vivado/bin');RUNNER=H/'run_partitioned.py';VERIFY=DEPLOY/'host/verify_v024.py'
def need(x,m):
 if not x:raise RuntimeError(m)
def sha(p):
 need(p.is_file(),f'missing prerequisite: {p}');return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def listening(port):
 try:
  with socket.create_connection(('127.0.0.1',port),timeout=0.5):return True
 except OSError:return False
def server_options(name,port):
 # hw_server 2025.2 embedded usage: -s<url>, -I<idle-seconds>, -p0.
 # cs_server 2025.2 embedded Click help: -s <url>, -I <idle-seconds>.
 # Both use TCP:<host>:<port>; constrain new listeners to IPv4 loopback.
 if name=='hw_server' and port==3121:return ['-sTCP:127.0.0.1:3121','-I60','-p0']
 if name=='cs_server' and port==3042:return ['-s','TCP:127.0.0.1:3042','-I','60']
 raise RuntimeError('unsupported server/port')
def describe_server_cleanup():
 if OWNED_SERVER_LAUNCHERS:
  print('Temporary server launchers were started with 60-second no-connection auto-exit; no process was killed. In-use or ownership-uncertain services are left running.',flush=True)
atexit.register(describe_server_cleanup)
def ensure_server(name,port):
 if listening(port):print(f'{name}: existing local listener {port}; left unchanged',flush=True);return
 exe=BIN/(name+'.bat');need(exe.is_file(),f'{name} executable absent');proc=subprocess.Popen(['cmd.exe','/d','/c',str(exe),*server_options(name,port)],cwd=BIN,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW);OWNED_SERVER_LAUNCHERS.append((name,proc.pid));print(f'{name}: started launcher PID {proc.pid} with loopback and 60-second idle exit; no PID-based termination will be attempted',flush=True);deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  if listening(port):return
  need(proc.poll() is None,f'{name} launcher exited before port became available');time.sleep(0.25)
 raise RuntimeError(f'{name} did not open localhost:{port}')
def preflight():
 gate_path=H/'BOARD_READY.json';g=read(gate_path);plan=read(H/'HARDWARE_PLAN.json');physical=P/'PHYSICAL_IMPLEMENTATION_REVIEW.json';pr=read(physical);ready=P/'READY_FOR_IMPLEMENTATION.json';rg=read(ready);leaf=P/'LEAF_ACCEPTANCE.json';manifest=SHARED/'reports/SOURCE_MANIFEST.json';functional=SHARED/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json';impl=P/'IMPLEMENTATION_PLAN.json';bit=OUT/'build/candidate_A51A2491.bit';ltx=bit.with_suffix('.ltx')
 need(g.get('status')=='PASS' and g.get('scope')=='PARTITIONED_SHARED16_SEVEN_NODE' and g.get('part')=='xczu15eg-ffvb1156-2-i' and g.get('usr_access')=='0xA51A2491' and g.get('cable_serial')=='210512180081' and g.get('device_part')=='xczu15','board gate identity invalid')
 need(all(g.get(k) is True for k in ('route_complete','setup_met','hold_met','drc_pass','clock_coverage_pass','bus_skew_pass','io_pass','original_pe_array_sources_unchanged','candidate_functional_review_pass')) and type(g.get('blackbox_count')) is int and g['blackbox_count']==0,'board gate physical requirements incomplete')
 for key,path in [('hardware_plan_sha256',H/'HARDWARE_PLAN.json'),('physical_review_sha256',physical),('synthesis_gate_sha256',ready),('leaf_acceptance_sha256',leaf),('source_manifest_sha256',manifest),('functional_acceptance_sha256',functional),('implementation_plan_sha256',impl),('bitstream_sha256',bit),('debug_probes_sha256',ltx)]:need(g.get(key)==sha(path),f'board gate hash mismatch: {key}')
 need(pr.get('status')=='PASS' and pr.get('bitstream_sha256')==sha(bit) and pr.get('debug_probes_sha256')==sha(ltx) and pr.get('synthesis_gate_sha256')==sha(ready),'physical review is not PASS or is not bound')
 need(rg.get('status')=='PASS' and rg.get('core_checkpoint_sha256')==sha(OUT/'build/candidate_synth.dcp') and rg.get('leaf_acceptance_sha256')==sha(leaf),'core synthesis gate invalid')
 need(read(functional).get('status')=='PASS' and read(functional).get('source_manifest_sha256')==sha(manifest) and read(leaf).get('status')=='PASS','functional/leaf gate invalid')
 for rel,digest in read(manifest)['frozen_files'].items():
  path=(SHARED/rel).resolve();need(path.is_relative_to(SHARED.resolve()) and sha(path)==digest,f'frozen source changed: {rel}')
 for path,digest in plan['pinned_inputs'].items():need(sha(Path(path))==digest,f'host input changed: {path}')
 need(plan['runner_sha256']==sha(RUNNER) and plan['program_tcl_sha256']==sha(H/'program_partitioned_and_verify.tcl'),'reviewed board scripts changed')
 return g

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run-name',required=True);args=ap.parse_args();need(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}',args.run_name),'invalid run name');run=H/args.run_name;need(not run.exists() and all(not (H/f'{args.run_name}{suffix}').exists() for suffix in ('_vivado.log','_console.log','_process.json')),'existing run evidence must be preserved');preflight()
 # The running hardware server is a documented prerequisite. Configuration
 # server auto-start is guaranteed only for the default URL; the pinned Tcl
 # explicitly names localhost, so ensure the local 3042 listener as well.
 ensure_server('hw_server',3121);ensure_server('cs_server',3042)
 rc=subprocess.run([sys.executable,'-I',str(RUNNER),'--run-name',args.run_name],cwd=H).returncode;need(rc==0,f'original board runner failed: {rc}')
 result=read(H/f'{args.run_name}_process.json');need(result.get('process_exit_code')==0 and result.get('board_gate_sha256')==sha(H/'BOARD_READY.json'),'board process receipt invalid')
 receipt=(run/'programming_receipt.txt').read_text(errors='strict');need(re.search(r'^TARGET=.*?/Digilent/210512180081\s*$',receipt,re.M) and re.search(r'^PART=xczu15\s*$',receipt,re.M) and re.search(r'^PROGRAMMED_USR_ACCESS=(?:0x)?A51A2491\s*$',receipt,re.M|re.I) and re.search(r'^FUNCTIONAL_ACCEPTANCE=PASS\s*$',receipt,re.M),'target/programming receipt mismatch')
 functional=run/'functional';saved=read(functional/'verification.json');need(saved.get('pass') is True and saved.get('evidence_kind')=='physical_board_jtag_axi','original numeric verifier did not pass');need(saved.get('board_receipt_sha256')==sha(functional/'board_receipt.json') and saved.get('output_sha256')==sha(functional/'output.bin'),'saved physical evidence hash mismatch')
 spec=importlib.util.spec_from_file_location('frozen_v024_verifier',VERIFY);need(spec and spec.loader,'cannot load original verifier');verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier);checked=verifier.verify(DEPLOY/'core',functional);need(checked==saved,'re-run of original independent verifier differs from saved result');need(checked.get('dump_words')==8192 and checked.get('cycles',0)>0,'incomplete seven-node output/cycle evidence')
 print(f'PARTITIONED_BOARD_ACCEPTANCE_PASS run={run} words=8192 cycles={checked["cycles"]}',flush=True);return 0
if __name__=='__main__':
 try:raise SystemExit(main())
 except Exception as error:print(f'PARTITIONED_BOARD_ACCEPTANCE_FAIL: {error}',file=sys.stderr,flush=True);raise SystemExit(1)
