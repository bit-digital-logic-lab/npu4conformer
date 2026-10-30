#!/usr/bin/env python3
"""A/W ping-pong before/after：同 RTL、同 BFM、4 页负载；只改描述符供给策略。"""
import json, re, shutil, subprocess, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORK = Path('/home/yang/Desktop/项目/work')
OUT = HERE / 'candidate'
LOGS = HERE / 'logs/pingpong'
REPORTS = HERE / 'reports'
for d in (OUT, LOGS, REPORTS):
    d.mkdir(parents=True, exist_ok=True)
IVERILOG = shutil.which('iverilog')
VVP = shutil.which('vvp')
TB = HERE / 'tb_ab_pingpong.sv'
BFM = HERE / 'bfm/axi128_ddr_bfm_ds.sv'
DMA = ROOT / 'candidate/axi_dma_v020_multi.sv'
PP = ROOT / 'candidate/ab_pingpong_prefetch.sv'
PAT = re.compile(r'PP_RESULT prefetch=(\d+) cycles=(\d+) fill_cycles=(\d+) overlap=(\d+) '
                 r'stall=(\d+) prefetch_n=(\d+) consume_n=(\d+) dma_rbeats=(\d+) pass=(\d+)')


def run(cmd, timeout=300):
    t = time.perf_counter()
    cp = subprocess.run(cmd, cwd=OUT, capture_output=True, text=True, timeout=timeout)
    return cp, time.perf_counter() - t


def main():
    exe = OUT / 'tb_ab_pingpong.vvp'
    cp, _ = run([IVERILOG, '-g2012', '-s', 'tb_ab_pingpong', '-o', str(exe),
                 str(TB), str(BFM), str(DMA), str(PP)])
    (LOGS / 'compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode != 0:
        raise RuntimeError('pingpong compile failed')
    rows = []
    for pref in (0, 1):
        cp, dt = run([VVP, '-i', str(exe), f'+prefetch={pref}'])
        (LOGS / f'prefetch{pref}.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
        m = PAT.search(cp.stdout)
        if cp.returncode != 0 or not m:
            raise RuntimeError(f'prefetch{pref} failed: {cp.stdout[-1000:]}')
        keys = ['prefetch', 'cycles', 'fill_cycles', 'overlap', 'stall', 'prefetch_n',
                'consume_n', 'dma_rbeats', 'pass']
        d = dict(zip(keys, m.groups()))
        for k in keys:
            d[k] = int(d[k])
        d['host_seconds'] = round(dt, 3)
        rows.append(d)
    base = rows[0]
    for r in rows:
        r['speedup_vs_serial'] = round(base['cycles'] / r['cycles'], 4)
    out = dict(scope='Icarus RTL：ab_pingpong_prefetch + axi_dma_v020_multi + 参数化 AXI128 BFM；'
                     '4 页×64beat，消费者每页 300 cycles；不是 CASE0000。',
               results=rows,
               note='串行/预取使用完全相同的 RTL、BFM 和页数据；仅描述符供给策略不同。')
    (REPORTS / 'pingpong.json').write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(out, indent=2))


if __name__ == '__main__':
    main()
