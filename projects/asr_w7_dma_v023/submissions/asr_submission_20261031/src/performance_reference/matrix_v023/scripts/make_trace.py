#!/usr/bin/env python3
"""Build traffic-ledger + module-activity JSONL from tb_p2_cluster_axi CSV.

The CSV is produced by RTL simulation at the testbench clock.  All resources
share one explicitly declared timebase (`tb_clk`) and are in logic cycles.
No physical DDR frequency or bandwidth is claimed.
"""
import argparse, json, re
from pathlib import Path

BASE = 0x03000000
C_BASE = 0x03003000
BYTES = {0: 2048, 1: 1024, 2: 6144}

def parse(path):
    start = end = None
    cycles = {}
    ev = []
    for line in Path(path).read_text().splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == 'S':
            start = int(p[1])
        elif p[0] == 'D':
            end = int(p[1])
        elif p[0] == 'C':
            v = [int(x) for x in p[1:]]
            cycles[v[0]] = v[1:]
        elif p[0] == 'E':
            ev.append((p[1], [int(x) for x in p[2:]]))
    if start is None or end is None:
        raise SystemExit('trace has no S/D window')
    return start, end, cycles, ev

def merge(intervals):
    out = []
    for e in intervals:
        if out and out[-1]['state'] == e['state'] and out[-1]['end'] == e['start'] \
           and out[-1].get('reason') == e.get('reason'):
            out[-1]['end'] = e['end']
            out[-1]['bytes'] = out[-1].get('bytes', 0) + e.get('bytes', 0)
            out[-1]['wire_bytes'] = out[-1].get('wire_bytes', 0) + e.get('wire_bytes', 0)
        else:
            out.append(dict(e))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('csv', type=Path)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--scope', default='RTL logic simulation: matrix P2 cluster, AXI128 BFM; not board DDR')
    a = ap.parse_args()
    start, end, cycles, ev = parse(a.csv)

    # Event dictionaries
    lds = [dict(cycle=v[0], kind=v[1], row=v[2], col=v[3], addr=v[4]) for k, v in ev if k == 'ld']
    rdc = [dict(cycle=v[0], addr=v[1], beats=v[2]) for k, v in ev if k == 'rdcmd']
    rdb = [dict(cycle=v[0], n=v[1]) for k, v in ev if k == 'rdbeat']
    rdd = [dict(cycle=v[0]) for k, v in ev if k == 'rddone']
    csg = [dict(cycle=v[0], addr=v[1], beats=v[2], rowcol=v[3]) for k, v in ev if k == 'cseg']
    wrc = [dict(cycle=v[0], addr=v[1], beats=v[2]) for k, v in ev if k == 'wrcmd']
    wrb = [dict(cycle=v[0], n=v[1]) for k, v in ev if k == 'wrbeat']
    wrd = [dict(cycle=v[0]) for k, v in ev if k == 'wrdone']

    resources = {}
    for name, kind, evd in [
        ('axi_r', 'channel', 'RVALID&&RREADY / ARVALID&&ARREADY'),
        ('axi_w', 'channel', 'WVALID&&WREADY / AWVALID&&AWREADY / BVALID&&BREADY'),
        ('ddr_bfm', 'channel', 'AXI128 BFM shared data channel; logic model only'),
        ('compute', 'module', 'engine FSM state and array drain'),
        ('c_cache_rd', 'module', 'c_cache_banked4_pipe read port issue'),
        ('c_cache_wr', 'module', 'c_cache_banked4_pipe write port issue'),
        ('packer', 'module', 'C48 cseg/cval packer handshake'),
    ]:
        resources[name] = dict(unit='cycle', timebase='tb_clk', start=start, end=end,
                               kind=kind, evidence=evd)
    resources['axi_r']['capacity_bytes_per_tick'] = 16
    resources['axi_w']['capacity_bytes_per_tick'] = 16
    resources['ddr_bfm']['capacity_bytes_per_tick'] = 16

    # Write-beat bytes by cycle (C stream full beats are 16 B; tail uses WSTRB)
    wbytes = {}
    for e in wrb:
        wbytes[e['cycle']] = wbytes.get(e['cycle'], 0) + e['n']

    intervals = {k: [] for k in resources}
    # Event cycle counters for read grouping
    cur_r = None
    rq = list(rdc)
    rdone_q = list(rdd)
    ld_q = list(lds)
    # Only one read command is outstanding at a time in the storage.
    # Pair ld[i] with rdcmd[i] and rddone[i]; the engine is sequential.
    for i, ld in enumerate(ld_q):
        if i >= len(rq) or i >= len(rdone_q):
            break
        req = rq[i]
        done = rdone_q[i]
        beats = [b['cycle'] for b in rdb if req['cycle'] <= b['cycle'] <= done['cycle']]
        if not beats:
            continue
        kind = ld['kind']
        nb = BYTES[kind]
        tid = f'rd{i:03d}'
        tensor = 'A' if kind == 0 else 'W' if kind == 1 else 'Cpartial'
        fmt = 'A16' if kind == 0 else 'W7p8' if kind == 1 else 'C48'
        dst = 'Abank' if kind == 0 else 'Wbank' if kind == 1 else 'Ccache'
        rec = dict(type='transfer', id=tid, resource='axi_r', start=ld['cycle'], end=done['cycle'] + 1,
                   tensor=tensor, version='epoch3', format=fmt, src='DDR', dst=dst,
                   op='matrix', phase='load', reason='block_load',
                   logical_offset=ld['addr'] - BASE, logical_bytes=nb,
                   valid_bytes=req['beats'] * 16, bus_bytes=req['beats'] * 16,
                   request=req['cycle'], first_data=beats[0], last_data=beats[-1],
                   completion=done['cycle'], status='success', descriptor_id=tid)
        resources['axi_r']['start'] = min(resources['axi_r']['start'], rec['start'])
        resources['axi_r']['end'] = max(resources['axi_r']['end'], rec['end'])
        intervals['axi_r'].append(rec)

    # C write segments: cseg[i] -> wrcmd[i] -> wrdone[i]
    for i, cs in enumerate(csg):
        if i >= len(wrc) or i >= len(wrd):
            break
        req = wrc[i]
        done = wrd[i]
        beats = [b for b in wrb if req['cycle'] <= b['cycle'] <= done['cycle']]
        if not beats:
            continue
        tid = f'wr{i:03d}'
        rec = dict(type='transfer', id=tid, resource='axi_w', start=cs['cycle'], end=done['cycle'] + 1,
                   tensor='C', version='epoch3', format='C48', src='Ccache', dst='DDR',
                   op='matrix', phase='writeback', reason='result_stream',
                   logical_offset=cs['addr'] - C_BASE, logical_bytes=96,
                   valid_bytes=sum(b['n'] for b in beats), bus_bytes=len(beats) * 16,
                   request=req['cycle'], first_data=beats[0]['cycle'],
                   last_data=beats[-1]['cycle'], completion=done['cycle'],
                   status='success', descriptor_id=tid)
        resources['axi_w']['start'] = min(resources['axi_w']['start'], rec['start'])
        resources['axi_w']['end'] = max(resources['axi_w']['end'], rec['end'])
        intervals['axi_w'].append(rec)

    # Per-cycle intervals
    for cyc in range(start, end):
        c = cycles.get(cyc)
        if c is None:
            c = [0] * 21
        # columns (after cycle): 1 ar, 2 r, 3 rbp, 4 rdcmd, 5 aw, 6 w, 7 wbp,
        # 8 wrcmd, 9 b, 10 engstate, 11 storers, 12 wractive, 13 cacheread,
        # 14 cachewrite, 15 cseg, 16 cval, 17 cvalbp, 18 wq, 19 bout,
        # 20 rd_active, 21 wr_active
        d = c + [0] * (21 - len(c))
        st = {}
        if d[1]: st['axi_r'] = ('payload', 16, 'R beat accepted', 'RVALID&&RREADY')
        elif d[2]: st['axi_r'] = ('backpressure', 0, 'RVALID held, RREADY low', 'RVALID&&!RREADY')
        elif d[3]: st['axi_r'] = ('command', 0, 'AR accepted', 'ARVALID&&ARREADY')
        elif d[19]: st['axi_r'] = ('wait_memory', 0, 'read active, no R beat', 'DMA read state')
        else: st['axi_r'] = ('idle_no_work', 0, 'no read work', 'read FSM idle')
        # Write channel: payload priority, then backpressure, command, wait
        if d[5]: st['axi_w'] = ('payload', wbytes.get(cyc, 16), 'W beat accepted', 'WVALID&&WREADY')
        elif d[6]: st['axi_w'] = ('backpressure', 0, 'WVALID held, WREADY low', 'WVALID&&!WREADY')
        elif d[4]: st['axi_w'] = ('command', 0, 'AW accepted', 'AWVALID&&AWREADY')
        elif d[8]: st['axi_w'] = ('response', 0, 'B response accepted', 'BVALID&&BREADY')
        elif d[20]: st['axi_w'] = ('wait_memory', 0, 'write active, no W beat', 'write FSM state')
        else: st['axi_w'] = ('idle_no_work', 0, 'no write work', 'write FSM idle')
        # Shared BFM data channel (DUPLEx=0 default: one 128b beat/cycle)
        if d[1] or d[5]:
            st['ddr_bfm'] = ('payload', 16 if (d[1] or d[5]) else 0, 'one BFM data beat', 'R or W handshake')
        elif d[3] or d[4]:
            st['ddr_bfm'] = ('command', 0, 'AXI command', 'AR/AW handshake')
        else:
            st['ddr_bfm'] = ('idle_no_work', 0, 'no BFM data beat', 'BFM shared channel idle')
        es = d[9]
        if es == 11: st['compute'] = ('compute', 0, 'systolic RUN', 'engine state RUN=11')
        elif es in (12, 13): st['compute'] = ('c_collect', 0, 'C read-modify-write / stream', 'engine state CREAD/COLLECT')
        elif es in (7, 8, 9): st['compute'] = ('wait_operand', 0, 'waiting for prefetched stage / issuing prefetch', 'engine state WAITCUR/PREFA/PREFW')
        elif es == 0: st['compute'] = ('idle_no_work', 0, 'engine idle', 'engine state IDLE')
        else: st['compute'] = ('control', 0, 'grid/loop control', 'engine FSM')
        st['c_cache_rd'] = ('payload', 0, 'synchronous read issue', 'cache_rd_issue') if d[12] else ('idle_no_work', 0, 'no read group', 'cache_rd_issue=0')
        st['c_cache_wr'] = ('payload', 0, 'write group', 'cache_wr_load||cache_wr_collect') if d[13] else ('idle_no_work', 0, 'no write group', 'cache_wr=0')
        if d[14]: st['packer'] = ('command', 0, 'C segment command', 'cseg_valid&&cseg_ready')
        elif d[15]: st['packer'] = ('payload', 0, 'C48 value group', 'cval_valid&&cval_ready')
        elif d[16]: st['packer'] = ('backpressure', 0, 'cval held, packer full', 'cval_valid&&!cval_ready')
        else: st['packer'] = ('idle_no_work', 0, 'no C value', 'packer idle')
        for name, (state, byt, reason, evid) in st.items():
            e = dict(type='interval', resource=name, start=cyc, end=cyc + 1,
                     state=state, reason=reason, evidence=evid)
            if byt:
                e['bytes'] = byt; e['wire_bytes'] = byt
            intervals[name].append(e)

    metadata = dict(type='metadata', schema=1, scope=a.scope, resources=resources)
    lines = [json.dumps(metadata, ensure_ascii=False)]
    for name in intervals:
        for e in intervals[name]:
            if e.get('type') == 'transfer':
                lines.append(json.dumps(e, ensure_ascii=False))
            else:
                # Replace the temporary per-cycle event with a compact interval
                lines.append(json.dumps(e, ensure_ascii=False))
    # merge per-cycle intervals per resource
    out = [json.dumps(metadata, ensure_ascii=False)]
    for name in ['axi_r', 'axi_w', 'ddr_bfm', 'compute', 'c_cache_rd', 'c_cache_wr', 'packer']:
        tx = [e for e in intervals[name] if e.get('type') == 'transfer']
        iv = [e for e in intervals[name] if e.get('type') != 'transfer']
        for e in tx:
            out.append(json.dumps(e, ensure_ascii=False))
        for e in merge(iv):
            out.append(json.dumps(e, ensure_ascii=False))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text('\n'.join(out) + '\n')
    print(json.dumps(dict(out=str(a.out), transfers=len([x for x in out if '"type": "transfer"' in x]),
                          intervals=len(out) - 1 - len([x for x in out if '"type": "transfer"' in x]),
                          window=[start, end]), ensure_ascii=False))

if __name__ == '__main__':
    main()
