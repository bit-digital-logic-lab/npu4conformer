from pathlib import Path
import hashlib, json, shutil
src=Path(r'C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023/v024_opt/ds_final_organize/final_export')
dst=Path(r'C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/core')
files=[x.strip() for x in (src/'filelist.f').read_text(encoding='utf-8').splitlines() if x.strip() and not x.strip().startswith('//')]
files=[x for x in files if not x.endswith('fma_forbidden_stub.sv')]
extra=['README.md','scripts/sim/gen_v024_graph.py','scripts/sim/graph_common.py','scripts/analysis/gen_matrix_gold.py','scripts/analysis/check_export.py','sim/tb/tb_v024_unified.sv','sim/tb/wc_safety_bfm.sv','sim/tb/tb_v024_epilogue.sv','sim/fixtures/mat32/init.hex','sim/fixtures/mat32/exp_c.txt','sim/fixtures/mat32/manifest.json','sim/fixtures/REFERENCE_FREEZE.json','sim/fixtures/gold_a16.hex','sim/fixtures/gold_fallback_i16.hex','sim/fixtures/lane_gold.hex','sim/fixtures/lane_muladd.hex','sim/fixtures/lane_vectors.hex','sim/fixtures/v024_ref.json','software/CSR_MAP.md']
record={}
for rel in files+extra:
 p=src/rel;q=dst/rel;q.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(p,q)
 record[rel]=hashlib.sha256(q.read_bytes()).hexdigest()
(dst/'filelist.f').write_text('\n'.join(files)+'\n',encoding='utf-8')
(dst/'SOURCE_IMPORT_SHA256.json').write_text(json.dumps({'source_root':str(src),'excluded':['rtl/common/fma_forbidden_stub.sv'],'imported_sha256':record},indent=2)+'\n')
(dst/'scripts/deploy').mkdir(parents=True,exist_ok=True)
(dst/'logs').mkdir(exist_ok=True)
(dst/'reports').mkdir(exist_ok=True)
print('IMPORTED',len(files),'RTL files;',len(extra),'support files')
