from pathlib import Path
import datetime,hashlib,json,subprocess
D=Path(__file__).resolve().parent;root=D.parent; script=D/'synth_shell.tcl';src=root/'ps_ddr_shell.tcl';old=D/'PLAN.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def now():return datetime.datetime.now().astimezone().isoformat()
assert not (D/'shell_run').exists() and not (D/'SHELL_PLAN.json').exists()
files=[script,src,Path(__file__).resolve(),root.parent/'v024_deploy_20261101/ps_platform/alinx_ps_config_original.tcl',root.parent/'v024_deploy_20261101/platform/v024_unified_stub.sv',root.parent/'v024_deploy_20261101/platform/v024_core_wrapper.sv',root.parent/'v024_deploy_20261101/board_control/v024_board_control.sv'];plan={'scope':'PS+DDR shell without PL ethernet; staging only, no bit or board','inputs':{str(p.resolve()):sha(p) for p in files}};f=D/'SHELL_PLAN.json';f.write_text(json.dumps(plan,indent=2));stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S');log=D/'logs'/('shell_'+stamp+'.log');receipt=D/'reports'/('shell_'+stamp+'_process.json');r={'stage':'shell_synthesis','status':'RUNNING','started':now(),'plan_sha256':sha(f),'script_sha256':sha(script),'vivado_log':str(log)};cmd=['cmd.exe','/d','/c','C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat','-mode','batch','-nojournal','-log',str(log),'-source',str(script)]
with (D/'logs'/('shell_console_'+stamp+'.log')).open('x') as out:
 p=subprocess.Popen(cmd,cwd=D,stdout=out,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW);r['launcher_pid']=p.pid;receipt.write_text(json.dumps(r,indent=2));print('SHELL_RUNNING',p.pid,receipt,flush=True);code=p.wait()
r.update(status='PROCESS_EXITED',finished=now(),exit_code=code);receipt.write_text(json.dumps(r,indent=2));print('SHELL_EXIT',code,flush=True)
if code:raise SystemExit(code)
for path,digest in plan['inputs'].items():
 if sha(Path(path))!=digest:raise RuntimeError('changed input '+path)
