#!/usr/bin/env python3
"""Sequential reproducible test driver (no parallel compiles).

Every command, return code, log and artifact hash is written under
ds_graph/reports/run_all.  Icarus is the functional simulator.  Verilator is
used only as an independent structural lint, with -j 1.
"""
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

TASK = Path(__file__).resolve().parents[1]
PROJ = TASK.parents[1]
WORK = PROJ / 'work'
REP = TASK / 'reports' / 'run_all'
REP.mkdir(parents=True, exist_ok=True)
FIX = TASK / 'tests' / 'fixtures'

CTRL_SRC = ['rtl/wc_graph_ctrl.sv', str(WORK / 'rtl/axi_dma_v019.sv'),
            'tb/wc_graph_bfm.sv', 'tb/tb_wc_graph_ctrl.sv']
REAL_SRC = ['rtl/wc_graph_top.sv', 'rtl/wc_graph_ctrl.sv',
            str(WORK / 'rtl/ddr_vector_axi.sv'), str(WORK / 'rtl/ddr_vector_engine.sv'),
            str(WORK / 'rtl/ddr_layout_axi.sv'), str(WORK / 'rtl/ddr_layout_engine.sv'),
            str(WORK / 'rtl/asr_fp32_alu.sv'), str(WORK / 'rtl/u16_divmod.sv'),
            str(WORK / 'rtl/axi_dma_v019.sv'),
            str(WORK / 'tests/fma_forbidden_stub.sv'),
            'tb/wc_graph_bfm.sv', 'tb/tb_wc_graph_real.sv']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(name, cmd, expect=0, timeout=900):
    t0 = time.time()
    cp = subprocess.run(cmd, cwd=TASK, capture_output=True, text=True, timeout=timeout)
    out = cp.stdout + cp.stderr
    (REP / f'{name}.log').write_text(out)
    rec = dict(name=name, cmd=cmd, rc=cp.returncode, expect_rc=expect,
               ok=cp.returncode == expect, seconds=round(time.time() - t0, 3),
               tail='\n'.join(out.splitlines()[-6:]))
    return rec, out


