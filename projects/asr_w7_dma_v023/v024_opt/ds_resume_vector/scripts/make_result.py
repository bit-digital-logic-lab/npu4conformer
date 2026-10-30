#!/usr/bin/env python3
"""Assemble result.json strictly from this run's logs.  No old PASS is reused.

The expected case set is derived from the freshly generated manifest plus the
exact latency/7-stage/backpressure stage lists.  Missing cases, extra cases,
nonzero sim/check rc, a missing stage rc, an unexpected negative-control
result or a baseline mismatch makes pass=false and the process exit 1.  The
same boolean is written to reports/run_all_status.json so run_all.sh exits with
the identical rc.
"""
import datetime, hashlib, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
LOGS = HERE / 'logs'
REP = HERE / 'reports'
FIX = HERE / 'fixtures'

X3_CASES = ['full8734', 'official_fixture_1001', 'tail_0260', 'tail_0270',
            'tail_0513', 'mul_0010', 'i16_0016']
FMA7_CASES = ['full8734', 'official_fixture_1001', 'tail_0260', 'tail_0270',
              'tail_0513', 'mul_0010', 'i16_0016', 'abort_newepoch',
              'reset_newepoch']
BASE_STAGES = [
    'audit_imported', 'gen_fixtures', 'check_frozen', 'check_unique_modules',
    'compile_top', 'compile_plan', 'compile_plan_x3', 'compile_abort',
    'compile_top_fma7', 'compile_plan_fma7', 'compile_abort_fma7',
    'compile_fma7_latency', 'negative_control', 'backpressure_seeds',
    'baseline_compare', 'summarize',
]
BP_ROWS_EXPECTED = 13


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def parse_rc():
    out = {}
    p = LOGS / 'rc.txt'
    if not p.exists():
        return out
    for ln in p.read_text().splitlines():
        m = re.match(r'(\S+)\s+rc=(-?\d+)', ln)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def parse_reg():
    rows = []
    p = REP / 'regression.tsv'
    if p.exists():
        for ln in p.read_text().splitlines():
            a = ln.split()
            if len(a) >= 3:
                rows.append({'case': a[0], 'sim_rc': int(a[1]),
                             'check_rc': int(a[2])})
    return rows


def parse_bp():
    rows = []
    p = REP / 'backpressure.tsv'
    if p.exists():
        for ln in p.read_text().splitlines():
            a = ln.split()
            if len(a) >= 5:
                rows.append({'case': a[0], 'seed': a[1], 'tag': a[2],
                             'sim_rc': int(a[3]), 'check_rc': int(a[4])})
    return rows


def parse_kv(path):
    d = {}
    p = Path(path)
    if p.exists():
        for ln in p.read_text().splitlines():
            if '=' in ln:
                k, v = ln.split('=', 1)
                d[k.strip()] = v.strip()
    return d


