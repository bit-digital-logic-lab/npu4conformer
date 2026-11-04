from pathlib import Path
import hashlib,json,shutil
r=Path('.')
mods=[]
for rel in ['rtl/graph/v024_unified_top.sv','rtl/graph/v023_integrated_top.sv']:
 p=r/rel;s=p.read_text(); old=hashlib.sha256(p.read_bytes()).hexdigest()
 needle=' parameter integer PIPE_STAGES = 4,'
 assert s.count(needle)==1
 s=s.replace(needle,' // AXU15EGB bounded small-graph deployment; not a 591-node model configuration.\n parameter integer MAX_NODES = 128,\n'+needle)
 needle='wc_graph_top_v023 #(.ARENA_BASE'
 assert s.count(needle)==1
 s=s.replace(needle,'wc_graph_top_v023 #(.MAX_NODES(MAX_NODES),.ARENA_BASE')
 p.write_text(s,encoding='utf-8',newline='\n')
 mods.append({'path':rel,'original_sha256':old,'deployed_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'change':'Add MAX_NODES=128 top parameter and pass to graph controller. No WCPG ABI or arithmetic change.'})
(r/'reports/RTL_PATCHES.json').write_text(json.dumps(mods,indent=2)+'\n')
src=Path(r'C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023')
shutil.copy2(src/'v024_opt/ds_final_organize/final_export/sim/tb/tb_safety_integrated.sv',r/'sim/tb/tb_safety_integrated.sv')
for name in ['mem_normal.hex','mem_multitask.hex','mem_bad_queue_magic.hex','mem_bad_vec_op.hex']:
 shutil.copy2(src/'v023_repair/ds_closeout_safety/fixtures'/name,r/'sim/fixtures'/name)
print('Configured both V024 unified and legacy-baseline top MAX_NODES=128; restored four sourced baseline fixtures')
