#!/usr/bin/env python3
"""Place the compiled 68-node serial superplan into a control-test image.

The SEQ engine is a stub in this test; subplan pointers are not fetched.  The
header's param_end is widened to 0x40000000 so the original immutable program
addresses (about 0x19d6xxxx) pass the controller's parameter-window check.
This is control evidence for the real compiled 68-node plan, not arithmetic.
"""
import hashlib, json, struct
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FIX = HERE / 'tests/fixtures'
SEED = 0x811c9dc5
MAGIC_H = 0x5743504c


def fnv(h, w):
    return ((h ^ (w & 0xffffffff)) * 0x01000193) & 0xffffffff


def main():
    blob = bytearray((HERE / 'analysis/whole68_serial.bin').read_bytes())
    w = list(struct.unpack_from('<16I', blob, 0))
    w[4] = 0x40000000          # param_end for the control fixture
    w[6] = 0                   # ignore runtime generation in this control test
    h = SEED
    for j, v in enumerate(w):
        if j != 7:
            h = fnv(h, v)
    for i in range(w[2]):
        nd = list(struct.unpack_from('<16I', blob, 64 + 64 * i))
        for v in nd:
            h = fnv(h, v)
    w[7] = h
    struct.pack_into('<16I', blob, 0, *w)
    # Load 32-bit words into the BFM parameter window.
    mem = bytearray(0x100000)
    for i, line in enumerate((FIX / 'mem_init.hex').read_text().splitlines()):
        struct.pack_into('<I', mem, i * 4, int(line, 16))
    off = 0xc0000 + 0x30000
    mem[off:off + len(blob)] = blob
    (FIX / 'mem68.hex').write_text('\n'.join('%08x' % struct.unpack_from('<I', mem, i)[0]
                                             for i in range(0, len(mem), 4)) + '\n')
    # Before-style: 68 independent one-node superplans, each with one START.
    base = 0x10030000
    for k in range(68):
        hw = [MAGIC_H, 0x00010001, 1, 3, 0x40000000, 128, 0, 0] + [0] * 8
        hn = [0x57434e44, 4, 0, 0, 0, 0, 0, 0x10020800, 2, 0, 0, 0, 0, k + 1, 0, 0]
        h = SEED
        for j, v in enumerate(hw):
            if j != 7:
                h = fnv(h, v)
        for v in hn:
            h = fnv(h, v)
        hw[7] = h
        blob2 = struct.pack('<16I', *hw) + struct.pack('<16I', *hn)
        off2 = 0xc0000 + (base + k * 128) - 0x10000000
        mem[off2:off2 + len(blob2)] = blob2
    (FIX / 'mem68_before.hex').write_text('\n'.join('%08x' % struct.unpack_from('<I', mem, i)[0]
                                                      for i in range(0, len(mem), 4)) + '\n')
    (FIX / 'whole68_ctrl.json').write_text(json.dumps(dict(
        load_address='0x10030000', param_end='0x40000000', node_count=w[2],
        bytes=len(blob), sha256=hashlib.sha256(blob).hexdigest(),
        original_sha256=hashlib.sha256((HERE / 'analysis/whole68_serial.bin').read_bytes()).hexdigest(),
        scope='control fixture only; SEQ stub; no subplan fetch/arithmetic'), indent=2) + '\n')
    print('WC_CTRL68_FIXTURE', w[2], hex(h), len(blob))


if __name__ == '__main__':
    main()
