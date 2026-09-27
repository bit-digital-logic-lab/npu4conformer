"""Record artifact hashes and already completed physical acceptance evidence."""
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
asr=root.parent
hardware=json.loads((root/'reports/benchmark_hardware.json').read_text())
v1=json.loads((root/'reports/comparison_v1.json').read_text())
v2=json.loads((root/'reports/comparison_v2.json').read_text())
assert hardware['pass'] and hardware['physical_fpga_executed']
assert v1['pass_all'] and v2['pass_all']
files=list((root/'rtl').glob('*.sv'))+list((root/'host').glob('*.py'))+list((root/'scripts').glob('*'))
files+=[root/'PROTOCOL_V2.md',root/'build/board_build_921600/asr_v2_ax7035.bit']
manifest=dict(recorded_utc=datetime.now(timezone.utc).isoformat(),
              physical_operator_acceptance=True, full_model_inference_completed=False,
              fpga='xc7a35tfgg484-2', board_identification='photo matches ALINX AX7035 older board',
              clock_hz=50000000,baud=921600,user_access='A5160002',flash_written=False,
              resources=dict(lut=6653,ff=2168,dsp=6,bram36=32,bram36_available=50),
              timing_ns=dict(setup_slack=0.063,hold_slack=0.070),
              physical_test_count=len(hardware['tests']),comparisons=[],sha256={})
for a,b in zip(v1['tests'],v2['tests']):
    assert a['name']==b['name'] and a['pass'] and b['pass']
    manifest['comparisons'].append(dict(name=a['name'],v1_seconds=a['elapsed_seconds'],
                                        v2_seconds=b['elapsed_seconds'],
                                        speedup=a['elapsed_seconds']/b['elapsed_seconds']))
for path in files:
    if path.is_file():
        manifest['sha256'][path.relative_to(asr).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
freeze=asr/'releases/v1_20260922_board_verified/FREEZE_MANIFEST.json'
manifest['v1_freeze_manifest_sha256']=hashlib.sha256(freeze.read_bytes()).hexdigest()
destination=root/'reports/board_acceptance.json'
destination.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(destination)
