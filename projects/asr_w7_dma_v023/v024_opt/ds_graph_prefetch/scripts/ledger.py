#!/usr/bin/env python3
"""Rebuild the per-node time account and the exclusive-union cycle ledger.

Reads the real RTL per-cycle CSV traces (and the RTL exported counters) and:
  * partitions every busy cycle into fetch / dispatch / engine / idle plus
    their overlap buckets (exclusive union);
  * attributes fetch and dispatch cycles to node ids;
  * computes the legacy `total - last-op counters` residual that produced the
    rejected 59.8% "control overhead" claim;
  * compares lookahead off vs on and reports the real measured saved cycles.

Any invariant failure exits non-zero.
"""
import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FETCH_STATES = {1, 2, 3, 4, 5, 6, 10, 11}  # HREQ/HFETCH/NREQ/NFETCH/PREQ/PFETCH/LREQ/LFETCH
DISP_STATE = 8
ENGINE_NAMES = ['mat', 'vec', 'lay', 'seq']  # e_active bits 0..3 are seq,mat,vec,lay in this RTL


def kv(text, prefix):
    for line in text.splitlines():
        if line.startswith(prefix):
            return dict(re.findall(r'([A-Za-z_][A-Za-z0-9_]*)=([0-9a-fA-FxX]+)', line))
    return {}


def num(d, k, default=0):
    v = d.get(k)
    if v is None:
        return default
    return int(v, 16) if v.lower().startswith('0x') or re.fullmatch(r'[0-9a-fA-F]+', v) and any(c in 'abcdefABCDEF' for c in v) else int(v, 10)


def read_trace(path):
    with open(path, newline='') as f:
        rows = list(csv.DictReader(f))
    out = []
    for r in rows:
        out.append({
            'cyc': int(r['cyc']),
            'busy': int(r['busy']),
            'state': int(r['state']),
            'target': int(r['target']),
            'e_active': int(r['e_active']),
            'e_node': [int(r[f'e_node{i}']) for i in range(4)],
            'nfetch_idx': int(r['nfetch_idx']),
            'payload_node': int(r['payload_node']),
            'completed': int(r['completed']),
            'done_mask': int(r['done_mask'], 10),
            'lu_req_node': int(r.get('lu_req_node') or 0),
            'lu_node': int(r.get('lu_node') or 0),
            'lu_busy': int(r.get('lu_busy') or 0),
        })
    return out


def ledger(rows):
    cat = defaultdict(int)
    per_node = defaultdict(lambda: defaultdict(int))
    first_seen = {}
    engine_start = {}
    engine_end = {}
    done_cycle = {}
    prev_done = 0
    for r in rows:
        if not r['busy']:
            prev_done = r['done_mask']
            continue
        cyc = r['cyc']
        fetch = r['state'] in FETCH_STATES
        disp = r['state'] == DISP_STATE
        eng = r['e_active'] != 0
        if fetch and not disp and not eng:
            cat['fetch_only'] += 1
        elif not fetch and disp and not eng:
            cat['dispatch_only'] += 1
        elif not fetch and not disp and eng:
            cat['engine_only'] += 1
        elif fetch and not disp and eng:
            cat['fetch_engine'] += 1
        elif not fetch and disp and eng:
            cat['dispatch_engine'] += 1
        elif fetch and disp and not eng:
            cat['fetch_dispatch'] += 1
        elif fetch and disp and eng:
            cat['all'] += 1
        else:
            cat['idle'] += 1

        if r['state'] in (1, 2):
            per_node[-1]['fetch_header'] += 1
        elif r['state'] in (3, 4):
            n = r['nfetch_idx']
            per_node[n]['fetch_node'] += 1
            first_seen.setdefault(n, cyc)
        elif r['state'] in (5, 6):
            n = r['payload_node']
            per_node[n]['fetch_payload'] += 1
            first_seen.setdefault(n, cyc)
        elif r['state'] in (10, 11):
            n = r['lu_req_node']
            per_node[n]['fetch_lookahead'] += 1
            first_seen.setdefault(n, cyc)

        if disp:
            n = r['target']
            per_node[n]['dispatch'] += 1
            first_seen.setdefault(n, cyc)

        for q in range(4):
            if r['e_active'] & (1 << q):
                n = r['e_node'][q]
                per_node[n]['engine'] += 1
                first_seen.setdefault(n, cyc)
                engine_start[n] = min(engine_start.get(n, cyc), cyc)
                engine_end[n] = max(engine_end.get(n, cyc), cyc)

        newly = r['done_mask'] & ~prev_done
        for n in range(64):
            if newly & (1 << n):
                done_cycle[n] = cyc
        prev_done = r['done_mask']
    return cat, per_node, first_seen, engine_start, engine_end, done_cycle


