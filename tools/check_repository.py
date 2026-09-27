"""Check source layout, Python syntax, required dependency files and file hashes."""
from pathlib import Path
import argparse
import ast
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'docs/repository-manifest.json'


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def tracked_or_selected():
    # After initialization respect Git's ignore rules; never include model assets.
    if (ROOT / '.git').is_dir():
        result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
                                cwd=ROOT, capture_output=True, check=True)
        return sorted(set(x.decode('utf-8') for x in result.stdout.split(b'\0') if x))
    ignored_parts = {'.git', '.venv', '__pycache__', 'build', 'core_hls', 'artifacts', 'weights'}
    ignored_suffix = {'.pyc', '.pyo', '.bit', '.dcp', '.vvp', '.log', '.bin', '.pt', '.pth', '.npz', '.onnx', '.zip'}
    return [p.relative_to(ROOT).as_posix() for p in sorted(ROOT.rglob('*'))
            if p.is_file() and not ignored_parts.intersection(p.relative_to(ROOT).parts)
            and p.suffix not in ignored_suffix]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--refresh', action='store_true', help='Refresh hash inventory after reviewing intended changes')
    args = p.parse_args()
    names = [x for x in tracked_or_selected() if x != MANIFEST.relative_to(ROOT).as_posix()]
    py_count = 0
    for name in names:
        f = ROOT / name
        if f.suffix == '.py':
            ast.parse(f.read_text(encoding='utf-8-sig'), filename=name)
            py_count += 1
    current = {name: digest(ROOT / name) for name in names}
    if args.refresh:
        MANIFEST.write_text(json.dumps({'schema': 1, 'sha256': current}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    else:
        expected = json.loads(MANIFEST.read_text(encoding='utf-8'))['sha256']
        if current != expected:
            changed = sorted(k for k in current.keys() | expected.keys() if current.get(k) != expected.get(k))
            raise SystemExit('File inventory differs; review changes before --refresh:\n' + '\n'.join(changed))
    head = ROOT / 'projects/conformer_attention_head'
    generated = head / 'rtl/generated'
    for name in (generated / 'sources.txt').read_text().splitlines():
        if name.strip() and not (generated / name.strip()).is_file():
            raise SystemExit('Missing HLS generated design input: ' + name)
    v5 = ROOT / 'projects/asr_qdq_fpga/v5'
    build = (v5 / 'scripts/build_board.tcl').read_text()
    for names_, template in re.findall(r'foreach name \{([^}]+)\} \{\s*(?:read_verilog|source) \[file join \$vendor ([^\]]+)\]', build):
        for name in names_.split():
            f = (v5 / 'vendor/verilog-ethernet').joinpath(*template.replace('${name}', name).split())
            if not f.is_file():
                raise SystemExit('Missing Ethernet/AXIS build dependency: ' + str(f))
    assert (v5.parent / 'golden_validation/scripts/golden_common.py').is_file()
    release = v5.parent / 'releases/v2_20260922_pre_golden'
    freeze = json.loads((release / 'FREEZE_MANIFEST.json').read_text(encoding='utf-8-sig'))['sha256']
    for name, sha in freeze.items():
        f = release / name
        if f.is_file() and digest(f) != sha:
            raise SystemExit('Archived V2 file changed: ' + name)
    success = json.loads((v5 / 'reports/case_0000_v5_b001_full_chain_001/result.json').read_text())
    failure = json.loads((v5 / 'validation_case0001/runs/case_0001_full_chain_001/result.json').read_text())
    assert success['acceptance_pass'] is True and failure['acceptance_pass'] is False
    print(f'REPOSITORY_CHECK_PASS files={len(current)} python_syntax={py_count}; source paths and success/failure evidence verified')


if __name__ == '__main__':
    main()
