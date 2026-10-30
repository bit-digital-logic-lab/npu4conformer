#!/usr/bin/env python3
"""Build the integrated fixture, WCPG plan, payloads and independent golden.

The matrix A16/W7 input is the ds_matrix eng_c0 integer fixture, relocated into
the integrated parameter window.  The matrix golden is ds_matrix's independent
integer exp_c; the vector/layout golden is computed here in numpy float32 from
that integer output, not read from RTL.
"""
import json, struct, subprocess, sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parents[1]
FIX = HERE / 'fixtures'
MAT = FIX / 'mat32'
MAT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(HERE / 'scripts'))
import graph_common as G

PARAM_END = 0x10040000
PLAN_BASE = 0x10008000
PAY = 0x10009000
ARENA_A = 0x04000000
ARENA_B = 0x04001000
ARENA_C = 0x04002000
ARENA_D0 = 0x04004000
ARENA_D1 = 0x04005000
ARENA_D2 = 0x04006000
ARENA_I16 = 0x04007000
ARENA_OUT = 0x04008000
QUEUE_BASE = 0x0400C000
PARAM_A = 0x10001000
PARAM_W = 0x10002000
SCALAR_ONE = 0x10000000
SCALAR_SCALE = 0x10000004
SCALAR_HALF = 0x10000008
SCALAR_DUMMY = 0x1000000C
SCALE = 2.0 ** -10
HALF = 0.5

MAT_WORDS = 262144
MEM_BASE = {"arena": 0x04000000, "external": 0x08000000, "param": 0x10000000}
WIN = {"arena": 0x40000, "external": 0x80000, "param": 0xC0000}


def win_index(addr):
    for name, base in MEM_BASE.items():
        if base <= addr < base + 0x40000:
            return (WIN[name] + (addr - base)) // 4
    raise ValueError(hex(addr))


def mem_get(mem, addr):
    return mem[win_index(addr)]


def mem_set(mem, addr, word):
    mem[win_index(addr)] = word & 0xffffffff


def mem_set_bytes(mem, addr, blob):
    for i in range(0, len(blob), 4):
        chunk = blob[i:i+4]
        chunk += b'\x00' * (4 - len(chunk))
        mem_set(mem, addr + i, int.from_bytes(chunk, 'little'))


def f32(x):
    return struct.unpack('<I', struct.pack('<f', np.float32(x)))[0]


