from pathlib import Path
import hashlib,json
r=Path('.')
f=json.loads((r/'sim/fixtures/REFERENCE_FREEZE.json').read_text())
out=[]
for name,want in f.items():
 b=(r/name).read_bytes(); got=hashlib.sha256(b).hexdigest(); canonical=hashlib.sha256(b.replace(b'\r\n',b'\n')).hexdigest()
 out.append({'file':name,'expected':want,'actual':got,'lf_canonical':canonical,'exact':got==want,'lf_canonical_matches':canonical==want})
print(json.dumps(out,indent=2))
(r/'reports/fixture_original_freeze_comparison.json').write_text(json.dumps(out,indent=2)+'\n')
