#!/usr/bin/env python3
"""Compile the recovered sets into WCPG v2 control graphs.

Outputs (all in analysis/):
  whole68_global.bin   68 external-input nodes + 68 real V022 SEQ nodes
  ledger591.bin        591 host-order ledger MAT nodes (NOT a dataflow DAG)
  small_real.bin       4-node real LAY->ADD->MUL chain
  bad_root.bin         root without input provenance (negative)
  no_output.bin        graph with no retained output (negative)
  bad_hash.bin         integrity failure (negative)
  forward_dep.bin      forward dependency (negative)

The 68 SEQ node payloads are the sealed V022 linear plans.  The control test
uses a SEQ stub; no arithmetic is claimed for those nodes.  The small graph
uses the real vector/layout engines in tb_wc_graph_real.
"""
import json
import math
import struct
from pathlib import Path

import graph_common as G

TASK = Path(__file__).resolve().parents[1]
A = TASK / 'analysis'
PARAM_END = 0x10040000
PARAM68 = 0x1A5AC000
PLAN68 = 0x10010000
PLAN591 = 0x10020000
PLANSMALL = 0x10008000
PAY = 0x10009000

FLAG_ROOT = 1
FLAG_OUTPUT = 2
FLAG_EXTERNAL = 4
FLAG_RETAINED = 8
FLAG_SYNTH_ORDER = 16


def write(name, blob, meta):
    (A / name).write_bytes(blob)
    meta['bytes'] = len(blob)
    meta['sha256'] = __import__('hashlib').sha256(blob).hexdigest()
    return meta


