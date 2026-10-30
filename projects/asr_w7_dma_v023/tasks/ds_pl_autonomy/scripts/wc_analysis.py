#!/usr/bin/env python3
"""Static analysis of the sealed V022 image: real program DAG, DDR footprint,
temporary/scratch aliasing, and host-residual control.

Read-only inputs:
  work/assets/parameters002/parameters.bin
  assets/manifest_v022.json (extracted from the sealed zip, byte-identical)
No write to work/.  All derived files go under this task directory.
"""
import argparse, collections, hashlib, json, struct, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parents[1]
WORK = HERE.parents[1] / 'work'
PARAM = WORK / 'assets/parameters002/parameters.bin'
MANIFEST = HERE / 'assets/manifest_v022.json'
OUT = HERE / 'analysis'

PARAM_BASE = 0x10000000
ARENA_BASE = 0x03000000
SCRATCH_END = 0x04000000
INTER_BASE = 0x04000000
INTER_END = 0x08000000
MAGIC_INSN = 0x22504c4e
MAGIC_VEC = 0x22564543
MAGIC_LAY = 0x224c4159
MAGIC_QUEUE = 0x51415352


def align(x, n=64):
    return (x + n - 1) // n * n


def tiles(x):
    return (x + 31) // 32


def words(img, addr, count):
    if addr < PARAM_BASE or addr + count * 4 > len(img) + PARAM_BASE:
        raise ValueError('word read outside image: %x %d' % (addr, count))
    return struct.unpack_from('<%dI' % count, img, addr - PARAM_BASE)


class Shadow:
    """Minimal byte shadow for scratch copies performed by a layout move.
    V022 emits the matrix queue in parameter DDR, then a real PL layout move
    copies it to 0x03000000 before kind=1 dispatch.  Static analysis must
    follow that copy to see the real queue descriptors."""
    def __init__(self):
        self.b = {}

    def copy_from_param(self, img, src, dst, n):
        if src < PARAM_BASE or src + n > len(img) + PARAM_BASE:
            return False
        blob = bytes(img[src - PARAM_BASE:src - PARAM_BASE + n])
        for i, v in enumerate(blob):
            self.b[dst + i] = v
        return True

    def read(self, addr, count):
        try:
            return bytes(self.b[addr + i] for i in range(count))
        except KeyError:
            raise ValueError('shadow read miss at %x' % addr)


def shadow_words(sh, addr, count):
    blob = sh.read(addr, count * 4)
    return struct.unpack('<%dI' % count, blob)


def clamp_range(base, size, limit_lo=0, limit_hi=1 << 40):
    """Conservative byte interval; never invents an address outside [lo,hi)."""
    if size <= 0:
        return None
    lo = max(base, limit_lo)
    hi = min(base + size, limit_hi)
    if hi <= lo:
        return None
    return (lo, hi)


def add_span(spans, base, size, kind, detail):
    r = clamp_range(base, size)
    if r:
        spans.append(dict(lo=r[0], hi=r[1], kind=kind, detail=detail))


def parse_vector(img, addr):
    w = words(img, addr, 16)
    if w[0] != MAGIC_VEC:
        raise ValueError('vector magic %08x at %x' % (w[0], addr))
    flags = w[1]
    op = flags & 0xff
    a16 = (flags >> 8) & 1
    out16 = (flags >> 9) & 1
    bs = (flags >> 10) & 1
    as_ = (flags >> 11) & 1
    cs = (flags >> 12) & 1
    a48 = (flags >> 13) & 1
    tiled = (flags >> 14) & 1
    a, b, c, d, total, period = w[2], w[3], w[4], w[5], w[6], w[7]
    abytes = (1 if as_ else total) * (6 if a48 else 2 if a16 else 4)
    if bs:
        bbytes = 4
    elif tiled:
        bbytes = ((period + 31) & ~31) * 4
    elif period:
        bbytes = period * 4
    else:
        bbytes = total * 4
    cbytes = (1 if cs else total) * 4
    dbytes = total * (2 if out16 else 4)
    return dict(kind='vector', addr=addr, op=op, a=a, b=b, c=c, d=d,
                total=total, period=period, flags=flags,
                abytes=abytes, bbytes=bbytes, cbytes=cbytes, dbytes=dbytes)


