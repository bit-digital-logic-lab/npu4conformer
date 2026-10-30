#!/usr/bin/env python3
"""Independent checker for the numeric-closeout graph runs.

Recomputes the reference from the read-only adversarial vector lists with
refmodel.py (FMA/DIV) and an exact integer-sqrt rounding routine (SQRT).  The
checker does not read the RTL and does not call gemini's golden code.
"""
import json, re, sys
from decimal import Decimal, getcontext
from fractions import Fraction
from math import isqrt
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
DS = ROOT / 'ds_numeric_adversarial'
sys.path.insert(0, str(DS / 'ref'))
import refmodel as R

getcontext().prec = 220
FIX = HERE / 'fixtures'
LOG = HERE / 'logs'
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)


def read_hex(path):
    return [int(x, 16) for x in Path(path).read_text().split()]


def read_pairs(path):
    out = []
    for ln in Path(path).read_text().splitlines():
        if ln.strip():
            out.append(tuple(int(x, 16) for x in ln.split()))
    return out


def read_single(path):
    return [int(x, 16) for x in Path(path).read_text().split()]


def floor_log2(x):
    return R._floor_log2(x)


def rne_int_exact_half(x, q):
    half = Fraction((2 * q + 1) ** 2, 4)
    if x > half:
        return q + 1
    if x < half:
        return q
    return q if (q & 1) == 0 else q + 1


def round_sqrt_f32(a_bits):
    x = R.f32_to_frac(a_bits)
    e = floor_log2(x)
    e2 = e // 2
    k = 23 - e2
    A = x * (1 << (2 * k)) if k >= 0 else x / (1 << (-2 * k))
    p, d = A.numerator, A.denominator
    q = isqrt(p * d) // d
    n = rne_int_exact_half(A, q)
    if n == (1 << 24):
        n >>= 1
        e2 += 1
    return ((e2 + 127) << 23) | (n - (1 << 23))


def parse_log(path):
    text = Path(path).read_text() if Path(path).exists() else ''
    d = {'path': str(path), 'pass': 'CLOSEOUT_RESULT PASS' in text,
         'lines': [l for l in text.splitlines() if l.startswith(('HOST', 'CLOSEOUT_', 'CHECK_FAIL'))]}
    m = re.search(r'CLOSEOUT_STATUS[^\n]*cycles=(\d+)[^\n]*completed=(\d+)[^\n]*last=(\d+)', text)
    if m:
        d['cycles'] = int(m.group(1)); d['completed'] = int(m.group(2)); d['last_node'] = int(m.group(3))
    m = re.search(r'CLOSEOUT_STATUS[^\n]*fault=(\d+)[^\n]*aborted=(\d+)', text)
    if m:
        d['fault'] = int(m.group(1)); d['aborted'] = int(m.group(2))
    m = re.search(r'CLOSEOUT_VEC[^\n]*vcyc=(\d+)[^\n]*vrb=(\d+)[^\n]*vwb=(\d+)', text)
    if m:
        d['vcyc'] = int(m.group(1)); d['vrb'] = int(m.group(2)); d['vwb'] = int(m.group(3))
    m = re.search(r'CLOSEOUT_AXI[^\n]*rburst=(\d+)[^\n]*wburst=(\d+)[^\n]*rbeats=(\d+)[^\n]*wbeats=(\d+)[^\n]*tag_err=(\d+)', text)
    if m:
        d['rburst'] = int(m.group(1)); d['wburst'] = int(m.group(2))
        d['rbeats'] = int(m.group(3)); d['wbeats'] = int(m.group(4)); d['tag_err'] = int(m.group(5))
    m = re.search(r'CLOSEOUT_BOUNDARY[^\n]*done_cycle=(-?\d+)[^\n]*last_b_cycle=(-?\d+)[^\n]*b_count_at_done=(\d+)[^\n]*b_after_done=(\d+)[^\n]*aw_after_done=(\d+)', text)
    if m:
        d['done_cycle'] = int(m.group(1)); d['last_b_cycle'] = int(m.group(2))
        d['b_count_at_done'] = int(m.group(3)); d['b_after_done'] = int(m.group(4))
        d['aw_after_done'] = int(m.group(5))
    return d