def main():
    out = {
        'task': 'ds_resume_vector',
        'model': 'opencode-go/deepseek-v4.1-flash',
        'timestamp': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'scope': ('local RTL logic simulation only: op17 FMA II=1 into the real '
                  '4-stage fp32_fma_pipe and into the ds_fma_deep 7-stage '
                  'candidate; 4-lane fixed-op short-bank tail fix; independent '
                  'gold, backpressure, abort/reset epoch and same-input baseline'),
        'pass': False,
        'run_all_exit_rc': 1,
        'checks': {},
        'regression': [],
    }
    try:
        manifest = json.loads((FIX / 'manifest.json').read_text())
        cases = [c['name'] for c in manifest['cases']]
        expected_reg = set(cases)
        expected_reg |= {f'x3:{c}' for c in X3_CASES}
        expected_reg |= {f'fma7:{c}' for c in FMA7_CASES}
        reg = parse_reg()
        reg_names = [r['case'] for r in reg]
        reg_map = {r['case']: r for r in reg}
        dup_reg = sorted({n for n in reg_names if reg_names.count(n) > 1})
        missing_reg = sorted(expected_reg - set(reg_names))
        extra_reg = sorted(set(reg_names) - expected_reg)
        bad_reg = sorted(r['case'] for r in reg
                         if r['sim_rc'] != 0 or r['check_rc'] != 0)

        rc = parse_rc()
        expected_stages = set(BASE_STAGES)
        expected_stages |= {f'sim_{c}' for c in cases}
        expected_stages |= {f'sim_x3_{c}' for c in X3_CASES}
        expected_stages |= {f'sim_fma7_{c}' for c in FMA7_CASES}
        expected_stages |= {'sim_fma7_latency'}
        missing_stage = sorted(expected_stages - set(rc))
        # run_all records its own final make_result rc after this script reads
        # rc.txt; allow that single self-entry on a manual re-run.
        extra_stage = sorted(set(rc) - expected_stages - {'make_result'})
        bad_stage = sorted(k for k, v in rc.items()
                           if v != 0 and k != 'make_result')

        frozen = json.loads((REP / 'frozen.json').read_text()) \
            if (REP / 'frozen.json').exists() else {'pass': False}
        unique = json.loads((REP / 'unique_modules.json').read_text()) \
            if (REP / 'unique_modules.json').exists() else {'pass': False}

        neg_txt = (REP / 'negative_control.txt').read_text() \
            if (REP / 'negative_control.txt').exists() else ''
        neg_ok = ('overall=pass' in neg_txt and
                  neg_txt.count('observed=expected_failure') == 2)

        bp = parse_bp()
        bp_ok = (len(bp) == BP_ROWS_EXPECTED and
                 all(r['sim_rc'] == 0 and r['check_rc'] == 0 for r in bp) and
                 any(r['tag'].startswith('x7') for r in bp) and
                 any(r['case'] == 'full8734' for r in bp))

        base_lines = []
        p = LOGS / 'rc_baseline.txt'
        if p.exists():
            base_lines = p.read_text().splitlines()
        base_txt = '\n'.join(base_lines)
        base_ok = (base_txt.count('byte_identical=1') == 3 and
                   'BASELINE PASS byte_identical=3/3' in base_txt and
                   all(f'{c}_sim_baseline rc=0' in base_txt
                       for c in ('full8734', 'tail_0270', 'official_fixture_1001')) and
                   all(f'{c}_check_baseline rc=0' in base_txt
                       for c in ('full8734', 'tail_0270', 'official_fixture_1001')))

        fma7_txt = (LOGS / 'fma7_latency.log').read_text() \
            if (LOGS / 'fma7_latency.log').exists() else ''
        fma7_lat_ok = ('FMA7_LATENCY PASS latency=7' in fma7_txt and
                       'ii1=1' in fma7_txt and 'flush_drop=1' in fma7_txt and
                       'new_epoch=1' in fma7_txt)

        imported = json.loads((REP / 'imported_audit.json').read_text()) \
            if (REP / 'imported_audit.json').exists() else {}

        groups = {}
        for r in reg:
            n = r['case']
            if n.startswith('x3:'):
                g = 'latency EXTRA_STAGES=3'
            elif n.startswith('fma7:'):
                g = 'ds_fma_deep 7-stage core'
            elif n.startswith('tail_'):
                g = 'FMA tails'
            elif n.startswith(('mul_', 'add_', 'i16_')):
                g = '4-lane fixed-op tails'
            elif n.startswith('fma_'):
                g = 'FMA operand modes'
            elif n in ('abort_newepoch', 'reset_newepoch'):
                g = 'abort/reset new epoch'
            elif n == 'official_fixture_1001':
                g = 'official fixture'
            elif n == 'full8734':
                g = 'full 8734'
            else:
                g = 'other'
            groups.setdefault(g, []).append(r)

        pass_ = bool(
            not missing_reg and not extra_reg and not dup_reg and not bad_reg and
            not missing_stage and not extra_stage and not bad_stage and
            frozen.get('pass') and unique.get('pass') and neg_ok and bp_ok and
            base_ok and fma7_lat_ok and
            reg_map.get('full8734', {}).get('check_rc') == 0 and
            len(cases) == 122)
        out['checks'] = {
            'expected_case_count': 122,
            'manifest_case_count': len(cases),
            'expected_regression_count': len(expected_reg),
            'regression_count': len(reg),
            'missing_regression': missing_reg,
            'extra_regression': extra_reg,
            'duplicate_regression': dup_reg,
            'nonzero_regression': bad_reg,
            'missing_stage_rc': missing_stage,
            'extra_stage_rc': extra_stage,
            'nonzero_stage_rc': bad_stage,
            'frozen_sources': frozen.get('pass', False),
            'unique_modules': unique.get('pass', False),
            'negative_control_expected_failure': neg_ok,
            'backpressure_rows': len(bp),
            'backpressure_ok': bp_ok,
            'baseline_ok': base_ok,
            'fma7_latency_ok': fma7_lat_ok,
            'groups': {g: {'count': len(v),
                           'sim_ok': all(x['sim_rc'] == 0 for x in v),
                           'check_ok': all(x['check_rc'] == 0 for x in v)}
                       for g, v in sorted(groups.items())},
        }
        out['cases'] = len(cases)
        out['regression'] = reg
        out['regression_count'] = len(reg)
        out['rc'] = rc
        out['stage_failures'] = bad_stage
        out['regression_failures'] = bad_reg
        out['fma7_latency'] = {
            'sha256': sha(HERE / 'fma7/fp32_fma_pipe.sv'),
            'log': 'logs/fma7_latency.log',
            'pass': fma7_lat_ok,
            'measured_latency_cycles': 7,
            'ii': 1,
        }
        out['baseline'] = parse_kv(LOGS / 'rc_baseline.txt')
        out['backpressure'] = bp
        out['imported_audit'] = imported
        out['upstream_sha256'] = manifest.get('upstream', {})
        out['sha256'] = {}
        files = ['filelist_vector_fma.f', 'filelist_vector_fma7.f',
                 'run_all.sh', 'baseline_compare.sh', 'backpressure_seeds.sh',
                 'rtl/ddr_vector_engine_pipe.sv', 'rtl/vector_fma_lane.sv',
                 'rtl/fp32_fma_pipe.sv', 'fma7/fp32_fma_pipe.sv',
                 'baseline/ddr_vector_engine_pipe_base.sv',
                 'tb/wc_graph_bfm.sv', 'tb/tb_vector_fma_plan.sv',
                 'tb/tb_vector_fma_abort_reset.sv', 'tb/tb_fma7_latency.sv',
                 'scripts/gen_cases.py', 'scripts/check_case.py',
                 'scripts/check_unique_modules.py', 'scripts/check_frozen.py',
                 'scripts/audit_imported.py', 'scripts/negative_control.py',
                 'scripts/make_result.py', 'scripts/summarize.py',
                 'scripts/report_gen.py', 'fixtures/manifest.json',
                 'imported/fixtures_manifest.json', 'imported/logs/rc.txt']
        out['sha256'] = {f: sha(HERE / f) for f in files if (HERE / f).exists()}
        out['filelist'] = 'filelist_vector_fma.f (+ filelist_vector_fma7.f)'
        out['reproduce'] = 'bash run_all.sh'
        out['tested'] = [
            'full 8734 adversarial FMA vectors through WCPG graph + shared AXI128 + real 4-stage fp32_fma_pipe',
            'the same full set plus official fixture/tails through the ds_fma_deep 7-stage core (SHA b062284a...)',
            'FMA tails 256 (tail 0), 257..273 (tails 1..17), 383, 511, 513, 1001',
            '4-lane fixed-op MUL/ADD/F32_I16 totals 1..17 (includes the previously untested 10..16), 31/32/33, 63/64/65, 127, 255/256/257, 511, 513, 1001',
            'bscalar, cscalar, periodic B 32/128, btiled 32-element tile 1024/2048',
            'official work/tests/fma_fixture 1001-vector memory/gold/descriptor',
            'latency-variable EXTRA_STAGES=3 build on full/official/tails/fixed-op cases',
            'actual 7-stage latency/II/flush directed test: latency=7, II=1, flush drops in-flight, new epoch exact',
            'random AXI BFM backpressure seeds on canonical and 7-stage builds',
            'abort mid-op and reset mid-op followed by a new-epoch 257-value plan on both core builds',
            'negative control: two corrupted gold words must be rejected by the independent checker',
            'same-input/same-BFM baseline cycle comparison on full8734, tail270 and official fixture',
        ]
        out['unfinished'] = [
            'AR-001 (fp32_fma_pipe asserts in_ready while flush=1) is a core-level protocol finding in ds_fma_deep; this vector engine never issues during core_flush and is not the fix owner (ds_repair_fmaflush).',
            '4-lane op17 (four FMA cores / four 129-bit accumulators) is costed but not implemented; this is a single-lane II=1 op17.',
            'multi-tile btiled (period > 32 with coefficient-tile switching) is existing engine behaviour and is not changed or claimed.',
            'matrix W7A16C48 numerics are not modified or re-verified here; matrix/layout abort is outside this task.',
            'no full 591-tensor DAG, host executor, ONNX, WER/CER, synthesis, STA, Vivado, board, VNC or push.',
            'no frequency, ns, 300/600 MHz or whole-model seconds claim.',
            'the 8,734 vectors and deterministic tails are strong adversarial selection, not an exhaustive 2^96 FMA proof.',
        ]
        out['limits'] = [
            'logic simulation with a sparse AXI BFM, not a DDR timing model',
            'the baseline engine is a copied read-only v023 comparison, not the deliverable',
            'module/vector-child PASS is not a unified-graph or system PASS',
        ]
        out['pass'] = pass_
        out['x3_cases'] = X3_CASES
        out['fma7_cases'] = FMA7_CASES
        summary = json.loads((REP / 'summary.json').read_text()) \
            if (REP / 'summary.json').exists() else {'cases': []}
        import report_gen
        report_gen.write_report(out, summary, HERE)
    except Exception as e:
        out['error'] = repr(e)
        out['pass'] = False

    out['run_all_exit_rc'] = 0 if out['pass'] else 1
    (HERE / 'result.json').write_text(json.dumps(out, indent=2) + '\n')
    status = {
        'rc': out['run_all_exit_rc'],
        'pass': out['pass'],
        'result': 'result.json',
        'stage_failures': out.get('stage_failures', []),
        'regression_failures': out.get('regression_failures', []),
        'error': out.get('error'),
    }
    (REP / 'run_all_status.json').write_text(json.dumps(status, indent=2) + '\n')
    print(json.dumps({k: out.get(k) for k in (
        'pass', 'run_all_exit_rc', 'cases', 'regression_count',
        'stage_failures', 'regression_failures', 'error')}, indent=2))
    return 0 if out['pass'] else 1


if __name__ == '__main__':
    sys.exit(main())
