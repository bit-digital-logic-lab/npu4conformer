from pathlib import Path
import json,hashlib,re
r=Path(__file__).resolve().parents[2];d=r/'analysis/iterhash_logs';rows=[]
for state in (10,11):
 name=f'v024_genfault_{state}';log=(d/(name+'.log')).read_text();out=(d/(name+'_out.hex')).read_text().split()
 assert f'ITERHASH_GENERATION_INJECT state={state} hash_word=4' in log
 assert 'V024_RESULT PASS' in log and not re.search(r'Fatal:|FATAL|RESULT FAIL|ERROR:',log)
 assert 'V024_END done=1 fault=1 error=02' in log and 'completed=0' in log
 assert 'V024_DRAIN rd_pending=0 wr_pending=0 b_pending=0 quiesced=1' in log
 assert 'vec_ops=0 layout_ops=0 matrix_ops=0' in log
 assert len(out)==8192 and all(0<=int(x,16)<=0xffffffff for x in out)
 rows.append({'state':state,'phase':'HHASH' if state==10 else 'NHASH','status':'PASS','injected_at_word':4,'expected_error':'02','completed':0,'new_fetch_or_dispatch_after_invalidation':False,'port_quiesced':True})
report={'status':'PASS','candidate_sha256':hashlib.sha256((r/'analysis/wc_graph_ctrl_iterhash.sv').read_bytes()).hexdigest(),'generation_invalidation_cases':rows}
(r/'analysis/GENERATION_INVALIDATION_CHECKS.json').write_text(json.dumps(report,indent=2)+'\n')
print('ITERHASH_GENERATION_NEGATIVE_PASS',len(rows),'cases')