def compare_bits(got, exp):
    mism = [i for i, (g, e) in enumerate(zip(got, exp)) if g != e]
    ulps = [R.ulp_distance(got[i], exp[i]) for i in mism]
    ulps = [u for u in ulps if u is not None]
    return {
        'n': len(got), 'mismatches': len(mism),
        'first_mismatches': [{'index': i, 'got': f'{got[i]:08x}', 'exp': f'{exp[i]:08x}'} for i in mism[:5]],
        'max_ulp': max(ulps) if ulps else 0,
        'mean_ulp': (sum(ulps) / len(ulps)) if ulps else 0.0,
        'pass': len(mism) == 0 and len(got) == len(exp),
    }


def err_stats(got, true_vals):
    rels = []
    missing = 0
    for g, t in zip(got, true_vals):
        e = R.rel_error(g, t)
        if e is None:
            missing += 1
        else:
            rels.append(e)
    vals = [float(x) for x in rels]
    return {
        'n': len(got), 'missing_or_special': missing,
        'max_rel': max(vals) if vals else None,
        'mean_rel': (sum(vals) / len(vals)) if vals else None,
        'over_10pct': sum(1 for x in vals if x > 0.10),
        'over_0p2pct': sum(1 for x in vals if x > 0.002),
        'pass_error_bound': (not vals or max(vals) < 0.002),
    }


