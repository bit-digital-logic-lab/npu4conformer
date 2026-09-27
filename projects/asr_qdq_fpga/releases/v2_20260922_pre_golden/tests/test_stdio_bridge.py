"""Check Windows vvp stdin/stdout transport, including persistent requests.

Usage: python -B tests/test_stdio_bridge.py <vvp.exe> <compiled-bridge.vvp>
"""
from __future__ import annotations

import binascii
from pathlib import Path
import subprocess
import sys


def request(sequence: int, opcode: int, payload: bytes = b"", flags: int = 0) -> bytes:
    body = sequence.to_bytes(2, "little") + bytes((opcode, flags)) + len(payload).to_bytes(2, "little") + payload
    return b"\xa5\x5a" + body + binascii.crc_hqx(body, 0xFFFF).to_bytes(2, "little")


def line(packet: bytes) -> str:
    return str(len(packet)) + " " + packet.hex(" ") + "\n"


def decode(text: str) -> bytes:
    fields = text.strip().split()
    assert fields[0] == "R", text
    assert len(fields) == int(fields[1]) + 2, text
    raw = bytes.fromhex(" ".join(fields[2:]))
    assert raw[:2] == b"\x5a\xa5", raw
    assert int.from_bytes(raw[6:8], "little") == len(raw) - 10, raw
    assert binascii.crc_hqx(raw[2:-2], 0xFFFF) == int.from_bytes(raw[-2:], "little"), raw
    return raw


def main() -> None:
    vvp, bridge = map(str, map(Path, sys.argv[1:]))
    commands = [
        request(7, 0),
        request(8, 1, (123).to_bytes(6, "little", signed=True)),
        request(9, 2, (-17).to_bytes(2, "little", signed=True) + (31).to_bytes(2, "little", signed=True)),
        request(10, 3),
        request(11, 5, b"\x01\x00\x01\x00" * 256, flags=1),
        request(12, 3),
    ]
    result = subprocess.run([vvp, bridge], input="".join(map(line, commands)), capture_output=True, text=True, timeout=20, check=True)
    replies = [decode(item) for item in result.stdout.splitlines() if item.startswith("R ")]
    assert len(replies) == len(commands), result.stdout
    for sequence, reply in zip(range(7, 7 + len(commands)), replies):
        assert int.from_bytes(reply[2:4], "little") == sequence
        assert reply[5] == 0
    assert replies[0][8:-2] == b"ASR1\x01\x00\x00\x00"
    assert int.from_bytes(replies[3][8:-2], "little", signed=True) == -404
    assert int.from_bytes(replies[5][8:-2], "little", signed=True) == 256

    # readline while stdin remains open proves output really is flushed per
    # request; merely testing communicate would allow EOF-buffered output.
    process = subprocess.Popen([vvp, bridge], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    try:
        for packet in commands:
            process.stdin.write(line(packet))
            process.stdin.flush()
            reply = decode(process.stdout.readline())
            assert reply[2:4] == packet[2:4]
        process.stdin.close()
        assert process.wait(timeout=20) == 0
        assert process.stderr.read() == ""
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
    print("PASS stdio bridge: Windows communicate and persistent write/flush/readline, CRC, retained accumulator, 1034-byte frame")


if __name__ == "__main__":
    main()