def main():
    rows = []
    for name, cmd, expect in [
        ('explore_sources', ['python3', 'scripts/explore_sources.py'], 0),
        ('allocator', ['python3', 'scripts/allocator.py'], 0),
        ('compile_graph', ['python3', 'scripts/compile_graph.py'], 0),
        ('make_fixtures', ['python3', 'scripts/make_fixtures.py'], 0),
        ('check_alloc', ['python3', 'scripts/check_alloc.py'], 0),
        ('verify_whole68', ['python3', 'scripts/verify_graph.py',
                            '--plan', 'analysis/whole68_global.bin',
                            '--alloc', 'analysis/global_alloc.json',
                            '--tag', 'whole68_global'], 0),
        ('verify_ledger591', ['python3', 'scripts/verify_graph.py',
                              '--plan', 'analysis/ledger591.bin',
                              '--alloc', 'analysis/global_alloc.json',
                              '--tag', 'ledger591'], 0),
        ('verify_small_real', ['python3', 'scripts/verify_graph.py',
                               '--plan', 'analysis/small_real.bin',
                               '--tag', 'small_real'], 0),
        ('reject_bad_root', ['python3', 'scripts/verify_graph.py',
                             '--plan', 'analysis/bad_root.bin',
                             '--tag', 'bad_root', '--expect-reject'], 0),
        ('reject_no_output', ['python3', 'scripts/verify_graph.py',
                              '--plan', 'analysis/no_output.bin',
                              '--tag', 'no_output', '--expect-reject'], 0),
        ('reject_bad_hash', ['python3', 'scripts/verify_graph.py',
                             '--plan', 'analysis/bad_hash.bin',
                             '--tag', 'bad_hash', '--expect-reject'], 0),
        ('reject_forward_dep', ['python3', 'scripts/verify_graph.py',
                                '--plan', 'analysis/forward_dep.bin',
                                '--tag', 'forward_dep', '--expect-reject'], 0),
    ]:
        rec, out = run(name, cmd, expect)
        rows.append(rec)

    # Icarus builds, one at a time.
    rec, _ = run('iverilog_ctrl', ['iverilog', '-g2012', '-s', 'tb_wc_graph_ctrl',
                                   '-o', str(REP / 'ctrl.vvp'), *CTRL_SRC], 0)
    rows.append(rec)
    rec, _ = run('iverilog_real', ['iverilog', '-g2012', '-s', 'tb_wc_graph_real',
                                   '-o', str(REP / 'real.vvp'), *REAL_SRC], 0)
    rows.append(rec)

    # Control tests.  Mode 0 is the same 4-node chain as the real test but with
    # stubs; mode 1 is the real 68-program control plan; mode 2 is the 591
    # ledger replay; modes 3..6 are negative guards; mode 7 is retention.
    for m in range(9):
        rec, out = run(f'run_ctrl_mode{m}',
                       ['vvp', str(REP / 'ctrl.vvp'), f'+mode={m}',
                        '+memfile=tests/fixtures/mem_graph.hex', '+seed=7'], 0)
        rec['metrics'] = re.findall(r'WC_GRAPH_CTRL_PASS.*', out)
        rows.append(rec)

    rec, out = run('run_real_mode10',
                   ['vvp', str(REP / 'real.vvp'), '+mode=10',
                    '+memfile=tests/fixtures/mem_graph.hex', '+seed=7'], 0)
    rec['metrics'] = re.findall(r'WC_GRAPH_REAL_PASS.*', out)
    rows.append(rec)

    # Independent structural lint (-j 1, no synthesis).
    lint = ['verilator', '--lint-only', '-j', '1', '--timing', '-Wno-fatal',
            '-Wno-WIDTH', '-Wno-UNOPTFLAT', '-Wno-CASEINCOMPLETE', '-Wno-LATCH',
            '-Wno-COMBDLY', '--top-module', 'wc_graph_ctrl',
            'rtl/wc_graph_ctrl.sv']
    rec, _ = run('verilator_lint_ctrl', lint, 0, timeout=600)
    rows.append(rec)
    lint_top = ['verilator', '--lint-only', '-j', '1', '--timing', '-Wno-fatal',
                '-Wno-WIDTH', '-Wno-UNOPTFLAT', '-Wno-CASEINCOMPLETE', '-Wno-LATCH',
                '-Wno-COMBDLY', '--top-module', 'wc_graph_top',
                'rtl/wc_graph_top.sv', 'rtl/wc_graph_ctrl.sv',
                str(WORK / 'rtl/ddr_vector_axi.sv'), str(WORK / 'rtl/ddr_vector_engine.sv'),
                str(WORK / 'rtl/ddr_layout_axi.sv'), str(WORK / 'rtl/ddr_layout_engine.sv'),
                str(WORK / 'rtl/asr_fp32_alu.sv'), str(WORK / 'rtl/u16_divmod.sv'),
                str(WORK / 'rtl/axi_dma_v019.sv'),
                str(WORK / 'tests/fma_forbidden_stub.sv')]
    rec, _ = run('verilator_lint_top', lint_top, 0, timeout=900)
    rows.append(rec)

    failed = [r for r in rows if not r['ok']]
    artifacts = {}
    for p in sorted((TASK / 'analysis').glob('*')):
        if p.is_file() and p.suffix in ('.bin', '.json'):
            artifacts[str(p.relative_to(TASK))] = sha(p)
    artifacts['tests/fixtures/mem_graph.hex'] = sha(FIX / 'mem_graph.hex')
    artifacts['tests/fixtures/gold_small.hex'] = sha(FIX / 'gold_small.hex')
    out = dict(run_all_ok=not failed, total=len(rows), passed=len(rows) - len(failed),
               failed=[r['name'] for r in failed], rows=rows,
               artifacts=artifacts, core_hz='logic only; no frequency claim',
               generated_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
    (REP / 'run_all.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps(dict(run_all_ok=out['run_all_ok'], total=out['total'],
                          passed=out['passed'], failed=out['failed']), indent=2))
    return 0 if not failed else 1


if __name__ == '__main__':
    raise SystemExit(main())
