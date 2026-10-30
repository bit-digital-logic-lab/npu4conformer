#!/usr/bin/env python3
"""Run the complete W023 evidence set sequentially (no parallel compiles).

All outputs stay in this task directory.  Every command, return code and key
metric is recorded.  Icarus is the primary simulator; Verilator is an
independent 2-state build/run check with the same BFM and plusargs.
"""
import json, re, subprocess, time
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
WORK = HERE.parents[1] / 'work'
REP = HERE / 'reports' / 'run_all'
REP.mkdir(parents=True, exist_ok=True)
FIX = HERE / 'tests/fixtures'
IVER = 'iverilog'
VVP = 'vvp'
VER = 'verilator'

COMMON = [str(WORK / 'rtl/axi_dma_v019.sv')]
CTRL_SRC = ['rtl/wc_superplan_ctrl.sv', *COMMON, 'tb/wc_axi_bfm.sv', 'tb/tb_wc_ctrl.sv']
TOP_SRC = [
    'rtl/wc_plan_top_v023.sv', 'rtl/wc_superplan_ctrl.sv',
    str(WORK / 'rtl/pl_execution_plan_v022.sv'),
    str(WORK / 'rtl/ddr_vector_axi.sv'), str(WORK / 'rtl/ddr_vector_engine.sv'),
    str(WORK / 'rtl/ddr_layout_axi.sv'), str(WORK / 'rtl/ddr_layout_engine.sv'),
    str(WORK / 'rtl/asr_fp32_alu.sv'), str(WORK / 'rtl/u16_divmod.sv'),
    *COMMON, str(WORK / 'tests/fma_forbidden_stub.sv'),
    'tb/wc_axi_bfm.sv', 'tb/tb_wc_top.sv']
BEFORE_SRC = [
    str(WORK / 'rtl/pl_execution_plan_v022.sv'),
    str(WORK / 'rtl/ddr_vector_axi.sv'), str(WORK / 'rtl/ddr_vector_engine.sv'),
    str(WORK / 'rtl/ddr_layout_axi.sv'), str(WORK / 'rtl/ddr_layout_engine.sv'),
    str(WORK / 'rtl/asr_fp32_alu.sv'), str(WORK / 'rtl/u16_divmod.sv'),
    *COMMON, str(WORK / 'tests/fma_forbidden_stub.sv'),
    'tb/wc_axi_bfm.sv', 'tb/tb_wc_before.sv']
BEFORE68_SRC = ['rtl/wc_superplan_ctrl.sv', *COMMON,
                'tb/wc_axi_bfm.sv', 'tb/tb_wc_ctrl68_before.sv']
CSR_SRC = ['rtl/wc_plan_csr.sv', 'tb/tb_wc_csr.sv']


def run(name, cmd, timeout=300, expect_rc=0):
    t0 = time.time()
    cp = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True, timeout=timeout)
    out = cp.stdout + cp.stderr
    (REP / f'{name}.log').write_text(out)
    rec = dict(name=name, cmd=cmd, rc=cp.returncode, seconds=round(time.time() - t0, 3),
               expect_rc=expect_rc, ok=(cp.returncode == expect_rc),
               tail='\n'.join(out.splitlines()[-8:]))
    return rec, out


def parse_metrics(text):
    m = {}
    for pat, key in [
        (r'WC_CTRL_PASS mode=\s*(\d+) cycles=\s*(\d+) completed=\s*(\d+) err=(\S+)', 'ctrl'),
        (r'WC_TOP_PASS mode=\s*(\d+) cycles=\s*(\d+) completed=\s*(\d+) err=(\S+)', 'top'),
        (r'WC_BEFORE_PASS starts=\s*(\d+) dones=\s*(\d+) cycles=\s*(\d+) gap=(\d+)', 'before'),
        (r'WC_CTRL68_BEFORE_PASS starts=\s*(\d+) dones=\s*(\d+) cycles=\s*(\d+)', 'before68'),
    ]:
        mm = re.search(pat, text)
        if mm:
            m[key] = mm.groups()
    return m


