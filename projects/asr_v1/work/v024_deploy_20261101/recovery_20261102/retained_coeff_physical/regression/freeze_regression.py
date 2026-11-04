from pathlib import Path
import json,hashlib,shutil
O=Path(__file__).resolve().parent;R=O.parent.parent;B=R/'shared16_candidate';F=R/'retained_coeff_fix';gate=F/'reports/ACCEPTANCE.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def need(c,m):
 if not c:raise RuntimeError(m)
need(gate.is_file(),'repair acceptance not yet available');g=json.loads(gate.read_text(encoding='utf-8-sig'));need(g.get('status')=='PASS','repair acceptance has not passed')
items={'epilogue_stream_engine_v024.sv':'epilogue','matrix_stream_fusion_top_v024.sv':'epilogue','v024_matrix_queue_engine.sv':'graph'}
need(len(g.get('overlay',[]))==3,'wrong repair overlay count')
need(all(g.get(k) is True for k in ('baseline_bug_reproduced','hard_reset_defaults_verified','reset_parameter_handshake_blocked','data_plane_reset_unchanged','all_steps_exit_zero')) and g.get('retained_table_words')==64 and g.get('retained_broadcast_words')==2 and g.get('real_numeric_beats_checked')==7 and g.get('remaining_unit_processes')==[],'repair validation facts incomplete')
for x in g['overlay']:
 need(sha(Path(x['source']))==x['source_sha256'] and sha(Path(x['selected']))==x['selected_sha256'],'repair acceptance source hash mismatch')
receipt=Path(g['process_receipt']);need(sha(receipt)==g['process_receipt_sha256'],'repair process receipt changed');z=json.loads(receipt.read_text(encoding='utf-8-sig'));need(z.get('exit_code')==0,'repair test actual exit failed')

filelist=[x.strip() for x in (O/'core/filelist.f').read_text().splitlines() if x.strip()]
for name,sub in items.items():
 src=F/'rtl'/name;dst=O/'core/rtl'/sub/name;need(src.is_file() and dst.is_file(),f'missing {name}');need(f'rtl/{sub}/{name}' in filelist,'filelist mismatch');shutil.copy2(src,dst);need(sha(src)==sha(dst),'copy mismatch')
changed=[]
for rel in filelist:
 a=O/'core'/rel;b=B/'core'/rel;need(a.is_file() and b.is_file(),'source missing '+rel)
 if sha(a)!=sha(b):changed.append(rel)
need(set(changed)=={f'rtl/{sub}/{name}' for name,sub in items.items()},f'unexpected source differences: {changed}')
inputs=[]
for root in ['core','scripts']:
 inputs.extend(p for p in (O/root).rglob('*') if p.is_file())
inputs.extend([O/'ip/asr_fma_ip/asr_fma_ip.xci',O/'ip/asr_fma_ip/generated/asr_fma_ip.dcp',Path(__file__).resolve(),O/'run_regression.py',gate]); hashes={str(p.resolve()):sha(p) for p in sorted(inputs)}
plan={'status':'PREPARED_NOT_RUN','scope':'17+2 real xsim independent review against preserved baseline','fix_acceptance_sha256':sha(gate),'changed_rtl':changed,'inputs':hashes}
p=O/'REGRESSION_PLAN.json';need(not p.exists(),'do not overwrite frozen plan');p.write_text(json.dumps(plan,indent=2)+'\n');print('PLAN',sha(p),'INPUTS',len(hashes),'CHANGED',changed)



