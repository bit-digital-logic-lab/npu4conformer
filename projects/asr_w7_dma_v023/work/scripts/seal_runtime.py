"""Fresh content manifest binds candidate RTL/ELF/image/tests to signed-off bit."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verify(tag='full002'):
    path=ROOT/'reports'/f'release_{tag}.json';r=json.loads(path.read_text())
    for name,h in r['files'].items():
        if sha(ROOT/name)!=h:raise ValueError('Release file changed '+name)
    if not r['offline_gates_passed']:raise ValueError('No offline signoff')
    return r
if __name__=='__main__':
    tag=sys.argv[1] if len(sys.argv)>1 else 'full002';path=ROOT/'reports'/f'release_{tag}.json'
    if '--verify' in sys.argv:verify(tag);print('V022_RUNTIME_SEAL_VERIFIED');raise SystemExit
    if path.exists():raise ValueError('Fresh release')
    build=ROOT/'soc_full/build'/tag;result=(build/'result.txt').read_text()
    if 'V022_FULL_BUILD_PASS' not in result:raise ValueError('Fullboard build not signed off')
    gates=['vector_axi004','vendor_fma004','layout_rtl005','layout_cluster002','reuse_rtl002','alignment001','matrix_epoch001','plan_oracle001','csr001','im2col_slice001','protocol_native001']
    for gate in gates:
        data=json.loads((ROOT/'reports'/gate/'result.json').read_text())
        if not data.get('passed'):raise ValueError('Offline gate '+gate)
        hashes=data.get('source_sha256',{})
        for source,h in (hashes.items() if isinstance(hashes,dict) else []):
            if source.startswith(str(ROOT/'rtl')) and sha(Path(source))!=h:raise ValueError('Gate source changed '+source)
    files=[*[p for p in (ROOT/'rtl').glob('*.sv')],*[p for p in (ROOT/'ps').iterdir() if p.is_file()],*[p for p in (ROOT/'host').glob('*.py')],*[p for p in (ROOT/'scripts').iterdir() if p.suffix in ('.py','.ps1','.tcl')],ROOT/'assets/parameters002/parameters.bin',ROOT/'assets/parameters002/manifest.json',build/'v022_full.bit',build/'result.txt',build/'timing.rpt',build/'drc.rpt']
    manifest=dict(version='V0.22_phase1',offline_gates_passed=True,hardware_tested=False,scope='68closedCONV/FFN PL schedules andDDR/vector/layout, serialinteger matrix storage; outerhostDAG remains; not wholegraphPL',build_tag=tag,bit_sha256=sha(build/'v022_full.bit'),elf_sha256=sha(ROOT/'ps/gateway_v022.elf'),image_sha256=sha(ROOT/'assets/parameters002/parameters.bin'),files={str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in files},gates=gates)
    path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');verify(tag);print('V022_RUNTIME_SEALED',manifest['bit_sha256'])
