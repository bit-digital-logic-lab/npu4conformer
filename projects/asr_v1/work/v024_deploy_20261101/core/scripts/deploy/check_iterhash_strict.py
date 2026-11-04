"""Strict independent acceptance for bounded128 simulation; no hardware claim."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
R=Path(__file__).resolve().parents[2];F=R/'sim/fixtures';L=R/'analysis/iterhash_logs'
def need(cond,msg):
 if not cond: raise AssertionError(msg)
def words(path,n):
 out=[int(v,16) for v in path.read_text().split()]
 need(len(out)==n,f'{path.name}: words {len(out)} != {n}')
 need(all(0<=x<=0xffffffff for x in out),f'{path.name}: non-32-bit value')
 return out
frozen=json.loads((F/'REFERENCE_FREEZE.json').read_text())
for rel,expected in frozen.items(): need(hashlib.sha256((R/rel).read_bytes()).hexdigest()==expected,f'Golden/input SHA mismatch: {rel}')
cases=['v024_fused','v024_fallback','v024_multicons','v024_badflag','v024_hold','v024_bound128','v024_over129','v024_baddep128','v024_badcrc_stored','v024_badcrc_header','v024_badcrc_node','base_normal','base_multitask','base_bad_queue_magic','base_bad_vec_op','base_hold_b_c','v024_lane']
rows=[]
for name in cases:
 log=(L/(name+'.log')).read_text(errors='replace')
 marker='V024_LANE_RESULT PASS' if name=='v024_lane' else ('SAFETY_RESULT PASS' if name.startswith('base_') else 'V024_RESULT PASS')
 need(marker in log,f'{name}: missing exact PASS marker')
 need(not re.search(r'(?:RESULT FAIL|Fatal:|FATAL|\bTIMEOUT\b|ERROR:)',log),f'{name}: fatal/failure marker')
 count=64 if name=='v024_lane' else (512 if name.startswith('base_') else 8192)
 words(L/(name+'_out.hex'),count)
 if name in ['v024_fused','v024_fallback','v024_multicons','v024_bound128','base_normal','base_multitask']:
  need(re.search(r'(?:V024|SAFETY)_DRAIN .*rd_pending=0 wr_pending=0 b_pending=0 quiesced=1',log),f'{name}: not completely drained')
 if name=='v024_bound128': need('completed=128' in log,f'{name}: did not complete all128 nodes')
 if name in ['v024_over129','v024_baddep128']:
  need(re.search(r'V024_END done=1 fault=1 error=04',log),f'{name}: wrong bounds failure')
  need('completed=0' in log,f'{name}: dispatched before validating bounds')
 m=re.search(r'(?:V024|SAFETY)_END .*cycles=(\d+)',log)
 rows.append({'case':name,'status':'PASS','output_words':count,'cycles':int(m.group(1)) if m else None})
# Existing independent arithmetic checker is safe after these complete-length and freeze guards.
import importlib.util
spec=importlib.util.spec_from_file_location('original_judge',R/'scripts/analysis/check_export.py')
judge=importlib.util.module_from_spec(spec);spec.loader.exec_module(judge);judge.LOG=L
need(judge.main()==0,'Independent numerical judge failed')
need(words(L/'v024_fused_out.hex',8192)==words(R/'logs/v024_fused_out.hex',8192),'Candidate fused differs from original 128-node result')
for name in ['v024_fused','v024_bound128']:
 log=(L/(name+'.log')).read_text()
 m=re.search(r'ITERHASH_FINAL computed=([0-9a-f]+) expected=([0-9a-f]+) header_steps=(\d+) node_steps=(\d+)',log)
 need(m is not None and m[1]==m[2],name+': hash mismatch')
 need(int(m[3])==16,name+': header traversal count wrong')
 need(int(m[4])==(7 if name=='v024_fused' else 128)*48,name+': node traversal count wrong')
for name in ['v024_badcrc_stored','v024_badcrc_header','v024_badcrc_node']:
 log=(L/(name+'.log')).read_text()
 m=re.search(r'ITERHASH_FINAL computed=([0-9a-f]+) expected=([0-9a-f]+)',log)
 need(m is not None and m[1]!=m[2],name+': mutation not rejected by final checksum')
 need('completed=0' in log and 'V024_END done=1 fault=1 error=04' in log,name+': checksum rejection wrong terminal state')
report={'status':'PASS','candidate_sha256':hashlib.sha256((R/'analysis/wc_graph_ctrl_iterhash.sv').read_bytes()).hexdigest(),'fused_8192_words_bit_exact_vs_original128':True,'scope':'ITERATIVE HASH CANDIDATE, MAX_NODES=128, real vendor FMA IP XSim; original11+boundary3+checksum3; no synthesis or board claim','cases':rows}
(R/'analysis/REGRESSION_ITERHASH.json').write_text(json.dumps(report,indent=2)+'\n')
print('V024_ITERHASH_REGRESSION_STRICT_PASS',len(rows),'cases')
