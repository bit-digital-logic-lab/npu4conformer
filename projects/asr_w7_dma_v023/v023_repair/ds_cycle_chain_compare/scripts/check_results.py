#!/usr/bin/env python3
"""Check all scenario outputs against independent gold and emit result.json."""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
RUNS = HERE / 'runs'
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)

SCEN = ['default', 'rand_bp', 'long_wait']

def load_hex(p):
    return [int(x, 16) for x in Path(p).read_text().split()]

def ints(text, keys):
    out = {}
    for k in keys:
        m = re.findall(r'\b%s=(\d+)' % re.escape(k), text)
        out[k] = int(m[-1]) if m else None
    return out

def pair(text, prefix):
    m = re.search(r'%s (\d+)\.\.(\d+) \((\d+)\)' % re.escape(prefix), text)
    if not m:
        return None
    return {'first': int(m.group(1)), 'last': int(m.group(2)), 'busy_cycles': int(m.group(3))}

def parse_cand(text):
    d = {}
    mt = re.search(r'CAND_TOTAL start=(\d+) done=(\d+) drain=(\d+) total_start_to_drain=(\d+) done_to_drain=(\d+) csr_cycles=(\d+)', text)
    if mt:
        d.update(dict(zip(['start','done','drain','total_start_to_drain','done_to_drain','csr_cycles'],
                          [int(x) for x in mt.groups()])))
    w = re.search(r'CAND_WINDOW matrix=(\d+)\.\.(\d+) \((\d+)\) vector=(\d+)\.\.(\d+) \((\d+)\) layout=(\d+)\.\.(\d+) \((\d+)\) any_busy=(\d+)', text)
    if w:
        d['windows'] = {
            'matrix': {'first': int(w.group(1)), 'last': int(w.group(2)), 'busy_cycles': int(w.group(3))},
            'vector': {'first': int(w.group(4)), 'last': int(w.group(5)), 'busy_cycles': int(w.group(6))},
            'layout': {'first': int(w.group(7)), 'last': int(w.group(8)), 'busy_cycles': int(w.group(9))},
            'any_busy': int(w.group(10)),
        }
    mm = re.search(r'CAND_MATRIX cycles=(\d+) compute=(\d+) queue=(\d+) fetch=(\d+) engine_wait=(\d+) retire_wait=(\d+) rblk=(\d+) wblk=(\d+) cg=(\d+) cc=(\d+)', text)
    d['matrix'] = dict(zip(['cycles','compute','queue','fetch','engine_wait','retire_wait','rblk','wblk','cg','cc'],
                           [int(x) for x in mm.groups()])) if mm else {}
    d['veclay'] = ints(text, ['vcyc','lcyc','vrb','vwb','lrb','lwb'])
    d['axi'] = ints(text, ['rburst','wburst','rbeats','wbeats','rdpeak','wrpeak','rdstall','wrstall','tag_err'])
    d['wait'] = ints(text, ['ar_stall','aw_stall','w_stall','r_stall','b_stall','bfm_read_busy','bfm_write_busy','bfm_bresp_wait'])
    m = re.search(r'CAND_ENGWAIT matrix ar=(\d+) aw=(\d+) w=(\d+) r=(\d+) b=(\d+) \| vector ar=(\d+) aw=(\d+) w=(\d+) r=(\d+) b=(\d+) \| layout ar=(\d+) aw=(\d+) w=(\d+) r=(\d+) b=(\d+) \| graph_fetch ar=(\d+) r=(\d+) \| queue ar=(\d+) r=(\d+)', text)
    if m:
        g = [int(x) for x in m.groups()]
        d['engine_wait'] = {
            'matrix': dict(zip(['ar','aw','w','r','b'], g[0:5])),
            'vector': dict(zip(['ar','aw','w','r','b'], g[5:10])),
            'layout': dict(zip(['ar','aw','w','r','b'], g[10:15])),
            'graph_fetch': {'ar': g[15], 'r': g[16]},
            'queue': {'ar': g[17], 'r': g[18]},
        }
    d['graph'] = ints(text, ['fetch','operator','drain','busy_cycles'])
    m = re.search(r'CAND_STATUS busy=(\d+) done=(\d+) fault=(\d+) err=([0-9a-fA-F]+) completed=(\d+) last=(\d+)', text)
    if m:
        d['status'] = {'busy': int(m.group(1)), 'done': int(m.group(2)), 'fault': int(m.group(3)),
                       'error': int(m.group(4), 16), 'completed': int(m.group(5)), 'last': int(m.group(6))}
    d['result'] = (re.findall(r'CAND_RESULT (\w+)', text) or [None])[-1]
    return d