def main():
    rows = []
    # Static analysis/compiler chain.
    for name, cmd, expect in [
        ('analysis', ['python3', 'scripts/wc_analysis.py'], 0),
        ('host_audit', ['python3', 'scripts/wc_host_audit.py'], 0),
        ('fixtures', ['python3', 'scripts/wc_fixtures.py'], 0),
        ('compile68', ['python3', 'scripts/wc_compile.py'], 0),
        ('verify68_serial', ['python3', 'scripts/wc_verify_plan.py',
                             '--plan', 'analysis/whole68_serial.bin', '--tag', 'real68'], 0),
        ('verify68_roots_strict', ['python3', 'scripts/wc_verify_plan.py',
                                   '--plan', 'analysis/whole68_roots.bin', '--tag', 'roots_strict'], 1),
        ('compiler_random', ['python3', 'scripts/test_compiler_random.py'], 0),
        ('clearance', ['python3', 'scripts/wc_clearance.py'], 0),
        ('ctrl68_fixture', ['python3', 'scripts/wc_ctrl68_fixture.py'], 0),
    ]:
        rec, out = run(name, cmd, timeout=600, expect_rc=expect)
        rec['metrics'] = parse_metrics(out)
        rows.append(rec)
    # Verilator lint (structural compile only, no timing claim).
    lint = ['--lint-only', '--timing', '-Wno-fatal', '-Wno-WIDTH', '-Wno-UNOPTFLAT',
            '-Wno-CASEINCOMPLETE', '-Wno-LATCH', '-Wno-COMBDLY']
    rec, _ = run('verilator_lint_ctrl', [VER, *lint, '--top-module', 'wc_superplan_ctrl',
                                         'rtl/wc_superplan_ctrl.sv'], timeout=300)
    rows.append(rec)
    lint_top_src = [x for x in TOP_SRC if not x.startswith('tb/') and 'tb_wc_top' not in x]
    rec, _ = run('verilator_lint_top', [VER, *lint, '--top-module', 'wc_plan_top_v023',
                                        *lint_top_src], timeout=300)
    rows.append(rec)
    # Icarus compiles.
    builds = {}
    for name, src in [('ctrl_iv', CTRL_SRC), ('top_iv', TOP_SRC),
                      ('before_iv', BEFORE_SRC), ('before68_iv', BEFORE68_SRC),
                      ('csr_iv', CSR_SRC)]:
        exe = str(REP / f'{name}.vvp')
        cmd = [IVER, '-g2012', '-s', 'tb_wc_ctrl' if name == 'ctrl_iv' else
               ('tb_wc_csr' if name == 'csr_iv' else
               ('tb_wc_top' if name == 'top_iv' else
                ('tb_wc_before' if name == 'before_iv' else 'tb_wc_ctrl68_before'))),
               '-o', exe, *src]
        rec, _ = run(f'compile_{name}', cmd, timeout=300, expect_rc=0)
        rows.append(rec)
        builds[name] = exe
    # Icarus runs.
    def ctrl_args(mode, seed):
        a = [builds['ctrl_iv'], f'+mode={mode}', f'+seed={seed}']
        if mode != 7:
            a += ['+memfile=tests/fixtures/mem_init.hex']
        if mode == 0:
            a += ['+plan=10000000']
        elif mode == 1:
            a += ['+plan=10001000', '+fault_mat=1', '+dly_mat=50', '+dly_lay=200']
        elif mode == 2:
            a += ['+plan=10002000']
        elif mode == 3:
            a += ['+plan=10003000']
        elif mode == 4:
            a += ['+plan=10004000']
        elif mode == 5:
            a += ['+plan=10005000']
        elif mode == 6:
            a += ['+plan=10006000']
        elif mode == 7:
            a += ['+plan=10030000', '+param_end=40000000',
                  '+memfile=tests/fixtures/mem68.hex']
        return a
    for mode in range(8):
        for seed in ([1, 12345] if mode in (0, 7) else [7]):
            rec, out = run(f'ctrl_mode{mode}_seed{seed}', ctrl_args(mode, seed), timeout=120)
            rec['metrics'] = parse_metrics(out)
            rec['passed'] = rec['ok'] and 'WC_CTRL_PASS' in out and 'FATAL' not in out
            rows.append(rec)
    for mode, plan in [(10, '10008000'), (11, '10009000'), (12, '1000a000')]:
        for seed in (1, 12345):
            cmd = [builds['top_iv'], f'+mode={mode}', f'+plan={plan}',
                   '+memfile=tests/fixtures/mem_init.hex', f'+seed={seed}']
            rec, out = run(f'top_mode{mode}_seed{seed}', cmd, timeout=120)
            rec['metrics'] = parse_metrics(out)
            rec['passed'] = rec['ok'] and 'WC_TOP_PASS' in out and 'FATAL' not in out
            rows.append(rec)
    rec, out = run('csr', [builds['csr_iv']], timeout=60)
    rec['metrics'] = {'csr': ['pass'] if 'WC_CSR_PASS' in out else ['fail']}
    rec['passed'] = rec['ok'] and 'WC_CSR_PASS' in out and 'FATAL' not in out
    rows.append(rec)
    for gap in (0, 200):
        cmd = [builds['before_iv'], f'+gap={gap}', '+memfile=tests/fixtures/mem_init.hex', '+seed=7']
        rec, out = run(f'before_gap{gap}', cmd, timeout=120)
        rec['metrics'] = parse_metrics(out)
        rec['passed'] = rec['ok'] and 'WC_BEFORE_PASS' in out and 'FATAL' not in out
        rows.append(rec)
    rec, out = run('before68', [builds['before68_iv'], '+memfile=tests/fixtures/mem68_before.hex', '+seed=7'],
                   timeout=120)
    rec['metrics'] = parse_metrics(out)
    rec['passed'] = rec['ok'] and 'WC_CTRL68_BEFORE_PASS' in out and 'FATAL' not in out
    rows.append(rec)
    # Verilator builds/runs (independent 2-state path).
    vbuilds = {}
    for name, top, src in [
        ('ctrl_v', 'tb_wc_ctrl', ['rtl/wc_superplan_ctrl.sv', *COMMON,
                                  'tb/wc_axi_bfm.sv', 'tb/tb_wc_ctrl.sv']),
        ('top_v', 'tb_wc_top', TOP_SRC),
    ]:
        mdir = REP / f'obj_{name}'
        exe_name = f'{name}_sim'
        cmd = [VER, '--binary', '--timing', '-j', '2', '-Wno-fatal', '-Wno-WIDTH',
               '-Wno-UNOPTFLAT', '-Wno-CASEINCOMPLETE', '-Wno-LATCH', '-Wno-COMBDLY',
               '--top-module', top, '--Mdir', str(mdir), '-o', exe_name, *src]
        rec, _ = run(f'compile_{name}', cmd, timeout=600, expect_rc=0)
        rows.append(rec)
        vbuilds[name] = str(mdir / exe_name)
    if Path(vbuilds['ctrl_v']).exists():
        for mode, extra in [(0, ['+plan=10000000', '+memfile=tests/fixtures/mem_init.hex']),
                            (7, ['+plan=10030000', '+param_end=40000000',
                                 '+memfile=tests/fixtures/mem68.hex'])]:
            cmd = [vbuilds['ctrl_v'], f'+mode={mode}', '+seed=7', *extra]
            rec, out = run(f'verilator_ctrl_mode{mode}', cmd, timeout=120)
            rec['metrics'] = parse_metrics(out)
            rec['passed'] = rec['ok'] and 'WC_CTRL_PASS' in out
            rows.append(rec)
    if Path(vbuilds['top_v']).exists():
        for mode, plan in [(10, '10008000'), (12, '1000a000')]:
            cmd = [vbuilds['top_v'], f'+mode={mode}', f'+plan={plan}',
                   '+memfile=tests/fixtures/mem_init.hex', '+seed=7']
            rec, out = run(f'verilator_top_mode{mode}', cmd, timeout=120)
            rec['metrics'] = parse_metrics(out)
            rec['passed'] = rec['ok'] and 'WC_TOP_PASS' in out
            rows.append(rec)
    # Summary.
    sims = [r for r in rows if 'passed' in r]
    summary = dict(
        generated_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        total_records=len(rows), sim_runs=len(sims),
        sim_passed=sum(1 for r in sims if r['passed']),
        sim_failed=sum(1 for r in sims if not r['passed']),
        static_checks=sum(1 for r in rows if 'expect_rc' in r and 'passed' not in r),
        all_ok=all(r['ok'] for r in rows) and all(r['passed'] for r in sims),
        scope='Control/data-chain logic simulation only; no synthesis, STA, board, full CASE0000 or whole-model claim.',
        compiler_random='reports/compiler_random.json',
        analysis='analysis/analysis.json',
        whole68='analysis/whole68.json',
        verilator_lint='reports/verilator/lint_ctrl.log, reports/verilator/lint_top.log',
        rows=rows)
    (REP / 'run_all.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({k: v for k, v in summary.items() if k != 'rows'}, indent=2))


if __name__ == '__main__':
    main()
