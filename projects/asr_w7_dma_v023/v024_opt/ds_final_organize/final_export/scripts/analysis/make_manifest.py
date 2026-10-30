#!/usr/bin/env python3
"""Build/verify the export manifest: SHA-256, old->new map, unique modules.

Reads only final_export/.  Writes under assets_manifest/.  Exits non-zero if
the filelist references a missing file, a module is defined twice, or the
frozen fixture hashes do not match.
"""
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAN = ROOT / 'assets_manifest'
SKIP_DIRS = {'build', 'logs', '__pycache__'}
SKIP_FILES = {
    'assets_manifest/FILE_SHA256.txt',
    'assets_manifest/SOURCE_SHA256.json',
    'assets_manifest/OLD_TO_NEW.csv',
    'assets_manifest/OLD_TO_NEW.md',
    'assets_manifest/SUMMARY.json',
}


def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def main():
    fail = 0
    fl = ROOT / 'filelist.f'
    entries = [ln.strip() for ln in fl.read_text().splitlines()
               if ln.strip() and not ln.strip().startswith('//')]
    mods = {}
    for rel in entries:
        p = ROOT / rel
        if not p.exists():
            print('FAIL missing filelist entry', rel)
            fail += 1
            continue
        text = p.read_text(errors='replace')
        for m in re.finditer(r'^\s*module\s+([A-Za-z_]\w*)', text, re.M):
            mods.setdefault(m.group(1), []).append(rel)
    dup = {m: v for m, v in mods.items() if len(v) > 1}
    if dup:
        print('FAIL duplicate module definitions:', json.dumps(dup, indent=2))
        fail += 1
    print(f'INFO filelist entries={len(entries)} unique_modules={len(mods)}')

    freeze = json.loads((ROOT / 'sim/fixtures/REFERENCE_FREEZE.json').read_text())
    for rel, want in freeze.items():
        p = ROOT / rel
        got = sha(p) if p.exists() else 'MISSING'
        if got != want:
            print('FAIL frozen reference changed:', rel)
            fail += 1

    origin = json.loads((MAN / 'ORIGIN_MAP.json').read_text())
    # Origin map may point at a path that no longer exists in this workspace
    # (the source trees are read-only and retained); record its recorded SHA
    # from the frozen stage when available.
    files = []
    for p in sorted(ROOT.rglob('*')):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if rel.parts[0] in SKIP_DIRS or '__pycache__' in rel.parts:
            continue
        if str(rel) in SKIP_FILES:
            continue
        files.append(rel)
    out = {}
    for rel in files:
        r = str(rel)
        out[r] = {'sha256': sha(ROOT / rel), 'origin': origin.get(r, 'export-authored')}
    (MAN / 'SOURCE_SHA256.json').write_text(
        json.dumps(out, indent=2, ensure_ascii=False) + '\n')
    with (MAN / 'OLD_TO_NEW.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['new_path', 'old_or_origin_path', 'sha256'])
        for r, v in out.items():
            w.writerow([r, v['origin'], v['sha256']])
    (MAN / 'FILE_SHA256.txt').write_text(
        ''.join(f'{v["sha256"]}  {r}\n' for r, v in out.items()))
    md = ['# Old -> new map', '',
          'Every exported file, its read-only origin and SHA-256.', '',
          '| New path | Origin | SHA-256 (first 16) |', '|---|---|---|']
    for r, v in out.items():
        md.append(f'| `{r}` | `{v["origin"]}` | `{v["sha256"][:16]}` |')
    (MAN / 'OLD_TO_NEW.md').write_text('\n'.join(md) + '\n')
    summary = {
        'files': len(out),
        'rtl_sources': len([r for r in out if r.startswith('rtl/')]),
        'filelist_entries': len(entries),
        'unique_modules': len(mods),
        'duplicate_modules': dup,
        'frozen_references': len(freeze),
        'fail': fail,
    }
    (MAN / 'SUMMARY.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main())
