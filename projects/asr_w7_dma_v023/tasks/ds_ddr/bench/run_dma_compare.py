#!/usr/bin/env python3
"""DDR/AXI before/after 公平测量：同 seed、同负载、同 BFM 参数，只换 DMA RTL。
输出 bench/reports/dma_compare.json 与逐场景日志。非板级、非综合。"""
import json, hashlib, re, shutil, subprocess, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORK = Path('/home/yang/Desktop/项目/work')
TB = HERE / 'tb_dma_compare.sv'
BFM = HERE / 'bfm/axi128_ddr_bfm_ds.sv'
BASE = WORK / 'rtl/axi_dma_v019.sv'
CAND = ROOT / 'candidate/axi_dma_v020_multi.sv'
IVERILOG = shutil.which('iverilog')
VVP = shutil.which('vvp')
OUT = HERE / 'candidate'
LOGS = HERE / 'logs/dma_compare'
REPORTS = HERE / 'reports'
for d in (OUT, LOGS, REPORTS):
    d.mkdir(parents=True, exist_ok=True)

SCEN = [
    dict(name='lat8_bp0', latmin=8, latmax=8, bp=0, seed=1),
    dict(name='lat32_bp0', latmin=32, latmax=32, bp=0, seed=7),
    dict(name='lat64_bp0', latmin=64, latmax=64, bp=0, seed=13),
    dict(name='lat32_bp25', latmin=32, latmax=32, bp=25, seed=29),
]
MODES = [0, 1, 2]
MODENAME = {0: 'read', 1: 'write', 2: 'mix'}
MAXOUTS = [2, 4, 8]
BEATS = 4096


def run(cmd, cwd, timeout=300):
    t = time.perf_counter()
    cp = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return cp, time.perf_counter() - t


def compile_one(dut, sc, maxout):
    tag = f'{dut}_{sc["name"]}_o{maxout}'
    exe = OUT / f'{tag}.vvp'
    src = [TB, BFM, BASE if dut == 'base' else CAND]
    cmd = [IVERILOG, '-g2012', '-s', 'tb_dma_compare',
           f'-DLATMIN={sc["latmin"]}', f'-DLATMAX={sc["latmax"]}',
           f'-DBP={sc["bp"]}', f'-DSEED={sc["seed"]}',
           f'-DMAXOUT={maxout}', '-o', str(exe)]
    if dut == 'cand':
        cmd.append('-DCAND')
    cmd += [str(p) for p in src]
    cp, dt = run(cmd, OUT)
    (LOGS / f'{tag}.compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode != 0:
        raise RuntimeError(f'{tag} compile failed')
    return exe


PAT = re.compile(r'DMA_RESULT mode=(\d+) dut=(\w+) beats=(\d+) cycles=(\d+) total_bfm_cycles=(\d+) '
                 r'busy=(\d+) rbeats=(\d+) wbeats=(\d+) rbursts=(\d+) wbursts=(\d+) '
                 r'rbubble=(\d+) wbubble=(\d+) armax=(\d+) awmax=(\d+) pass=(\d+)')


def parse(txt):
    m = PAT.search(txt)
    if not m:
        return None
    keys = ['mode', 'dut', 'beats', 'cycles', 'bfm_cycles', 'busy', 'rbeats', 'wbeats',
            'rbursts', 'wbursts', 'rbubble', 'wbubble', 'armax', 'awmax', 'pass']
    d = dict(zip(keys, m.groups()))
    for k in keys:
        if k not in ('dut',):
            d[k] = int(d[k])
    # 16B/beat；mix 的 read/write 利用率分别对共享通道总周期
    d['bytes'] = d['busy'] * 16
    d['effective_B_per_cycle'] = round(d['bytes'] / d['cycles'], 4) if d['cycles'] else 0
    d['bus_util'] = round(d['busy'] / d['cycles'], 4) if d['cycles'] else 0
    d['read_util'] = round(d['rbeats'] / d['cycles'], 4) if d['cycles'] else 0
    d['write_util'] = round(d['wbeats'] / d['cycles'], 4) if d['cycles'] else 0
    d['read_bubble_frac'] = round(d['rbubble'] / d['cycles'], 4) if d['cycles'] else 0
    d['write_bubble_frac'] = round(d['wbubble'] / d['cycles'], 4) if d['cycles'] else 0
    return d


def main():
    results = []
    for sc in SCEN:
        for mode in MODES:
            for maxout in MAXOUTS:
                for dut in ('base', 'cand'):
                    if dut == 'base' and maxout != MAXOUTS[0]:
                        continue
                    exe = compile_one(dut, sc, maxout)
                    tag = f'{dut}_{sc["name"]}_o{maxout}_m{mode}'
                    cp, dt = run([VVP, '-i', str(exe), f'+mode={mode}', f'+beats={BEATS}'], LOGS)
                    (LOGS / f'{tag}.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
                    d = parse(cp.stdout)
                    if cp.returncode != 0 or not d or not d['pass']:
                        raise RuntimeError(f'{tag} failed: {cp.stdout[-800:]}')
                    d.update(scenario=sc['name'], dut=dut, max_out=maxout, mode_name=MODENAME[mode],
                             host_seconds=round(dt, 3), log=str(LOGS / f'{tag}.log'))
                    results.append(d)
                    print(f'{tag} cycles={d["cycles"]} util={d["bus_util"]:.3f} '
                          f'bub={d["read_bubble_frac"]:.3f}/{d["write_bubble_frac"]:.3f}', flush=True)

    # 汇总相对基线的加速比（同 scenario/mode）
    by = {(r['scenario'], r['mode'], r['dut'], r['max_out']): r for r in results}
    for r in results:
        if r['dut'] == 'base':
            continue
        b = by[(r['scenario'], r['mode'], 'base', MAXOUTS[0])]
        r['speedup_vs_base'] = round(b['cycles'] / r['cycles'], 4)
        r['bubble_reduction'] = round(1 - (r['rbubble'] + r['wbubble']) /
                                      max(1, b['rbubble'] + b['wbubble']), 4)
    # 理论共享通道下界：4096 read + 4096 write beats（mix）
    bound = dict(
        axiom='DUPLEX=0 时每拍最多一个 128bit 数据 beat；16B/beat',
        read_only_lb_cycles=BEATS, write_only_lb_cycles=BEATS, mix_lb_cycles=2 * BEATS,
        note='下界只计数据 beat，不含命令/延迟；实际利用率按 busy/cycles 计算。')
    inputs = {}
    for p in (TB, BFM, BASE, CAND):
        inputs[str(p)] = hashlib.sha256(p.read_bytes()).hexdigest()
    out = dict(
        scope='Icarus RTL + 参数化共享 AXI128 DDR BFM；不是板级 DDR、无综合、无 STA。',
        workload=dict(beats=BEATS, bytes_per_direction=BEATS * 16,
                      read_base='0x04000000', write_base='0x04010000',
                      burst_max=16, page_boundary='BFM 强制不跨 4KiB'),
        scenarios=SCEN, bound=bound, results=results,
        source_sha256=inputs,
        baseline_note='base=work/rtl/axi_dma_v019.sv；cand=tasks/ds_ddr/candidate/axi_dma_v020_multi.sv')
    (REPORTS / 'dma_compare.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n',
                                              encoding='utf-8')
    print('DMA_COMPARE_DONE', len(results), 'runs ->', REPORTS / 'dma_compare.json')


if __name__ == '__main__':
    main()