def main():
    closed = json.loads((A / 'closed68.json').read_text())
    ledger = json.loads((A / 'outer591_ledger.json').read_text())
    alloc = json.loads((A / 'global_alloc.json').read_text())
    reloc = json.loads((A / 'relocation_map.json').read_text())

    maps = {}

    # ---------------- 68 closed programs, one IN and one SEQ each ----------
    nodes = []
    n = 0
    for key, p in closed.items():
        r = reloc['closed68'][key]
        nodes.append(G.node(
            G.T_IN, n, 0, base=r['input_new'], count=(p['input_bytes_q16'] + 3) // 4,
            flags=FLAG_ROOT | FLAG_EXTERNAL,
            output_tid=r['input_tid'], input_tid=r['input_tid'],
            input_base=r['input_new'], input_bytes=p['input_bytes_q16'],
            output_base=r['input_new'], output_bytes=p['input_bytes_q16'],
            version=1, epoch=n + 1))
        n += 1
    seq_base = n
    for i, (key, p) in enumerate(closed.items()):
        r = reloc['closed68'][key]
        nodes.append(G.node(
            G.T_SEQ, n, 1 << i, base=p['plan_address'], count=p['plan_count'],
            flags=FLAG_OUTPUT,
            input_tid=r['input_tid'], output_tid=r['output_tid'],
            input_base=r['input_new'], input_bytes=p['input_bytes_q16'],
            output_base=r['output_new'], output_bytes=p['output_bytes_f32'],
            version=1, epoch=n + 1))
        n += 1
    blob, hw = G.emit(PLAN68, nodes, PARAM68, generation=0,
                      flags=0xF, input_base=G.EXTERNAL_BASE,
                      input_limit=G.EXTERNAL_LIMIT)
    maps['whole68_global'] = write('whole68_global.bin', blob, dict(
        kind='whole68_global', format='WCPG v2', plan_base=PLAN68,
        node_count=len(nodes), input_nodes=seq_base, seq_nodes=len(closed),
        param_end=PARAM68, generation=0,
        closed_programs=len(closed), edges=len(closed),
        tensor_dependencies='68 independent external inputs -> 68 SEQ programs',
        arithmetic='SEQ stub in control test; real V022 payload not executed',
        runnable_whole_case=False,
        runnable_reason='outer ONNX/executor and 591 true dataflow edges absent; '
                        'the 68 inputs are external boundary tensors, not '
                        'produced inside this plan',
        node_map=[dict(id=i, type=nodes[i][1], base=nodes[i][4],
                       output_tid=nodes[i][7]) for i in range(len(nodes))]))

    # ---------------- 591 ledger host-order replay -------------------------
    nodes = []
    for i, t in enumerate(ledger):
        deps = 0 if i == 0 else (1 << (i - 1))
        flags = FLAG_SYNTH_ORDER
        if i == 0:
            flags |= FLAG_ROOT
            input_base, input_bytes = t['global_a_base'], t['a_bytes_q16']
            version = 1
        else:
            input_base, input_bytes = t['global_a_base'], t['a_bytes_q16']
            version = 1
        if i == len(ledger) - 1:
            flags |= FLAG_OUTPUT | FLAG_RETAINED
        nodes.append(G.node(
            G.T_MAT, i, deps, base=t['queue_base'], count=t['queue_count'],
            flags=flags, input_tid=t['global_a_tid'], output_tid=t['global_c_tid'],
            input_base=input_base, input_bytes=input_bytes,
            output_base=t['global_c_base'], output_bytes=t['c48_bytes'],
            version=version, epoch=i + 1))
    blob, hw = G.emit(PLAN591, nodes, PARAM_END, generation=0,
                      flags=0xF, input_base=G.EXTERNAL_BASE,
                      input_limit=G.EXTERNAL_LIMIT)
    maps['ledger591'] = write('ledger591.bin', blob, dict(
        kind='ledger591', format='WCPG v2', plan_base=PLAN591,
        node_count=len(nodes), param_end=PARAM_END, generation=0,
        ledger_tasks=len(ledger),
        edges=len(ledger) - 1,
        dependency_kind='synthetic host-order chain, NOT recovered tensor DAG',
        arithmetic='MAT control stub only; no matrix arithmetic executed',
        runnable_whole_case=False,
        runnable_reason='outer ONNX/executor absent; ledger has shapes and '
                        'parameter provenance but no A/output tensor names',
        node_map=[dict(id=i, type=1, base=ledger[i]['queue_base'],
                       output_base=ledger[i]['global_c_base'],
                       param_name=ledger[i]['param_name']) for i in range(len(nodes))]))

    # ---------------- small real LAY -> ADD -> MUL -------------------------
    lay = [0x224c4159, 0, 0x10001000, 0x04000000, 64, 4] + [0] * 26
    add = [0x22564543, 0x00000400, 0x04000000, 0x10000000, 0,
           0x04001000, 64, 0] + [0] * 8
    mul = [0x22564543, 0x00000402, 0x04001000, 0x10000004, 0,
           0x04002000, 64, 0] + [0] * 8
    payloads = [(PAY, struct.pack('<32I', *lay)),
                (PAY + 0x100, struct.pack('<16I', *add)),
                (PAY + 0x200, struct.pack('<16I', *mul))]
    nodes = [
        G.node(G.T_IN, 0, 0, base=0x10001000, count=64,
               flags=FLAG_ROOT | FLAG_EXTERNAL, input_tid=0, output_tid=0,
               input_base=0x10001000, input_bytes=256,
               output_base=0x10001000, output_bytes=256, version=1),
        G.node(G.T_LAY, 1, 1 << 0, base=PAY, count=0,
               input_tid=0, output_tid=1,
               input_base=0x10001000, input_bytes=256,
               output_base=0x04000000, output_bytes=256, version=1),
        G.node(G.T_VEC, 2, 1 << 1, base=PAY + 0x100, count=0,
               input_tid=1, output_tid=2,
               input_base=0x04000000, input_bytes=256,
               output_base=0x04001000, output_bytes=256, version=1),
        G.node(G.T_VEC, 3, 1 << 2, base=PAY + 0x200, count=0,
               flags=FLAG_OUTPUT | FLAG_RETAINED, input_tid=2, output_tid=3,
               input_base=0x04001000, input_bytes=256,
               output_base=0x04002000, output_bytes=256, version=1),
    ]
    blob, hw = G.emit(PLANSMALL, nodes, PARAM_END, generation=0,
                      flags=0xF, input_base=G.EXTERNAL_BASE,
                      input_limit=G.EXTERNAL_LIMIT)
    maps['small_real'] = write('small_real.bin', blob, dict(
        kind='small_real', format='WCPG v2', plan_base=PLANSMALL,
        node_count=len(nodes), param_end=PARAM_END, generation=0,
        payloads=[dict(addr=a, bytes=len(b)) for a, b in payloads],
        chain='IN -> LAY(copy 64 words) -> VEC(add float 1.0) -> VEC(mul float 2.0)',
        arithmetic='real ddr_layout_axi + ddr_vector_axi + asr_fp32_alu',
        runnable_whole_case=False,
        runnable_reason='small operator-level proof, not the ASR model'))

    # ---------------- negative plans ---------------------------------------
    # bad root: replace IN input/output base with an address outside every
    # legal window; keep the rest valid.
    bad_nodes = [list(x) for x in nodes]
    bad_nodes[0][8] = 0x02000000
    bad_nodes[0][10] = 0x02000000
    bad_nodes[0][4] = 0x02000000
    b, _ = G.emit(PLANSMALL + 0x2000, bad_nodes, PARAM_END, generation=0,
                  flags=0xF, input_base=G.EXTERNAL_BASE, input_limit=G.EXTERNAL_LIMIT)
    maps['bad_root'] = write('bad_root.bin', b, dict(kind='bad_root', expect='fault 0x08'))

    # no output: clear output flags everywhere
    no_nodes = [list(x) for x in nodes]
    for nd in no_nodes:
        nd[3] &= ~(FLAG_OUTPUT | FLAG_RETAINED)
    b, _ = G.emit(PLANSMALL + 0x3000, no_nodes, PARAM_END, generation=0,
                  flags=0xF, input_base=G.EXTERNAL_BASE,
                  input_limit=G.EXTERNAL_LIMIT)
    maps['no_output'] = write('no_output.bin', b, dict(kind='no_output', expect='fault 0x0a'))

    # bad hash
    b, _ = G.emit(PLANSMALL + 0x4000, nodes, PARAM_END, generation=0,
                  flags=0xF, input_base=G.EXTERNAL_BASE,
                  input_limit=G.EXTERNAL_LIMIT, bad_hash=True)
    maps['bad_hash'] = write('bad_hash.bin', b, dict(kind='bad_hash', expect='fault 0x04'))

    # forward dependency: node 0 depends on node 1
    fwd = [list(x) for x in nodes]
    fwd[0][16] = 1 << 1
    b, _ = G.emit(PLANSMALL + 0x5000, fwd, PARAM_END, generation=0,
                  flags=0xF, input_base=G.EXTERNAL_BASE,
                  input_limit=G.EXTERNAL_LIMIT)
    maps['forward_dep'] = write('forward_dep.bin', b, dict(kind='forward_dep', expect='fault 0x04'))

    # payload image for the real test (not a plan)
    payload_blob = bytearray(0x100000)
    for addr, data in payloads:
        off = 0xC0000 + (addr - 0x10000000)
        payload_blob[off:off + len(data)] = data
    (A / 'small_real_payloads.bin').write_bytes(bytes(payload_blob))
    maps['payloads'] = dict(bytes=len(payload_blob),
                            sha256=__import__('hashlib').sha256(payload_blob).hexdigest())

    # Joined trace/fusion views.
    (A / 'tensor_map.json').write_text(json.dumps(dict(
        tensors=alloc['tensors'],
        note='tid -> global base/bytes/live interval/version.  Boundary '
             'tensors of the 68 closed set are globally unique; the SEQ temp '
             'extent is scheduler-exclusive; 591 A/C are unique.'),
        indent=2) + '\n')

    def desc_map(name, nodes):
        return [dict(id=i, type=nodes[i][1], flags=nodes[i][3],
                     base=nodes[i][4], count=nodes[i][5],
                     input_tid=nodes[i][6], output_tid=nodes[i][7],
                     input_base=nodes[i][8], input_bytes=nodes[i][9],
                     output_base=nodes[i][10], output_bytes=nodes[i][11],
                     version=nodes[i][12],
                     deps=[j for j in range(1024)
                           if (sum(nodes[i][16+w] << (32*w)
                                   for w in range(32)) >> j) & 1])
                for i in range(len(nodes))]
    # Reconstruct node lists for the two main plans from their files.
    import struct as _st
    def load_nodes(path):
        b = Path(path).read_bytes()
        hw = _st.unpack_from('<16I', b, 0)
        out = []
        for i in range(hw[2]):
            out.append(list(_st.unpack_from('<48I', b, 64 + 192 * i)))
        return out
    nm = load_nodes(A / 'whole68_global.bin')
    nl = load_nodes(A / 'ledger591.bin')
    ns = load_nodes(A / 'small_real.bin')
    (A / 'descriptor_map.json').write_text(json.dumps(dict(
        whole68_global=desc_map('whole68_global', nm),
        ledger591=desc_map('ledger591', nl),
        small_real=desc_map('small_real', ns),
        note='descriptor -> global tensor ids and live storage; for trace and '
             'fusion planning.  Ledger dependencies are synthetic host order.'),
        indent=2) + '\n')

    (A / 'graph_manifest.json').write_text(json.dumps(maps, indent=2) + '\n')
    print(json.dumps({k: {kk: v[kk] for kk in ('bytes', 'node_count', 'sha256')}
                      for k, v in maps.items() if 'node_count' in v}, indent=2))


if __name__ == '__main__':
    main()
