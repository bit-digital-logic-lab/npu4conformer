#!/usr/bin/env python3
"""Small per-stage progress updater (progress.json is written by every stage)."""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
P = HERE / 'progress.json'


def main():
    if len(sys.argv) < 2:
        print('usage: progress.py STAGE [STATE] [NOTE]')
        return 2
    stage = sys.argv[1]
    state = sys.argv[2] if len(sys.argv) > 2 else 'running'
    note = sys.argv[3] if len(sys.argv) > 3 else ''
    d = json.loads(P.read_text()) if P.exists() else {'task': 'ds_graph_prefetch', 'steps': []}
    d['stage'] = stage
    d['state'] = state
    d['note'] = note
    steps = d.setdefault('steps', [])
    for s in steps:
        if s.get('step') == stage:
            s['state'] = state
            s['note'] = note
            break
    else:
        steps.append({'step': stage, 'state': state, 'note': note})
    P.write_text(json.dumps(d, indent=2) + '\n')
    print('progress', stage, state, note)
    return 0


if __name__ == '__main__':
    sys.exit(main())
