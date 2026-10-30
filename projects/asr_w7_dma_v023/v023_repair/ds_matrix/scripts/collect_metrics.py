#!/usr/bin/env python3
"""Rebuild logs/metrics.txt from logs/run_*.log (commands.log has every rc)."""
from pathlib import Path
import re
L=Path(__file__).resolve().parent.parent/'logs'
rx=re.compile(r'PASS|FAIL|INFO done|INFO cluster|INFO dma|MULTI_TEST_END|STROBE|TIMEOUT|PASS_FAULT|DMA_EDGE')
out=[]
for p in sorted(L.glob('run_*.log')):
    hits=[ln.strip() for ln in p.read_text(errors='replace').splitlines() if rx.search(ln)]
    out.append(f'### {p.stem}')
    out.extend(hits)
(L/'metrics.txt').write_text('\n'.join(out)+'\n')
print(len(out), 'lines')
