from pathlib import Path
import json,importlib.util,hashlib,sys
D=Path(__file__).resolve().parent;R=D.parent;ready=json.loads((D/'reports/READY_FOR_IMPLEMENTATION.json').read_text());receipt=Path(sys.argv[1]).resolve();spec=importlib.util.spec_from_file_location('gate',R/'post_core_gate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);v=m.verify_postcore(receipt,D,ready)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
out=D/'reports/POST_CORE_ACCEPTANCE.json';assert not out.exists();out.write_text(json.dumps({'status':'PASS','scope':'independent post-core structural and OOC checks; not routed closure','core_checkpoint_sha256':sha(D/'build/candidate_synth.dcp'),'underlying_receipt':str(receipt),'underlying_receipt_sha256':sha(receipt),'underlying_acceptance_sha256':v['acceptance_sha256']},indent=2)+'\n');print('POST_CORE_BOUND_PASS')
