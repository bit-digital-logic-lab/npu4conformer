#!/usr/bin/env python3
"""Compile the sealed V022 per-program plans into one W023 superplan.

The superplan format is the one accepted by rtl/wc_superplan_ctrl.sv:
  header 64B + N*64B node descriptors, FNV-1a integrity hash.
A node type 4 (SEQ) points at an existing immutable V022 program plan.

For the 68 real programs this compiler emits:
  * whole68_serial.bin : conservative total order justified by measured DDR
    WAW/RAW/WAR conflicts (all 68 programs currently share scratch/temp ranges).
  * whole68_roots.bin  : all roots, intentionally rejected by the verifier
    because the same ranges alias.  This is the scheduling counter-example.
Both are marked non-runnable as a whole CASE because the 68 programs consume
tensors produced by the non-fused host/legacy DAG, which is not in the image.
"""
import argparse, hashlib, json, struct, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'scripts'))
import wc_analysis as A

OUT = HERE / 'analysis'
MAGIC_H = 0x5743504c
MAGIC_N = 0x57434e44
VERSION = 0x00010001
HASH_SEED = 0x811c9dc5
TYPE_SEQ = 4


def fnv(h, w):
    return ((h ^ (w & 0xffffffff)) * 0x01000193) & 0xffffffff


def hash_header(words):
    h = HASH_SEED
    for j, v in enumerate(words):
        if j != 7:
            h = fnv(h, v)
    return h


def hash_node(h, words):
    for v in words:
        h = fnv(h, v)
    return h


def align(x, n=4096):
    return (x + n - 1) // n * n


def node(i, base, count, depmask, epoch=1):
    return [MAGIC_N, TYPE_SEQ, i,
            depmask & 0xffffffff, (depmask >> 32) & 0xffffffff,
            (depmask >> 64) & 0xffffffff, (depmask >> 96) & 0xffffffff,
            base, count, 0, 0, 0, 0, epoch, 0, 0]


def emit(base, nodes, param_end, generation=0, bad_hash=False):
    n = len(nodes)
    words = [MAGIC_H, VERSION, n, 3, param_end, 64 + 64 * n, generation, 0] + [0] * 8
    h = hash_header(words)
    for nd in nodes:
        h = hash_node(h, nd)
    words[7] = h ^ (1 if bad_hash else 0)
    blob = bytearray(struct.pack('<16I', *words))
    for nd in nodes:
        blob += struct.pack('<16I', *nd)
    return bytes(blob)


def parse_plan_blob(blob):
    if len(blob) < 64 or len(blob) % 64:
        raise ValueError('bad superplan length')
    w = list(struct.unpack_from('<16I', blob, 0))
    if w[0] != MAGIC_H or w[1] != VERSION:
        raise ValueError('bad header magic/version')
    if w[2] != len(blob) // 64 - 1:
        raise ValueError('node count mismatch')
    h = hash_header(w)
    nodes = []
    for i in range(w[2]):
        nd = list(struct.unpack_from('<16I', blob, 64 + 64 * i))
        h = hash_node(h, nd)
        nodes.append(nd)
    return dict(words=w, nodes=nodes, hash=h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--image-bytes', type=int, default=None)
    args = ap.parse_args()
    ana = json.loads((OUT / 'analysis.json').read_text())
    progs = json.loads((OUT / 'programs.json').read_text())
    deps = json.loads((OUT / 'deps.json').read_text())
    manifest = json.loads((HERE / 'assets/manifest_v022.json').read_text())
    image_bytes = args.image_bytes or manifest['image_bytes']
    base = align(0x10000000 + image_bytes, 4096)
    order = ana['topo_order']
    n = len(order)
    if n > 128:
        raise ValueError('candidate controller supports 128 nodes')
    # Every program is a root in the tensor-name graph.  A serial order is
    # required because the measured byte footprints conflict pairwise.
    serial_nodes = []
    for i, key in enumerate(order):
        p = progs[key]
        mask = (1 << (i - 1)) if i else 0
        serial_nodes.append(node(i, p['plan_address'], p['plan_count'], mask, i + 1))
    serial_blob = emit(base, serial_nodes, base + 64 + 64 * n, generation=0)
    (OUT / 'whole68_serial.bin').write_bytes(serial_blob)

    roots_nodes = [node(i, progs[k]['plan_address'], progs[k]['plan_count'], 0, i + 1)
                   for i, k in enumerate(order)]
    roots_blob = emit(base, roots_nodes, base + 64 + 64 * n, generation=0)
    (OUT / 'whole68_roots.bin').write_bytes(roots_blob)

    # Peak temp-liveness sweep and shared-write statistics.
    events = []
    for key in order:
        p = progs[key]
        events.append((p['temp_base'], 1))
        events.append((p['temp_end'], -1))
    events.sort()
    cur = peak = 0
    for _, d in events:
        cur += d
        peak = max(peak, cur)
    write_spans = {}
    for key in order:
        for lo, hi in progs[key]['writes']:
            if hi > 0x04000000:
                write_spans.setdefault((lo, hi), []).append(key)
    shared = {f'{lo:x}-{hi:x}': v for (lo, hi), v in write_spans.items() if len(v) > 1}

    report = dict(
        compiler='wc_compile.py', format='WCPL v1 / 64B header + 64B nodes',
        source_image_sha256=ana['image']['sha256'],
        manifest_sha256=ana['manifest_sha256'],
        load_address=f'0x{base:08x}',
        plan_bytes=len(serial_blob), node_count=n,
        generation=0, generation_note='0 means ignore runtime generation; production must bind the sealed generation',
        closed_programs=n, closed_original_nodes=ana['members'],
        plan_instructions=ana['instructions'],
        matrix_descriptors=ana['matrix_descriptors'],
        serial_edges=n - 1,
        tensor_name_dependencies=ana['max_deps'],
        external_inputs=len(ana['external_inputs']),
        external_outputs=len(ana['external_outputs']),
        hazard_pairs=ana['hazard_pairs'],
        hazard_kinds=ana['hazard_kinds'],
        temp_overlap_pairs=ana['temp_overlap_pairs'],
        peak_temp_live_ranges=peak,
        shared_write_spans=len(shared),
        shared_write_examples=list(shared.items())[:5],
        runnable_whole_case=False,
        runnable_reason='68 closed programs are disjoint islands: all 68 inputs are produced outside the closed set; 591 legacy queues/593 descriptors remain in the host DAG (quoted from work/CURRENT_WORK.txt). A single START here would read tensors not yet produced.',
        scope='Compiler/control-path candidate. Not a whole-model result; not board-tested; no timing claim.',
        source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        order=order,
        serial_plan_sha256=hashlib.sha256(serial_blob).hexdigest(),
        roots_plan_sha256=hashlib.sha256(roots_blob).hexdigest(),
    )
    (OUT / 'whole68.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ('order', 'shared_write_examples')}, indent=2))


if __name__ == '__main__':
    main()