def parse_base(text):
    d = {}
    mt = re.search(r'BASE_TOTAL start=(\d+) done=(\d+) drain=(\d+) total_start_to_drain=(\d+) done_to_drain=(\d+)', text)
    if mt:
        d.update(dict(zip(['start','done','drain','total_start_to_drain','done_to_drain'],
                          [int(x) for x in mt.groups()])))
    w = re.search(r'BASE_WINDOW matrix=(\d+)\.\.(\d+) \((\d+)\) vector=(\d+)\.\.(\d+) \((\d+)\) layout=(\d+)\.\.(\d+) \((\d+)\) any_busy=(\d+)', text)
    if w:
        d['windows'] = {
            'matrix': {'first': int(w.group(1)), 'last': int(w.group(2)), 'busy_cycles': int(w.group(3))},
            'vector': {'first': int(w.group(4)), 'last': int(w.group(5)), 'busy_cycles': int(w.group(6))},
            'layout': {'first': int(w.group(7)), 'last': int(w.group(8)), 'busy_cycles': int(w.group(9))},
            'any_busy': int(w.group(10)),
        }
    mm = re.search(r'BASE_MATRIX cycles=(\d+) compute=(\d+) rblk=(\d+) wblk=(\d+) rdwait=(\d+) wrwait=(\d+) scalar=(\d+) c48_errs=(\d+)', text)
    d['matrix'] = dict(zip(['cycles','compute','rblk','wblk','rdwait','wrwait','scalar','c48_errs'],
                           [int(x) for x in mm.groups()])) if mm else {}
    d['veclay'] = ints(text, ['sum','sum'])
    m = re.search(r'BASE_VECLAY vcyc=(\d+)/(\d+)/(\d+)/(\d+) sum=(\d+) lcyc=(\d+)/(\d+)/(\d+) sum=(\d+)', text)
    if m:
        g = [int(x) for x in m.groups()]
        d['veclay'] = {'vcyc': g[0:4], 'vsum': g[4], 'lcyc': g[5:8], 'lsum': g[8]}
    d['axi'] = ints(text, ['rburst','wburst','rbeats','wbeats','rdpeak','wrpeak','rdstall','wrstall','tag_err'])
    d['wait'] = ints(text, ['ar_stall','aw_stall','w_stall','r_stall','b_stall','bfm_read_busy','bfm_write_busy','bfm_bresp_wait'])
    d['result'] = (re.findall(r'BASE_RESULT (\w+)', text) or [None])[-1]
    return d

def c48_check(path, exp):
    words = load_hex(path)
    blob = b''.join(w.to_bytes(4, 'little') for w in words)
    got = [int.from_bytes(blob[i:i+6], 'little') for i in range(0, 1024*6, 6)]
    return sum(1 for a, b in zip(got, exp) if a != b)

