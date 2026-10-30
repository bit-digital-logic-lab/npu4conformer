#!/usr/bin/env python3
"""部分 WSTRB 字节计数回归：V019 与 V020 同写负载、同 BFM。
验证 write_bytes == sum(popcount(WSTRB))，避免把尾拍部分字节算成 16B。
输出 bench/reports/strobe_account.json；非板级、非综合。"""
import json, re, shutil, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORK = Path('/home/yang/Desktop/项目/work')
TB = HERE / 'tb_strobe_account.sv'
BFM = HERE / 'bfm/axi128_ddr_bfm_ds.sv'
BASE = WORK / 'rtl/axi_dma_v019.sv'
CAND = ROOT / 'candidate/axi_dma_v020_multi.sv'
IVERILOG = shutil.which('iverilog')
VVP = shutil.which('vvp')
OUT = HERE / 'candidate'
LOGS = HERE / 'logs/strobe'
REPORTS = HERE / 'reports'
for d in (OUT, LOGS, REPORTS):
    d.mkdir(parents=True, exist_ok=True)

PAT = re.compile(r'STROBE_RESULT exp=(\d+) got=(\d+) error=(\d+) cycles=(\d+) '
                 r'dma_wbeats=(\d+) bfm_wbeats=(\d+)')


def one(dut):
    exe = OUT / f'strobe_{dut}.vvp'
    src = BASE if dut == 'base' else CAND
    cmd = [IVERILOG, '-g2012', '-s', 'tb_strobe_account', '-o', str(exe)]
    if dut == 'base':
        cmd.append('-DUSE_V019')
    cmd += [str(TB), str(BFM), str(src)]
    cp = subprocess.run(cmd, cwd=OUT, capture_output=True, text=True, timeout=180)
    (LOGS / f'{dut}.compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode != 0:
        return dict(dut=dut, pass_=False, error='compile', log=str(LOGS / f'{dut}.compile.log'))
    cp = subprocess.run([VVP, str(exe)], cwd=OUT, capture_output=True, text=True, timeout=180)
    (LOGS / f'{dut}.run.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    m = PAT.search(cp.stdout + cp.stderr)
    if not m:
        return dict(dut=dut, pass_=False, error='no_result', log=str(LOGS / f'{dut}.run.log'))
    exp, got, err, cyc, dma_wb, bfm_wb = map(int, m.groups())
    return dict(dut=dut, expected_bytes=exp, write_bytes=got, dma_error=err,
                cycles=cyc, dma_write_beats=dma_wb, bfm_write_beats=bfm_wb,
                pass_=(cp.returncode == 0 and err == 0 and got == exp),
                log=str(LOGS / f'{dut}.run.log'))


res = [one('base'), one('cand')]
out = dict(
    note='单端口 AXI128 BFM；64beat 写，8 种部分 WSTRB 循环，每 8beat 共 53 字节。'
         'V019/V020 的 write_bytes 都必须按 popcount 累计。',
    nbeats=64, bytes_per_8beats=53, expected_bytes=424, results=res,
    pass_=all(r.get('pass_') for r in res),
)
(REPORTS / 'strobe_account.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n',
                                             encoding='utf-8')
for r in res:
    print(f"{'PASS' if r.get('pass_') else 'FAIL'} {r['dut']} "
          f"exp={r.get('expected_bytes')} got={r.get('write_bytes')} cycles={r.get('cycles')}")
print('STROBE_ACCOUNT_DONE')
raise SystemExit(0 if out['pass_'] else 1)