def parse_layout(img, addr):
    w = words(img, addr, 32)
    if w[0] != MAGIC_LAY:
        raise ValueError('layout magic %08x at %x' % (w[0], addr))
    mode, src, dst, total, nbytes = w[1], w[2], w[3], w[4], w[5]
    m, n, full_n, col_start = w[6], w[7], w[8], w[9]
    channels, ih, iw = w[10], w[11], w[12]
    kh, kw, oh, ow = w[13], w[14], w[15], w[16]
    sh, sw, dh, dw = w[17], w[18], w[19], w[20]
    ph, pw, koff = w[21], w[22], w[23]
    if mode == 0:
        src_elems, dst_elems = total, total
    elif mode == 1:
        src_elems, dst_elems = m * full_n, total
    elif mode == 2:
        src_elems, dst_elems = channels * ih * iw * 2, total
    elif mode == 3:
        src_elems = tiles(m) * tiles(n) * 1024
        dst_elems = (m - 1) * full_n + col_start + n if m else total
    elif mode == 4:
        src_elems = tiles(m) * tiles(n) * 1024
        dst_elems = (col_start + n) * m
    else:
        raise ValueError('layout mode')
    return dict(kind='layout', addr=addr, mode=mode, src=src, dst=dst,
                total=total, bytes=nbytes, m=m, n=n, full_n=full_n,
                col_start=col_start, src_bytes=src_elems * nbytes,
                dst_bytes=max(dst_elems, total) * nbytes)


def parse_queue(reader, addr, count):
    if count <= 0 or count > 65535:
        raise ValueError('queue count')
    out = []
    for i in range(count):
        w = reader(addr + i * 64, 16)
        if w[0] != MAGIC_QUEUE:
            raise ValueError('queue magic')
        epoch = w[2]
        prev = w[3]
        abase, bbase, cbase = w[4], w[5], w[6]
        m, n, depth = w[7], w[8], w[9]
        flags = w[13]
        accum = (flags >> 16) & 1
        abytes = tiles(m) * tiles(depth) * 2048
        bbytes = tiles(depth) * tiles(n) * 1024
        cbytes = tiles(m) * tiles(n) * 6144
        out.append(dict(kind='queue_desc', addr=addr + i * 64, epoch=epoch,
                        prev=prev, a=abase, b=bbase, c=cbase, m=m, n=n,
                        depth=depth, accum=accum, abytes=abytes,
                        bbytes=bbytes, cbytes=cbytes))
    return out


def parse_plan(img, plan_addr, plan_count):
    if plan_count <= 0 or plan_count > 65535:
        raise ValueError('plan count')
    ins = []
    for i in range(plan_count):
        w = words(img, plan_addr + i * 64, 16)
        if w[0] != MAGIC_INSN:
            raise ValueError('insn magic')
        kind, ticket, dep = w[1], w[2], w[3]
        ptr, length = w[4], w[5]
        if ticket != i + 1:
            raise ValueError('ticket order')
        if dep != (0xffffffff if i == 0 else i - 1):
            raise ValueError('non-linear dependency at %d' % i)
        if any(w[6:]):
            raise ValueError('reserved instruction words')
        ins.append(dict(index=i, kind=kind, ticket=ticket, dep=dep,
                        ptr=ptr, length=length))
    return ins


