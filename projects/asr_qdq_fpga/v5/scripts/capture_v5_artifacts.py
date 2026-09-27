"""Snapshot provenance for a completed V5 build; no device access."""
from pathlib import Path
import argparse,hashlib,json
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run',required=True);ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    if not args.run.replace('_','').isalnum():ap.error('safe run name required')
    if (ROOT/'reports').resolve() not in args.out.resolve().parents:ap.error('write only under v5/reports')
    if args.out.exists():ap.error('existing evidence protected')
    build=ROOT/'build'/args.run
    files=[p for p in build.rglob('*') if p.is_file()]
    files += [p for d in ['rtl','host','constraints'] for p in (ROOT/d).glob('*') if p.is_file()]
    for folder in ['build/fma_ip_002/project/fma_probe.gen/sources_1/ip/asr_fma_ip','build/fma_ip_002/project/fma_probe.srcs/sources_1/ip/asr_fma_ip']:
        files += [p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix.lower() in {'.v','.sv','.vhd','.xdc','.xci','.dcp','.xml'}]
    files += [p for p in (ROOT/'build'/f'{args.run}_program_logs').glob('*') if p.is_file()]
    files += [ROOT/'build/numeric_sim_001/report.json',ROOT/'sim/tb_v5_numeric.sv']
    value=dict(captured_utc=datetime.now(timezone.utc).isoformat(),scope='completed V5 build and deployed numerical implementation',sha256={str(p.resolve()):sha(p) for p in sorted(set(files))})
    args.out.parent.mkdir(exist_ok=True,parents=True)
    with args.out.open('x',encoding='utf-8') as f:json.dump(value,f,indent=2)
    print('ARTIFACT_HASHES',len(files))
if __name__=='__main__':main()
