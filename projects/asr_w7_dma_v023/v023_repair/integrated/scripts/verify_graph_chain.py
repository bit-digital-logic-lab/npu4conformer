#!/usr/bin/env python3
"""Independently check the real LAY->VEC->VEC graph-chain output.

Golden is computed here from the input fixture and the two descriptor
constants (1.0 then 2.0).  It is not read from any worker gold file.
"""
import re, struct, sys
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parents[1]
fixture = root.parent / 'ds_graph' / 'tests' / 'fixtures' / 'mem_graph.hex'
log = root / 'logs' / 'run_graph_real_candidate.log'

lines = fixture.read_text().splitlines()
def word(addr):
    off = (addr - 0x10000000) + 0xc0000
    return int(lines[off // 4], 16)

inp = [struct.unpack('<f', struct.pack('<I', word(0x10001000 + i*4)))[0] for i in range(64)]
exp = np.float32((np.array(inp, dtype=np.float32) + np.float32(1.0)) * np.float32(2.0))

out = {}
for line in log.read_text().splitlines():
    m = re.match(r'AUDIT_OUT (\d+) ([0-9a-fA-F]+)', line)
    if m:
        out[int(m.group(1))] = int(m.group(2), 16)

bad = []
for i in range(64):
    if i not in out:
        bad.append((i, 'missing'))
        continue
    got = struct.unpack('<f', struct.pack('<I', out[i]))[0]
    if struct.pack('<f', got) != struct.pack('<f', exp[i]):
        bad.append((i, inp[i], got, float(exp[i])))

summary = {
    'chain': 'LAY copy -> VEC ADD 1.0 -> VEC MUL 2.0',
    'words_checked': 64,
    'words_matching': 64 - len(bad),
    'bad': bad[:10],
    'golden_source': 'local fixture input + descriptor constants 1.0/2.0, computed with numpy float32',
    'pass': not bad,
}
import json
(root / 'analysis').mkdir(exist_ok=True)
(root / 'analysis' / 'graph_chain_verify.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
sys.exit(0 if not bad else 1)
