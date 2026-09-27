"""Stop-and-wait UART backend. Every dynamic neural arithmetic operation is RTL.

No connection is opened on import. Windows uses the system serial API; pyserial
is an optional alternative on other operating systems. There are no automatic
retries of stateful commands and no numerical CPU fallback.
"""
from __future__ import annotations
import ctypes
import os
import struct
import time
from collections import Counter
import numpy as np

MAX_PAYLOAD = 1024
SCALAR = {"Add": 0, "Sub": 1, "Mul": 2, "Div": 3, "Sqrt": 4,
          "Exp": 5, "Log": 6, "I32": 7, "ToI32": 8, "Max": 9,
          "Less": 10, "Equal": 11, "Abs": 12, "Neg": 13,
          "I48": 14, "ToI16": 15}

def crc16(data: bytes) -> int:
    crc = 0xffff
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ (0x1021 if crc & 0x8000 else 0)) & 0xffff
    return crc

def encode_frame(seq: int, opcode: int, flags: int, payload: bytes,
                 magic: bytes = b"\xa5\x5a") -> bytes:
    if len(payload) > MAX_PAYLOAD:
        raise ValueError("payload exceeds hardware packet RAM")
    body = struct.pack("<HBBH", seq & 0xffff, opcode, flags, len(payload)) + payload
    return magic + body + struct.pack("<H", crc16(body))

class ProtocolError(RuntimeError):
    pass

class WindowsSerial:
    """Minimal binary 8N1 serial port; does not toggle DTR to reset a board."""
    def __init__(self, port: str, baud: int, timeout: float = 5.0):
        if os.name != "nt":
            raise OSError("WindowsSerial requires Windows")
        from ctypes import wintypes as w
        class DCB(ctypes.Structure):
            _fields_ = [("length", w.DWORD), ("baud", w.DWORD), ("flags", w.DWORD),
                        ("reserved", w.WORD), ("xonlim", w.WORD), ("xofflim", w.WORD),
                        ("bytesize", w.BYTE), ("parity", w.BYTE), ("stopbits", w.BYTE),
                        ("xon", ctypes.c_char), ("xoff", ctypes.c_char),
                        ("error", ctypes.c_char), ("eof", ctypes.c_char),
                        ("event", ctypes.c_char), ("reserved1", w.WORD)]
        class Timeouts(ctypes.Structure):
            _fields_ = [(name, w.DWORD) for name in
                        ("interval", "read_mult", "read_const", "write_mult", "write_const")]
        self.api = ctypes.WinDLL("kernel32", use_last_error=True)
        self.api.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p,
                                         w.DWORD, w.DWORD, w.HANDLE]
        self.api.CreateFileW.restype = w.HANDLE
        for name in ("CloseHandle", "PurgeComm"):
            getattr(self.api, name).restype = w.BOOL
        self.api.CloseHandle.argtypes = [w.HANDLE]
        self.api.PurgeComm.argtypes = [w.HANDLE, w.DWORD]
        self.api.GetCommState.argtypes = [w.HANDLE, ctypes.POINTER(DCB)]
        self.api.SetCommState.argtypes = [w.HANDLE, ctypes.POINTER(DCB)]
        self.api.SetCommTimeouts.argtypes = [w.HANDLE, ctypes.POINTER(Timeouts)]
        for name in ("ReadFile", "WriteFile"):
            getattr(self.api, name).argtypes = [w.HANDLE, ctypes.c_void_p, w.DWORD,
                                               ctypes.POINTER(w.DWORD), ctypes.c_void_p]
            getattr(self.api, name).restype = w.BOOL
        self.handle = self.api.CreateFileW("\\\\.\\" + port, 0xc0000000, 0, None, 3, 0, None)
        if self.handle == ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        self.timeout = timeout
        try:
            dcb = DCB(); dcb.length = ctypes.sizeof(DCB)
            self._check(self.api.GetCommState(self.handle, ctypes.byref(dcb)))
            dcb.baud, dcb.bytesize, dcb.parity, dcb.stopbits = baud, 8, 0, 0
            dcb.flags = 1  # binary; no software/hardware flow control, DTR/RTS disabled
            self._check(self.api.SetCommState(self.handle, ctypes.byref(dcb)))
            timings = Timeouts(50, 0, 100, 0, max(1000, int(timeout * 1000)))
            self._check(self.api.SetCommTimeouts(self.handle, ctypes.byref(timings)))
            self._check(self.api.PurgeComm(self.handle, 0x0f))
        except BaseException:
            self.close(); raise

    @staticmethod
    def _check(ok):
        if not ok:
            raise ctypes.WinError(ctypes.get_last_error())

    def write(self, data: bytes):
        from ctypes import wintypes as w
        done = w.DWORD()
        buf = ctypes.create_string_buffer(data)
        self._check(self.api.WriteFile(self.handle, buf, len(data), ctypes.byref(done), None))
        if done.value != len(data):
            raise ProtocolError("partial write; restart job explicitly, do not retry MAC packet")
        return done.value

    def read(self, size: int) -> bytes:
        from ctypes import wintypes as w
        done = w.DWORD(); buf = ctypes.create_string_buffer(size)
        self._check(self.api.ReadFile(self.handle, buf, size, ctypes.byref(done), None))
        return buf.raw[:done.value]

    def close(self):
        if getattr(self, "handle", None) is not None:
            self.api.CloseHandle(self.handle); self.handle = None

