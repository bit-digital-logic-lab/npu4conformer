#!/usr/bin/env python3
"""Generate WCPG plans + BFM images for the SEQ-exclusive unit tests.

Plans are built with the same independent graph_common.py format used by the
integrated fixture.  Nothing here is read from RTL.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'integrated_copy' / 'scripts'))
import graph_common as G

FIX = HERE / 'fixtures'
FIX.mkdir(parents=True, exist_ok=True)

PLAN = 0x10008000
PAY = 0x10009000
PARAM_A = 0x10001000
ARENA_A = 0x04000000
PARAM_END = 0x10040000
WORDS = 262144

BASE = {'arena': 0x04000000, 'external': 0x08000000, 'param': 0x10000000}
WIN = {'arena': 0x40000, 'external': 0x80000, 'param': 0xC0000}


def wi(addr):
    for name, base in BASE.items():
        if base <= addr < base + 0x40000:
            return (WIN[name] + addr - base) // 4
    raise ValueError(hex(addr))


def put(mem, addr, word):
    mem[wi(addr)] = word & 0xffffffff


def put_bytes(mem, addr, blob):
    for i in range(0, len(blob), 4):
        chunk = blob[i:i + 4] + b'\x00' * (4 - len(blob[i:i + 4]))
        put(mem, addr + i, int.from_bytes(chunk, 'little'))


def lay_payload(mode=0, src=PARAM_A, dst=ARENA_A, total=256, nb=2):
    return [0x224C4159, mode, src, dst, total, nb] + [0] * 26


def base_mem():
    mem = [0] * WORDS
    # source data (only the layout copy touches it)
    for i in range(64):
        put(mem, PARAM_A + i * 4, 0x11110000 + i)
    return mem


def plan(mem, nodes, flags=0):
    blob, hw = G.emit(PLAN, nodes, PARAM_END, generation=0, flags=flags,
                      input_base=0x08000000, input_limit=0x10000000)
    for off in range(0, len(blob), 4):
        put(mem, PLAN + off, int.from_bytes(blob[off:off + 4], 'little'))
    return blob, hw


def write(name, mem):
    (FIX / name).write_text('\n'.join(f'{w:08x}' for w in mem) + '\n')


def in_node(nid, dep, flags=G.FLAG_ROOT | G.FLAG_EXTERNAL):
    return G.node(G.T_IN, nid, dep, base=PARAM_A, count=512, flags=flags,
                  input_tid=0, output_tid=0, input_base=PARAM_A,
                  input_bytes=2048, output_base=PARAM_A, output_bytes=2048,
                  version=1, epoch=1)


def lay_node(nid, dep, pay_off=0x000):
    return G.node(G.T_LAY, nid, dep, base=PAY + pay_off, count=0,
                  input_tid=0, output_tid=1, input_base=PARAM_A,
                  input_bytes=2048, output_base=ARENA_A, output_bytes=512,
                  version=1, epoch=2)


def seq_node(nid, dep):
    return G.node(G.T_SEQ, nid, dep, base=PAY + 0x700, count=2,
                  input_tid=1, output_tid=2, input_base=PARAM_A,
                  input_bytes=512, output_base=ARENA_A, output_bytes=512,
                  version=1, epoch=3)


def main():
    # LAY is earlier in scan order than SEQ, and both depend only on IN.
    mem = base_mem()
    for off, words in {0x000: lay_payload()}.items():
        for i, v in enumerate(words):
            put(mem, PAY + off + i * 4, v)
    plan(mem, [in_node(0, 0), lay_node(1, 1 << 0), seq_node(2, 1 << 0)])
    write('mutex_lay_first.hex', mem)

    # SEQ is earlier; LAY becomes eligible while SEQ is in flight.
    mem = base_mem()
    for i, v in enumerate(lay_payload()):
        put(mem, PAY + i * 4, v)
    plan(mem, [in_node(0, 0), seq_node(1, 1 << 0), lay_node(2, 1 << 0)])
    write('mutex_seq_first.hex', mem)

    # SEQ never accepts (dispatch-wait hang).
    mem = base_mem()
    plan(mem, [in_node(0, 0), seq_node(1, 1 << 0)])
    write('mutex_hang_wait.hex', mem)

    # SEQ accepts but never returns done (in-flight hang).
    mem = base_mem()
    plan(mem, [in_node(0, 0), seq_node(1, 1 << 0)])
    write('mutex_hang_run.hex', mem)

    # Healthy SEQ + LAY, both short.
    mem = base_mem()
    for i, v in enumerate(lay_payload()):
        put(mem, PAY + i * 4, v)
    plan(mem, [in_node(0, 0), seq_node(1, 1 << 0), lay_node(2, 1 << 0)])
    write('mutex_healthy.hex', mem)

    print('wrote mutex fixtures:', sorted(p.name for p in FIX.glob('mutex_*.hex')))


if __name__ == '__main__':
    main()