def main():
    gold = load_hex(HERE/'inputs'/'gold_i16.hex')
    exp = load_hex(HERE/'inputs'/'mat32'/'exp_c.txt')
    scenarios = {}
    all_ok = True
    for s in SCEN:
        entry = {'scenario': s}
        for who in ['candidate', 'baseline']:
            d = RUNS/s/who
            log = (d/'run.log')
            txt = log.read_text() if log.exists() else ''
            out = d/'out.hex'
            ov = load_hex(out) if out.exists() else []
            mism = [i for i, (a, b) in enumerate(zip(ov, gold)) if a != b]
            c48m = c48_check(d/'stage_c48.hex', exp) if (d/'stage_c48.hex').exists() else None
            parsed = parse_cand(txt) if who == 'candidate' else parse_base(txt)
            ok = (parsed.get('result') == 'PASS' and len(ov) == len(gold) and not mism and c48m == 0)
            all_ok = all_ok and ok
            entry[who] = {
                'log': str(log.relative_to(HERE)),
                'out_hex': str(out.relative_to(HERE)) if out.exists() else None,
                'gold_words': len(gold),
                'out_words': len(ov),
                'gold_mismatches': len(mism),
                'c48_mismatches': c48m,
                'pass': ok,
                'metrics': parsed,
            }
        c = entry['candidate']['metrics']
        b = entry['baseline']['metrics']
        if c.get('total_start_to_drain') and b.get('total_start_to_drain'):
            entry['delta'] = {
                'total_cycles_baseline': b['total_start_to_drain'],
                'total_cycles_candidate': c['total_start_to_drain'],
                'candidate_minus_baseline': c['total_start_to_drain'] - b['total_start_to_drain'],
                'baseline_over_candidate': round(b['total_start_to_drain'] / c['total_start_to_drain'], 4),
            }
            bsum = (b['matrix'].get('cycles') or 0) + (b['veclay'].get('vsum') or 0) + (b['veclay'].get('lsum') or 0)
            csum = (c['matrix'].get('cycles') or 0) + (c['veclay'].get('vcyc') or 0) + (c['veclay'].get('lcyc') or 0)
            entry['delta']['baseline_engine_sum'] = bsum
            entry['delta']['candidate_engine_sum'] = csum
            entry['delta']['baseline_residual_non_engine'] = b['total_start_to_drain'] - bsum
            entry['delta']['candidate_residual_non_engine'] = c['total_start_to_drain'] - csum
        scenarios[s] = entry

    result = {
        'status': 'small_chain_logic_pass_full_system_pending',
        'scope': 'single-clock logic simulation of a 32x32x32 matrix -> I48/F32 -> vector -> layout chain; not CASE0000, not full model, not board, not STA',
        'gold': {
            'source': 'fixtures/mat32/exp_c.txt (ds_matrix integer golden) -> independent numpy float32 scale/bias/RNE/clip -> i16',
            'sha256': hashlib.sha256((HERE/'inputs'/'gold_i16.hex').read_bytes()).hexdigest() if False else None,
        },
        'inputs': json.loads((REP/'input_check.json').read_text()) if (REP/'input_check.json').exists() else None,
        'scenarios': scenarios,
        'all_outputs_and_c48_match_gold': all_ok,
        'limits': [
            'baseline is host-sequenced with sealed vector/layout RTL, sealed matrix engine/storage and axi_dma_v019; candidate is one START PL superplan with the integrated P2 cluster/multi-DMA. Control/interface boundaries differ.',
            'therefore ratios below are comparable-chain interval ratios, not whole-machine or CASE0000 speedups.',
            'the shared-BFM/xbar harness is not a DDR/PHY model and all runs are logic simulation at one clock.',
            'primary_stream_fix is an epilogue stream module and is not in the current integrated filelist/data path; its 127-cycle packed-output result is not counted here.',
            'no synthesis, STA, Vivado, board, VNC, push, or frequency claim was made.',
        ],
    }
    # fill gold sha without importing hashlib twice weirdly
    import hashlib
    result['gold']['sha256'] = hashlib.sha256((HERE/'inputs'/'gold_i16.hex').read_bytes()).hexdigest()
    ws = HERE/'runs'/'watchdog_selftest'/'candidate'/'run.log'
    if ws.exists():
        wt = ws.read_text()
        result['watchdog_selftest'] = {
            'log': str(ws.relative_to(HERE)),
            'fired': 'WATCHDOG_FIRED' in wt,
            'expected_fail_marker': 'CAND_RESULT FAIL watchdog' in wt,
        }
    (HERE/'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({s: {'candidate_ok': v['candidate']['pass'], 'baseline_ok': v['baseline']['pass'],
                          'delta': v.get('delta')} for s, v in scenarios.items()}, indent=2))
    sys.exit(0 if all_ok else 1)

if __name__ == '__main__':
    main()