class Link:
    def __init__(self, stream, timeout=5.0):
        self.stream, self.timeout, self.sequence = stream, timeout, 0
        self.commands = Counter()
        self.bytes_sent = self.bytes_received = 0

    def _read_exact(self, count, deadline):
        chunks = bytearray()
        while len(chunks) < count:
            if time.monotonic() > deadline:
                raise TimeoutError("UART response timeout; accumulator state is uncertain; restart job")
            part = self.stream.read(count-len(chunks))
            chunks.extend(part)
        self.bytes_received += len(chunks)
        return bytes(chunks)

    def request(self, opcode, payload=b"", flags=0, allow_arithmetic=False):
        seq = self.sequence; self.sequence = (seq+1) & 0xffff
        frame = encode_frame(seq, opcode, flags, payload)
        written = self.stream.write(frame)
        if written is not None and written != len(frame):
            raise ProtocolError("incomplete packet write; not retried")
        self.bytes_sent += len(frame)
        deadline = time.monotonic()+self.timeout
        magic = self._read_exact(2, deadline)
        if magic != b"\x5a\xa5":
            raise ProtocolError("reply sync mismatch; restart link explicitly")
        header = self._read_exact(6, deadline)
        rseq, rop, status, size = struct.unpack("<HBBH", header)
        if size > MAX_PAYLOAD:
            raise ProtocolError("invalid reply length")
        data = self._read_exact(size, deadline)
        check = struct.unpack("<H", self._read_exact(2, deadline))[0]
        if crc16(header+data) != check:
            raise ProtocolError("response CRC mismatch; stateful operation is not retried")
        if (rseq, rop) != (seq, opcode):
            raise ProtocolError("response sequence/opcode mismatch")
        self.commands[opcode] += 1
        if status and not (allow_arithmetic and status == 4):
            raise ProtocolError(f"hardware returned status={status} opcode=0x{opcode:02x}")
        return data

    def ping(self):
        result = self.request(0)
        if result != b"ASR1\x01\x00\x00\x00":
            raise ProtocolError(f"unexpected RTL protocol version: {result!r}")
        return result

def open_link(port, baud=115200, timeout=5.0):
    if os.name == "nt":
        stream = WindowsSerial(port, baud, timeout)
    else:
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError("non-Windows serial access requires pyserial") from exc
        stream = serial.Serial(port, baud, timeout=0.1, write_timeout=timeout)
    link = Link(stream, timeout)
    try:
        link.ping()
    except BaseException:
        stream.close(); raise
    return link

