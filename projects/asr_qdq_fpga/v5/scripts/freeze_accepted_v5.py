"""Freeze V5 only after original physical full-chain acceptance passes.
Copies authorized ASR V5 artifacts; protects existing destinations and checks
every copy before/after. Does not delete, program hardware or write Flash.
"""
from pathlib import Path
import argparse,hashlib,json,shutil
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run',required=True);ap.add_argument('--release',required=True);ap.add_argument('--check-only',action='store_true');args=ap.parse_args()
    for value in (args.run,args.release):
        if not value.replace('_','').isalnum():ap.error('safe names only')
    report_path=ROOT/'reports'/args.run/'result.json'
    if not report_path.exists():raise SystemExit('NOT READY: physical run has not finished')
    result=json.loads(report_path.read_text())
    keys=('completed','physical_fpga_executed','encoder_hardware_executed','full_chain_tested','golden_pass','acceptance_pass','end_provenance_verified','decoder_uses_actual_encoder_output')
    if result.get('scope')!='full_chain' or not all(result.get(k) is True for k in keys):raise SystemExit('NOT ACCEPTED: original physical full-chain gate failed')
    link=result['ethernet_after_close']
    if not link['close_confirmed'] or link['poisoned']:raise SystemExit('NOT ACCEPTED: unclean session')
    if result.get('model_modified') or result.get('cpu_arithmetic_fallback') or result.get('golden_reference_regenerated'):raise SystemExit('NOT ACCEPTED: prohibited validation substitution')
    bit=Path(result['bitstream_file']).resolve()
    if bit.parent.parent!=(ROOT/'build').resolve() or sha(bit)!=result['bitstream_file_sha256']:raise SystemExit('Bitstream path/hash mismatch')
    for name,digest in result['source_sha256'].items():
        if sha(Path(name))!=digest:raise SystemExit(f'Physical run source changed: {name}')
    build_sources=json.loads((bit.parent/'source_manifest.json').read_text())
    for name,digest in build_sources['sha256'].items():
        if sha(Path(name))!=digest:raise SystemExit(f'Build input changed: {name}')
    artifact_manifest=ROOT/'reports/board_001_fma_artifact_manifest.json'
    for name,digest in json.loads(artifact_manifest.read_text())['sha256'].items():
        if sha(Path(name))!=digest:raise SystemExit(f'Build artifact changed: {name}')
    release=ROOT.parent/'releases'/args.release
    if release.exists():raise SystemExit('Existing release protected')
    roots=[ROOT/p for p in ('rtl','host','constraints','vendor','scripts','diagnostics','tests','sim','reference','reports')]
    roots += [bit.parent,ROOT/'build'/f'{bit.parent.name}_build_logs',ROOT/'build'/f'{bit.parent.name}_program_logs',ROOT/'build/numeric_sim_001',ROOT/'build/fma_ip_002']
    files=[ROOT/'README.md',ROOT/'RESULT_20260923_zh.md']
    for directory in roots:
        files.extend(p for p in directory.rglob('*') if p.is_file() and not any(t in p.parts for t in ('__pycache__','.git','.Xil','xsim.dir')) and p.suffix.lower() not in ('.pyc','.wdb','.vvp'))
    files=sorted(set(files))
    entries=[dict(path=p.relative_to(ROOT).as_posix(),bytes=p.stat().st_size,sha256=sha(p)) for p in files]
    if args.check_only:print('READY_TO_FREEZE',len(files),'files');return
    release.mkdir()
    for source,entry in zip(files,entries):
        target=release/entry['path'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        if sha(source)!=entry['sha256'] or sha(target)!=entry['sha256']:raise RuntimeError(f'Copy verification failed: {source}')
    # Explicitly embed immutable shared numerical/scheduler dependency.
    frozen=ROOT.parent/'releases/v2_20260922_pre_golden'
    dependencies=[]
    for source in sorted(p for p in frozen.rglob('*') if p.is_file() and '__pycache__' not in p.parts):
        relative=Path('dependencies/v2_20260922_pre_golden')/source.relative_to(frozen);target=release/relative
        digest=sha(source);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        if sha(source)!=digest or sha(target)!=digest:raise RuntimeError('Dependency copy changed')
        dependencies.append(dict(path=relative.as_posix(),bytes=source.stat().st_size,sha256=digest))
    manifest=dict(created_utc=datetime.now(timezone.utc).isoformat(),status='ACCEPTED: original case_0000 physical Encoder->Decoder, unchanged golden tolerance',scope='one original case only; NOT a claim that all inputs/platforms are validated',original_root=str(ROOT),physical_report=f'reports/{args.run}/result.json',bitstream_sha256=result['bitstream_file_sha256'],entries=entries+dependencies)
    with (release/'FREEZE_MANIFEST.json').open('x',encoding='utf-8') as f:json.dump(manifest,f,indent=2)
    print('FROZEN_ACCEPTED_VERIFIED',len(entries)+len(dependencies),str(release))
if __name__=='__main__':main()
