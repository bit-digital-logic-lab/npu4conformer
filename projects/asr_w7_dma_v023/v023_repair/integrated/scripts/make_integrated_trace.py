#!/usr/bin/env python3
"""Convert the integrated RTL per-cycle trace into traffic-ledger JSONL.

Observed valid&&ready events only.  Module lanes use the sampled busy state;
no PE-cycle or idle time is invented.  AR/AW event lines carry the real
address/length; R/W beats are counted at the same shared AXI port.
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
CSV = HERE / 'traces' / 'integrated_trace.csv'
OUT = HERE / 'traces' / 'integrated_trace.jsonl'
WINDOW_START = 12

REGIONS = [
    (0x10000000, 0x10001000, 'scalars', 'F32'),
    (0x10001000, 0x10002000, 'A16_param', 'A16'),
    (0x10002000, 0x10003000, 'W7_param', 'W7p8'),
    (0x10008000, 0x10009000, 'plan', 'PLAN'),
    (0x10009000, 0x1000a000, 'payloads', 'DESC'),
    (0x04000000, 0x04001000, 'A16', 'A16'),
    (0x04001000, 0x04002000, 'W7', 'W7p8'),
    (0x04002000, 0x04004000, 'C48', 'C48'),
    (0x04004000, 0x04005000, 'F32_conv', 'F32'),
    (0x04005000, 0x04006000, 'F32_scale', 'F32'),
    (0x04006000, 0x04007000, 'F32_bias', 'F32'),
    (0x04007000, 0x04008000, 'A16_out', 'I16'),
    (0x04008000, 0x04009000, 'final', 'I16'),
    (0x0400c000, 0x0400d000, 'queue', 'DESC'),
]


def region(addr):
    for base, end, name, fmt in REGIONS:
        if base <= addr < end:
            return name, fmt, addr - base
    return ('other_%08x' % addr, 'RAW', 0)


def popcount(x):
    return bin(x & 0xffff).count('1')


def num(d, k, default=0):
    try:
        return int(d.get(k, default))
    except (TypeError, ValueError):
        return default


def main():
    lines = CSV.read_text().splitlines()
    header = lines[0].split(',')
    per = []
    arq, awq = [], []
    transfers = []
    rid = wid = 0
    last = WINDOW_START

    for raw in lines[1:]:
        if not raw:
            continue
        if raw.startswith('AR,'):
            _, c, owner, addr, ln = raw.split(',')
            arq.append({'owner': int(owner), 'addr': int(addr, 16),
                        'beats': int(ln) + 1, 'start': int(c), 'got': 0})
            continue
        if raw.startswith('AW,'):
            _, c, owner, addr, ln = raw.split(',')
            awq.append({'owner': int(owner), 'addr': int(addr, 16),
                        'beats': int(ln) + 1, 'start': int(c), 'got': 0, 'bytes': 0})
            continue
        parts = raw.split(',')
        if len(parts) < len(header):
            continue
        try:
            d = {header[i]: parts[i] for i in range(len(header))}
            c = int(d['cycle'])
        except (ValueError, IndexError):
            continue
        last = max(last, c)
        rv = d.get('rv') == '1'; rr = d.get('rready') == '1'; rl = d.get('rlast') == '1'
        wv = d.get('wv') == '1'; wr = d.get('wr') == '1'; wl = d.get('wlast') == '1'
        if rv and rr and arq:
            q = arq[0]
            q['got'] += 1
            if rl:
                b = arq.pop(0)
                name, fmt, off = region(b['addr'])
                omap = {0: 'graph_fetch', 1: 'vector', 2: 'layout', 3: 'matrix', 4: 'matrix_queue'}
                op = omap.get(b['owner'], 'unknown')
                transfers.append({
                    'type': 'transfer', 'id': 'rd%04d' % rid, 'resource': 'axi_r',
                    'start': b['start'], 'end': c + 1, 'tensor': name, 'version': 'run1',
                    'format': fmt, 'src': 'DDR', 'dst': op + '_bank', 'op': op,
                    'phase': 'load', 'reason': 'burst_load', 'logical_offset': off,
                    'logical_bytes': b['got'] * 16, 'valid_bytes': b['got'] * 16,
                    'bus_bytes': b['got'] * 16, 'request': b['start'],
                    'first_data': b['start'], 'last_data': c, 'completion': c + 1,
                    'status': 'success', 'descriptor_id': 'rd%04d' % rid, 'owner': b['owner'],
                })
                rid += 1
        if wv and wr and awq:
            q = awq[0]
            q['got'] += 1
            q['bytes'] += popcount(num(d, 'wstrb'))
            if wl:
                b = awq.pop(0)
                name, fmt, off = region(b['addr'])
                omap = {0: 'vector', 1: 'layout', 2: 'matrix'}
                op = omap.get(b['owner'], 'unknown')
                transfers.append({
                    'type': 'transfer', 'id': 'wr%04d' % wid, 'resource': 'axi_w',
                    'start': b['start'], 'end': c + 1, 'tensor': name, 'version': 'run1',
                    'format': fmt, 'src': op + '_bank', 'dst': 'DDR', 'op': op,
                    'phase': 'store', 'reason': 'burst_store', 'logical_offset': off,
                    'logical_bytes': b['got'] * 16, 'valid_bytes': b['bytes'],
                    'bus_bytes': b['got'] * 16, 'request': b['start'],
                    'first_data': b['start'], 'last_data': c, 'completion': c + 1,
                    'status': 'success', 'descriptor_id': 'wr%04d' % wid, 'owner': b['owner'],
                })
                wid += 1

        arv = d.get('arv') == '1'; arr = d.get('arr') == '1'
        awv = d.get('awv') == '1'; awr = d.get('awr') == '1'
        bv = d.get('bv') == '1'; br = d.get('br') == '1'
        ac = num(d, 'ar_count'); wc = num(d, 'aw_count'); bc = num(d, 'b_count')
        if rv and rr:
            rs, rr_, rb, rw = 'payload', 'R beat', 16, 16
        elif arv and arr:
            rs, rr_, rb, rw = 'command', 'AR accepted', 0, 0
        elif ac:
            rs, rr_, rb, rw = 'wait_memory', 'outstanding read', 0, 0
        else:
            rs, rr_, rb, rw = 'idle_no_work', 'no read work', 0, 0
        if wv and wr:
            ws, wr_, wb, ww = 'payload', 'W beat', popcount(num(d, 'wstrb')), 16
        elif awv and awr:
            ws, wr_, wb, ww = 'command', 'AW accepted', 0, 0
        elif bv and br:
            ws, wr_, wb, ww = 'response', 'B response', 0, 0
        elif wc or bc:
            ws, wr_, wb, ww = 'wait_memory', 'outstanding write/response', 0, 0
        else:
            ws, wr_, wb, ww = 'idle_no_work', 'no write work', 0, 0
        per.append({
            'cycle': c,
            'axi_r': (rs, rr_, rb, rw),
            'axi_w': (ws, wr_, wb, ww),
            'ddr_bfm': ('payload', 'shared data channel', rb + wb, rw + ww) if (rb or wb) else
                       ('command', 'shared command channel', 0, 0) if (arv and arr) or (awv and awr) else
                       ('wait_memory', 'outstanding shared transaction', 0, 0) if (ac or wc or bc) else
                       ('idle_no_work', 'no shared transaction', 0, 0),
            'graph': ('compute', 'WCPG busy', 0, 0) if d.get('busy') == '1' else ('idle_no_work', 'graph idle', 0, 0),
            'matrix': ('compute', 'matrix child busy', 0, 0) if d.get('matrix_busy') == '1' else ('idle_no_work', 'matrix idle', 0, 0),
            'vector': ('compute', 'vector engine busy', 0, 0) if d.get('vector_busy') == '1' else ('idle_no_work', 'vector idle', 0, 0),
            'layout': ('compute', 'layout engine busy', 0, 0) if d.get('layout_busy') == '1' else ('idle_no_work', 'layout idle', 0, 0),
        })

    meta = {
        'type': 'metadata', 'schema': 1,
        'scope': 'V0.23 integrated single-clock logic simulation; shared AXI128 BFM, not board DDR',
        'resources': {
            'axi_r': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                      'kind': 'channel', 'evidence': 'RVALID&&RREADY / ARVALID&&ARREADY / outstanding count',
                      'capacity_bytes_per_tick': 16},
            'axi_w': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                      'kind': 'channel', 'evidence': 'WVALID&&WREADY (WSTRB bytes) / AW / B',
                      'capacity_bytes_per_tick': 16},
            'ddr_bfm': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                        'kind': 'channel', 'evidence': 'shared BFM R/W handshakes; union of both directions (separate R and W channels)',
                        'capacity_bytes_per_tick': 32},
            'graph': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                      'kind': 'module', 'evidence': 'WCPG controller busy sample'},
            'matrix': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                       'kind': 'module', 'evidence': 'matrix queue child/core busy sample; no PE-cycle fabrication'},
            'vector': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                       'kind': 'module', 'evidence': 'vector engine busy sample'},
            'layout': {'unit': 'cycle', 'timebase': 'tb_clk', 'start': WINDOW_START, 'end': last + 1,
                       'kind': 'module', 'evidence': 'layout engine busy sample'},
        },
        'window': {'start': WINDOW_START, 'end': last + 1},
        'source': 'tb_v023_integrated.sv per-cycle valid&&ready/busy monitor + AR/AW event lines',
        'notes': 'A burst is a transfer; bytes are R beats*16 and WSTRB popcount. '
                 'Prefetch over-read is real read traffic and is not labelled cache hit.',
    }
    out = [meta] + transfers
    resources = list(meta['resources'].keys())
    for res in resources:
        cur = None
        for item in per:
            c = item['cycle']
            if c < WINDOW_START:
                continue
            st, reason, b, wire = item[res]
            if cur is None:
                cur = {'start': c, 'state': st, 'reason': reason, 'bytes': b, 'wire_bytes': wire}
            elif cur['state'] == st and cur['reason'] == reason:
                cur['bytes'] += b
                cur['wire_bytes'] += wire
            else:
                cur['end'] = c
                out.append({'type': 'interval', 'resource': res, 'start': cur['start'],
                            'end': cur['end'], 'state': cur['state'], 'reason': cur['reason'],
                            'evidence': meta['resources'][res]['evidence'],
                            'bytes': cur['bytes'], 'wire_bytes': cur['wire_bytes']})
                cur = {'start': c, 'state': st, 'reason': reason, 'bytes': b, 'wire_bytes': wire}
        if cur is not None:
            cur['end'] = last + 1
            out.append({'type': 'interval', 'resource': res, 'start': cur['start'],
                        'end': cur['end'], 'state': cur['state'], 'reason': cur['reason'],
                        'evidence': meta['resources'][res]['evidence'],
                        'bytes': cur['bytes'], 'wire_bytes': cur['wire_bytes']})
    OUT.write_text('\n'.join(json.dumps(o, ensure_ascii=False) for o in out) + '\n')
    print(json.dumps({'cycles': len(per), 'transfers': len(transfers),
                      'intervals': len(out) - 1 - len(transfers),
                      'window': [WINDOW_START, last + 1]}, indent=2))


if __name__ == '__main__':
    main()
