from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[2]
files=[x.strip() for x in (r/'filelist.f').read_text().splitlines() if x.strip()]
assert len(files)==50 and not any('forbidden_stub' in x for x in files)
files+=['filelist.f','scripts/deploy/core_ooc.xdc','scripts/deploy/synth_core128_ooc.tcl','build/project/v024_core.srcs/sources_1/ip/asr_fma_ip/asr_fma_ip.xci','build/project/v024_core.gen/sources_1/ip/asr_fma_ip/asr_fma_ip.dcp']
record={rel:hashlib.sha256((r/rel).read_bytes()).hexdigest() for rel in files}
manifest={'top':'v024_unified_top','MAX_NODES':128,'SEQ_ENABLE':0,'target_part':'xczu15eg-ffvb1156-2-i','vendor_fma':'AMD floating_point 7.1, FMA, 32-bit Single, NonBlocking, 12 cycles','production_files_sha256':record,'core_checkpoint':None}
p=r/'build/v024_core128_synth.dcp'
if p.is_file(): manifest['core_checkpoint']={'path':str(p.relative_to(r)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(r/'reports/DEPLOYMENT_SOURCE_SHA256.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('DEPLOYMENT_SOURCE_FROZEN',len(record),'files','CORE_CHECKPOINT_PRESENT',p.is_file())
