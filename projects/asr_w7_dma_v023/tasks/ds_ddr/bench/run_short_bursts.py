#!/usr/bin/env python3
"""短突发/单 beat 对照：同一 L=32 延迟、同一 BFM，只改请求 beat 数。"""
import json, re, shutil, subprocess
from pathlib import Path

T = Path(__file__).resolve().parent
ROOT = T.parent
WORK = Path('/home/yang/Desktop/项目/work')
OUT = T / 'candidate'; LOGS = T / 'logs/short_burst'; REP = T / 'reports'
for d in (OUT, LOGS, REP): d.mkdir(parents=True, exist_ok=True)
IVERILOG, VVP = shutil.which('iverilog'), shutil.which('vvp')
PAT = re.compile(r'DMA_RESULT mode=(\d+) dut=(\w+) beats=(\d+) cycles=(\d+).*?rbeats=(\d+) wbeats=(\d+).*?pass=(\d+)')


def compile_one(cand):
    exe = OUT / f'short_{"cand" if cand else "base"}.vvp'
    src = [T / 'tb_dma_compare.sv', T / 'bfm/axi128_ddr_bfm_ds.sv',
           ROOT / 'candidate/axi_dma_v020_multi.sv' if cand else WORK / 'rtl/axi_dma_v019.sv']
    cmd = [IVERILOG, '-g2012', '-s', 'tb_dma_compare', '-DLATMIN=32', '-DLATMAX=32',
           '-DBP=0', '-DSEED=9', '-DMAXOUT=8', '-o', str(exe)]
    if cand: cmd.append('-DCAND')
    cmd += [str(x) for x in src]
    cp = subprocess.run(cmd, cwd=OUT, capture_output=True, text=True)
    (LOGS / f'compile_{"cand" if cand else "base"}.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode: raise SystemExit('compile failed')
    return exe


rows = []
for cand in (False, True):
    exe = compile_one(cand)
    for beats in (1, 4, 7, 13, 16, 32, 64):
        for mode in (0, 1):
            cp = subprocess.run([VVP, '-i', str(exe), f'+mode={mode}', f'+beats={beats}'],
                                cwd=LOGS, capture_output=True, text=True, timeout=120)
            (LOGS / f'{"cand" if cand else "base"}_b{beats}_m{mode}.log').write_text(
                cp.stdout + cp.stderr, encoding='utf-8')
            m = PAT.search(cp.stdout)
            if cp.returncode or not m:
                raise SystemExit(f'short burst failed {cand} {beats} {mode}')
            rows.append(dict(dut='cand' if cand else 'base', beats=beats,
                             mode='read' if mode == 0 else 'write',
                             cycles=int(m.group(4)), pass_=int(m.group(7))))
out = dict(scope='Icarus RTL + 共享 AXI128 BFM；L=32，短请求 1..64 beat；只改请求长度。',
           results=rows,
           note='单/短突发下 v020 的 FIFO/握手开销可见；长突发才有多在途收益。')
(REP / 'short_burst.json').write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
for r in rows:
    print(r)
