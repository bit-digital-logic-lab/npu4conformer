"""Capture or verify exact V4 build inputs without touching old/frozen sources."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FROZEN = ROOT.parent / 'releases' / 'v2_20260922_pre_golden'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run', required=True)
    p.add_argument('--verify', action='store_true')
    args = p.parse_args()
    if not args.run.replace('_', '').isalnum():
        p.error('safe unique build name required')
    dest = ROOT / 'build' / args.run / 'source_manifest.json'
    if args.verify:
        data = json.loads(dest.read_text())
        bad = [f for f, sha in data['sha256'].items() if digest(Path(f)) != sha]
        if bad:
            raise SystemExit(f'Build inputs changed: {bad}')
        print(f'BUILD_SOURCE_HASHES_PASS {len(data["sha256"])} files')
        return
    if dest.exists():
        raise SystemExit('Existing source manifest protected')
    files = [ROOT / 'scripts/build_board.tcl', ROOT / 'scripts/run_vivado.ps1', Path(__file__).resolve()]
    for sub, pattern in [('rtl', '*.sv'), ('constraints', '*.xdc')]:
        files += list((ROOT / sub).glob(pattern))
    for sub in ['rtl', 'lib/axis/rtl']:
        files += list((ROOT / 'vendor/verilog-ethernet' / sub).glob('*.v'))
    for sub in ['syn/vivado', 'lib/axis/syn/vivado']:
        files += list((ROOT / 'vendor/verilog-ethernet' / sub).glob('*.tcl'))
    files += [FROZEN / 'rtl' / f'{name}.sv' for name in
              ['asr_i16_mac', 'asr_requant', 'asr_fp32_alu', 'asr_uart_tx']]
    files += [ROOT / 'build/fma_ip_002/project/fma_probe.srcs/sources_1/ip/asr_fma_ip/asr_fma_ip.xci',
              ROOT / 'scripts/generate_fma_ip.tcl']
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open('x', encoding='utf-8') as handle:
        json.dump(dict(captured_utc=datetime.now(timezone.utc).isoformat(),
                       sha256={str(f.resolve()): digest(f) for f in sorted(files)}), handle, indent=2)
    print(f'BUILD_SOURCE_HASHES_CAPTURED {len(files)} files')


if __name__ == '__main__':
    main()
