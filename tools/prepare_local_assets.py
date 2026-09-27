"""Restore ignored local assets from the user's complete extracted archives."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def restore(source, target, expected):
    if digest(source) != expected:
        raise ValueError('Archive asset hash mismatch: ' + str(source))
    if target.exists():
        if digest(target) != expected:
            raise ValueError('Refusing to overwrite a different local file: ' + str(target))
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    if digest(target) != expected:
        raise ValueError('Copied asset hash mismatch: ' + str(target))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive-dir', type=Path, required=True)
    p.add_argument('--project', choices=['head', 'asr'], required=True)
    args = p.parse_args()
    if args.project == 'head':
        source = args.archive_dir / 'modelA_conformer_head_full_fpga/modelA_conformer_head_full_fpga'
        target = ROOT / 'projects/conformer_attention_head'
        manifest = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))['files']
        names = ['weights/layer_0.pth'] + ['fixtures/' + prefix + name
                for prefix in ['', 't1/', 't8_masks/'] for name in ['input.bin', 'reference.pt']]
        names += ['artifacts/csim_output.bin', 'artifacts/integer_reference.bin']
        for name in names:
            restore(source / name, target / name, manifest[name]['sha256'])
        count = len(names)
    else:
        source = args.archive_dir / 'v5_xc7a35t_frozen/project/asr/releases/v2_20260922_pre_golden'
        target = ROOT / 'projects/asr_qdq_fpga/releases/v2_20260922_pre_golden'
        manifest = json.loads((source / 'FREEZE_MANIFEST.json').read_text(encoding='utf-8-sig'))['sha256']
        for name, sha in manifest.items():
            part = Path(name)
            if part.is_absolute() or '..' in part.parts:
                raise ValueError('Unsafe path in archived manifest')
            restore(source / name, target / name, sha)
        count = len(manifest)
    print(f'LOCAL_ASSETS_VERIFIED: project={args.project} files={count}; no FPGA access')


if __name__ == '__main__':
    main()
