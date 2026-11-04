"""Review two real synthesis phases and publish exact artifacts to canonical path.

Does not start Vivado or access hardware. Requires distinct successful receipts.
"""
from pathlib import Path
import argparse,datetime as dt,hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'partitioned_shared16';V=OUT/'retry_parent_v2'; SHARED=ROOT/'shared16_candidate'; REPORTS=OUT/'reports';VR=V/'reports';EXPECTED_PART='xczu15eg-ffvb1156-2-i';EXPECTED_IP_DCP='3398344c3a787c46194e63ef81cd5968daa2bbcbd13176d1c2205819d8d6f10d'
def need(c,m):
 if not c: raise RuntimeError(m)
def sha(p):
 need(p.is_file(),f'missing file: {p}');return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def text(p):return p.read_text(encoding='utf-8-sig',errors='replace')
def under(p,root):return p.resolve().is_relative_to(root.resolve())
def fresh(p,start,end):need(p.is_file() and start<=p.stat().st_mtime<=end+5,f'missing/stale output: {p}')
ap=argparse.ArgumentParser();ap.add_argument('--parent-receipt',required=True,type=Path);ap.add_argument('--link-receipt',required=True,type=Path);args=ap.parse_args();pr=args.parent_receipt.resolve();lr=args.link_receipt.resolve();need(pr!=lr and under(pr,VR) and under(lr,VR),'receipts must be distinct and local');p=load(pr);l=load(lr)
for receipt,stage in [(p,'parent'),(l,'link')]:need(receipt.get('stage')==stage and receipt.get('status')=='PROCESS_EXITED' and type(receipt.get('exit_code')) is int and receipt['exit_code']==0,f'{stage} did not exit successfully')
ps=dt.datetime.fromisoformat(p['started']).timestamp();pe=dt.datetime.fromisoformat(p['finished']).timestamp();ls=dt.datetime.fromisoformat(l['started']).timestamp();le=dt.datetime.fromisoformat(l['finished']).timestamp();need(ps<pe<=ls<le,'stage times inconsistent')
vplan=load(V/'PLAN.json');plan_sha=sha(V/'PLAN.json');need(p.get('plan_sha256')==plan_sha and l.get('plan_sha256')==plan_sha,'receipt plan mismatch')
for path,digest in vplan['inputs'].items():need(sha(Path(path))==digest,f'v2 input changed: {path}')
need(p.get('script_sha256')==sha(V/'synth_parent.tcl') and l.get('script_sha256')==sha(V/'link_core.tcl'),'stage script mismatch')
manifest_path=SHARED/'reports/SOURCE_MANIFEST.json';manifest=load(manifest_path);manifest_sha=sha(manifest_path);gate=load(SHARED/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json');need(gate.get('status')=='PASS' and gate.get('source_manifest_sha256')==manifest_sha and gate.get('acceptance_sha256')==sha(SHARED/'reports/SHARED16_RESULTS.json'),'functional gate mismatch');need(p.get('source_manifest_sha256')==manifest_sha and l.get('source_manifest_sha256')==manifest_sha,'stage manifest mismatch')
for rel,digest in manifest['frozen_files'].items():
 item=(SHARED/rel).resolve();need(under(item,SHARED) and sha(item)==digest,f'frozen input changed: {rel}')
leaf=REPORTS/'LEAF_ACCEPTANCE.json';leafdcp=OUT/'build/array16_ooc_clockless.dcp';leafg=load(leaf);need(leafg.get('status')=='PASS' and leafg.get('array_checkpoint_sha256')==sha(leafdcp) and leafg.get('partition_plan_sha256')==sha(REPORTS/'PARTITION_PLAN.json'),'leaf gate mismatch')
for receipt in [p,l]:need(receipt.get('leaf_acceptance_sha256')==sha(leaf) and receipt.get('leaf_checkpoint_sha256')==sha(leafdcp),'stage leaf binding mismatch')
parent=V/'build/parent_unlinked.dcp';pg=VR/'PARENT_ACCEPTANCE.json';g=load(pg);fresh(parent,ps,pe);need(g.get('status')=='PASS' and g.get('plan_sha256')==plan_sha and g.get('parent_checkpoint_sha256')==sha(parent) and g.get('process_receipt_sha256')==sha(pr),'parent gate mismatch');need(l.get('parent_acceptance_sha256')==sha(pg) and l.get('parent_checkpoint_sha256')==sha(parent),'link did not bind parent')
plog=Path(p['vivado_log']).resolve();llog=Path(l['vivado_log']).resolve();need(under(plog,V/'logs') and under(llog,V/'logs'),'stage log path wrong');fresh(plog,ps,pe);fresh(llog,ls,le);pt=text(plog);lt=text(llog);need(g.get('vivado_log_sha256')==sha(plog),'parent log differs');need('synth_design completed successfully' in pt and re.search(r'^PARENT_DCP_WRITTEN matrix/shared_array BB=1 FMA_LINKED=1\s*$',pt,re.M) and re.search(r'^PARENT_SYNTH_PASS\s*$',pt,re.M) and not re.search(r'^ERROR:',pt,re.M),'parent log incomplete');ip=(SHARED/'ip/asr_fma_ip/generated/asr_fma_ip.dcp').resolve();need(sha(ip)==EXPECTED_IP_DCP,'FMA checkpoint mismatch');imports=re.findall(r"\[Project 1-454\] Reading design checkpoint ['\"]([^'\"]+)['\"] for cell ['\"]([^'\"]+)['\"]",pt);need(any(Path(path).resolve()==ip and cell=='graph/vec/arithmetic/fused' for path,cell in imports) and 'Using original IP XDC constraints' in pt,'FMA actual import missing');leaf_imports=re.findall(r"\[Project 1-454\] Reading design checkpoint ['\"]([^'\"]+)['\"] for cell ['\"]([^'\"]+)['\"]",lt)
need('link_design completed successfully' in lt and re.search(r'^ARRAY_DCP_SCOPE=matrix/shared_array\s*$',lt,re.M) and re.search(r'^SCOPED_ARRAY_LINKED matrix/shared_array\s*$',lt,re.M) and re.search(r'^CANDIDATE_SYNTH_PASS\s*$',lt,re.M) and not re.search(r'^ERROR:',lt,re.M),'scoped link log incomplete')
need(any(Path(path).resolve()==leafdcp.resolve() and cell=='matrix/shared_array' for path,cell in leaf_imports),'actual expected leaf DCP import missing')
lg=VR/'LINK_ACCEPTANCE.json';linkg=load(lg);need(linkg.get('status')=='PASS' and linkg.get('plan_sha256')==plan_sha and linkg.get('parent_checkpoint_sha256')==sha(parent) and linkg.get('leaf_checkpoint_sha256')==sha(leafdcp) and linkg.get('linked_checkpoint_sha256')==sha(V/'build/candidate_synth.dcp') and linkg.get('process_receipt_sha256')==sha(lr) and linkg.get('vivado_log_sha256')==sha(llog),'link acceptance mismatch')

required=[V/'build/candidate_synth.dcp',VR/'synth_pass.txt',VR/'synthesized_array_shape.txt',VR/'utilization.rpt',VR/'timing.rpt'];parent_ip_status=VR/'retry2_ip_status.rpt';fresh(parent_ip_status,ps,pe)
for item in required:fresh(item,ls,le)
for item in [VR/'utilization_hier.rpt',VR/'drc.rpt',VR/'check_timing.rpt']:fresh(item,ls,le)
need(required[0].stat().st_size>0,'empty core checkpoint');need(re.search(r'^SYNTH_PASS BLACKBOX=0 MAX_NODES=128 FMA_LATENCY=12 PARTITIONED=1\s*$',text(required[1]),re.M),'core gate marker mismatch');shape=text(required[2]);need(re.search(r'^ARRAY_COUNT=1 PE_COUNT=256\s*$',shape,re.M) and len(re.findall(r'^ARRAY=',shape,re.M))==1,'array/PE shape mismatch')
timing = text(required[4])
need(re.search(r'^core_clk\s+\{[^}]+\}\s+20\.0+\s+50\.0+\s*$', timing, re.M), '20 ns clock absent from timing report')
ipstatus = text(parent_ip_status)
need(re.search(r'^\|\s*asr_fma_ip\s*\|\s*Up-to-date\s*\|\s*No changes required\s*\|', ipstatus, re.M | re.I), 'FMA IP status is not explicitly up-to-date')
util = text(required[3])
need(re.search(r'Design\s*:\s*v024_unified_top\b', util) and EXPECTED_PART in util.lower() and re.search(r'Design State\s*:\s*Synthesized', util), 'Utilization report design/part/state mismatch')
resources = {}
for label in ['CLB LUTs*', 'LUT as Memory', 'CLB Registers', 'CARRY8', 'F7 Muxes', 'F8 Muxes', 'F9 Muxes', 'Block RAM Tile', 'DSPs']:
    pattern = r'^\|\s*' + re.escape(label) + r'\s*\|\s*([\d,.]+)\s*\|\s*[\d,.]+\s*\|\s*[\d,.]+\s*\|\s*([\d,.]+)\s*\|\s*([\d,.]+)\s*\|'
    match = re.search(pattern, util, re.M)
    need(match, f'Cannot parse resource row: {label}')
    used, available, reported = (float(v.replace(',', '')) for v in match.groups())
    need(available > 0 and 0 <= used <= available and 0 <= reported <= 100, f'Resource exceeds device or invalid: {label}')
    need(abs(100 * used / available - reported) <= 0.06, f'Resource ratio inconsistent: {label}')
    resources[label] = {'used': used, 'available': available, 'percent': reported}
section = re.search(r'\n9\. Black Boxes\s*\n-+\s*(.*?)\n10\. Instantiated Netlists', util, re.S)
need(section is not None and not re.search(r'^\|\s*(?!Ref Name\b)[\w$./-]+\s*\|\s*\d+\s*\|', section[1], re.M), 'Black-box section missing or nonempty')
netlists = re.search(r'\n10\. Instantiated Netlists\s*\n-+\s*(.*?)(?:\n\d+\. |\Z)', util, re.S)
need(netlists and re.search(r'^\|\s*asr_fma_ip\s*\|\s*1\s*\|', netlists[1], re.M), 'FMA instantiated-netlist evidence missing')

plan=load(REPORTS/'IMPLEMENTATION_PLAN.json');need(plan.get('source_manifest_path')==str(manifest_path) and plan.get('source_manifest_sha256')==manifest_sha and plan.get('partition_plan_sha256')==sha(REPORTS/'PARTITION_PLAN.json'),'implementation plan source mismatch');need(plan.get('part')==EXPECTED_PART and plan.get('clock_period_ns')==20 and plan.get('required_array_instances')==1 and plan.get('required_pe_instances')==256,'implementation plan constraints mismatch');platform=OUT/'build/platform_synth_copy.dcp';implementation_script=OUT/'implement.tcl';need(sha(platform)==plan['platform_sha256'] and sha(implementation_script)==plan['script_sha256'],'implementation inputs mismatch')
artifacts=[(required[0],OUT/'build/candidate_synth.dcp'),(required[1],REPORTS/'synth_pass.txt'),(required[2],REPORTS/'synthesized_array_shape.txt'),(required[3],REPORTS/'utilization.rpt'),(required[4],REPORTS/'timing.rpt'),(VR/'utilization_hier.rpt',REPORTS/'utilization_hier.rpt'),(VR/'drc.rpt',REPORTS/'drc.rpt'),(VR/'check_timing.rpt',REPORTS/'check_timing.rpt'),(parent_ip_status,REPORTS/'parent_ip_status_v2.rpt')];target=REPORTS/'READY_FOR_IMPLEMENTATION.json';need(not target.exists() and all(not dst.exists() for _,dst in artifacts),'canonical destination exists; refusing overwrite')
for source,dest in artifacts:
 shutil.copy2(source,dest);need(sha(source)==sha(dest) and abs(source.stat().st_mtime-dest.stat().st_mtime)<0.01,f'copy verification failed: {dest}')
result={'status':'PASS','source_manifest_sha256':manifest_sha,'core_checkpoint_sha256':sha(OUT/'build/candidate_synth.dcp'),'platform_checkpoint_sha256':sha(platform),'implementation_script_sha256':sha(implementation_script),'functional_acceptance_sha256':sha(SHARED/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json'),'leaf_acceptance_sha256':sha(leaf),'leaf_checkpoint_sha256':sha(leafdcp),'partition_plan_sha256':sha(REPORTS/'PARTITION_PLAN.json'),'v2_plan_sha256':plan_sha,'parent_acceptance_sha256':sha(pg),'parent_checkpoint_sha256':sha(parent),'parent_receipt_sha256':sha(pr),'parent_log_sha256':sha(plog),'link_receipt_sha256':sha(lr),'link_log_sha256':sha(llog),'link_acceptance_sha256':sha(lg),'requires_post_core_port_identity':True,'fma_checkpoint_sha256':sha(ip),'part':EXPECTED_PART,'clock_period_ns':20,'array_count':1,'pe_count':256,'blackboxes':0,'resources':resources,'scope':'Two distinct OOC synthesis/link phases; no route, timing closure, or hardware claim'};target.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('V2_REVIEW_AND_CANONICAL_PUBLICATION_PASS')
