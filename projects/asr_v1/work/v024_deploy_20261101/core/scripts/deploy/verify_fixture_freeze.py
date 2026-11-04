from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[2]
frozen=json.loads((root/'sim/fixtures/REFERENCE_FREEZE.json').read_text())
for name,want in frozen.items():
 p=root/name; raw=p.read_bytes(); canonical=raw.replace(b'\r\n',b'\n')
 assert hashlib.sha256(canonical).hexdigest()==want, f'Content mismatch: {name}'
 p.write_bytes(canonical)
actual={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in frozen}
assert actual==frozen
(root/'reports/FIXTURE_SHA256_VERIFIED.json').write_text(json.dumps({'status':'PASS','normalization':'CRLF to LF only, after canonical SHA matches original freeze','sha256':actual},indent=2)+'\n')
print('FIXTURE_FREEZE_PASS',len(frozen),'files exactly match archived SHA256 after LF normalization')