def footprint(img, p):
    """Return conservative read/write byte spans for one V022 program."""
    reads, writes, ops = [], [], []
    sh = Shadow()
    for ins in parse_plan(img, p['plan_address'], p['plan_count']):
        if ins['kind'] == 1:
            def rd(addr, count):
                if addr >= PARAM_BASE:
                    return words(img, addr, count)
                return shadow_words(sh, addr, count)
            q = parse_queue(rd, ins['ptr'], ins['length'])
            for d in q:
                add_span(reads, d['a'], d['abytes'], 'A', d)
                add_span(reads, d['b'], d['bbytes'], 'B', d)
                if d['accum']:
                    add_span(reads, d['c'], d['cbytes'], 'Cacc', d)
                add_span(writes, d['c'], d['cbytes'], 'C', d)
            ops.append(dict(insn_kind=1, ptr=ins['ptr'], count=ins['length'], descs=q))
        elif ins['kind'] == 2:
            v = parse_vector(img, ins['ptr'])
            add_span(reads, v['a'], v['abytes'], 'Va', v)
            if v['op'] in (0, 1, 2, 3, 9, 10, 11, 14, 17):
                add_span(reads, v['b'], v['bbytes'], 'Vb', v)
            if v['op'] == 17:
                add_span(reads, v['c'], v['cbytes'], 'Vc', v)
            add_span(writes, v['d'], v['dbytes'], 'Vd', v)
            v=dict(v);v['insn_kind']=2;ops.append(v)
        elif ins['kind'] == 3:
            l = parse_layout(img, ins['ptr'])
            if l['mode'] == 0 and l['src'] >= PARAM_BASE and l['dst'] < PARAM_BASE:
                moved = sh.copy_from_param(img, l['src'], l['dst'], l['src_bytes'])
                l['shadow_copy'] = moved
            add_span(reads, l['src'], l['src_bytes'], 'Ls', l)
            add_span(writes, l['dst'], l['dst_bytes'], 'Ld', l)
            l=dict(l);l['insn_kind']=3;ops.append(l)
        else:
            raise ValueError('insn kind')
    return reads, writes, ops


def merge(spans):
    s = sorted((x['lo'], x['hi']) for x in spans)
    out = []
    for lo, hi in s:
        if out and lo <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], hi))
        else:
            out.append((lo, hi))
    return out


