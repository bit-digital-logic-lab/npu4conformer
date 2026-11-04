from pathlib import Path
import json,hashlib
D=Path(__file__).resolve().parent;R=D.parent;S=D/'synth';B=D/'regression';P=R/'partitioned_shared16';reg=D/'regression';fix=R/'retained_coeff_fix/reports/ACCEPTANCE.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def need(c,m):
 if not c:raise RuntimeError(m)
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
need(read(fix).get('status')=='PASS','fix acceptance not passed');rp=read(reg/'REGRESSION_PLAN.json');need(sha(fix)==rp['fix_acceptance_sha256'],'fix acceptance changed')
for path,h in rp['inputs'].items():need(sha(Path(path))==h,'regression input changed: '+path)
for step in ['regression','generation_fault','check17','check2']:
 p=reg/'reports'/(step+'_process.json');x=read(p);need(x.get('exit_code')==0 and x.get('status')=='PROCESS_EXITED' and x.get('plan_sha256')==sha(reg/'REGRESSION_PLAN.json'),'regression did not complete '+step)
for n in ['REGRESSION_COMBINED.json','GENERATION_INVALIDATION_CHECKS.json']:need(read(reg/'reports'/n).get('status')=='PASS','regression check failed '+n)
orig=read(P/'reports/IMPLEMENTATION_PLAN.json');orig.update(source_manifest_path=str((B/'reports/SOURCE_MANIFEST.json').resolve()),source_manifest_sha256=sha(B/'reports/SOURCE_MANIFEST.json'),usr_access='0xA51A2492',platform_sha256=sha(D/'build/platform_synth_copy.dcp'),script_sha256=sha(D/'physical/implement.tcl'),placement=['place_design -directive AltSpreadLogic_high'],scope='2492 new RTL; physical not yet executed')
p=D/'reports/IMPLEMENTATION_PLAN.json';need(not p.exists(),'plan already exists');p.write_text(json.dumps(orig,indent=2)+'\n')
files=[S/'synth_parent.tcl',S/'link_core.tcl',S/'run_stage.py',D/'review_synth.py',fix,reg/'REGRESSION_PLAN.json',reg/'reports/REGRESSION_COMBINED.json',reg/'reports/GENERATION_INVALIDATION_CHECKS.json',D/'reports/IMPLEMENTATION_PLAN.json',D/'build/array16_ooc_clockless.dcp',D/'build/platform_synth_copy.dcp',B/'reports/SOURCE_MANIFEST.json',B/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json',P/'reports/LEAF_ACCEPTANCE.json',P/'reports/PARTITION_PLAN.json']+[reg/'reports'/(x+'_process.json') for x in ['regression','generation_fault','check17','check2']]
files += [Path(p) for p in rp['inputs']];plan={'status':'PREPARED_NOT_RUN','fix_gate':str(fix.resolve()),'scope':'2492 corrected RTL parent synthesis followed by scoped OOC leaf link','inputs':{str(p.resolve()):sha(p) for p in files}}
out=S/'PLAN.json';need(not out.exists(),'synth plan already exists');out.write_text(json.dumps(plan,indent=2)+'\n');print('SYNTH_PLAN_READY',sha(out))

