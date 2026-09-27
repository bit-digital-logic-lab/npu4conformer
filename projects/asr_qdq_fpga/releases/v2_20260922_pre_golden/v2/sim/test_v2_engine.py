"""Independent packet-level RTL verification (stdlib only, no numeric backend).

The V1 scalar opcodes supply the bit-exact golden for resident scalar sequences;
Python integer arithmetic is used only to check MAC results, never as a fallback.
"""
from __future__ import annotations

import argparse
import binascii
import json
from pathlib import Path
import random
import struct
import subprocess
import time


class Engine:
    def __init__(self, vvp: str, image: Path):
        self.process = subprocess.Popen([vvp, str(image)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, bufsize=1)
        self.sequence = 0
        self.transactions = 0

    def command(self, op: int, payload: bytes = b"", flags: int = 0,
                expect: int = 0, corrupt: bool = False) -> bytes:
        self.sequence = (self.sequence + 1) & 65535
        header = struct.pack("<HBBH", self.sequence, op, flags, len(payload))
        crc = binascii.crc_hqx(header + payload, 65535)
        frame = b"\xa5\x5a" + header + payload + struct.pack("<H", crc ^ int(corrupt))
        self.process.stdin.write(str(len(frame)) + " " + frame.hex(" ") + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline().strip()
        if not line.startswith("R "):
            raise AssertionError(f"simulation did not reply: {line!r}")
        tokens = line.split()
        response = bytes.fromhex(" ".join(tokens[2:]))
        assert int(tokens[1]) == len(response), line
        assert response[:2] == b"\x5a\xa5", response
        sequence, actual_op, status, length = struct.unpack("<HBBH", response[2:8])
        assert (sequence, actual_op, status, len(response)) == (self.sequence, op, expect, length + 10), response.hex()
        assert binascii.crc_hqx(response[2:-2], 65535) == int.from_bytes(response[-2:], "little")
        self.transactions += 1
        return response[8:-2]

    def write(self, base: int, words: list[int]):
        for first in range(0, len(words), 255):
            chunk = words[first:first + 255]
            self.command(0x41, struct.pack("<HH", base + first, len(chunk)) +
                         struct.pack("<" + "I" * len(chunk), *(w & 0xffffffff for w in chunk)))

    def read(self, base: int, count: int) -> list[int]:
        words = []
        for first in range(0, count, 256):
            length = min(256, count - first)
            raw = self.command(0x42, struct.pack("<HH", base + first, length))
            words.extend(struct.unpack("<" + "I" * length, raw))
        return words

    def scalar(self, op: int, a: int, b: int) -> tuple[int, int]:
        raw = self.command(0x20 + op, struct.pack("<II", a, b))
        return struct.unpack("<IB", raw)

    def vec(self, op: int, mode: int, a: int, b: int, d: int, count: int,
            expect: int = 0) -> bytes:
        return self.command(0x43, struct.pack("<BBHHHH", op, mode, a, b, d, count), expect=expect)

    def mm(self, a: int, b: int, c: int, m: int, n: int, k: int,
           accumulate: int = 0, expect: int = 0) -> bytes:
        return self.command(0x45, struct.pack("<7H", a, b, c, m, n, k, accumulate), expect=expect)

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        errors = self.process.stderr.read()
        assert self.process.returncode == 0, errors

    def abort_by_reset(self, op: int, payload: bytes, clocks: int):
        self.sequence = (self.sequence + 1) & 65535
        header = struct.pack("<HBBH", self.sequence, op, 0, len(payload))
        crc = binascii.crc_hqx(header + payload, 65535)
        frame = b"\xa5\x5a" + header + payload + struct.pack("<H", crc)
        self.process.stdin.write(f"-2 {len(frame)} {clocks} " + frame.hex(" ") + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline().strip()
        assert line == "RESET", line
        self.transactions += 1


def float_bits(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]


def unpack_i48(words: list[int]) -> list[int]:
    result = []
    for i in range(0, len(words), 2):
        raw = words[i] | ((words[i + 1] & 65535) << 32)
        result.append(raw - (1 << 48) if raw & (1 << 47) else raw)
        assert words[i + 1] >> 16 == (65535 if raw & (1 << 47) else 0)
    return result


def run(engine: Engine) -> list[str]:
    tests = []
    rng = random.Random(0xA5160002)
    assert engine.command(0) == b"ASR1\x01\x00\x00\x00"
    assert engine.command(0x40) == b"ASR2" + struct.pack("<II", 2, 32768)
    tests.append("legacy_ping_and_v2_info")

    for base, count in ((0, 512), (1234, 257), (32512, 256), (32767, 1)):
        values = [rng.getrandbits(32) for _ in range(count)]
        engine.write(base, values)
        assert engine.read(base, count) == values
    tests.append("bram_burst_sizes_and_last_word")

    # All malformed commands are sent without the host's normal validation.
    sentinel = [0x1F205040, 0x12345678, 0xABCDEF98, 0xDEADBEEF]
    engine.write(30000, sentinel)
    engine.command(0x41, struct.pack("<HHI", 30000, 2, 0), expect=2)
    engine.command(0x41, struct.pack("<HHI", 30000, 1, 0), expect=1, corrupt=True)
    engine.command(0x41, struct.pack("<HHI", 32768, 1, 0), expect=2)
    engine.command(0x41, struct.pack("<HHI", 30000, 1, 0), flags=1, expect=3)
    for count in (0, 257, 65535):
        engine.command(0x42, struct.pack("<HH", 30000, count), expect=2)
    assert engine.read(30000, 4) == sentinel
    tests.append("write_crc_length_range_flags_are_transactional")

    # Bit-exact comparison against the shared frozen scalar, every internal op.
    a_floats = [0.0, -0.0, 0.25, 1.0, 2.0, 8.0, 1e-6, 100.0]
    b_floats = [1.0, 2.0, 0.75, 3.0, 0.5, 4.0, 2.0, 7.0]
    for op in range(16):
        aa = [float_bits(x) for x in a_floats]
        bb = [float_bits(x) for x in b_floats]
        if op == 6:  # LOG domain must be positive.
            aa = [float_bits(x) for x in (0.5, 0.25, 1, 2, 3, 4, 8, 100)]
        elif op == 5:
            aa = [float_bits(x) for x in (-6, -1, -0.0, 0, 0.125, 1, 3, 10)]
        elif op == 7:
            aa = [0, 1, 0xffffffff, 0x7fffffff, 0x80000000, 32767, 32768, 123456789]
        elif op == 14:
            aa = [0, 1, 0xffffffff, 0x7fffffff, 0x80000000, 32767, 32768, 123456789]
            bb = [0, 0, 65535, 32767, 32768, 0, 65535, 123]
        expected = [engine.scalar(op, a, b) for a, b in zip(aa, bb)]
        engine.write(100, aa)
        engine.write(200, bb)
        reply = engine.vec(op, 0, 100, 200, 300, len(aa))
        flags = 0
        for _, value in expected:
            flags |= value
        assert reply[0] == flags and int.from_bytes(reply[1:], "little") > 0
        assert engine.read(300, len(aa)) == [v for v, _ in expected], op
    tests.append("all_16_resident_scalar_ops_bit_exact_to_frozen_scalar")

    engine.write(100, [float_bits(x) for x in (1, 2, 3, 4)])
    engine.write(200, [float_bits(0.5)])
    engine.vec(2, 2, 100, 200, 100, 4)
    assert engine.read(100, 4) == [float_bits(x) for x in (0.5, 1, 1.5, 2)]
    before = engine.read(100, 4)
    engine.vec(0, 0, 100, 200, 101, 3, expect=2)
    engine.vec(0, 1, 100, 200, 100, 3, expect=2)
    engine.vec(0, 4, 100, 200, 300, 3, expect=3)
    engine.vec(16, 0, 100, 200, 300, 3, expect=3)
    engine.vec(0, 0, 32767, 200, 300, 2, expect=2)
    engine.vec(0, 0, 100, 200, 300, 0, expect=2)
    assert engine.read(100, 4) == before
    tests.append("broadcast_exact_inplace_and_rejected_partial_aliases")

    engine.write(100, [float_bits(1), float_bits(2)])
    engine.write(200, [float_bits(1), 0])
    reply = engine.vec(3, 0, 100, 200, 300, 2, expect=4)
    assert reply[0] & 2
    assert engine.read(300, 1) == [float_bits(1)]
    tests.append("vector_severe_arithmetic_flag_aborts")

    for op in (0, 9):
        for count in (1, 2, 97):
            aa = [float_bits(rng.uniform(-100, 100)) for _ in range(count)]
            gold = aa[0]
            for b in aa[1:]:
                gold, _ = engine.scalar(op, gold, b)
            engine.write(500, aa)
            engine.command(0x44, struct.pack("<BBHHH", op, 0, 500, 500 + count - 1, count))
            assert engine.read(500 + count - 1, 1) == [gold]
    engine.command(0x44, struct.pack("<BBHHH", 1, 0, 500, 900, 1), expect=3)
    engine.command(0x44, struct.pack("<BBHHH", 0, 1, 500, 900, 1), expect=3)
    tests.append("left_fold_reduce_bit_exact_and_overlapping_destination")

    for m, n, k in ((1, 1, 1), (3, 4, 7), (4, 3, 257), (2, 3, 31)):
        aa = [rng.randint(-32768, 32767) for _ in range(m * k)]
        bt = [rng.randint(-32768, 32767) for _ in range(n * k)]
        engine.write(0, aa)
        engine.write(8192, bt)
        gold = [sum(aa[r*k+t] * bt[c*k+t] for t in range(k)) for r in range(m) for c in range(n)]
        engine.mm(0, 8192, 20000, m, n, k)
        assert unpack_i48(engine.read(20000, m*n*2)) == gold
        engine.mm(0, 8192, 20000, m, n, k, 1)
        assert unpack_i48(engine.read(20000, m*n*2)) == [2*x for x in gold]
    tests.append("random_signed16_matrix_and_cross_k_signed48_accumulation")

    # Full-length overflow-resistant validation (16-bit products must not wrap).
    for dims in ((65535, 65535, 65535), (32768, 32768, 2), (1, 1, 0)):
        engine.mm(0, 8192, 20000, *dims, expect=2)
    engine.mm(0, 10, 0, 1, 1, 1, expect=2)
    engine.mm(0, 10, 20000, 1, 1, 1, 2, expect=3)
    engine.write(0, [32767])
    engine.write(10, [32767])
    engine.write(20000, [0xffffffff, 0x7fff])
    reply = engine.mm(0, 10, 20000, 1, 1, 1, 1, expect=4)
    assert reply[0] & 4
    engine.write(0, [0xffff])
    engine.write(10, [1])
    engine.write(20000, [0, 0xffff8000])
    reply = engine.mm(0, 10, 20000, 1, 1, 1, 1, expect=4)
    assert reply[0] & 4
    tests.append("matrix_wide_dimensions_overlap_and_signed48_overflow")

    engine.write(1000, [float_bits(0.25)] * 128)
    engine.write(2000, [0] * 128)
    engine.write(32000, sentinel)
    engine.abort_by_reset(0x43, struct.pack("<BBHHHH", 5, 0, 1000, 2000, 3000, 128), 100)
    assert engine.command(0) == b"ASR1\x01\x00\x00\x00"
    assert engine.read(32000, 4) == sentinel  # RAM contents survive reset.
    assert engine.scalar(0, float_bits(1), float_bits(2))[0] == float_bits(3)
    engine.write(0, [3, 4] * 64)
    engine.write(8192, [5, 6] * 64)
    engine.abort_by_reset(0x45, struct.pack("<7H", 0, 8192, 20000, 1, 1, 128, 0), 100)
    engine.mm(0, 8192, 20000, 1, 1, 2)
    assert unpack_i48(engine.read(20000, 2)) == [39]
    tests.append("reset_interrupts_vector_and_matrix_then_recovers_without_clearing_bram")
    return tests


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vvp", default=r"D:\app\iverilog\iverilog\bin\vvp.exe")
    parser.add_argument("--image", type=Path, default=Path(__file__).with_name("tb_asr_stdio_v2.vvp"))
    parser.add_argument("--report", type=Path, default=Path(__file__).with_name("independent_rtl_report.json"))
    args = parser.parse_args()
    engine = Engine(args.vvp, args.image)
    started = time.perf_counter()
    try:
        tests = run(engine)
    finally:
        engine.close()
    report = {"backend": "synthesizable_rtl_simulation", "physical_fpga_executed": False,
              "passed": True, "tests": tests, "transactions": engine.transactions,
              "seconds": time.perf_counter() - started}
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
