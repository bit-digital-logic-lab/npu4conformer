#!/usr/bin/env python3
"""Generate abnormal-closeout fixtures from the integrated fixture.

The normal image is the integrated candidate's own fixture (already built from
the independent ds_matrix golden).  Variants patch one descriptor/payload field
at a time; SEQ and multi-task plans are rebuilt with graph_common.  No RTL
output is used as a golden.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'integrated_copy' / 'scripts'))
import graph_common as G

FIX = HERE / 'fixtures'
FIX.mkdir(parents=True, exist_ok=True)
SRC = HERE / 'integrated_copy' / 'fixtures' / 'mem_integrated.hex'

WORDS = 262144
PLAN = 0x10008000
PAY = 0x10009000
PARAM_A = 0x10001000
PARAM_W = 0x10002000
SCALAR_ONE = 0x10000000
SCALAR_SCALE = 0x10000004
SCALAR_HALF = 0x10000008
SCALAR_DUMMY = 0x1000000C
ARENA_A = 0x04000000
ARENA_B = 0x04001000
ARENA_C = 0x04002000
ARENA_C2 = 0x0400A000
ARENA_D0 = 0x04004000
ARENA_D1 = 0x04005000
ARENA_D2 = 0x04006000
ARENA_I16 = 0x04007000
ARENA_OUT = 0x04008000
QUEUE_BASE = 0x0400C000
PARAM_END = 0x10040000

BASE = {'arena': 0x04000000, 'external': 0x08000000, 'param': 0x10000000}
WIN = {'arena': 0x40000, 'external': 0x80000, 'param': 0xC0000}


def wi(addr):
    for name, base in BASE.items():
        if base <= addr < base + 0x40000:
            return (WIN[name] + addr - base) // 4
    raise ValueError(hex(addr))


def get(mem, addr):
    return mem[wi(addr)]


def put(mem, addr, word):
    mem[wi(addr)] = word & 0xffffffff


def write(name, mem):
    (FIX / name).write_text('\n'.join(f'{w:08x}' for w in mem) + '\n')


def emit_plan(mem, nodes, flags=0):
    blob, _ = G.emit(PLAN, nodes, PARAM_END, generation=0, flags=flags,
                     input_base=0x08000000, input_limit=0x10000000)
    for off in range(0, len(blob), 4):
        put(mem, PLAN + off, int.from_bytes(blob[off:off + 4], 'little'))


def in_node():
    return G.node(G.T_IN, 0, 0, base=PARAM_A, count=512,
                  flags=G.FLAG_ROOT | G.FLAG_EXTERNAL, input_tid=0,
                  output_tid=0, input_base=PARAM_A, input_bytes=2048,
                  output_base=PARAM_A, output_bytes=2048, version=1, epoch=1)


def lay_node(nid, dep, pay_off=0x000):
    return G.node(G.T_LAY, nid, dep, base=PAY + pay_off, count=0,
                  input_tid=0, output_tid=1, input_base=PARAM_A,
                  input_bytes=2048, output_base=ARENA_A, output_bytes=2048,
                  version=1, epoch=2)


def seq_node(nid, dep):
    return G.node(G.T_SEQ, nid, dep, base=PAY + 0x700, count=2,
                  input_tid=1, output_tid=2, input_base=PARAM_A,
                  input_bytes=512, output_base=ARENA_A, output_bytes=512,
                  version=1, epoch=3)


def integrated_nodes(mat_count=1):
    """Same 9-node chain as the integrated fixture, with MAT queue count."""
    return [
        G.node(G.T_IN, 0, 0, base=PARAM_A, count=512,
               flags=G.FLAG_ROOT | G.FLAG_EXTERNAL, input_tid=0, output_tid=0,
               input_base=PARAM_A, input_bytes=2048, output_base=PARAM_A,
               output_bytes=2048, version=1, epoch=1),
        G.node(G.T_LAY, 1, 1 << 0, base=PAY + 0x000, count=0,
               input_tid=0, output_tid=1, input_base=PARAM_A, input_bytes=2048,
               output_base=ARENA_A, output_bytes=2048, version=1, epoch=2),
        G.node(G.T_LAY, 2, 1 << 0, base=PAY + 0x100, count=0,
               input_tid=0, output_tid=2, input_base=PARAM_W, input_bytes=1024,
               output_base=ARENA_B, output_bytes=1024, version=1, epoch=3),
        G.node(G.T_MAT, 3, (1 << 1) | (1 << 2), base=QUEUE_BASE, count=mat_count,
               input_tid=1, output_tid=3, input_base=ARENA_A, input_bytes=2048,
               output_base=ARENA_C, output_bytes=6144, version=1, epoch=4),
        G.node(G.T_VEC, 4, 1 << 3, base=PAY + 0x200, count=0,
               input_tid=3, output_tid=4, input_base=ARENA_C, input_bytes=6144,
               output_base=ARENA_D0, output_bytes=4096, version=1, epoch=5),
        G.node(G.T_VEC, 5, 1 << 4, base=PAY + 0x300, count=0,
               input_tid=4, output_tid=5, input_base=ARENA_D0, input_bytes=4096,
               output_base=ARENA_D1, output_bytes=4096, version=1, epoch=6),
        G.node(G.T_VEC, 6, 1 << 5, base=PAY + 0x400, count=0,
               input_tid=5, output_tid=6, input_base=ARENA_D1, input_bytes=4096,
               output_base=ARENA_D2, output_bytes=4096, version=1, epoch=7),
        G.node(G.T_VEC, 7, 1 << 6, base=PAY + 0x500, count=0,
               input_tid=6, output_tid=7, input_base=ARENA_D2, input_bytes=4096,
               output_base=ARENA_I16, output_bytes=2048, version=1, epoch=8),
        G.node(G.T_LAY, 8, 1 << 7, base=PAY + 0x600, count=0,
               flags=G.FLAG_OUTPUT | G.FLAG_RETAINED,
               input_tid=7, output_tid=8, input_base=ARENA_I16, input_bytes=2048,
               output_base=ARENA_OUT, output_bytes=2048, version=1, epoch=9),
    ]


def main():
    words = [int(x, 16) for x in SRC.read_text().split()]
    assert len(words) == WORDS
    normal = list(words)
    write('mem_normal.hex', normal)

    # SEQ mutex / hang plans (reuse the normal data/payloads)
    mem = list(normal)
    emit_plan(mem, [in_node(), lay_node(1, 1 << 0), seq_node(2, 1 << 0)])
    write('mem_seq_lay_first.hex', mem)

    mem = list(normal)
    emit_plan(mem, [in_node(), seq_node(1, 1 << 0), lay_node(2, 1 << 0)])
    write('mem_seq_seq_first.hex', mem)

    mem = list(normal)
    emit_plan(mem, [in_node(), seq_node(1, 1 << 0)])
    write('mem_seq_hang_wait.hex', mem)
    write('mem_seq_hang_run.hex', mem)

    # Multi-task matrix queue: two descriptors, second writes ARENA_C2.
    mem = list(normal)
    q0 = [get(mem, QUEUE_BASE + i * 4) for i in range(16)]
    q1 = list(q0)
    q1[3] = 0xffffffff
    q1[6] = ARENA_C2
    q1[2] = 2
    for i, v in enumerate(q1):
        put(mem, QUEUE_BASE + 64 + i * 4, v)
    emit_plan(mem, integrated_nodes(mat_count=2))
    write('mem_multitask.hex', mem)

    # Bad queue variants
    mem = list(normal); put(mem, QUEUE_BASE, 0xdeadbeef); write('mem_bad_queue_magic.hex', mem)
    mem = list(normal); put(mem, QUEUE_BASE + 4, 1 | (20 << 16)); write('mem_bad_queue_backend.hex', mem)
    mem = list(normal); put(mem, QUEUE_BASE + 12, 0); write('mem_bad_queue_pred.hex', mem)
    mem = list(normal); put(mem, QUEUE_BASE + 16, QUEUE_BASE); write('mem_bad_queue_overlap.hex', mem)
    mem = list(normal); put(mem, QUEUE_BASE + 56, 0); put(mem, QUEUE_BASE + 60, 1 | (1 << 16))
    write('mem_bad_mat_op.hex', mem)

    # Illegal vector op (op19) and illegal layout mode (7)
    mem = list(normal); put(mem, PAY + 0x200 + 4, 0x13); write('mem_bad_vec_op.hex', mem)
    mem = list(normal); put(mem, PAY + 0x000 + 4, 7); write('mem_bad_lay_mode.hex', mem)

    print('wrote safety fixtures:', sorted(p.name for p in FIX.glob('mem_*.hex')))


if __name__ == '__main__':
    main()
