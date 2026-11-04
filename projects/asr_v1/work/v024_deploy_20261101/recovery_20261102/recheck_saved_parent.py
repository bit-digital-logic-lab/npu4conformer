"""Re-qualify the saved netlist after the postprocess-only publisher drift.
The Vivado process receipt is immutable. This is an independent artifact review,
not a second claim that the original Python validator exited successfully.
"""
from pathlib import Path
import datetime as dt, hashlib, json, re, zipfile
R=Path(__file__).resolve().parent
P=R/'partitioned_shared16'
V=P/'retry_parent_v2'
S=R/'shared16_candidate'
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
def need(b,m):
    if not b:raise ValueError(m)
rec=V/'reports/parent_20261102_135930_process.json'
d=load(rec);plan=V/'PLAN.json';pp=load(plan);log=Path(d['vivado_log'])
need(d['status']=='PROCESS_EXITED' and d['stage']=='parent' and d['exit_code']==0,'No successful Vivado process')
need(sha(plan)==d['plan_sha256']=='8079e5831c310e21dac9dd862257a7f0bffd730528d90cd87369829761101446','Parent plan mismatch')
for path,h in pp['inputs'].items():need(sha(Path(path))==h,'Frozen plan input drift: '+path)
published=R/'review_partitioned_v2_publish.py';changed=R/'review_partitioned_v3_publish.py'
need(sha(published)==pp['inputs'][str(published)] and changed.exists(),'Postprocessor versions not preserved')
tcl=V/'synth_parent.tcl'
need(sha(tcl)==d['script_sha256'] and 'publish.py' not in tcl.read_text() and 'exec ' not in tcl.read_text(),'Unexpected external postprocessor in synth flow')
manifest=S/'reports/SOURCE_MANIFEST.json';m=load(manifest)
for rel,h in m['frozen_files'].items():
    path=(S/rel).resolve();need(path.is_relative_to(S) and sha(path)==h,'Frozen RTL/fixture drift: '+rel)
need(sha(manifest)==d['source_manifest_sha256'] and load(S/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json')['status']=='PASS','Source review mismatch')
leaf=P/'reports/LEAF_ACCEPTANCE.json';need(sha(leaf)==d['leaf_acceptance_sha256'] and load(leaf)['array_checkpoint_sha256']==sha(P/'build/array16_ooc_clockless.dcp')==d['leaf_checkpoint_sha256'],'Leaf mismatch')
first=dt.datetime.fromisoformat(d['started']).timestamp();last=dt.datetime.fromisoformat(d['finished']).timestamp()
net=V/'build/parent_unlinked.dcp';util=V/'reports/parent_utilization.rpt'
for f in [net,util,log,V/'reports/parent_timing.rpt',V/'reports/parent_pass.txt',V/'reports/retry2_ip_status.rpt']:
    need(f.is_file() and f.stat().st_size and first<=f.stat().st_mtime<=last+5,'Stale or missing '+str(f))
with zipfile.ZipFile(net) as z:
    need(z.testzip() is None and z.getinfo('v024_unified_top.edf').file_size>100000,'Incomplete synthesized checkpoint')
t=log.read_text(errors='replace');u=util.read_text()
need(not re.search(r'^ERROR:',t,re.M) and 'synth_design completed successfully' in t and 'Using original IP XDC constraints' in t,'Vivado stage failed')
for tag in ('PARENT_DCP_WRITTEN matrix/shared_array BB=1 FMA_LINKED=1','PARENT_SYNTH_PASS'):
    need(tag in t.splitlines(),'Missing runtime event '+tag)
need((V/'reports/parent_pass.txt').read_text().strip()=='PARENT_SYNTH_PASS BB=1 FMA_LINKED=1 MAX_NODES=128','Missing parent marker')
ip=S/'ip/asr_fma_ip/generated/asr_fma_ip.dcp'
imports=re.findall(r"\[Project 1-454\] Reading design checkpoint '([^']+)' for cell '([^']+)'",t)
need(any(Path(s).resolve()==ip and n=='graph/vec/arithmetic/fused' for s,n in imports),'FMA import absent')
warnings=[s for s in t.splitlines() if s.startswith('CRITICAL WARNING:')]
need(len(warnings)==1 and 'matrix/shared_array' in warnings[0] and 'Project 1-486' in warnings[0],'Other critical warnings found')
need(re.search(r'^\|\s*array16_w7_c48_cfg\s*\|\s*1\s*\|',u,re.M) and re.search(r'^\|\s*asr_fma_ip\s*\|\s*1\s*\|',u,re.M),'Parent netlist/blackbox report mismatch')
result={'status':'PASS','scope':'independently re-reviewed synthesized parent only; one intentional array blackbox',
        'plan_sha256':sha(plan),'parent_checkpoint_sha256':sha(net),'process_receipt_sha256':sha(rec),
        'vivado_log_sha256':sha(log),'source_manifest_sha256':sha(manifest),'leaf_acceptance_sha256':sha(leaf),
        'original_python_launcher_exit':1,'original_vivado_exit':0,'first_validator_failure':'postprocessor file changed during build; no synth input changed',
        'postprocessor_restored_sha256':sha(published),'separate_later_publisher_sha256':sha(changed),
        'reviewed_at':dt.datetime.now().astimezone().isoformat(),'review_script_sha256':sha(Path(__file__))}
with (V/'reports/PARENT_ACCEPTANCE.json').open('x') as f:json.dump(result,f,indent=2)
print('SAVED_PARENT_INDEPENDENT_REVIEW_PASS',sha(net))
