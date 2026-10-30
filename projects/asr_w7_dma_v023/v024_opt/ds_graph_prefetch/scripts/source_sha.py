#!/usr/bin/env python3
"""Write SOURCE_SHA256.json for the delivered candidate and frozen inputs."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    groups = {
        'rtl': sorted(HERE.glob('rtl/*.sv')),
        'tb': sorted(HERE.glob('tb/*.sv')),
        'scripts': sorted(HERE.glob('scripts/*.py')) + sorted(HERE.glob('scripts/*.sh')),
        'filelists': sorted(HERE.glob('filelist_*.f')) + sorted(HERE.glob('*.f')),
        'reference': sorted(HERE.glob('reference/*.json')),
        'fixtures': sorted(HERE.glob('fixtures/*.hex')),
        'integrated_copy_fixtures': sorted(HERE.glob('integrated_copy/fixtures/**/*')),
        'baseline_rtl': sorted(HERE.glob('baseline_rtl/*.sv')),
    }
    d = {}
    for name, files in groups.items():
        d[name] = {str(p.relative_to(HERE)): sha(p) for p in files if p.is_file()}
    (HERE / 'SOURCE_SHA256.json').write_text(json.dumps(d, indent=2, sort_keys=True) + '\n')
    print('wrote SOURCE_SHA256.json', sum(len(v) for v in d.values()), 'files')


if __name__ == '__main__':
    main()
