"""V2 resident-buffer transport. All dynamic numeric operations execute in RTL.

NumPy is used for storage, broadcasting, indexing and bit packing only. Signed
48-bit partial sums remain in board RAM between K tiles. A failure aborts the
operation: no stateful command is retried and there is no CPU numeric fallback.
"""
from __future__ import annotations
from collections import Counter
import struct
import time
import numpy as np
from host.transport import SerialBackend, ProtocolError, SCALAR

MEMORY_WORDS = 32768
VECTOR_CHUNK = 8192


def tile_shape(m, n, k):
    """Fixed deterministic maximum tile, occupying <=113152 bytes."""
    if min(m, n, k) < 1:
        raise ValueError("matrix dimensions must be positive")
    return min(31, m), min(64, n), min(256, k)


def float_words(values):
    return np.ascontiguousarray(np.asarray(values, np.float32)).view(np.uint32).reshape(-1)


class BufferedBackend(SerialBackend):
    name = "hardware-v2"
    hardware_executed = True
    hardware_matmul_i16 = True
    resident_operators = True

    def __init__(self, link):
        super().__init__(link)
        self.execution_cycles = Counter()
        self.execution_calls = Counter()
        self.started = time.perf_counter()
        try:
            reply = self.link.request(0x40)
            if len(reply) != 12 or reply[:4] != b"ASR2":
                raise ProtocolError(f"expected ASR2 INFO, got {reply!r}")
            self.version, self.memory_words = struct.unpack("<II", reply[4:])
            if (self.version, self.memory_words) != (2, MEMORY_WORDS):
                raise ProtocolError("unsupported V2 version or SRAM capacity")
        except BaseException:
            self.link.stream.close()
            raise

    def _range(self, base, count):
        if not isinstance(base, (int, np.integer)) or not isinstance(count, (int, np.integer)):
            raise TypeError("SRAM address/count must be integers")
        if base < 0 or count < 0 or base + count > self.memory_words:
            raise ValueError("SRAM range out of bounds")

    def write_words(self, base, values):
        words = np.asarray(values, dtype="<u4").reshape(-1)
        self._range(base, words.size)
        for start in range(0, words.size, 255):
            chunk = words[start:start + 255]
            reply = self.link.request(0x41, struct.pack("<HH", base + start, chunk.size) + chunk.tobytes())
            if reply:
                raise ProtocolError("WRITE reply must be empty")

    def read_words(self, base, count):
        self._range(base, count)
        words = np.empty(count, np.uint32)
        for start in range(0, count, 256):
            size = min(256, count - start)
            reply = self.link.request(0x42, struct.pack("<HH", base + start, size))
            if len(reply) != size * 4:
                raise ProtocolError("READ reply length mismatch")
            words[start:start + size] = np.frombuffer(reply, dtype="<u4")
        return words

    def _execution(self, opcode, payload):
        reply = self.link.request(opcode, payload)
        if len(reply) != 5:
            raise ProtocolError("V2 execution reply length mismatch")
        flags, cycles = struct.unpack("<BI", reply)
        self.arithmetic_flags[flags] += 1
        self.execution_cycles[opcode] += cycles
        self.execution_calls[opcode] += 1
        if flags & 7:
            raise ArithmeticError(f"V2 opcode=0x{opcode:02x} flags=0x{flags:02x}; destination invalid")
        return flags, cycles

    def vec(self, op, a, b, dest, count, mode=0):
        op = SCALAR[op] if isinstance(op, str) else op
        if op not in range(16) or mode not in range(4) or count < 1:
            raise ValueError("invalid VEC op/mode/count")
        self._range(a, 1 if mode & 1 else count)
        self._range(b, 1 if mode & 2 else count)
        self._range(dest, count)
        for source, broadcast in ((a, mode & 1), (b, mode & 2)):
            extent = 1 if broadcast else count
            if dest < source + extent and source < dest + count:
                if broadcast or dest != source:
                    raise ValueError("VEC partial/broadcast destination alias is forbidden")
        return self._execution(0x43, struct.pack("<BBHHHH", op, mode, a, b, dest, count))

    def reduce_words(self, op, a, dest, count):
        op = SCALAR[op] if isinstance(op, str) else op
        if op not in (0, 9) or count < 1:
            raise ValueError("REDUCE supports Add/Max with nonempty input")
        self._range(a, count)
        self._range(dest, 1)
        return self._execution(0x44, struct.pack("<BBHHH", op, 0, a, dest, count))

    def mm_tile(self, a, bt, c, m, n, k, accumulate=False):
        if min(m, n, k) < 1 or accumulate not in (False, True, 0, 1):
            raise ValueError("invalid MM_TILE dimensions or accumulate")
        for base, count in ((a, m*k), (bt, n*k), (c, 2*m*n)):
            self._range(base, count)
        for source, extent in ((a, m*k), (bt, n*k)):
            if c < source + extent and source < c + 2*m*n:
                raise ValueError("MM_TILE output overlaps input")
        return self._execution(0x45, struct.pack("<7H", a, bt, c, m, n, k, int(accumulate)))

    def _vector(self, op, a, b):
        aa, bb = np.broadcast_arrays(np.asarray(a, np.float32), np.asarray(b, np.float32))
        av, bv = float_words(aa), float_words(bb)
        scalar_a, scalar_b = np.size(a) == 1, np.size(b) == 1
        output = np.empty(av.size, np.uint32)
        for start in range(0, av.size, VECTOR_CHUNK):
            count = min(VECTOR_CHUNK, av.size - start)
            # Separate destination when A is broadcast; otherwise exact A alias.
            abase, bbase = 0, count
            dest = 2*count if scalar_a else abase
            self.write_words(abase, av[start:start + (1 if scalar_a else count)])
            self.write_words(bbase, bv[start:start + (1 if scalar_b else count)])
            self.vec(op, abase, bbase, dest, count, int(scalar_a) | (int(scalar_b) << 1))
            output[start:start + count] = self.read_words(dest, count)
        return output.reshape(aa.shape)

    def binary(self, op, a, b):
        if op not in ("Add", "Sub", "Mul", "Div", "Max", "Less", "Equal"):
            raise NotImplementedError(f"V2 binary {op}")
        words = self._vector(op, a, b)
        if op in ("Less", "Equal"):
            # Integer predicate -> canonical floating boolean is representation.
            words = np.where(words != 0, np.uint32(0x3f800000), np.uint32(0))
        return words.view(np.float32)

    def unary(self, op, a):
        if op == "Sigmoid":
            return self.sigmoid(a)
        if op == "Relu":
            return super().unary(op, a)
        if op not in ("Sqrt", "Exp", "Log", "Abs", "Neg"):
            raise NotImplementedError(f"V2 unary {op}")
        return self._vector(op, a, np.float32(0)).view(np.float32)

    def sigmoid(self, x):
        """Stable V1 sigmoid; both branches computed on board, sign selects only."""
        x = np.asarray(x, np.float32)
        words = float_words(x)
        output = np.empty(words.size, np.uint32)
        for start in range(0, words.size, VECTOR_CHUNK):
            count = min(VECTOR_CHUNK, words.size - start)
            one, zero = 3*count, 3*count + 1
            self.write_words(0, words[start:start + count])
            self.write_words(one, [0x3f800000, 0])
            for op in ("Abs", "Neg", "Exp"):
                self.vec(op, 0, zero, 0, count, 2)
            self.vec("Add", 0, one, count, count, 2)
            self.vec("Div", one, count, 2*count, count, 1)
            self.vec("Div", 0, count, 0, count)
            positive, negative = self.read_words(2*count, count), self.read_words(0, count)
            output[start:start + count] = np.where(words[start:start + count] & 0x80000000, negative, positive)
        return output.view(np.float32).reshape(x.shape)

    def int48_to_float(self, values):
        values = np.asarray(values, np.int64)
        if np.any(values < -(1 << 47)) or np.any(values >= (1 << 47)):
            raise OverflowError("outside signed48 accumulator range")
        raw = values.reshape(-1)
        output = np.empty(raw.size, np.uint32)
        for start in range(0, raw.size, VECTOR_CHUNK):
            chunk = raw[start:start + VECTOR_CHUNK]
            count = chunk.size
            self.write_words(0, (chunk & 0xffffffff).astype(np.uint32))
            self.write_words(count, ((chunk >> 32) & 0xffff).astype(np.uint32))
            self.vec("I48", 0, count, 0, count)
            output[start:start + count] = self.read_words(0, count)
        return output.view(np.float32).reshape(values.shape)

    @staticmethod
    def _scale(scale):
        scale = np.asarray(scale, np.float32)
        if np.any(scale <= 0) or not np.all(np.isfinite(scale)):
            raise ValueError("quantization scale must be finite and positive")
        return scale

    def quantize(self, x, scale):
        scale = self._scale(scale)
        aa, ss = np.broadcast_arrays(np.asarray(x, np.float32), scale)
        av, sv, scalar = float_words(aa), float_words(ss), scale.size == 1
        output = np.empty(av.size, np.uint16)
        for start in range(0, av.size, VECTOR_CHUNK):
            count = min(VECTOR_CHUNK, av.size - start)
            self.write_words(0, av[start:start + count])
            self.write_words(count, sv[start:start + (1 if scalar else count)])
            self.vec("Div", 0, count, 0, count, 2 if scalar else 0)
            self.vec("ToI16", 0, count, 0, count, 2 if scalar else 0)
            output[start:start + count] = self.read_words(0, count).astype(np.uint16)
        return output.view(np.int16).reshape(aa.shape)

    def dequantize(self, q, scale):
        q, scale = np.asarray(q), self._scale(scale)
        if q.dtype != np.int16:
            raise TypeError("only original signed INT16 QDQ is supported")
        qq, ss = np.broadcast_arrays(q, scale)
        raw = np.ascontiguousarray(qq).reshape(-1).astype(np.int32)
        sv, scalar = float_words(ss), scale.size == 1
        output = np.empty(raw.size, np.uint32)
        for start in range(0, raw.size, VECTOR_CHUNK):
            chunk = raw[start:start + VECTOR_CHUNK]
            count = chunk.size
            self.write_words(0, chunk.view(np.uint32))
            # I32 is exact for signed16, saving the high-word buffer upload.
            self.write_words(count, sv[start:start + (1 if scalar else count)])
            self.vec("I32", 0, count, 0, count, 2 if scalar else 0)
            self.vec("Mul", 0, count, 0, count, 2 if scalar else 0)
            output[start:start + count] = self.read_words(0, count)
        return output.view(np.float32).reshape(qq.shape)

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
        outer = tuple(x.shape[i] for i in rest)
        count = int(np.prod([x.shape[i] for i in axes]))
        rows = np.transpose(x, rest + axes).reshape((int(np.prod(outer, dtype=np.int64)), count))
        output = np.empty(rows.shape[0], np.uint32)
        if count == 0:
            if op == "Max":
                raise ValueError("empty max reduction")
            output.fill(0)
        for i, row in enumerate(rows):
            if count == 0:
                break
            words, offset, carry = float_words(row), 0, None
            while offset < count:
                prefix = 0 if carry is None else 1
                take = min(self.memory_words - prefix, count - offset)
                if carry is not None:
                    self.write_words(0, carry)
                self.write_words(prefix, words[offset:offset + take])
                self.reduce_words(op, 0, 0, take + prefix)
                carry = self.read_words(0, 1)
                offset += take
            output[i] = carry[0]
        result = output.view(np.float32).reshape(outer)
        if keepdims:
            result = result.reshape(tuple(1 if i in axes else x.shape[i] for i in range(x.ndim)))
        return result

    def matmul_i16(self, a, b):
        a, b = np.asarray(a), np.asarray(b)
        if a.dtype != np.int16 or b.dtype != np.int16 or min(a.ndim, b.ndim) < 2:
            raise ValueError("matmul_i16 expects rank>=2 signed INT16 arrays")
        m, k, n = a.shape[-2], a.shape[-1], b.shape[-1]
        if k != b.shape[-2] or k == 0:
            raise ValueError("invalid matrix contraction")
        batch_shape = np.broadcast_shapes(a.shape[:-2], b.shape[:-2])
        aa, bb = np.broadcast_to(a, batch_shape + (m, k)), np.broadcast_to(b, batch_shape + (k, n))
        output = np.empty(batch_shape + (m, n), np.int64)
        if m == 0 or n == 0:
            return output
        tm, tn, tk = tile_shape(m, n, k)
        for batch in np.ndindex(batch_shape):
            for row in range(0, m, tm):
                mr = min(tm, m - row)
                for col in range(0, n, tn):
                    nc = min(tn, n - col)
                    bbase, cbase = mr*tk, (mr + nc)*tk
                    for depth in range(0, k, tk):
                        kc = min(tk, k - depth)
                        av = aa[batch + (slice(row, row + mr), slice(depth, depth + kc))]
                        bv = bb[batch + (slice(depth, depth + kc), slice(col, col + nc))].T
                        self.write_words(0, np.ascontiguousarray(av).view(np.uint16).astype(np.uint32))
                        self.write_words(bbase, np.ascontiguousarray(bv).view(np.uint16).astype(np.uint32))
                        self.mm_tile(0, bbase, cbase, mr, nc, kc, depth != 0)
                    packed = self.read_words(cbase, 2*mr*nc).reshape(-1, 2)
                    # Sign reconstruction is type transport, never dot arithmetic.
                    high = (packed[:, 1] & 0xffff).astype(np.uint16).view(np.int16).astype(np.int64)
                    values = (high << 32) | packed[:, 0].astype(np.int64)
                    output[batch + (slice(row, row + mr), slice(col, col + nc))] = values.reshape(mr, nc)
        return output

    def softmax(self, x, axis=-1, logarithmic=False):
        """One complete row stays resident; oversized rows use RTL batching."""
        x = np.asarray(x, np.float32)
        if x.ndim == 0 or not -x.ndim <= axis < x.ndim:
            raise ValueError("invalid Softmax axis")
        axis %= x.ndim
        count = x.shape[axis]
        if count < 1:
            raise ValueError("empty Softmax axis")
        required = (2 if logarithmic else 1)*count + 3
        if required > self.memory_words:
            shifted = self.binary("Sub", x, self.reduce_max(x, [axis], True))
            exp = self.unary("Exp", shifted)
            denominator = self.reduce_sum(exp, [axis], True)
            return self.binary("Sub", shifted, self.unary("Log", denominator)) if logarithmic else self.binary("Div", exp, denominator)
        moved = np.moveaxis(x, axis, -1)
        rows = moved.reshape(-1, count)
        output = np.empty(rows.shape, np.uint32)
        scalar = (2 if logarithmic else 1)*count
        exp_base = count if logarithmic else 0
        for i, row in enumerate(rows):
            self.write_words(0, float_words(row))
            self.write_words(scalar, np.zeros(3, np.uint32))
            self.reduce_words("Max", 0, scalar, count)
            self.vec("Sub", 0, scalar, 0, count, 2)
            self.vec("Exp", 0, scalar + 2, exp_base, count, 2)
            self.reduce_words("Add", exp_base, scalar + 1, count)
            if logarithmic:
                self.vec("Log", scalar + 1, scalar + 2, scalar + 1, 1, 2)
                self.vec("Sub", 0, scalar + 1, 0, count, 2)
            else:
                self.vec("Div", exp_base, scalar + 1, 0, count, 2)
            output[i] = self.read_words(0, count)
        return np.moveaxis(output.view(np.float32).reshape(moved.shape), -1, axis)

    def layer_norm(self, x, gamma, beta=None, axis=-1, epsilon=1e-5):
        """Resident centered values/squares/statistics; exactly V1 op ordering."""
        x = np.asarray(x, np.float32)
        if x.ndim == 0 or not -x.ndim <= axis < x.ndim:
            raise ValueError("invalid LayerNormalization axis")
        axis %= x.ndim
        axes = list(range(axis, x.ndim))
        count = int(np.prod(x.shape[axis:]))
        if count < 1:
            raise ValueError("empty LayerNormalization extent")
        if 2*count + 6 > self.memory_words:
            divisor = np.float32(count)
            mean = self.binary("Div", self.reduce_sum(x, axes, True), divisor)
            centered = self.binary("Sub", x, mean)
            variance = self.binary("Div", self.reduce_sum(self.binary("Mul", centered, centered), axes, True), divisor)
            denominator = self.unary("Sqrt", self.binary("Add", variance, np.float32(epsilon)))
            inv = self.binary("Div", np.float32(1), denominator)
            out = self.binary("Mul", self.binary("Mul", centered, inv), gamma)
            if beta is not None:
                out = self.binary("Add", out, beta)
            return out, mean, inv
        rows = x.reshape(-1, count)
        gs = np.broadcast_to(np.asarray(gamma, np.float32), x.shape).reshape(-1, count)
        bs = None if beta is None else np.broadcast_to(np.asarray(beta, np.float32), x.shape).reshape(-1, count)
        output = np.empty(rows.shape, np.uint32)
        means, inverses = np.empty(rows.shape[0], np.uint32), np.empty(rows.shape[0], np.uint32)
        base = 2*count
        count_addr, epsilon_addr, one_addr, mean_addr, var_addr, inv_addr = range(base, base + 6)
        constants = float_words([np.float32(count), np.float32(epsilon), np.float32(1), 0, 0, 0])
        for i, row in enumerate(rows):
            self.write_words(0, float_words(row))
            self.write_words(base, constants)
            self.reduce_words("Add", 0, mean_addr, count)
            self.vec("Div", mean_addr, count_addr, mean_addr, 1, 2)
            self.vec("Sub", 0, mean_addr, 0, count, 2)
            self.vec("Mul", 0, 0, count, count)
            self.reduce_words("Add", count, var_addr, count)
            self.vec("Div", var_addr, count_addr, var_addr, 1, 2)
            self.vec("Add", var_addr, epsilon_addr, var_addr, 1, 2)
            self.vec("Sqrt", var_addr, epsilon_addr, var_addr, 1, 2)
            self.vec("Div", one_addr, var_addr, inv_addr, 1)
            self.vec("Mul", 0, inv_addr, 0, count, 2)
            # Squared values are dead; reuse their SRAM for affine operands.
            self.write_words(count, float_words(gs[i]))
            self.vec("Mul", 0, count, 0, count)
            if bs is not None:
                self.write_words(count, float_words(bs[i]))
                self.vec("Add", 0, count, 0, count)
            output[i] = self.read_words(0, count)
            means[i], inverses[i] = self.read_words(mean_addr, 1)[0], self.read_words(inv_addr, 1)[0]
        stats_shape = x.shape[:axis] + (1,)*(x.ndim - axis)
        return output.view(np.float32).reshape(x.shape), means.view(np.float32).reshape(stats_shape), inverses.view(np.float32).reshape(stats_shape)

    def report(self):
        result = super().report()
        result.update(protocol_version=self.version, memory_words=self.memory_words,
                      physical_fpga_executed=bool(self.hardware_executed),
                      execution_cycles=dict(self.execution_cycles),
                      execution_calls=dict(self.execution_calls),
                      execution_cycles_total=sum(self.execution_cycles.values()),
                      execution_cycle_counter="per-command modulo 2^32; summed by host",
                      elapsed_seconds=time.perf_counter() - self.started,
                      matrix_tile_limits=[31, 64, 256], resident_scope="intra-operator; host tensors between nodes")
        return result
