#!/usr/bin/env python3
"""Assemble result.json from the actual run logs.  No old PASS is reused."""
import hashlib, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
LOGS = HERE / 'logs'
REP = HERE / 'reports'
FIX = HERE / 'fixtures'
REP.mkdir(exist_ok=True)


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


def main():
    rc = parse_rc()
    reg = []
    p = REP / 'regression.tsv'
    if p.exists():
        for ln in p.read_text().splitlines():
            parts = ln.split()
            if len(parts) >= 3:
                reg.append({'case': parts[0], 'sim_rc': int(parts[1]),
                            'check_rc': int(parts[2])})
    manifest = json.loads((FIX / 'manifest.json').read_text())
    cases = {c['name']: c for c in manifest['cases']}
    unique = {}
    if (REP / 'unique_modules.json').exists():
        unique = json.loads((REP / 'unique_modules.json').read_text())

    compile_names = [k for k in rc if k.startswith('compile_')]
    compile_ok = all(rc[k] == 0 for k in compile_names) and bool(compile_names)
    sim_ok = all(r['sim_rc'] == 0 and r['check_rc'] == 0 for r in reg) and bool(reg)
    neg_ok = False
    negp = REP / 'negative_control.txt'
    if negp.exists():
        neg_ok = 'observed=expected_failure' in negp.read_text() and 'rc=1' in negp.read_text()

    # Optional cross-checks; if their artifacts exist they must pass.
    frozen = None
    fp = REP / 'frozen.json'
    if fp.exists():
        frozen = json.loads(fp.read_text())
    base_lines = []
    bp = LOGS / 'rc_baseline.txt'
    if bp.exists():
        base_lines = bp.read_text().splitlines()
    bp_rows = []
    bpp = REP / 'backpressure.tsv'
    if bpp.exists():
        for ln in bpp.read_text().splitlines():
            a = ln.split()
            if len(a) >= 5:
                bp_rows.append({'case': a[0], 'seed': a[1], 'tag': a[2],
                                'sim_rc': int(a[3]), 'check_rc': int(a[4])})
    cross_ok = True
    if frozen is not None:
        cross_ok = cross_ok and bool(frozen.get('pass'))
    if base_lines:
        cross_ok = cross_ok and any('baseline_vs_new byte_identical=1' in x for x in base_lines)
    if bp_rows:
        cross_ok = cross_ok and all(r['sim_rc'] == 0 and r['check_rc'] == 0 for r in bp_rows)

    required_groups = {
        'full8734': any(r['case'] == 'full8734' and r['check_rc'] == 0 for r in reg),
        'tails': all(any(r['case'] == f'tail_{t:04d}' and r['check_rc'] == 0 for r in reg)
                     for t in [256] + list(range(257, 274)) + [383, 511, 513, 1001]),
        'operand_modes': all(any(r['case'] == n and r['check_rc'] == 0 for r in reg)
                             for n in ['fma_bscalar_1001', 'fma_cscalar_1001',
                                       'fma_period32_1001', 'fma_period128_1001',
                                       'fma_btiled1024', 'fma_btiled2048']),
        'official_fixture': any(r['case'] == 'official_fixture_1001' and r['check_rc'] == 0 for r in reg),
        'lane_short': all(any(r['case'].startswith(prefix) and r['check_rc'] == 0 for r in reg)
                          for prefix in ['mul_', 'add_', 'i16_']),
        'abort': any(r['case'] == 'abort_newepoch' and r['check_rc'] == 0 for r in reg),
        'reset': any(r['case'] == 'reset_newepoch' and r['check_rc'] == 0 for r in reg),
        'latency_x3': all(any(r['case'] == f'x3:{n}' and r['check_rc'] == 0 for r in reg)
                          for n in ['full8734', 'official_fixture_1001', 'tail_0260',
                                    'tail_0513', 'mul_0005', 'i16_0007']),
    }
    pass_ = bool(compile_ok and sim_ok and unique.get('pass') and neg_ok
                 and all(required_groups.values()) and cross_ok)

    files = [
        'filelist_vector_fma.f', 'run_all.sh',
        'rtl/ddr_vector_engine_pipe.sv', 'rtl/vector_fma_lane.sv',
        'rtl/fp32_fma_pipe.sv', 'rtl/asr_fma_ip.sv',
        'tb/tb_vector_fma_plan.sv', 'tb/tb_vector_fma_abort_reset.sv',
        'tb/wc_graph_bfm.sv',
        'scripts/gen_cases.py', 'scripts/check_case.py',
        'scripts/check_unique_modules.py', 'scripts/make_result.py',
        'scripts/check_frozen.py', 'scripts/summarize.py',
        'scripts/fill_report.py', 'baseline_compare.sh',
        'backpressure_seeds.sh', 'filelist_baseline.f',
        'fixtures/manifest.json',
    ]
    shas = {f: sha(HERE / f) for f in files if (HERE / f).exists()}

    result = {
        'task': 'ds_vector_fma',
        'model': 'opencode-go/deepseek-v4.1-flash',
        'scope': 'local RTL logic simulation: op17 FMA II=1 single-lane ready/valid into the real fp32_fma_pipe; 4-lane fixed-op short-bank tail fix and fallback removal; graph-level vector regression',
        'pass': pass_,
        'rc': rc,
        'checks': {
            'compile_ok': compile_ok,
            'sim_and_check_ok': sim_ok,
            'unique_modules': unique.get('pass', False),
            'negative_control_expected_failure': neg_ok,
            'required_groups': required_groups,
        },
        'case_count': len(cases),
        'regression': reg,
        'cross_checks': {
            'frozen_sources': frozen,
            'baseline_compare': base_lines,
            'backpressure_seeds': bp_rows,
        },
        'upstream_sha256': manifest.get('upstream', {}),
        'sha256': shas,
        'filelist': 'filelist_vector_fma.f',
        'reproduce': 'bash run_all.sh',
        'tested': [
            'full 8734 adversarial FMA vectors (modes 0/1/2 mapped to op17) through WCPG graph + shared AXI128 + real fp32_fma_pipe',
            'tail totals 256 (tail 0), 257..273 (tails 1..17), 383, 511, 513, 1001',
            'bscalar, cscalar, periodic B period 32/128, btiled 32-element tile 1024/2048',
            'official work/tests/fma_fixture 1001-vector memory/gold/descriptor',
            '4-lane fixed-op short banks: MUL/ADD/F32_I16 totals 1..9,17,127,255,257,1001 (16-bit tail packing included)',
            'abort mid-op and reset mid-op, new-epoch 257-value plan, old region unchanged, no AW/B quiescent window',
            'latency-variable check with vector_fma_lane EXTRA_STAGES=3 on full8734/official/tails/lane cases',
            'negative control: one corrupted expected word must make the checker exit non-zero',
            'same BFM and same input images; b_count_at_done=0 and no post-done AW/B',
        ],
        'unfinished': [
            '4-lane op17 (four FMA cores / four 129-bit accumulators) is costed in REPORT.md but not implemented; this delivery is single-lane II=1',
            'multi-tile btiled (period > 32 with coefficient-tile switching) is existing engine behaviour, not changed or claimed here',
            'matrix W7A16C48 numerics were not modified or re-verified here',
            'no full 591-tensor DAG, host executor, ONNX, WER/CER, synthesis/STA, board, VNC or push',
            'no frequency or whole-model seconds claim',
        ],
        'limits': [
            'logic simulation with a sparse AXI BFM, not a DDR timing model',
            'official fixture and 8734 set are seed/selection evidence, not an exhaustive 2^96 FMA proof',
            'matrix/layout abort is outside this task; only the vector child has abort/drain',
        ],
    }
    (HERE / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({
        'pass': pass_, 'compile_ok': compile_ok, 'sim_ok': sim_ok,
        'unique': unique.get('pass'), 'negative_ok': neg_ok,
        'required_groups': required_groups, 'cases': len(reg),
    }, indent=2))
    return 0 if pass_ else 1


if __name__ == '__main__':
    sys.exit(main())
