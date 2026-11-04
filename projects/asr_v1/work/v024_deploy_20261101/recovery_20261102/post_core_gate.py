"""Validate independent post-core acceptance; no EDA execution or side effects."""
from pathlib import Path
import hashlib,json,math

def need(v,message):
 if not v: raise RuntimeError(message)
def sha(path):
 need(path.is_file(),f'missing file: {path}');return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def verify_postcore(receipt_path,candidate,ready):
 candidate=Path(candidate).resolve();receipt_path=Path(receipt_path).resolve();base=(candidate/'reports').resolve();folder=receipt_path.parent
 need(folder.is_relative_to(base) and folder.parent==base and folder.name.startswith('postcore_') and receipt_path.name=='PROCESS_RECEIPT.json','post-core receipt outside expected directory')
 d=load(receipt_path);accept_path=folder/'POST_CORE_ACCEPTANCE.json';a=load(accept_path)
 need(d.get('stage')=='post_core_read_only_checks' and d.get('status')=='PROCESS_EXITED' and type(d.get('exit_code')) is int and d['exit_code']==0,'post-core process did not exit successfully')
 exits=d.get('actual_vivado_exit_codes');need(isinstance(exits,list) and len(exits)>0 and all(type(x.get('exit_code')) is int and x['exit_code']==0 for x in exits),'actual Vivado exit not confirmed')
 need(d.get('descendant_check_verified') is True and d.get('remaining_EDA_processes')==[] and d.get('inputs_unchanged_after_run') is True,'process descendants or bound inputs not verified')
 need(any(x.get('Name','').lower()=='vivado.exe' for x in d.get('tracked_EDA_processes',[])),'actual Vivado process not observed')
 tracked={(x.get('ProcessId'),x.get('birth')) for x in d.get('tracked_EDA_processes',[]) if x.get('Name','').lower()=='vivado.exe'};need(all((x.get('pid'),x.get('birth')) in tracked for x in exits),'actual Vivado exit identity not tied to tracked process')
 need(Path(d['output_dir']).resolve()==folder and Path(d['checks_kv']).resolve()==folder/'checks.kv','receipt output paths mismatch')
 need(a.get('status')=='STRUCTURAL_TIMING_COVERAGE_ACCEPTED' and a.get('scope')=='post-synthesis partitioned-core structural/clock/timing coverage only; not routed timing closure' and a.get('routed_timing_closed') is False,'post-core review did not pass OOC coverage')
 need(a.get('receipt_sha256')==sha(receipt_path) and a.get('actual_exit_code')==0 and a.get('owned_EDA_descendants_verified_exited') is True,'post-core acceptance not bound to successful receipt')
 need(a.get('interface_bit_count')==12727 and type(a.get('leaf_FF_count')) is int and a['leaf_FF_count']>0 and a.get('leaf_FF_clocked')==a['leaf_FF_count'],'post-core interface or clock coverage incomplete')
 need(a.get('check_timing')=={'no_clock':0,'unconstrained_internal_endpoints':0,'loops':0,'latch_loops':0},'OOC timing coverage incomplete')
 slacks=a.get('actual_slacks_ns');names={f'{part}_{delay}' for part in ('parent_to_leaf','leaf_to_parent','leaf_internal','core') for delay in ('max','min')};need(isinstance(slacks,dict) and set(slacks)==names and all(type(x) in (int,float) and math.isfinite(x) and x>=0 for x in slacks.values()) and a.get('negative_slacks_ns')=={},'post-core OOC slack review did not pass')
 core=(candidate/'build/candidate_synth.dcp').resolve();leaf=(candidate/'build/array16_ooc_clockless.dcp').resolve();need(Path(d['core_dcp']).resolve()==core and Path(d['leaf_dcp']).resolve()==leaf,'post-core receipt used a different core or leaf')
 need(sha(core)==ready['core_checkpoint_sha256'] and sha(leaf)==ready['leaf_checkpoint_sha256'],'post-core core/leaf does not match reviewed synthesis')
 input_hashes=d.get('inputs_sha256');need(isinstance(input_hashes,dict) and input_hashes==a.get('inputs_sha256'),'post-core input binding missing')
 for name,digest in input_hashes.items():need(sha(Path(name))==digest,f'post-core bound input changed: {name}')
 need(input_hashes.get(str(core))==ready['core_checkpoint_sha256'] and input_hashes.get(str(leaf))==ready['leaf_checkpoint_sha256'],'core/leaf not hash-bound by post-core process')
 core_receipt=Path(d['core_receipt']).resolve();need(input_hashes.get(str(core_receipt))==sha(core_receipt)==ready.get('link_receipt_sha256'),'post-core did not inspect the reviewed v2 link output')
 reviewer=(candidate/'post_core_review/review_post_core.py').resolve();need(input_hashes.get(str(reviewer))==sha(reviewer),'independent reviewer not bound')
 artifacts=a.get('artifact_sha256');need(isinstance(artifacts,dict) and len(artifacts)>0,'post-core artifact hashes missing')
 required={'checks.kv','vivado.log','PROCESS_RECEIPT.json','leaf_ports.tsv','linked_pins.tsv','leaf_ff_relative.txt','linked_ff_relative.txt','leaf_ff_without_core_clock.txt','check_timing.rpt','timing_summary.rpt'} | {f'{name}.rpt' for name in names}
 need(required.issubset(artifacts),'post-core artifact set incomplete')
 for name,digest in artifacts.items():
  path=(folder/name).resolve();need(path.is_relative_to(folder) and sha(path)==digest,f'post-core artifact changed: {name}')
 facts={};statuses=[]
 for line in (folder/'checks.kv').read_text().splitlines():
  need('=' in line,'malformed post-core facts');key,value=line.split('=',1)
  if key=='status': statuses.append(value)
  else: need(key not in facts,'duplicate post-core fact '+key);facts[key]=value
 need(statuses==['NOT_COMPLETED','CHECKS_COMPLETED_REVIEW_REQUIRED'],'post-core facts incomplete')
 for key,value in {'leaf_clockless':'1','leaf_blackboxes':'0','core_blackboxes':'0','leaf_bit_ports':'12727','exact_leaf_interface':'1','leaf_and_linked_PE_count':'256','core_clock_name':'core_clk','leaf_clock_pin_core_clk':'1','leaf_ff_missing_clock':'0','leaf_ff_names_preserved':'1','no_clock':'0','unconstrained_internal_endpoints':'0','loops':'0','latch_loops':'0','scope':'SYNTHESIZED_CORE_ONLY_NOT_ROUTED_CLOSURE'}.items():need(facts.get(key)==value,'post-core fact mismatch: '+key)
 need(abs(float(facts['core_clock_period_ns'])-20.0)<0.001 and int(facts['leaf_ff_count'])==int(facts['leaf_ff_clocked'])==a['leaf_FF_count'],'post-core facts do not match acceptance')
 for name in names:need(float(facts[name+'_worst_slack'])==slacks[name],'post-core slack facts differ: '+name)
 need((folder/'leaf_ff_without_core_clock.txt').read_text()=='','post-core missing-clock FF list is not empty')
 return {'receipt_path':str(receipt_path),'receipt_sha256':sha(receipt_path),'acceptance_path':str(accept_path),'acceptance_sha256':sha(accept_path),'core_checkpoint_sha256':sha(core),'scope':'OOC structural/clock coverage and OOC slack screen; routed closure remains unproven'}
