#!/usr/bin/env python3
"""Strict acceptance checks for the v024 graph/prefetch task.

No old PASS JSON is consulted.  Every check reads this run's logs/outputs and
the frozen independent gold.  Any missing/failed item exits non-zero.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
LOGS = HERE / 'logs'
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)


def load_words(p):
    return [int(x, 16) for x in Path(p).read_text().split()]


def kv_line(text, prefix):
    for line in text.splitlines():
        if line.startswith(prefix):
            return dict(re.findall(r'([A-Za-z_][A-Za-z0-9_]*)=([0-9a-fA-FxX]+)', line))
    return {}


def log(name):
    p = LOGS / name
    return p.read_text(errors='replace') if p.exists() else ''


def as_int(d, k, default=None):
    if k not in d:
        return default
    v = d[k]
    try:
        return int(v, 0)
    except ValueError:
        pass
    try:
        if k in ('error', 'err', 'status') or re.search(r'[a-fA-F]', v):
            return int(v, 16)
        return int(v, 10)
    except ValueError:
        return default


def main():
    checks = []

    def add(name, ok, detail=''):
        checks.append({'name': name, 'pass': bool(ok), 'detail': detail})

    # 0. frozen reference / independent gold recompute
    r = subprocess.run([sys.executable, str(HERE / 'scripts' / 'verify_reference.py')],
                       cwd=str(HERE), capture_output=True, text=True)
    add('reference_frozen_and_independent_gold', r.returncode == 0, r.stdout.strip()[-300:])

    gold = load_words(HERE / 'integrated_copy/fixtures/gold_i16.hex')
    exp = load_words(HERE / 'integrated_copy/fixtures/mat32/exp_c.txt')

    def out_ok(tag):
        f = load_words(LOGS / f'gp_{tag}_final.hex')
        c = load_words(LOGS / f'gp_{tag}_c48.hex')
        fm = sum(1 for a, b in zip(f, gold) if a != b)
        cm = sum(1 for a, b in zip(c, exp) if (a & ((1 << 48) - 1)) != (b & ((1 << 48) - 1)))
        return len(f) == 512 and len(c) == 1024 and fm == 0 and cm == 0, f'f_mism={fm} c48_mism={cm}'

    # 1. baseline / off / on graph runs
    for tag in ['base', 'off', 'on']:
        s = log(f'gp_{tag}.log')
        end = kv_line(s, 'GP_END done=')
        drain = kv_line(s, 'GP_DRAIN')
        axi = kv_line(s, 'GP_AXI rburst=')
        ok = ('GP_RESULT PASS' in s and
              as_int(end, 'done') == 1 and as_int(end, 'fault') == 0 and
              as_int(end, 'error') == 0 and as_int(end, 'iso') == 0 and
              as_int(drain, 'quiesced') == 1 and as_int(drain, 'rd_pending') == 0 and
              as_int(drain, 'wr_pending') == 0 and as_int(drain, 'b_pending') == 0 and
              as_int(axi, 'tag_err') == 0)
        o, d = out_ok(tag)
        add(f'graph_{tag}_terminal_and_gold', ok and o, f'{d} end={end} drain={drain}')

    # 2. ledger: exclusive union, legacy artifact, lookahead effect
    try:
        led = json.loads((REP / 'ledger.json').read_text())
        ok = (led.get('invariants_ok') is True and
              led['off']['cycles'] == led['off']['trace_exclusive_sum'] and
              led['off']['rtl_exclusive_sum'] == led['off']['cycles'] and
              55 <= led['off']['legacy_last_counters']['residual_pct'] <= 65 and
              led['on']['lookahead_aborts'] == 0 and
              led['on']['lookahead_hits'] >= 5 and
              led['comparison']['real_saved_cycles'] >= 0)
        add('exclusive_union_and_lookahead_ledger', ok,
            f"legacy_pct={led['off']['legacy_last_counters']['residual_pct']:.3f} "
            f"saved={led['comparison']['real_saved_cycles']} "
            f"hits={led['on']['lookahead_hits']}")
    except Exception as e:
        add('exclusive_union_and_lookahead_ledger', False, repr(e))

    # 3. multi-outstanding shared-AXI stress
    s = log('axi_multi.log')
    ok = ('AXI_STRESS_RESULT PASS' in s and
          'data_err=0' in s and 'tag_err=0' in s and
          'iso_hs=0' in s)
    add('axi_multi_outstanding_stress', ok, s.strip().splitlines()[-1] if s else 'missing')

    # 4. lookahead-enabled safety/negative suite
    def safety(name):
        return log(f'{name}.log')

    def end(name):
        return kv_line(safety(name), 'SAFETY_END done=')

    def drain(name):
        return kv_line(safety(name), 'SAFETY_DRAIN')

    def lu(name):
        return kv_line(safety(name), 'SAFETY_LU valid=')

    def overlap(name):
        return kv_line(safety(name), 'SAFETY_OVERLAP')

    def csr(name, prefix):
        return kv_line(safety(name), prefix)

    s = safety('lu_normal')
    e = end('lu_normal'); d = drain('lu_normal'); l = lu('lu_normal')
    # lu_normal output is written to logs/lu_normal_out.hex
    f = load_words(LOGS / 'lu_normal_out.hex') if (LOGS / 'lu_normal_out.hex').exists() else []
    fm = sum(1 for a, b in zip(f, gold) if a != b)
    ok = ('SAFETY_RESULT PASS' in s and as_int(e, 'done') == 1 and as_int(e, 'fault') == 0 and
          as_int(e, 'error') == 0 and as_int(e, 'iso') == 0 and as_int(d, 'quiesced') == 1 and
          fm == 0 and len(f) == 512 and as_int(l, 'valid') == 0 and
          as_int(l, 'fetches', 0) >= 1 and as_int(l, 'aborts', 0) == 0)
    add('lookahead_normal_gold_and_epoch', ok, f'f_mism={fm} end={e} lu={l}')

    s = safety('lu_multitask')
    e = end('lu_multitask'); mx = kv_line(s, 'SAFETY_MATRIX ops=')
    f = load_words(LOGS / 'lu_multitask_out.hex') if (LOGS / 'lu_multitask_out.hex').exists() else []
    fm = sum(1 for a, b in zip(f, gold) if a != b)
    add('lookahead_multitask_gold', 'SAFETY_RESULT PASS' in s and as_int(e, 'done') == 1 and
        as_int(e, 'fault') == 0 and as_int(mx, 'ops') == 2 and fm == 0 and len(f) == 512,
        f'ops={mx.get("ops")} f_mism={fm}')

    for name in ['lu_seq_lay', 'lu_seq_seq']:
        s = safety(name); e = end(name); ov = overlap(name); l = lu(name)
        add(f'lookahead_{name}_mutex_and_disabled',
            'SAFETY_RESULT PASS' in s and as_int(e, 'done') == 1 and as_int(e, 'fault') == 0 and
            as_int(ov, 'seq_direct') == 0 and as_int(l, 'has_seq') == 1 and
            as_int(l, 'fetches', 0) == 0,
            f'end={e} ov={ov} lu={l}')

    for name, flag in [('lu_hang_wait', 'seq_dto'), ('lu_hang_run', 'seq_ito')]:
        s = safety(name); e = end(name); l = lu(name)
        iso = kv_line(s, 'SAFETY_END')  # same line
        add(f'lookahead_{name}_isolation',
            'SAFETY_RESULT PASS' in s and as_int(e, 'done') == 1 and as_int(e, 'fault') == 1 and
            as_int(e, 'error') == 14 and as_int(e, 'iso') == 1 and
            as_int(e, 'requires_reset') == 1 and as_int(e, flag) == 1 and
            as_int(l, 'valid') == 0 and as_int(l, 'epoch', 0) > 1,
            f'end={e} lu={l}')

    for name, err in [('lu_bad_queue', 3), ('lu_bad_vec', 7), ('lu_bad_lay', 7)]:
        s = safety(name); e = end(name); d = drain(name)
        ok = ('SAFETY_RESULT PASS' in s and as_int(e, 'done') == 1 and
              as_int(e, 'fault') == 1 and as_int(e, 'error') == err and
              as_int(d, 'quiesced') == 1)
        if name == 'lu_bad_vec':
            ok = ok and as_int(csr(name, 'SAFETY_CSR vec_total='), 'vec_total') == 0
        if name == 'lu_bad_lay':
            ok = ok and as_int(csr(name, 'SAFETY_CSR vec_total='), 'layout_total') == 0
        add(f'lookahead_{name}_fault', ok, f'end={e} drain={d}')

    s = safety('lu_hold_r_c'); e = end('lu_hold_r_c'); d = drain('lu_hold_r_c'); l = lu('lu_hold_r_c')
    add('lookahead_hold_r_drain_boundary',
        'SAFETY_RESULT PASS' in s and as_int(e, 'error') == 14 and as_int(e, 'iso') == 1 and
        as_int(e, 'requires_reset') == 1 and as_int(d, 'rd_pending') == 1 and
        as_int(d, 'quiesced') == 0 and as_int(l, 'valid') == 0 and as_int(l, 'epoch', 0) > 1,
        f'end={e} drain={d} lu={l}')

    s = safety('lu_hold_b_c'); e = end('lu_hold_b_c'); d = drain('lu_hold_b_c')
    add('lookahead_hold_b_drain_boundary',
        'SAFETY_RESULT PASS' in s and as_int(e, 'error') == 14 and as_int(e, 'iso') == 1 and
        as_int(d, 'b_pending') == 1 and as_int(d, 'quiesced') == 0,
        f'end={e} drain={d}')

    s = safety('lu_restart'); e = end('lu_restart'); rs = kv_line(s, 'SAFETY_RESTART bresp=')
    add('lookahead_restart_lockout',
        'SAFETY_RESULT PASS' in s and as_int(e, 'error') == 14 and as_int(e, 'iso') == 1 and
        as_int(rs, 'bresp') == 2 and 'SAFETY_RESTART_TRAFFIC new_req=0' in s,
        f'end={e} restart={rs}')

    passed = sum(1 for c in checks if c['pass'])
    out = {
        'task': 'v024_ds_graph_prefetch',
        'scope': 'logic simulation only; no synthesis/STA/board/VNC/push',
        'checks_total': len(checks),
        'checks_passed': passed,
        'checks_failed': len(checks) - passed,
        'all_required_pass': passed == len(checks),
        'checks': checks,
    }
    (REP / 'check_summary.json').write_text(json.dumps(out, indent=2))
    print(json.dumps({'checks_total': len(checks), 'checks_passed': passed,
                      'checks_failed': len(checks) - passed,
                      'all_required_pass': passed == len(checks)}, indent=2))
    for c in checks:
        if not c['pass']:
            print('FAIL', c['name'], c['detail'])
    return 0 if passed == len(checks) else 1


if __name__ == '__main__':
    sys.exit(main())
