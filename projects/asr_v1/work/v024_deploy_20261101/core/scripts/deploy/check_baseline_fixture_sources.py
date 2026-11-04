from pathlib import Path
import hashlib,json
r=Path('.');src=Path(r'C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023/v023_repair/ds_closeout_safety/fixtures')
rows=[]
for name in ['mem_normal.hex','mem_multitask.hex','mem_bad_queue_magic.hex','mem_bad_vec_op.hex']:
 a=hashlib.sha256((src/name).read_bytes()).hexdigest();b=hashlib.sha256((r/'sim/fixtures'/name).read_bytes()).hexdigest();assert a==b
 rows.append({'file':name,'sha256':a,'exact_copy':True})
(r/'reports/BASELINE_FIXTURE_PROVENANCE.json').write_text(json.dumps({'source':str(src),'purpose':'Original baseline compatibility tests only; not replacing V024 core','files':rows},indent=2)+'\n')
print('BASELINE_FIXTURE_PROVENANCE_VERIFIED',len(rows))
