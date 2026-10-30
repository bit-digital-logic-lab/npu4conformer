#!/usr/bin/env python3
"""同一 vector/layout 夹具，只替换 DMA：v019 单在途 vs v020 多 outstanding。
数值 golden 仍由原 TB 的独立 numpy/整数参考判定；这里只汇总周期。
输出 bench/reports/vector_dma_compare.json。"""
import hashlib, json, re, shutil, subprocess, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORK = Path('/home/yang/Desktop/项目/work')
ALIAS = Path('/tmp/opencode/dsddr_work')
if not ALIAS.exists():
    ALIAS.symlink_to(WORK)
IVERILOG = shutil.which('iverilog')
VVP = shutil.which('vvp')
OUT = HERE / 'candidate'
LOGS = HERE / 'logs/vector_compare'
REPORTS = HERE / 'reports'
for d in (OUT, LOGS, REPORTS):
    d.mkdir(parents=True, exist_ok=True)

CYC = re.compile(r'cycles=\s*(\d+)')


def run(cmd, cwd, timeout=600):
    t = time.perf_counter()
    cp = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return cp, time.perf_counter() - t


def compile_one(kind, cand):
    tag = f'{kind}_{"cand" if cand else "base"}'
    exe = OUT / f'{tag}.vvp'
    if kind == 'vector':
        src = [WORK / 'tests/tb_vector_axi.sv', WORK / 'tests/axi128_memory_bfm.sv',
               WORK / 'tests/fma_forbidden_stub.sv',
               ROOT / 'candidate/ddr_vector_axi_v020.sv' if cand else WORK / 'rtl/ddr_vector_axi.sv',
               WORK / 'rtl/ddr_vector_engine.sv', WORK / 'rtl/asr_fp32_alu.sv',
               ROOT / 'candidate/axi_dma_v020_multi.sv' if cand else WORK / 'rtl/axi_dma_v019.sv']
        top = 'tb_vector_axi'
    else:
        src = [WORK / 'tests/tb_layout_axi.sv', WORK / 'tests/axi128_memory_bfm.sv',
               ROOT / 'candidate/ddr_layout_axi_v020.sv' if cand else WORK / 'rtl/ddr_layout_axi.sv',
               WORK / 'rtl/ddr_layout_engine.sv', WORK / 'rtl/u16_divmod.sv',
               ROOT / 'candidate/axi_dma_v020_multi.sv' if cand else WORK / 'rtl/axi_dma_v019.sv']
        top = 'tb_layout_axi'
    cp, dt = run([IVERILOG, '-g2012', '-s', top, '-o', str(exe), *map(str, src)], OUT)
    (LOGS / f'{tag}.compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode != 0:
        raise RuntimeError(tag + ' compile failed')
    return exe, top


def main():
    res = []
    for kind in ('vector', 'layout'):
        for cand in (False, True):
            exe, top = compile_one(kind, cand)
            fixtures = json.loads((WORK / f'tests/{kind}_fixtures/meta.json').read_text())
            for case in fixtures:
                modes = range(10) if case['name'] == 'add_scalar' else [0]
                for mode in modes:
                    folder = ALIAS / f'tests/{kind}_fixtures' / case['name']
                    tag = f'{kind}_{"cand" if cand else "base"}_{case["name"]}_{mode}'
                    cp, dt = run([VVP, '-i', str(exe), f'+folder={folder.as_posix()}',
                                  f'+nbytes={case["output_bytes"]}', f'+mode={mode}'], LOGS)
                    (LOGS / f'{tag}.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
                    ok = cp.returncode == 0 and f'V022_{kind.upper()}_AXI_PASS' in cp.stdout
                    m = CYC.search(cp.stdout)
                    res.append(dict(kind=kind, dut='cand' if cand else 'base', fixture=case['name'],
                                    mode=mode, cycles=int(m.group(1)) if m else None,
                                    pass_=ok, host_seconds=round(dt, 3),
                                    log=str(LOGS / f'{tag}.log')))
                    if not ok:
                        raise RuntimeError(tag + ' failed')
                    print(tag, res[-1]['cycles'], flush=True)
    # 同 fixture/mode 对比
    by = {(r['kind'], r['fixture'], r['mode'], r['dut']): r for r in res}
    for r in res:
        if r['dut'] != 'cand':
            continue
        b = by.get((r['kind'], r['fixture'], r['mode'], 'base'))
        if b and b['cycles'] and r['cycles']:
            r['speedup'] = round(b['cycles'] / r['cycles'], 4)
    inputs = {}
    for p in (WORK / 'rtl/ddr_vector_axi.sv', WORK / 'rtl/ddr_layout_axi.sv',
              WORK / 'rtl/ddr_vector_engine.sv', WORK / 'rtl/ddr_layout_engine.sv',
              WORK / 'rtl/axi_dma_v019.sv', ROOT / 'candidate/axi_dma_v020_multi.sv',
              ROOT / 'candidate/ddr_vector_axi_v020.sv', ROOT / 'candidate/ddr_layout_axi_v020.sv'):
        if p.exists():
            inputs[str(p)] = hashlib.sha256(p.read_bytes()).hexdigest()
    out = dict(scope='Icarus RTL：原 vector/layout 夹具 + 独立 golden；只换 DMA 层。',
               note='小请求负载（20 read/16 write 请求，64beat 级）下 DMA 多在途收益有限；大范围 DMA 微基准另见 dma_compare.json。',
               results=res, source_sha256=inputs)
    (REPORTS / 'vector_dma_compare.json').write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
    print('VECTOR_DMA_COMPARE_DONE', len(res))


if __name__ == '__main__':
    main()
