from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[2]
old=[x.strip() for x in (r/'filelist.f').read_text().splitlines() if x.strip()]
files=['analysis/wc_graph_ctrl_iterhash.sv' if x=='rtl/graph/wc_graph_ctrl.sv' else x for x in old]
(r/'filelist_iterhash.f').write_text('\n'.join(files)+'\n',newline='\n')
files+=['filelist_iterhash.f','scripts/deploy/core_ooc.xdc','scripts/deploy/synth_core128_iterhash_ooc.tcl','build/project/v024_core.srcs/sources_1/ip/asr_fma_ip/asr_fma_ip.xci','build/project/v024_core.gen/sources_1/ip/asr_fma_ip/asr_fma_ip.dcp']
record={name:hashlib.sha256((r/name).read_bytes()).hexdigest() for name in files}
m={'status':'SELECTED_FOR_OOC; board not yet verified','top':'v024_unified_top','MAX_NODES':128,'SEQ_ENABLE':0,'target_part':'xczu15eg-ffvb1156-2-i','source_controller_override':'analysis/wc_graph_ctrl_iterhash.sv','production_files_sha256':record,'core_checkpoint':None}
p=r/'build/v024_core128_iterhash_synth.dcp'
if p.is_file():m['core_checkpoint']={'path':str(p.relative_to(r)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(r/'reports/DEPLOYMENT_ITERHASH_SOURCE_SHA256.json').write_text(json.dumps(m,indent=2)+'\n')
a=r/'analysis/ITERHASH_MANIFEST.json';meta=json.loads(a.read_text());meta['status']='SELECTED_FOR_OOC_VIA_SOURCE_OVERRIDE_ORIGINAL_RTL_PRESERVED';meta['regression']='REGRESSION_ITERHASH.json:17 strict passes';meta['measured_fused_cycles']={'original_TB':18731,'iterhash_TB':19061,'original_CSR':18474,'iterhash_CSR':18804,'measured_delta':330,'hash_state_cycles_added':352,'other_cycles_net_change':-22};a.write_text(json.dumps(meta,indent=2)+'\n')
print('SELECTED_ITERHASH_SOURCE_FROZEN',len(record),'files','DCP_PRESENT',p.is_file())
