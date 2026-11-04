from pathlib import Path
import hashlib,json,datetime,subprocess,os,sys
D=Path(__file__).resolve().parent; W=D.parent.parent; R=W/'v024_deploy_20261101/recovery_20261102';S=R/'retained_coeff_physical/regression'; P=R/'retained_coeff_physical'; B=R/'partitioned_shared16'; old=S/'core/rtl/graph/v024_unified_top.sv';new=D/'rtl/v024_unified_top.sv';script=D/'synth_parent.tcl'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def need(x,m):
 if not x:raise RuntimeError(m)
def now():return datetime.datetime.now().astimezone().isoformat()
need(new.read_bytes()==old.read_bytes().replace(b"32'h10040000",b"32'h20000000",1),'only PARAM_END may differ')
manifest=S/'reports/SOURCE_MANIFEST.json';m=json.loads(manifest.read_text());
for rel,digest in m['frozen_files'].items():need(sha(S/rel)==digest,'2492 frozen source changed: '+rel)
for p in [P/'reports/READY_FOR_IMPLEMENTATION.json',P/'reports/PHYSICAL_REVIEW.json',P/'reports/POST_CORE_ACCEPTANCE.json',S/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json',B/'reports/LEAF_ACCEPTANCE.json'] : need(json.loads(p.read_text()).get('status')=='PASS','missing verified evidence '+str(p))
need(sha(S/'ip/asr_fma_ip/generated/asr_fma_ip.dcp')=='3398344c3a787c46194e63ef81cd5968daa2bbcbd13176d1c2205819d8d6f10d','FMA DCP changed')
files=[script,new,old,Path(__file__).resolve(),manifest,S/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json',P/'reports/READY_FOR_IMPLEMENTATION.json',P/'reports/PHYSICAL_REVIEW.json',P/'reports/POST_CORE_ACCEPTANCE.json',B/'reports/LEAF_ACCEPTANCE.json',B/'rtl/array16_blackbox.sv',S/'ip/asr_fma_ip/asr_fma_ip.xci',S/'ip/asr_fma_ip/generated/asr_fma_ip.dcp',S/'core/scripts/deploy/core_ooc.xdc']+[S/'core'/x.strip() for x in (S/'core/filelist.f').read_text().splitlines() if x.strip()]; plan={'scope':'resident DDR PARAM_END=0x20000000; same 2492 RTL except one top default parameter; parent OOC only','inputs':{str(p.resolve()):sha(p) for p in files},'original_functional_manifest_sha256':sha(manifest),'param_end':536870912,'max_nodes':128};out=D/'PLAN.json';need(not out.exists(),'preserve existing plan');out.write_text(json.dumps(plan,indent=2)+'\n')
stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S');log=D/'logs'/('parent_'+stamp+'.log');rec=D/'reports'/('parent_'+stamp+'_process.json');cmd=['cmd.exe','/d','/c','C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat','-mode','batch','-nojournal','-log',str(log),'-source',str(script)];r={'stage':'parent_synth','status':'RUNNING','started':now(),'plan_sha256':sha(out),'script_sha256':sha(script),'vivado_log':str(log)}
with (D/'logs'/('console_'+stamp+'.log')).open('x') as stream:
 p=subprocess.Popen(cmd,cwd=D,stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW);r['launcher_pid']=p.pid;rec.write_text(json.dumps(r,indent=2));print('RUNNING',p.pid,rec,flush=True);code=p.wait()
r.update(status='PROCESS_EXITED',finished=now(),exit_code=code);rec.write_text(json.dumps(r,indent=2));print('ACTUAL_EXIT',code,flush=True)
if code:raise SystemExit(code)
for path,digest in plan['inputs'].items():need(sha(Path(path))==digest,'bound input changed: '+path)
t=log.read_text(errors='replace');need('synth_design completed successfully' in t and 'PARENT_DCP_WRITTEN matrix/shared_array BB=1 FMA_LINKED=1' in t and 'PARENT_SYNTH_PASS' in t and not any(x.startswith('ERROR:') for x in t.splitlines()),'parent verification failed');need((D/'build/parent_unlinked.dcp').is_file(),'missing parent DCP');print('PARENT_RESULT_REVIEW_REQUIRED',flush=True)