def parse_log(path):
    text = Path(path).read_text(errors='replace')
    d = {}
    d.update(kv(text, 'GP_CSR status='))
    d.update(kv(text, 'GP_CSR vec_total='))
    d.update(kv(text, 'GP_CSR last_vec='))
    d.update(kv(text, 'GP_END done='))
    d.update(kv(text, 'GP_LEDGER fetch='))
    d.update(kv(text, 'GP_LEDGER_X'))
    d.update(kv(text, 'GP_LEDGER_F'))
    d.update(kv(text, 'GP_LU valid='))
    d.update(kv(text, 'GP_AXI rburst='))
    return d


def as_int(d, k, default=0):
    v = d.get(k)
    if v is None:
        return default
    try:
        return int(v, 0)
    except ValueError:
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--off-log', required=True)
    ap.add_argument('--off-trace', required=True)
    ap.add_argument('--on-log', required=True)
    ap.add_argument('--on-trace', required=True)
    ap.add_argument('--json', required=True)
    ap.add_argument('--csv', required=True)
    args = ap.parse_args()

    off_rows = read_trace(args.off_trace)
    on_rows = read_trace(args.on_trace)
    off_cat, off_nodes, off_first, off_es, off_ee, off_done = ledger(off_rows)
    on_cat, on_nodes, on_first, on_es, on_ee, on_done = ledger(on_rows)
    off_log = parse_log(args.off_log)
    on_log = parse_log(args.on_log)

    off_cycles = as_int(off_log, 'cycles')
    on_cycles = as_int(on_log, 'cycles')
    off_busy = sum(r['busy'] for r in off_rows)
    on_busy = sum(r['busy'] for r in on_rows)
    off_sum = sum(off_cat.values())
    on_sum = sum(on_cat.values())

    # Per-node table.
    csv_rows = []
    for n in sorted(set(list(off_nodes.keys()) + list(on_nodes.keys()))):
        if n < 0:
            continue
        row = {'node': n}
        for tag, nodes, first, es, ee, done in [
            ('off', off_nodes, off_first, off_es, off_ee, off_done),
            ('on', on_nodes, on_first, on_es, on_ee, on_done),
        ]:
            nd = nodes.get(n, {})
            row[f'{tag}_first_seen'] = first.get(n, '')
            row[f'{tag}_engine_start'] = es.get(n, '')
            row[f'{tag}_engine_end'] = ee.get(n, '')
            row[f'{tag}_engine_cycles'] = nd.get('engine', 0)
            row[f'{tag}_fetch_node'] = nd.get('fetch_node', 0)
            row[f'{tag}_fetch_payload'] = nd.get('fetch_payload', 0)
            row[f'{tag}_fetch_lookahead'] = nd.get('fetch_lookahead', 0)
            row[f'{tag}_dispatch'] = nd.get('dispatch', 0)
            row[f'{tag}_done_cycle'] = done.get(n, '')
            if done.get(n) is not None and first.get(n) is not None:
                life = done[n] - first[n] + 1
                row[f'{tag}_lifetime'] = life
                row[f'{tag}_other'] = life - nd.get('engine', 0) - nd.get('fetch_node', 0) - nd.get('fetch_payload', 0) - nd.get('fetch_lookahead', 0) - nd.get('dispatch', 0)
            else:
                row[f'{tag}_lifetime'] = ''
                row[f'{tag}_other'] = ''
        csv_rows.append(row)

    # Legacy (rejected) arithmetic: total - last-op telemetry.
    off_last = as_int(off_log, 'last_mat') + as_int(off_log, 'last_vec') + as_int(off_log, 'last_lay')
    off_legacy_res = off_cycles - off_last
    off_legacy_pct = 100.0 * off_legacy_res / off_cycles if off_cycles else 0.0
    off_tot = as_int(off_log, 'matrix_total') + as_int(off_log, 'vec_total') + as_int(off_log, 'layout_total')
    off_corr_res = off_cycles - off_tot
    off_corr_pct = 100.0 * off_corr_res / off_cycles if off_cycles else 0.0

    # RTL ledger cross-check.
    rtl = {k: as_int(off_log, k) for k in
           ['fetch_only', 'engine_only', 'dispatch_only', 'fetch_engine',
            'dispatch_engine', 'fetch_dispatch', 'all', 'idle',
            'fetch_hdr', 'fetch_node', 'fetch_payload', 'fetch_lookahead']}
    rtl_sum = sum(rtl[k] for k in ['fetch_only', 'engine_only', 'dispatch_only',
                                   'fetch_engine', 'dispatch_engine', 'fetch_dispatch', 'all', 'idle'])

    result = {
        'scope': 'same fixture/BFM/seed; logic simulation only',
        'off': {
            'cycles': off_cycles,
            'busy_rows': off_busy,
            'trace_exclusive_sum': off_sum,
            'exclusive': dict(off_cat),
            'rtl_exclusive': rtl,
            'rtl_exclusive_sum': rtl_sum,
            'legacy_last_counters': {
                'matrix': as_int(off_log, 'last_mat'), 'vector': as_int(off_log, 'last_vec'),
                'layout': as_int(off_log, 'last_lay'), 'sum': off_last,
                'residual': off_legacy_res, 'residual_pct': off_legacy_pct,
            },
            'per_op_csr_totals': {
                'matrix': as_int(off_log, 'matrix_total'), 'vector': as_int(off_log, 'vec_total'),
                'layout': as_int(off_log, 'layout_total'), 'sum': off_tot,
                'residual': off_corr_res, 'residual_pct': off_corr_pct,
            },
            'fetch_breakdown': {k: rtl[k] for k in ['fetch_hdr', 'fetch_node', 'fetch_payload', 'fetch_lookahead']},
        },
        'on': {
            'cycles': on_cycles,
            'busy_rows': on_busy,
            'trace_exclusive_sum': on_sum,
            'exclusive': dict(on_cat),
            'lookahead_hits': as_int(on_log, 'hits'),
            'lookahead_misses': as_int(on_log, 'misses'),
            'lookahead_fetches': as_int(on_log, 'fetches'),
            'lookahead_aborts': as_int(on_log, 'aborts'),
            'rtl_cycles': as_int(on_log, 'cycles'),
            'fetch_breakdown': {
                'header': as_int(on_log, 'fetch_hdr'),
                'node': as_int(on_log, 'fetch_node'),
                'payload': as_int(on_log, 'fetch_payload'),
                'lookahead': as_int(on_log, 'fetch_lookahead'),
            },
        },
        'comparison': {
            'real_saved_cycles': off_cycles - on_cycles,
            'saved_pct': 100.0 * (off_cycles - on_cycles) / off_cycles if off_cycles else 0.0,
            'delta_fetch_only': on_cat.get('fetch_only', 0) - off_cat.get('fetch_only', 0),
            'delta_engine_only': on_cat.get('engine_only', 0) - off_cat.get('engine_only', 0),
            'delta_fetch_engine': on_cat.get('fetch_engine', 0) - off_cat.get('fetch_engine', 0),
            'delta_idle': on_cat.get('idle', 0) - off_cat.get('idle', 0),
            'payload_fetch_cycles_off': rtl['fetch_payload'],
            'payload_fetch_cycles_on': as_int(on_log, 'fetch_payload'),
            'lookahead_fetch_cycles_on': as_int(on_log, 'fetch_lookahead'),
            'header_prefetch_saved_cycles': 0,
            'header_prefetch_note': 'The 64-byte header and all 192-byte node descriptors must be fetched and FNV-validated after START and before any dispatch. There is no legal engine work to overlap at that point, so a "header prefetch" saves 0 cycles in this contract; the measured saving is payload lookahead.',
        },
        'published_claim_check': {
            'published': 'ds_cycle_chain_compare: 21121 total, 12641 residual (59.8%) from 1329+659+6492',
            'same_arithmetic_on_this_run': {
                'total': off_cycles, 'last_counter_sum': off_last,
                'residual': off_legacy_res, 'pct': off_legacy_pct,
            },
            'verdict': 'The 59.8% figure is an arithmetic artifact of using the last op telemetry as if it were the sum of all ops. It is not an exclusive control-overhead measurement.',
        },
    }

    failures = []
    if off_cycles != off_busy or off_sum != off_cycles:
        failures.append(f'off trace/cycles mismatch cycles={off_cycles} busy={off_busy} sum={off_sum}')
    if on_cycles != on_busy or on_sum != on_cycles:
        failures.append(f'on trace/cycles mismatch cycles={on_cycles} busy={on_busy} sum={on_sum}')
    if rtl_sum != off_cycles:
        failures.append(f'RTL ledger sum {rtl_sum} != cycles {off_cycles}')
    for k in ['fetch_only', 'engine_only', 'dispatch_only', 'fetch_engine',
              'dispatch_engine', 'fetch_dispatch', 'all', 'idle']:
        if rtl[k] != off_cat.get(k, 0):
            failures.append(f'RTL/trace {k}: {rtl[k]} != {off_cat.get(k, 0)}')
    if off_legacy_pct < 55 or off_legacy_pct > 65:
        failures.append(f'legacy artifact not reproduced: {off_legacy_pct:.2f}%')
    if as_int(on_log, 'aborts') != 0:
        failures.append('lookahead aborted in the clean run')
    if as_int(on_log, 'hits') < 5:
        failures.append('lookahead did not hit the expected payloads')

    result['invariants_ok'] = not failures
    result['failures'] = failures
    Path(args.json).parent.mkdir(parents=True, exist_ok=True)
    Path(args.json).write_text(json.dumps(result, indent=2))
    with open(args.csv, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(csv_rows[0].keys()))
        w.writeheader()
        w.writerows(csv_rows)
    print(json.dumps({
        'off_cycles': off_cycles, 'on_cycles': on_cycles,
        'saved_cycles': off_cycles - on_cycles,
        'legacy_residual_pct': round(off_legacy_pct, 3),
        'exclusive_off': dict(off_cat),
        'lookahead': {k: as_int(on_log, k) for k in ['hits', 'misses', 'fetches', 'aborts']},
        'invariants_ok': not failures, 'failures': failures,
    }, indent=2))
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