def overlap(a, b):
    return a[0] < b[1] and b[0] < a[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', default='real68')
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    meta = json.loads(MANIFEST.read_text())
    img = np.memmap(PARAM, dtype=np.uint8, mode='r')
    print('image', len(img), 'sha', hashlib.sha256(img).hexdigest()[:16])
    progs = meta['v211_programs']
    order = list(progs)
    rec = {}
    for key in order:
        p = progs[key]
        v = meta['v022_programs'][key]
        reads, writes, ops = footprint(img, v)
        rec[key] = dict(key=key, part=p['part'], kind0=p['kind'],
                        input=p['input'], output=p['output'],
                        members=p['members'], ops_n=len(p['ops']),
                        plan_address=v['plan_address'], plan_count=v['plan_count'],
                        matrix_tasks=v['matrix_tasks'], temp_base=v['temp_base'],
                        temp_end=v['temp_end'], output_address=v['output_address'],
                        input_q_address=v['input_q_address'],
                        reads=merge(reads), writes=merge(writes),
                        read_bytes=sum(x[1] - x[0] for x in merge(reads)),
                        write_bytes=sum(x[1] - x[0] for x in merge(writes)),
                        op_hist=dict(collections.Counter(o['insn_kind'] for o in ops)),
                        op_count=len(ops))
    # Tensor-name DAG between the 68 closed programs.
    producer = {}
    for key, r in rec.items():
        producer.setdefault(r['output'], []).append(key)
    deps = {}
    for key, r in rec.items():
        d = sorted(set(producer.get(r['input'], [])))
        deps[key] = d
    # Kahn topological sort + cycle report.
    indeg = {k: len(d) for k, d in deps.items()}
    succ = collections.defaultdict(list)
    for k, ds in deps.items():
        for d in ds:
            succ[d].append(k)
    q = collections.deque(sorted(k for k, n in indeg.items() if n == 0))
    topo = []
    while q:
        k = q.popleft()
        topo.append(k)
        for s in sorted(succ[k]):
            indeg[s] -= 1
            if indeg[s] == 0:
                q.append(s)
    cycle_nodes = sorted(k for k, n in indeg.items() if n > 0)
    # Address-level hazards among programs (conservative merged extents).
    def spans(r, which):
        return r[which]
    hazards = []
    for i, a in enumerate(order):
        for b in order[i + 1:]:
            ra, rb = rec[a], rec[b]
            kinds = []
            for wa in ra['writes']:
                for wb in rb['writes']:
                    if overlap(wa, wb):
                        kinds.append('WAW')
                        break
                if kinds and kinds[-1] == 'WAW':
                    break
            for wa in ra['writes']:
                for rb_ in rb['reads']:
                    if overlap(wa, rb_):
                        kinds.append('RAW')
                        break
                if 'RAW' in kinds:
                    break
            for ra_ in ra['reads']:
                for wb in rb['writes']:
                    if overlap(ra_, wb):
                        kinds.append('WAR')
                        break
                if 'WAR' in kinds:
                    break
            if kinds:
                hazards.append(dict(a=a, b=b, kinds=sorted(set(kinds))))
    # Temp-range overlap is separately quantified: it is the V022 relocation target.
    temp_overlaps = []
    for i, a in enumerate(order):
        for b in order[i + 1:]:
            ra, rb = rec[a], rec[b]
            ta = (ra['temp_base'], ra['temp_end'])
            tb = (rb['temp_base'], rb['temp_end'])
            if overlap(ta, tb):
                temp_overlaps.append(dict(a=a, b=b,
                                          overlap_bytes=min(ta[1], tb[1]) - max(ta[0], tb[0])))
    # Output/address alias: same DDR output written by >1 program.
    addr_writers = collections.defaultdict(list)
    for key, r in rec.items():
        addr_writers[(r['output_address'], r['output_address'] + 4)].append(key)
    output_alias = [v for v in addr_writers.values() if len(v) > 1]
    # Same input consumed by multiple programs is legal, recorded.
    fanout = collections.Counter()
    for key, r in rec.items():
        for d in deps[key]:
            fanout[d] += 1
    summary = dict(
        image=dict(path=str(PARAM), bytes=len(img),
                   sha256=hashlib.sha256(img).hexdigest()),
        manifest_sha256=hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        programs=len(order), members=sum(len(r['members']) for r in rec.values()),
        instructions=sum(r['plan_count'] for r in rec.values()),
        matrix_descriptors=sum(r['matrix_tasks'] for r in rec.values()),
        topo_order=topo, cycle_nodes=cycle_nodes,
        roots=[k for k in order if not deps[k]],
        leaves=[k for k in order if fanout[k] == 0],
        max_deps=max(len(d) for d in deps.values()),
        multi_dep_nodes=[dict(key=k, deps=d) for k, d in deps.items() if len(d) > 1],
        external_inputs=sorted(set(r['input'] for r in rec.values()
                                   if not producer.get(r['input']))),
        external_outputs=sorted(set(rec[k]['output'] for k in order if fanout[k] == 0)),
        hazard_pairs=len(hazards), hazard_kinds=dict(collections.Counter(
            k for h in hazards for k in h['kinds'])),
        temp_overlap_pairs=len(temp_overlaps),
        temp_overlap_bytes=sum(t['overlap_bytes'] for t in temp_overlaps),
        output_alias=output_alias,
        total_read_bytes=sum(r['read_bytes'] for r in rec.values()),
        total_write_bytes=sum(r['write_bytes'] for r in rec.values()),
    )
    (OUT / 'programs.json').write_text(json.dumps(rec, indent=1) + '\n')
    (OUT / 'deps.json').write_text(json.dumps(dict(deps=deps, topo=topo), indent=1) + '\n')
    (OUT / 'hazards.json').write_text(json.dumps(dict(pairs=hazards,
                                                      temp_overlaps=temp_overlaps[:200],
                                                      temp_overlap_pairs=len(temp_overlaps)), indent=1) + '\n')
    (OUT / 'analysis.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({k: v for k, v in summary.items()
                      if k not in ('topo_order', 'roots', 'leaves', 'multi_dep_nodes',
                                   'external_inputs', 'external_outputs')}, indent=2))
    print('topo head', topo[:5])
    print('cycle', cycle_nodes[:5])
    print('max deps', summary['max_deps'])


if __name__ == '__main__':
    main()
