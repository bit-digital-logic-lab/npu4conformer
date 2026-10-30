#!/usr/bin/env python3
"""Evaluate the abnormal-closeout suite from real logs.

No result is inferred from a timeout alone: each test must print its terminal
state, error code, isolation flag and AXI drain boundary.  Baseline negative
controls are expected to fail (hang / overlap); the patched build must pass.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
LOG = HERE / 'logs'
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)

KV = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)=([0-9a-fA-FxX]+)')


def text(name):
    p = LOG / name
    return p.read_text(errors='replace') if p.exists() else ''


def conv(k, v):
    # error/status fields are printed with %x / %02x; everything else is
    # decimal in the testbench output.
    if k in ('error', 'err', 'status'):
        return int(v, 16)
    if re.fullmatch(r'[0-9]+', v):
        return int(v, 10)
    if re.fullmatch(r'0x[0-9a-fA-F]+', v):
        return int(v, 0)
    return v


def kv_line(s, prefix):
    for line in s.splitlines():
        if line.startswith(prefix):
            return {k: conv(k, v) for k, v in KV.findall(line)}
    return {}


def has(s, needle):
    return needle in s


def gold_match(outfile):
    gold = [int(x, 16) for x in (HERE / 'integrated_copy' / 'fixtures' / 'gold_i16.hex').read_text().split()]
    p = LOG / outfile
    if not p.exists():
        return False, 'missing output'
    got = [int(x, 16) for x in p.read_text().split()]
    if len(got) != len(gold):
        return False, f'length {len(got)} != {len(gold)}'
    bad = sum(1 for a, b in zip(got, gold) if a != b)
    return bad == 0, f'{bad} mismatches'


def safety(name, **expect):
    s = text(name)
    end = kv_line(s, 'SAFETY_END')
    drain = kv_line(s, 'SAFETY_DRAIN')
    quiesce = kv_line(s, 'SAFETY_QUIESCE')
    csr = kv_line(s, 'SAFETY_CSR vec_total')
    ov = kv_line(s, 'SAFETY_OVERLAP')
    restart = kv_line(s, 'SAFETY_RESTART ')
    ok = has(s, 'SAFETY_RESULT PASS')
    reasons = [] if ok else ['no SAFETY_RESULT PASS']
    groups = {'end': end, 'drain': drain, 'quiesce': quiesce, 'csr': csr,
              'overlap': ov, 'restart': restart}
    for group, vals in expect.items():
        src = groups.get(group, {})
        for k, v in vals.items():
            if src.get(k) != v:
                ok = False
                reasons.append(f'{group}.{k}={src.get(k)} want {v}')
    return ok, reasons, {'end': end, 'drain': drain, 'quiesce': quiesce,
                         'csr': csr, 'overlap': ov, 'restart': restart}


def mutex(name, **expect):
    s = text(name)
    end = kv_line(s, 'MUTEX_END')
    iso = kv_line(s, 'MUTEX_ISO')
    ok = has(s, 'MUTEX_RESULT PASS')
    reasons = [] if ok else ['no MUTEX_RESULT PASS']
    groups = {'end': end, 'iso': iso}
    for group, vals in expect.items():
        src = groups.get(group, {})
        for k, v in vals.items():
            if src.get(k) != v:
                ok = False
                reasons.append(f'{group}.{k}={src.get(k)} want {v}')
    return ok, reasons, {'end': end, 'iso': iso}


def main():
    tests = []
    def add(name, ok, reasons, evidence=None):
        tests.append({'name': name, 'pass': bool(ok), 'reasons': reasons,
                      'evidence': evidence or {}})

    # 1. normal exact path + per-op counters + golden
    ok, r, ev = safety('safety_normal.log',
                       end={'done': 1, 'fault': 0, 'error': 0, 'iso': 0,
                            'requires_reset': 0, 'drain_timeout': 0},
                       drain={'quiesced': 1, 'rd_pending': 0, 'wr_pending': 0, 'b_pending': 0},
                       csr={'vec_total': 4643, 'layout_total': 16788, 'matrix_total': 1880},
                       overlap={'seq_direct': 0})
    g, gr = gold_match('safety_normal_out.hex')
    if not g:
        ok = False; r.append('golden: ' + gr)
    add('normal_exact_path', ok, r, ev)

    # 2. multi-descriptor queue: per-task totals, not the last task
    ok, r, ev = safety('safety_multitask.log',
                       end={'done': 1, 'fault': 0, 'error': 0, 'iso': 0},
                       csr={'matrix_total': 3770, 'matrix_ops': 2},
                       drain={'quiesced': 1})
    g, gr = gold_match('safety_multitask_out.hex')
    if not g:
        ok = False; r.append('golden: ' + gr)
    add('matrix_multitask_totals', ok, r, ev)

    # 3. SEQ mutex, patched vs delivered baseline (negative control)
    ok, r, ev = mutex('mutex_lay_patched.log',
                      end={'done': 1, 'fault': 0, 'ov_seq_direct': 0})
    add('seq_mutex_lay_patched', ok, r, ev)
    sb = text('mutex_lay_baseline.log')
    add('seq_mutex_lay_baseline_negative',
        has(sb, 'MUTEX_RESULT FAIL') and has(sb, 'MUTEX_OVERLAP_VIOLATION'),
        [] if has(sb, 'MUTEX_OVERLAP_VIOLATION') else ['baseline did not expose overlap'],
        kv_line(sb, 'MUTEX_END'))

    ok, r, ev = mutex('mutex_seq_patched.log',
                      end={'done': 1, 'fault': 0, 'ov_seq_direct': 0})
    add('seq_mutex_seq_patched', ok, r, ev)
    sb = text('mutex_seq_baseline.log')
    add('seq_mutex_seq_baseline_negative',
        has(sb, 'MUTEX_RESULT FAIL') and has(sb, 'MUTEX_OVERLAP_VIOLATION'),
        [] if has(sb, 'MUTEX_OVERLAP_VIOLATION') else ['baseline did not expose overlap'],
        kv_line(sb, 'MUTEX_END'))

    ok, r, ev = mutex('mutex_healthy_patched.log',
                      end={'done': 1, 'fault': 0, 'ov_seq_direct': 0})
    add('seq_mutex_healthy_patched', ok, r, ev)

    # 4. real hung SEQ child: wait-to-dispatch and accepted-but-never-done
    ok, r, ev = mutex('mutex_hang_wait_patched.log',
                      end={'done': 1, 'fault': 1, 'error': 14},
                      iso={'iso': 1, 'requires_reset': 1, 'seq_dto': 1})
    add('seq_hang_wait_patched', ok, r, ev)
    sb = text('mutex_hang_wait_baseline.log')
    add('seq_hang_wait_baseline_negative',
        has(sb, 'MUTEX_RESULT FAIL') and
        (has(sb, 'MUTEX_TIMEOUT') or has(sb, 'MUTEX_GLOBAL_TIMEOUT')),
        [] if has(sb, 'MUTEX_TIMEOUT') or has(sb, 'MUTEX_GLOBAL_TIMEOUT') else ['baseline did not hang'],
        kv_line(sb, 'MUTEX_END'))

    ok, r, ev = mutex('mutex_hang_run_patched.log',
                      end={'done': 1, 'fault': 1, 'error': 14},
                      iso={'iso': 1, 'requires_reset': 1, 'seq_ito': 1})
    add('seq_hang_run_patched', ok, r, ev)
    sb = text('mutex_hang_run_baseline.log')
    add('seq_hang_run_baseline_negative',
        has(sb, 'MUTEX_RESULT FAIL') and
        (has(sb, 'MUTEX_TIMEOUT') or has(sb, 'MUTEX_GLOBAL_TIMEOUT')),
        [] if has(sb, 'MUTEX_TIMEOUT') or has(sb, 'MUTEX_GLOBAL_TIMEOUT') else ['baseline did not hang'],
        kv_line(sb, 'MUTEX_END'))

    # 5. bad queue / illegal operator
    for name, err in [('bad_queue_magic', 3), ('bad_queue_backend', 3),
                      ('bad_queue_pred', 4), ('bad_queue_overlap', 0x81),
                      ('bad_mat_op', 0x81), ('bad_vec_op', 7), ('bad_lay_mode', 7)]:
        ok, r, ev = safety(f'safety_{name}.log',
                           end={'done': 1, 'fault': 1, 'error': err, 'iso': 0,
                                'requires_reset': 0},
                           drain={'quiesced': 1})
        if name == 'bad_vec_op' and ev.get('csr', {}).get('vec_total') != 0:
            ok = False; r.append('illegal vector op wrote vector data')
        if name == 'bad_lay_mode' and ev.get('csr', {}).get('layout_total') != 0:
            ok = False; r.append('illegal layout op wrote layout data')
        add(f'negative_{name}', ok, r, ev)

    # 6. permanent AXI response wait
    ok, r, ev = safety('safety_hold_r_plan.log',
                       end={'done': 1, 'fault': 1, 'error': 14, 'iso': 1,
                            'requires_reset': 1, 'fetch_to': 1},
                       drain={'rd_pending': 1, 'quiesced': 0})
    add('axi_hold_r_plan', ok, r, ev)
    ok, r, ev = safety('safety_hold_r_c.log',
                       end={'done': 1, 'fault': 1, 'error': 14, 'iso': 1,
                            'requires_reset': 1},
                       drain={'rd_pending': 1, 'quiesced': 0})
    add('axi_hold_r_data', ok, r, ev)
    ok, r, ev = safety('safety_hold_b_c.log',
                       end={'done': 1, 'fault': 1, 'error': 14, 'iso': 1,
                            'requires_reset': 1},
                       drain={'b_pending': 1, 'quiesced': 0})
    add('axi_hold_b_matrix', ok, r, ev)
    ok, r, ev = safety('safety_hold_b_d0.log',
                       end={'done': 1, 'fault': 1, 'error': 14, 'iso': 1,
                            'requires_reset': 1},
                       drain={'b_pending': 1, 'quiesced': 0})
    add('axi_hold_b_vector', ok, r, ev)

    # 7. delayed response drains the port, but the child still needs reset
    ok, r, ev = safety('safety_hold_r_c_delayed.log',
                       end={'done': 1, 'fault': 1, 'error': 14, 'iso': 1,
                            'requires_reset': 1},
                       quiesce={'rd_pending': 0, 'quiesced': 1})
    add('axi_delayed_drain_quiesced', ok, r, ev)

    # 8. restart refused after isolation
    ok, r, ev = safety('safety_restart.log',
                       end={'done': 1, 'fault': 1, 'error': 14, 'iso': 1,
                            'requires_reset': 1},
                       restart={'bresp': 2, 'done_latched': 1})
    s = text('safety_restart.log')
    if 'SAFETY_RESTART_TRAFFIC new_req=0' not in s:
        ok = False; r.append('restart issued new AXI traffic')
    add('restart_refused_after_isolation', ok, r, ev)

    # 9. reset-reuse hazard proof
    s = text('axi_reset_hazard.log')
    add('axi_reset_reuse_hazard',
        has(s, 'HAZARD_RESULT PASS') and has(s, 'HAZARD_STALE_CONSUMED') and
        has(s, 'HAZARD_DRAIN rd_pending=0 quiesced=1'),
        [] if has(s, 'HAZARD_STALE_CONSUMED') else ['stale response not consumed'],
        {})

    # 10. sealed same-load baseline still passes
    s = text('baseline_chain_local.log')
    add('sealed_baseline_chain',
        has(s, 'BASE_CHAIN_RESULT PASS'), [] if has(s, 'BASE_CHAIN_RESULT PASS') else ['baseline failed'],
        {})

    passed = sum(1 for t in tests if t['pass'])
    total = len(tests)
    verdict = 'SAFETY_CLOSEOUT_LOCAL_ONLY'
    out = {
        'task': 'v023_closeout_safety',
        'date': '2026-10-30',
        'scope': 'logic simulation only; no synthesis/Vivado/board/VNC/push',
        'verdict': verdict,
        'full_model_accepted': False,
        'tests_total': total,
        'tests_passed': passed,
        'tests_failed': total - passed,
        'all_required_pass': passed == total,
        'tests': tests,
        'gate_context': {
            'old_gate_stale': True,
            'round2_fma': 'primary_acceptance/round2/result_primary_fma.json: 8734 vectors, 0 mismatches (independently rerun by main agent)',
            'round2_approx': 'primary_acceptance/round2/result_primary_approx.json: 15168 pass (DIV max 0.1114666%, SQRT 5.78e-6, RSQRT 5.72e-6, 5-cycle II1)',
            'stream': 'primary_stream_fix/REPORT.md: 65-item regression pass; stream_param_port 113-mismatch was a test-driver omission, fixed by main agent',
            'note': 'This task does not re-run FMA/approx/stream and does not claim full-model WER/CER or board timing.',
        },
    }
    (REP / 'safety_summary.json').write_text(json.dumps(out, indent=2))
    (HERE / 'result.json').write_text(json.dumps(out, indent=2))
    print(json.dumps({'tests_total': total, 'tests_passed': passed,
                      'tests_failed': total - passed,
                      'all_required_pass': passed == total}, indent=2))
    for t in tests:
        if not t['pass']:
            print('FAIL', t['name'], t['reasons'])
    sys.exit(0 if passed == total else 1)


if __name__ == '__main__':
    main()
