#!/usr/bin/env python3
"""Check integrated/baseline final outputs and write a compact result summary."""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
R = HERE / 'reports'
R.mkdir(exist_ok=True)


def load_hex(p):
    return [int(x, 16) for x in Path(p).read_text().split()]


def diffs(a, b):
    return [(i, x, y) for i, (x, y) in enumerate(zip(a, b)) if x != y]


def last_int(log, key):
    m = re.findall(r'%s=(\d+)' % re.escape(key), Path(log).read_text())
    return int(m[-1]) if m else None


def main():
    gold = load_hex(HERE / 'fixtures' / 'gold_i16.hex')
    cand = load_hex(HERE / 'logs' / 'integrated_out.hex')
    base = load_hex(HERE / 'logs' / 'baseline_out.hex')
    d_c = diffs(cand, gold)
    d_b = diffs(base, gold)
    d_bc = diffs(base, cand)
    summary = {
        'gold_words': len(gold),
        'candidate_words': len(cand),
        'baseline_words': len(base),
        'candidate_vs_gold_mismatches': len(d_c),
        'baseline_vs_gold_mismatches': len(d_b),
        'baseline_vs_candidate_mismatches': len(d_bc),
        'candidate_pass': not d_c and len(cand) == len(gold),
        'baseline_pass': not d_b and len(base) == len(gold),
        'integrated_log': str(HERE / 'logs' / 'integrated_run.log'),
        'baseline_log': str(HERE / 'logs' / 'baseline_chain.log'),
        'matrix_baseline_log': str(HERE / 'logs' / 'base_mx_m32.log'),
        'integrated_cycles': last_int(HERE / 'logs' / 'integrated_run.log', 'cycle'),
        'baseline_matrix_cycles': last_int(HERE / 'logs' / 'base_mx_m32.log', 'cycles'),
        'candidate_matrix_cycles': last_int(HERE / 'logs' / 'integrated_run.log', 'cycles'),
    }
    (R / 'check_summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    sys.exit(0 if summary['candidate_pass'] and summary['baseline_pass'] else 1)


if __name__ == '__main__':
    main()
