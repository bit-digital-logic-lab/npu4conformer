#!/usr/bin/env python3
"""Build the sparse BFM image and the real-chain golden."""
import json
import struct
from pathlib import Path
import numpy as np

TASK = Path(__file__).resolve().parents[1]
A = TASK / 'analysis'
FIX = TASK / 'tests' / 'fixtures'
FIX.mkdir(parents=True, exist_ok=True)

PARAM_OFF = 0xC0000
ARENA_OFF = 0x40000
EXT_OFF = 0x80000
MEM = bytearray(0x100000)


def put_param(addr, data):
    off = PARAM_OFF + (addr - 0x10000000)
    if off < PARAM_OFF or off + len(data) > len(MEM):
        raise ValueError('param fixture overflow %x' % addr)
    MEM[off:off + len(data)] = data


def put_ext(addr, data):
    off = EXT_OFF + (addr - 0x08000000)
    if off < EXT_OFF or off + len(data) > PARAM_OFF:
        raise ValueError('external fixture overflow %x' % addr)
    MEM[off:off + len(data)] = data


def main():
    # Scalars for the real ADD/MUL descriptors.
    put_param(0x10000000, struct.pack('<f', 1.0))
    put_param(0x10000004, struct.pack('<f', 2.0))

    # Small real plan + payloads.
    put_param(0x10008000, (A / 'small_real.bin').read_bytes())
    pay = (A / 'small_real_payloads.bin').read_bytes()
    put_param(0x10009000, pay[PARAM_OFF + 0x9000:PARAM_OFF + 0x9300])

    # 68/591 control plans.
    put_param(0x10010000, (A / 'whole68_global.bin').read_bytes())
    put_param(0x10020000, (A / 'ledger591.bin').read_bytes())

    # Negative plans.
    for name, addr in [('bad_root', 0x1000A000), ('no_output', 0x1000B000),
                       ('bad_hash', 0x1000C000), ('forward_dep', 0x1000D000)]:
        put_param(addr, (A / (name + '.bin')).read_bytes())

    # Real-chain input: float32 0..63 and golden (x+1)*2.
    x = np.arange(64, dtype=np.float32)
    put_param(0x10001000, x.tobytes())
    gold = ((x + np.float32(1.0)) * np.float32(2.0)).astype('<f4')
    (FIX / 'gold_small.hex').write_text(
        '\n'.join('%08x' % v for v in np.frombuffer(gold.tobytes(), dtype='<u4')) + '\n')

    with (FIX / 'mem_graph.hex').open('w') as f:
        for i in range(0, len(MEM), 4):
            f.write('%08x\n' % struct.unpack_from('<I', MEM, i)[0])

    meta = dict(mem_bytes=len(MEM),
                mem_sha256=__import__('hashlib').sha256(MEM).hexdigest(),
                plans=dict(small=0x10008000, whole68=0x10010000, ledger591=0x10020000,
                           bad_root=0x1000A000, no_output=0x1000B000,
                           bad_hash=0x1000C000, forward_dep=0x1000D000),
                input=0x10001000, input_words=64,
                scalars=dict(one=0x10000000, two=0x10000004),
                gold_words=64,
                gold_sha256=__import__('hashlib').sha256(
                    (FIX / 'gold_small.hex').read_bytes()).hexdigest())
    (FIX / 'fixtures.json').write_text(json.dumps(meta, indent=2) + '\n')
    print(json.dumps(meta, indent=2))


if __name__ == '__main__':
    main()