class SerialBackend:
    name = "hardware"
    hardware_executed = True

    def __init__(self, link):
        self.link = link
        self.arithmetic_flags = Counter()

    def _bits(self, op, a=0, b=0):
        data = self.link.request(0x20+op, struct.pack("<II", a & 0xffffffff, b & 0xffffffff))
        if len(data) != 5:
            raise ProtocolError("scalar reply length mismatch")
        bits, flags = struct.unpack("<IB", data)
        self.arithmetic_flags[flags] += 1
        if flags & 7:
            raise ArithmeticError(f"FPGA scalar op={op} flags=0x{flags:02x}")
        return bits

    def binary(self, op, a, b):
        if op not in ("Add", "Sub", "Mul", "Div", "Max", "Less", "Equal"):
            raise NotImplementedError(f"hardware binary: {op}")
        aa, bb = np.broadcast_arrays(np.asarray(a, np.float32), np.asarray(b, np.float32))
        av = np.ascontiguousarray(aa).view(np.uint32).reshape(-1)
        bv = np.ascontiguousarray(bb).view(np.uint32).reshape(-1)
        out = np.empty(av.size, dtype=np.uint32)
        for i, (x, y) in enumerate(zip(av, bv)):
            value = self._bits(SCALAR[op], int(x), int(y))
            if op in ("Less", "Equal"):
                value = 0x3f800000 if value else 0
            out[i] = value
        return out.view(np.float32).reshape(aa.shape)

    def unary(self, op, a):
        a = np.asarray(a, np.float32)
        if op == "Relu":
            return self.binary("Max", a, np.float32(0))
        if op == "Sigmoid":
            # Stable sigmoid: exp(-abs(x)) cannot overflow. Sign inspection only
            # selects branches; all addition/multiplication/division remains RTL.
            exp = self.unary("Exp", self.unary("Neg", self.unary("Abs", a)))
            denom = self.binary("Add", exp, np.float32(1))
            positive = self.binary("Div", np.float32(1), denom)
            negative = self.binary("Div", exp, denom)
            return np.where((a.view(np.uint32) & 0x80000000) != 0, negative, positive)
        if op not in ("Sqrt", "Exp", "Log", "Abs", "Neg"):
            raise NotImplementedError(f"hardware unary: {op}")
        words = np.ascontiguousarray(a).view(np.uint32).reshape(-1)
        out = np.empty(words.size, np.uint32)
        for i, value in enumerate(words):
            out[i] = self._bits(SCALAR[op], int(value))
        return out.view(np.float32).reshape(a.shape)

    def int48_to_float(self, values):
        values = np.asarray(values, np.int64)
        out = np.empty(values.size, np.uint32)
        for i, raw in enumerate(values.reshape(-1)):
            value = int(raw)
            if not -(1 << 47) <= value < (1 << 47):
                raise OverflowError("outside signed48 accumulator range")
            out[i] = self._bits(SCALAR["I48"], value & 0xffffffff, (value >> 32) & 0xffff)
        return out.view(np.float32).reshape(values.shape)

    def quantize(self, x, scale):
        divided = self.binary("Div", x, scale)
        words = np.ascontiguousarray(divided).view(np.uint32).reshape(-1)
        output = np.empty(words.size, np.uint16)
        for i, value in enumerate(words):
            output[i] = self._bits(SCALAR["ToI16"], int(value)) & 0xffff
        return output.view(np.int16).reshape(divided.shape)

    def dequantize(self, q, scale):
        q = np.asarray(q)
        if q.dtype != np.int16:
            raise TypeError("only original signed INT16 QDQ is supported")
        f = self.int48_to_float(q.astype(np.int64))
        return self.binary("Mul", f, scale)

    def dot_i16(self, a, b):
        a, b = np.asarray(a), np.asarray(b)
        if a.dtype != np.int16 or b.dtype != np.int16 or a.shape != b.shape or a.ndim != 1:
            raise ValueError("dot_i16 requires equal one-dimensional int16 vectors")
        if not a.size:
            self.link.request(1, (0).to_bytes(6, "little", signed=True))
            return 0
        result = 0
        for start in range(0, a.size, MAX_PAYLOAD//4):
            stop = min(start+MAX_PAYLOAD//4, a.size)
            pairs = np.empty((stop-start, 2), dtype="<i2")
            pairs[:, 0], pairs[:, 1] = a[start:stop], b[start:stop]
            reply = self.link.request(5, pairs.tobytes(), flags=int(start == 0))
            if len(reply) != 6:
                raise ProtocolError("dot reply length mismatch")
            result = int.from_bytes(reply, "little", signed=True)
        return result

    def _reduce(self, x, axes, keepdims, op):
        x = np.asarray(x, np.float32)
        if axes is None:
            axes = tuple(range(x.ndim))
        elif isinstance(axes, int):
            axes = (axes,)
        if any(not -x.ndim <= axis < x.ndim for axis in axes):
            raise ValueError("reduction axis out of range")
        axes = tuple(sorted({axis % x.ndim for axis in axes})) if x.ndim else ()
        if not axes:
            return x.copy()
        rest = tuple(i for i in range(x.ndim) if i not in axes)
        permuted = np.transpose(x, rest+axes)
        outer = tuple(x.shape[i] for i in rest)
        count = int(np.prod([x.shape[i] for i in axes]))
        if count == 0:
            if op == "Max":
                raise ValueError("empty max reduction")
            result = np.zeros(outer, np.float32)
        else:
            rows = permuted.reshape((int(np.prod(outer, dtype=np.int64)), count))
            result = np.empty(rows.shape[0], np.float32)
            for i, row in enumerate(rows):
                value = row[0]
                for element in row[1:]:
                    value = self.binary(op, value, element).reshape(())[()]
                result[i] = value
            result = result.reshape(outer)
        if keepdims:
            result = result.reshape(tuple(1 if i in axes else x.shape[i] for i in range(x.ndim)))
        return result

    def reduce_sum(self, x, axes=None, keepdims=False):
        return self._reduce(x, axes, keepdims, "Add")

    def reduce_max(self, x, axes=None, keepdims=False):
        return self._reduce(x, axes, keepdims, "Max")

    def report(self):
        return {"backend": self.name, "hardware_executed": bool(self.hardware_executed),
                "commands": dict(self.link.commands), "bytes_sent": self.link.bytes_sent,
                "bytes_received": self.link.bytes_received,
                "scalar_flag_counts": dict(self.arithmetic_flags)}

    def close(self):
        self.link.stream.close()

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()
    link = open_link(args.port, args.baud, args.timeout)
    try:
        print("ASR1 hardware protocol version 1 responded successfully")
    finally:
        link.stream.close()

if __name__ == "__main__":
    main()
