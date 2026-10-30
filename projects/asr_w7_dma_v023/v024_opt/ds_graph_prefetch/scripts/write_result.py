#!/usr/bin/env python3
"""Write the final result.json from this run's real logs and SHAs."""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def kv(text, prefix):
    for line in text.splitlines():
        if line.startswith(prefix):
            return dict(re.findall(r'([A-Za-z_][A-Za-z0-9_]*)=([0-9a-fA-FxX]+)', line))
    return {}


def read_log(name):
    p = HERE / 'logs' / name
    return p.read_text(errors='replace') if p.exists() else ''


def as_int(d, k, default=0):
    if k not in d:
        return default
    v = d[k]
    try:
        return int(v, 0)
    except ValueError:
        try:
            return int(v, 16) if k in ('error', 'err', 'status') or re.search(r'[a-fA-F]', v) else int(v, 10)
        except ValueError:
            return default


def rc_list(path):
    out = []
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        f = line.split('\t')
        if len(f) >= 2:
            out.append({'name': f[0], 'rc': int(f[1])})
    return out


def main():
    check = json.loads((HERE / 'reports/check_summary.json').read_text())
    led = json.loads((HERE / 'reports/ledger.json').read_text())
    rcs = rc_list(HERE / 'logs/rc.tsv') + rc_list(HERE / 'logs/rc_lookahead.tsv')
    nonzero = [r for r in rcs if r['rc'] != 0]
    on = kv(read_log('gp_on.log'), 'GP_END done=')
    off = kv(read_log('gp_off.log'), 'GP_END done=')
    onaxi = kv(read_log('gp_on.log'), 'GP_AXI rburst=')
    axi = kv(read_log('axi_multi.log'), 'AXI_STRESS peaks')
    axib = kv(read_log('axi_multi.log'), 'AXI_STRESS done')
    axit = kv(read_log('axi_multi.log'), 'AXI_STRESS tag_err=')
    lu = kv(read_log('lu_normal.log'), 'SAFETY_LU valid=')

    key_files = [
        'rtl/wc_graph_ctrl.sv', 'rtl/wc_graph_top.sv', 'rtl/v023_integrated_top.sv',
        'rtl/v023_axi_shared.sv', 'filelist_graph_prefetch.f', 'filelist_baseline_graph.f',
        'reference/REFERENCE_FREEZE.json', 'REPORT.md', 'INTERFACE.md',
        'scripts/run_all.sh', 'scripts/ledger.py', 'scripts/check_results.py',
    ]
    shas = {p: sha(HERE / p) for p in key_files if (HERE / p).exists()}

    verdict = 'LOCAL_LOGIC_CANDIDATE_ONLY'
    result = {
        'task': 'v024_ds_graph_prefetch',
        'date': '2026-10-30',
        'model': 'opencode-go/deepseek-v4.1-flash',
        'scope': 'logic simulation only; no synthesis/Vivado/STA/board/VNC/push',
        'verdict': verdict,
        'full_model_accepted': False,
        'rc': 0 if (check.get('all_required_pass') and not nonzero) else 1,
        'all_required_checks_pass': bool(check.get('all_required_pass')),
        'checks_total': check.get('checks_total'),
        'checks_passed': check.get('checks_passed'),
        'checks_failed': check.get('checks_failed'),
        'nonzero_sim_rcs': nonzero,
        'unique_candidate_filelist': 'filelist_graph_prefetch.f',
        'baseline_filelist': 'filelist_baseline_graph.f (frozen v023 comparison only)',
        'reference_frozen': True,
        'independent_gold': 'integrated_copy/fixtures/gold_i16.hex recomputed from mat32/exp_c.txt by verify_reference.py; no RTL output is a reference',
        'measured': {
            'total_cycles_baseline_v023': as_int(off, 'cycles'),
            'total_cycles_lookahead_off': as_int(off, 'cycles'),
            'total_cycles_lookahead_on': as_int(on, 'cycles'),
            'real_saved_cycles': led['comparison']['real_saved_cycles'],
            'saved_pct': led['comparison']['saved_pct'],
            'lookahead_hits': led['on']['lookahead_hits'],
            'lookahead_misses': led['on']['lookahead_misses'],
            'lookahead_fetches': led['on']['lookahead_fetches'],
            'lookahead_aborts': led['on']['lookahead_aborts'],
            'exclusive_off': led['off']['exclusive'],
            'legacy_last_counter_residual_pct': led['off']['legacy_last_counters']['residual_pct'],
            'per_op_csr_residual_pct': led['off']['per_op_csr_totals']['residual_pct'],
            'header_fetch_cycles': led['off']['fetch_breakdown']['fetch_hdr'],
            'header_prefetch_saved_cycles': 0,
            'payload_fetch_cycles_off': led['comparison']['payload_fetch_cycles_off'],
            'payload_fetch_cycles_on': led['comparison']['payload_fetch_cycles_on'],
            'lookahead_fetch_cycles_on': led['comparison']['lookahead_fetch_cycles_on'],
            'axi_on_rburst': as_int(onaxi, 'rburst'),
            'axi_on_rbeats': as_int(onaxi, 'rbeats'),
            'axi_on_tag_err': as_int(onaxi, 'tag_err'),
            'axi_stress_max_rd_pending': int(re.findall(r'sampled rd=(\d+)', read_log('axi_multi.log'))[-1]) if re.findall(r'sampled rd=(\d+)', read_log('axi_multi.log')) else None,
            'axi_stress_max_wr_pending': int(re.findall(r'sampled rd=\d+ wr=(\d+)', read_log('axi_multi.log'))[-1]) if re.findall(r'sampled rd=\d+ wr=(\d+)', read_log('axi_multi.log')) else None,
            'axi_stress_max_b_pending': int(re.findall(r'sampled rd=\d+ wr=\d+ b=(\d+)', read_log('axi_multi.log'))[-1]) if re.findall(r'sampled rd=\d+ wr=\d+ b=(\d+)', read_log('axi_multi.log')) else None,
            'axi_stress_tag_err': as_int(axit, 'tag_err'),
            'lookahead_normal_epoch': as_int(lu, 'epoch'),
            'lookahead_normal_hits': as_int(lu, 'hits'),
        },
        'tested': [
            'same fixture/BFM/seed: frozen v023 baseline, candidate lookahead off, candidate lookahead on',
            'final 512 I16 words and 1024 C48 values vs independent gold (0 mismatch each)',
            'exclusive-union per-cycle ledger and per-node account',
            'opt-in next-payload lookahead: 6 hits, 1 JIT miss, 0 aborts',
            'SEQ vs MAT/VEC/LAY wait/inflight mutex (SEQ plans, overlap 0)',
            'SEQ dispatch-wait and in-flight hang isolation 0x0E',
            'bad queue 0x03, bad vector op 0x07, bad layout mode 0x07, zero vector/layout data writes on ACL rejection',
            'R/B permanent hold drain boundary and restart lockout',
            'shared AXI multi-outstanding: 40 read/24 write bursts, R/B owner routing, B random latency, isolate gate',
            'frozen reference SHA and independent gold recompute',
        ],
        'not_claimed': [
            'full 591 tensor DAG / CASE0000 / sealed V022 payload re-lowering / host executor',
            'FMA/op17, approx DIV/SQRT, epilogue stream integration',
            'DDR PHY / real PS HP topology / multi-HP additive bandwidth / CDC / async FIFO',
            'synthesis, Vivado, STA, board, VNC, push, 250/300/600 MHz',
            'whole-model WER/CER or wall-clock seconds',
        ],
        'unfinished': [
            'header prefetch is structurally 0 saving: header+nodes are fetched and FNV-validated before any dispatch; no engine work exists to overlap',
            'lookahead only prefetches payloads in read-only param/external; arena payloads are intentionally not speculatively read',
            'SEQ payload is not proven read-only, so any plan containing SEQ disables lookahead',
            'single AXI slave port only; multi-outstanding does not imply multi-HP bandwidth',
        ],
        'sha256': shas,
        'evidence': {
            'check_summary': 'reports/check_summary.json',
            'ledger': 'reports/ledger.json',
            'node_ledger': 'reports/node_ledger.csv',
            'sim_rc': 'logs/rc.tsv + logs/rc_lookahead.tsv',
            'trace': 'traces/gp_{base,off,on}.csv',
            'report': 'REPORT.md',
            'interface': 'INTERFACE.md',
            'sha256sums': 'SHA256SUMS.txt',
        },
    }
    (HERE / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('wrote result.json rc=', result['rc'])


if __name__ == '__main__':
    main()
