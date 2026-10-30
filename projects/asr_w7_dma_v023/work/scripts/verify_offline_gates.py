"""Aggregate current-source offline gates and verify previous frozen releases."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';ASYNC=ROOT.parent/'model_a_v0_21_1_board_20261013_001/async002'
gates=['vector_axi004','vendor_fma004','layout_rtl005','layout_cluster002','reuse_rtl002','alignment001','matrix_epoch001','plan_oracle001','csr001','im2col_slice001','protocol_native001'];rows=[]
for gate in gates:
    data=json.loads((ROOT/'reports'/gate/'result.json').read_text())
    if not data.get('passed'):raise ValueError('Gate failed '+gate)
    hashes=data.get('source_sha256',{})
    for name,sha in (hashes.items() if isinstance(hashes,dict) else []):
        if name.startswith(str(ROOT/'rtl')) and hashlib.sha256(Path(name).read_bytes()).hexdigest()!=sha:raise ValueError('RTL changed '+name)
    rows.append(dict(gate=gate,passed=True,hardware_accessed=data['hardware_accessed']))
if not json.loads((ROOT/'reports/plan_oracle001/result.json').read_text())['all68_programs']:raise ValueError('Missing68 plans')
logs=[]
for p in (BASE/'scripts/seal_runtime.py',ASYNC/'scripts/seal_variant.py'):
    cp=subprocess.run([sys.executable,'-I','-B','-X','utf8',str(p),'--verify'],cwd=ROOT,capture_output=True,text=True,timeout=180)
    logs.append(dict(script=str(p),returncode=cp.returncode,output=cp.stdout+cp.stderr));print(cp.stdout,flush=True);cp.check_returncode()
tag=sys.argv[1] if len(sys.argv)>1 else 'offline_gates001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,fullboard_signoff_pending=True,not_yet_hardware_tested=True,gates=rows,sealed_previous_releases=logs),indent=2)+'\n',encoding='utf-8')
print('V022_CURRENT_SOURCE_OFFLINE_GATES_PASS; fullboardSTA/DRC and hardware stillpending')
