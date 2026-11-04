from pathlib import Path
import hashlib,json
D=Path(__file__).resolve().parent; O=D/'regression';R=D.parent;B=R/'shared16_candidate';P=O/'REGRESSION_PLAN.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def need(c,m):
 if not c:raise RuntimeError(m)
plan=read(P)
for p,h in plan['inputs'].items():need(sha(Path(p))==h,'regression input changed')
receipts={}
for name in ('regression','generation_fault','check17','check2'):
 p=O/'reports'/(name+'_process.json');r=read(p);need(r.get('status')=='PROCESS_EXITED' and r.get('exit_code')==0 and r.get('plan_sha256')==sha(P),'failed phase '+name);receipts[name]=sha(p)
a=O/'reports/REGRESSION_COMBINED.json';b=O/'reports/GENERATION_INVALIDATION_CHECKS.json';need(read(a).get('status')=='PASS' and len(read(a).get('cases',[]))==17,'17 cases missing');need(read(b).get('status')=='PASS' and len(read(b).get('generation_invalidation_cases',[]))==2,'2 fault cases missing');fix=R/'retained_coeff_fix/reports/ACCEPTANCE.json';need(read(fix).get('status')=='PASS' and sha(fix)==plan['fix_acceptance_sha256'],'fix gate mismatch')
for n in ('array16_w7_c48_cfg.sv','pe_w7_c48_cfg.sv'):need(sha(O/'core/rtl/matrix'/n)==sha(B/'core/rtl/matrix'/n),'array/PE altered')
frozen={}
for name,h in plan['inputs'].items():
 p=Path(name).resolve()
 if p.is_relative_to(O.resolve()):frozen[str(p.relative_to(O.resolve()))]=h
need(len(frozen)>=50,'insufficient frozen source');manifest=O/'reports/SOURCE_MANIFEST.json';results=O/'reports/SHARED16_RESULTS.json';gate=O/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json';need(not any(x.exists() for x in (manifest,results,gate)),'functional evidence exists');manifest.write_text(json.dumps({'entries':[x.strip() for x in (O/'core/filelist.f').read_text().splitlines() if x.strip()],'frozen_files':frozen},indent=2)+'\n');results.write_text(json.dumps({'status':'PASS','scope':'2492 corrected RTL, actual 17+2 full system XSim and separate repair unit test; no hardware','regression_plan_sha256':sha(P),'regression17_sha256':sha(a),'fault2_sha256':sha(b),'fix_acceptance_sha256':sha(fix),'process_receipt_sha256':receipts},indent=2)+'\n');gate.write_text(json.dumps({'status':'PASS','source_manifest_sha256':sha(manifest),'acceptance_sha256':sha(results),'original_pe_array_source_hashes_unchanged':True,'regression_cases':19,'scope':'2492 frozen source, 17+2 plus unit-level repair validation; no board claim'},indent=2)+'\n');print('ACTUAL_2492_FUNCTIONAL_GATE_PASS',sha(manifest))