def main():
    subprocess.run([
        sys.executable, str(HERE.parent / 'ds_matrix' / 'tests' / 'gen_engine_vectors.py'),
        '--out', str(MAT), '--m', '32', '--n', '32', '--k', '32',
        '--c-valid', '0', '--positions', '0x3210', '--clip', '1',
        '--a-base', '0x03000000', '--b-base', '0x03001000',
        '--c-base', '0x03002000', '--mem-words', '2048'
    ], check=True)

    init_words = [int(x, 16) for x in (MAT / 'init.hex').read_text().split()]
    init_bytes = b''.join(w.to_bytes(16, 'little') for w in init_words)
    a_bytes = init_bytes[0x0000:0x0000 + 2048]
    w_bytes = init_bytes[0x1000:0x1000 + 1024]
    exp = [int(x, 16) for x in (MAT / 'exp_c.txt').read_text().split()]
    assert len(exp) == 1024

    mem = [0] * MAT_WORDS
    # scalar constants
    mem_set(mem, SCALAR_ONE, f32(1.0))
    mem_set(mem, SCALAR_SCALE, f32(SCALE))
    mem_set(mem, SCALAR_HALF, f32(HALF))
    mem_set(mem, SCALAR_DUMMY, f32(1.0))
    # parameter-resident A16 A block and W8 W block (host preload only)
    mem_set_bytes(mem, PARAM_A, a_bytes)
    mem_set_bytes(mem, PARAM_W, w_bytes)

    # queue descriptor (V022 sealed descriptor layout, BACKEND=21)
    q = [0] * 16
    q[0] = 0x51415352
    q[1] = 1 | (21 << 16)
    q[2] = 1                     # cookie
    q[3] = 0xffffffff            # no predecessor
    q[4] = ARENA_A
    q[5] = ARENA_B
    q[6] = ARENA_C
    q[7] = 32                    # m
    q[8] = 32                    # n
    q[9] = 32                    # k
    q[10] = 1                    # epoch
    q[11] = 0 | (1 << 16)        # layer, a_id
    q[12] = 2 | (3 << 16)        # b_id, c_id
    q[13] = 0x3210 | (1 << 16)   # positions=0x3210, clip=1
    q[14] = 0 | (1 << 16)        # target_high=0, allowed=1 (MUL op)
    q[15] = 0                    # c_valid=0, c_completed=0
    for i, v in enumerate(q):
        mem_set(mem, QUEUE_BASE + i * 4, v)

    # layout payloads (32 words, 1024 b)
    def lay(mode, src, dst, total, nb):
        return [0x224C4159, mode, src, dst, total, nb] + [0] * 26
    pay = {}
    pay[0x000] = lay(0, PARAM_A, ARENA_A, 1024, 2)          # A bytes
    pay[0x100] = lay(0, PARAM_W, ARENA_B, 512, 2)           # W bytes
    pay[0x600] = lay(0, ARENA_I16, ARENA_OUT, 1024, 2)      # final I16

    # vector payloads (16 words, 512 b)
    def vec(flags, a, b, c, d, count, period=0):
        return [0x22564543, flags, a, b, c, d, count, period] + [0] * 8
    pay[0x200] = vec(14 | (1 << 13), ARENA_C, SCALAR_DUMMY, 0, ARENA_D0, 1024)
    pay[0x300] = vec(2 | (1 << 10), ARENA_D0, SCALAR_SCALE, 0, ARENA_D1, 1024)
    pay[0x400] = vec(0 | (1 << 10), ARENA_D1, SCALAR_HALF, 0, ARENA_D2, 1024)
    pay[0x500] = vec(15 | (1 << 9), ARENA_D2, 0, 0, ARENA_I16, 1024)
    for off, words in pay.items():
        for i, v in enumerate(words):
            mem_set(mem, PAY + off + i * 4, v)

    # WCPG v2 plan: IN -> LAY(A), LAY(W) -> MAT -> VEC(I48->F32) ->
    # VEC(MUL scale) -> VEC(ADD bias) -> VEC(F32->I16) -> LAY(copy)
    nodes = [
        G.node(G.T_IN, 0, 0, base=PARAM_A, count=512,
               flags=G.FLAG_ROOT | G.FLAG_EXTERNAL, input_tid=0, output_tid=0,
               input_base=PARAM_A, input_bytes=2048,
               output_base=PARAM_A, output_bytes=2048, version=1, epoch=1),
        G.node(G.T_LAY, 1, 1 << 0, base=PAY + 0x000, count=0,
               input_tid=0, output_tid=1, input_base=PARAM_A, input_bytes=2048,
               output_base=ARENA_A, output_bytes=2048, version=1, epoch=2),
        G.node(G.T_LAY, 2, 1 << 0, base=PAY + 0x100, count=0,
               input_tid=0, output_tid=2, input_base=PARAM_W, input_bytes=1024,
               output_base=ARENA_B, output_bytes=1024, version=1, epoch=3),
        G.node(G.T_MAT, 3, (1 << 1) | (1 << 2), base=QUEUE_BASE, count=1,
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
    blob, hw = G.emit(PLAN_BASE, nodes, PARAM_END, generation=0, flags=0xF,
                      input_base=0x08000000, input_limit=0x10000000)
    # write plan bytes as 4-byte words
    for off in range(0, len(blob), 4):
        mem_set(mem, PLAN_BASE + off, int.from_bytes(blob[off:off+4], 'little'))

    # BFM memory image: one 128-bit-padded word per line
    (HERE / 'fixtures' / 'mem_integrated.hex').write_text(
        '\n'.join(f'{w:08x}' for w in mem) + '\n')

    # Baseline-chain memory: the matrix result is preloaded because the sealed
    # matrix baseline is run separately (same fixture, verified C48).
    mem_base = list(mem)
    c48 = b''.join((v & ((1 << 48) - 1)).to_bytes(6, 'little') for v in exp)
    for i in range(0, len(c48), 4):
        chunk = c48[i:i+4] + b'\x00' * (4 - len(c48[i:i+4]))
        mem_base[(0x40000 + 0x2000 + i) // 4] = int.from_bytes(chunk, 'little')
    (HERE / 'fixtures' / 'mem_baseline.hex').write_text(
        '\n'.join(f'{w:08x}' for w in mem_base) + '\n')

    # Negative fixtures: bad matrix queue magic and unsupported vector op19.
    badq = list(mem); badq[(0x40000 + 0xC000) // 4] = 0xdeadbeef
    (HERE / 'fixtures' / 'mem_bad_queue.hex').write_text(
        '\n'.join(f'{w:08x}' for w in badq) + '\n')
    badv = list(mem); badv[(0xC0000 + 0x9200) // 4 + 1] = 0x00000013
    (HERE / 'fixtures' / 'mem_bad_vec.hex').write_text(
        '\n'.join(f'{w:08x}' for w in badv) + '\n')

    # Independent golden: matrix integer -> f32 -> *scale -> +0.5 -> RNE -> i16
    exp_s = [v - (1 << 48) if (v & (1 << 47)) else v for v in exp]
    x = np.array(exp_s, dtype=np.int64).astype(np.float32)
    y = (x * np.float32(SCALE)).astype(np.float32)
    z = (y + np.float32(HALF)).astype(np.float32)
    r = np.rint(z.astype(np.float64)).astype(np.int64)
    r = np.clip(r, -32768, 32767).astype(np.int16)
    gold_words = []
    for i in range(0, 1024, 2):
        gold_words.append((int(r[i]) & 0xffff) | ((int(r[i+1]) & 0xffff) << 16))
    (HERE / 'fixtures' / 'gold_i16.hex').write_text(
        '\n'.join(f'{w:08x}' for w in gold_words) + '\n')

    meta = {
        'plan_base': PLAN_BASE, 'param_end': PARAM_END,
        'plan_bytes': len(blob), 'plan_sha256': __import__('hashlib').sha256(blob).hexdigest(),
        'nodes': len(nodes), 'queue_base': QUEUE_BASE,
        'matrix': {'m': 32, 'n': 32, 'k': 32, 'a': ARENA_A, 'b': ARENA_B, 'c': ARENA_C,
                   'golden': 'ds_matrix eng_c0 independent integer exp_c'},
        'vector': {'i48_to_f32': ARENA_C, 'scale_out': ARENA_D0,
                   'mul_out': ARENA_D1, 'add_out': ARENA_D2, 'i16_out': ARENA_I16,
                   'scale': SCALE, 'bias': HALF},
        'layout_out': ARENA_OUT,
        'golden': 'matrix integer exp_c -> float32 -> *2^-10 -> +0.5 -> RNE -> clip i16',
        'scope': 'integrated logic simulation; not full CASE0000 and not sealed payload re-lowering',
    }
    (HERE / 'fixtures' / 'integrated_meta.json').write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == '__main__':
    main()