def main():
    meta = json.loads((FIX / 'closeout_meta.json').read_text())
    fma_in = read_pairs(FIX / 'used_fma.txt')
    div_in = read_pairs(FIX / 'used_div.txt')
    sqrt_in = read_single(FIX / 'used_sqrt.txt')
    fma2_in = read_pairs(FIX / 'used_fma2.txt')

    # used_fma.txt / used_fma2.txt store (scale, bias, x); FMA is x*scale+bias
    gold_fma = [R.fma_bits(x, s, b) for s, b, x in fma_in]
    gold_div = [R.round_f32(R.f32_to_frac(a) / R.f32_to_frac(b)) for a, b in div_in]
    gold_sqrt = [round_sqrt_f32(a) for a in sqrt_in]
    gold_fma2 = [R.fma_bits(x, s, b) for s, b, x in fma2_in]

    # generator gold must agree with this independent recomputation
    gen = {
        'fma': read_hex(FIX / 'gold_fma.hex'),
        'div': read_hex(FIX / 'gold_div.hex'),
        'sqrt': read_hex(FIX / 'gold_sqrt.hex'),
        'fma2': read_hex(FIX / 'gold_fma2.hex'),
    }
    gold_agree = {
        'fma': gen['fma'] == gold_fma, 'div': gen['div'] == gold_div,
        'sqrt': gen['sqrt'] == gold_sqrt, 'fma2': gen['fma2'] == gold_fma2,
    }

    exact = {k: read_hex(LOG / f'exact_{k}.hex') for k in ('fma', 'div', 'sqrt')}
    approx = {k: read_hex(LOG / f'approx_{k}.hex') for k in ('fma', 'div', 'sqrt')}
    abort2 = read_hex(LOG / 'abort_fma2.hex')
    reset2 = read_hex(LOG / 'reset_fma2.hex')

    report = {
        'scope': 'vector-numeric integration through shared AXI/WCPG; not full-model',
        'inputs': meta['vectors'],
        'gold_recompute_agrees_with_generator': gold_agree,
        'exact_baseline': {
            'fma_vs_exact_reference': compare_bits(exact['fma'], gold_fma),
            'div_vs_exact_reference': compare_bits(exact['div'], gold_div),
            'sqrt_vs_exact_reference': compare_bits(exact['sqrt'], gold_sqrt),
        },
        'candidate_approx': {
            'fma_vs_exact_reference': compare_bits(approx['fma'], gold_fma),
            'fma_vs_exact_baseline': compare_bits(approx['fma'], exact['fma']),
            'div_vs_exact_reference': compare_bits(approx['div'], gold_div),
            'div_vs_exact_baseline': compare_bits(approx['div'], exact['div']),
            'sqrt_vs_exact_reference': compare_bits(approx['sqrt'], gold_sqrt),
            'sqrt_vs_exact_baseline': compare_bits(approx['sqrt'], exact['sqrt']),
            'div_error': err_stats(approx['div'], [R.true_div_decimal(a, b) for a, b in div_in]),
            'sqrt_error': err_stats(approx['sqrt'], [R.true_sqrt_decimal(a) for a in sqrt_in]),
        },
        'epoch2': {
            'abort_fma2_vs_reference': compare_bits(abort2, gold_fma2),
            'reset_fma2_vs_reference': compare_bits(reset2, gold_fma2),
        },
        'logs': {
            'exact': parse_log(LOG / 'exact.log'),
            'approx': parse_log(LOG / 'approx.log'),
            'abort': parse_log(LOG / 'abort.log'),
            'reset': parse_log(LOG / 'reset.log'),
        },
    }

    fails = []
    for k, ok in gold_agree.items():
        if not ok:
            fails.append(f'gold generator/recompute disagreement: {k}')
    for name, d in report['exact_baseline'].items():
        if not d['pass']:
            fails.append(f'exact baseline mismatch: {name}')
    for name, d in report['candidate_approx'].items():
        if name.endswith('_error'):
            if not d['pass_error_bound']:
                fails.append(f'approx error bound: {name}')
        elif 'fma' in name:
            if not d['pass']:
                fails.append(f'approx mismatch: {name}')
        else:
            # DIV/SQRT approximate results intentionally differ from exact
            # baseline; only the error report above is a gate.
            d['informational_only'] = True
    for name, d in report['epoch2'].items():
        if not d['pass']:
            fails.append(f'epoch2 mismatch: {name}')

    lx = report['logs']
    for name in ('exact', 'approx'):
        if not lx[name]['pass'] or lx[name].get('fault') != 0:
            fails.append(f'log fail/fault: {name}')
    ab = lx['abort']
    if not ab['pass'] or ab.get('aborted') != 0:
        fails.append('abort scenario did not end cleanly on epoch 2')
    if 'abort-drain done=1 abort_done=1' not in (LOG / 'abort.log').read_text():
        fails.append('abort scenario did not latch abort done')
    if 'HOST plan2 done=1 abort_done=0' not in (LOG / 'abort.log').read_text():
        fails.append('abort scenario epoch 2 did not complete cleanly')
    if ab.get('aw_after_done', 0) != 0 or ab.get('b_after_done', 0) != 0:
        fails.append('abort quiescent window had AXI AW/B activity')
    rs = lx['reset']
    if not rs['pass'] or rs.get('fault') != 0:
        fails.append('reset scenario did not end cleanly')
    if 'plan2-after-reset done=1 abort_done=0' not in (LOG / 'reset.log').read_text():
        fails.append('reset scenario epoch 2 did not complete cleanly')
    if rs.get('aw_after_done', 0) != 0 or rs.get('b_after_done', 0) != 0:
        fails.append('reset quiescent window had AXI AW/B activity')

    report['fails'] = fails
    report['pass'] = not fails
    (REP / 'check_summary.json').write_text(json.dumps(report, indent=2))

    print(json.dumps({
        'pass': report['pass'],
        'fails': fails,
        'exact_fma_mism': report['exact_baseline']['fma_vs_exact_reference']['mismatches'],
        'exact_div_mism': report['exact_baseline']['div_vs_exact_reference']['mismatches'],
        'exact_sqrt_mism': report['exact_baseline']['sqrt_vs_exact_reference']['mismatches'],
        'approx_fma_mism': report['candidate_approx']['fma_vs_exact_reference']['mismatches'],
        'div_max_rel': report['candidate_approx']['div_error']['max_rel'],
        'sqrt_max_rel': report['candidate_approx']['sqrt_error']['max_rel'],
        'cycles_exact': lx['exact'].get('cycles'), 'vcyc_exact': lx['exact'].get('vcyc'),
        'cycles_approx': lx['approx'].get('cycles'), 'vcyc_approx': lx['approx'].get('vcyc'),
    }, indent=2))
    if fails:
        sys.exit(1)


if __name__ == '__main__':
    main()
