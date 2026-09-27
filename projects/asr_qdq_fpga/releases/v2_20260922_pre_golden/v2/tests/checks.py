"""Shared bounded V2 acceptance checks, usable on Icarus or an explicit board."""
from __future__ import annotations
import struct
import time
import numpy as np
import onnx
from host.smoke import compare, evaluate
from host.onnx_executor import SoftwareBackend, Tensor
from host.transport import crc16, encode_frame, ProtocolError
from v2.host.onnx_executor import OnnxExecutor


def executor(backend):
    graph = onnx.helper.make_graph([], "v2_bounded_checks", [], [])
    model = onnx.helper.make_model(graph, opset_imports=[onnx.helper.make_opsetid("", 21)])
    return OnnxExecutor(model, backend, fold_constants=False)


def raw_status(link, opcode, payload=b"", flags=0, corrupt_crc=False):
    """One deliberately malformed command; no retries, validates response CRC."""
    sequence = link.sequence
    link.sequence = (sequence + 1) & 0xffff
    frame = bytearray(encode_frame(sequence, opcode, flags, payload))
    if corrupt_crc:
        frame[-1] ^= 0x80
    written = link.stream.write(bytes(frame))
    if written is not None and written != len(frame):
        raise ProtocolError("partial test write")
    link.bytes_sent += len(frame)
    deadline = time.monotonic() + link.timeout
    if link._read_exact(2, deadline) != b"\x5a\xa5":
        raise ProtocolError("test response framing")
    header = link._read_exact(6, deadline)
    seq, op, status, length = struct.unpack("<HBBH", header)
    if length > 1024:
        raise ProtocolError("invalid response length")
    data = link._read_exact(length, deadline)
    check = struct.unpack("<H", link._read_exact(2, deadline))[0]
    if (seq, op) != (sequence, opcode) or crc16(header + data) != check:
        raise ProtocolError("test response identity/CRC")
    link.commands[opcode] += 1
    return status, data


def checks(backend, results, *, extended=False):
    reference = SoftwareBackend()
    target, software = executor(backend), executor(reference)

    def run(name, action):
        started = time.perf_counter()
        before = backend.report()
        try:
            item = action()
        except Exception as exc:
            results.append({"name": name, "pass": False, "error": f"{type(exc).__name__}: {exc}",
                            "elapsed_seconds": time.perf_counter() - started})
            raise
        after = backend.report()
        item["elapsed_seconds"] = time.perf_counter() - started
        for field in ("bytes_sent", "bytes_received", "execution_cycles_total"):
            item[field] = after[field] - before[field]
        results.append(item)
        print(f"{'PASS' if item['pass'] else 'FAIL'} {name}: {item['elapsed_seconds']:.3f}s, cycles={item['execution_cycles_total']}, bytes={item['bytes_sent'] + item['bytes_received']}", flush=True)
        if not item["pass"]:
            raise AssertionError(name)

    def node(name, op, values, atol=0., rtol=0., **attrs):
        actual = evaluate(target, backend, op, values, **attrs).data
        expected = evaluate(software, reference, op, values, **attrs).data
        return compare(name, actual, expected, atol=atol, rtol=rtol)

    run("ping_v1_compatibility", lambda: compare("ping_v1_compatibility", np.frombuffer(backend.link.ping(), np.uint8), np.frombuffer(b"ASR1\x01\0\0\0", np.uint8)))
    run("info_v2", lambda: compare("info_v2", [backend.version, backend.memory_words], [2, 32768]))

    def memory():
        rng = np.random.default_rng(77)
        words = rng.integers(0, 1 << 32, 769, dtype=np.uint32)
        backend.write_words(0, words)
        backend.write_words(32767, [0xfedcba98])
        actual = np.concatenate([backend.read_words(0, words.size), backend.read_words(32767, 1)])
        expected = np.concatenate([words, np.array([0xfedcba98], np.uint32)])
        return compare("sram_first_last_and_packets", actual, expected)
    run("sram_first_last_and_packets", memory)

    def vec_modes():
        aa = np.arange(17, dtype=np.float32) + 1
        bb = np.arange(17, dtype=np.float32) + 3
        actual, expected = [], []
        for mode in range(4):
            backend.write_words(0, aa.view(np.uint32))
            backend.write_words(32, bb.view(np.uint32))
            dest = 64 if mode & 1 else 0
            backend.vec("Add", 0, 32, dest, 17, mode)
            actual.extend(backend.read_words(dest, 17).view(np.float32))
            expected.extend(np.broadcast_to((aa[0] if mode & 1 else aa) + (bb[0] if mode & 2 else bb), (17,)))
        # Both non-broadcast inputs and output can have the exact same base.
        backend.write_words(0, aa.view(np.uint32))
        backend.vec("Mul", 0, 0, 0, 17)
        actual.extend(backend.read_words(0, 17).view(np.float32))
        expected.extend(aa*aa)
        return compare("vec_broadcast_alias", actual, expected)
    run("vec_broadcast_alias", vec_modes)

    def rejections():
        guard = np.arange(128, dtype=np.uint32) | np.uint32(0x3f000000)
        backend.write_words(0, guard)
        backend.write_words(32767, [0x1234abcd])
        cases = [
            (0x41, struct.pack("<HHII", 32767, 2, 1, 2), 0, False, 2),
            (0x42, struct.pack("<HH", 32767, 2), 0, False, 2),
            (0x43, struct.pack("<BBHHHH", 0, 0, 0, 32, 1, 8), 0, False, 2),
            (0x43, struct.pack("<BBHHHH", 0, 1, 0, 32, 0, 8), 0, False, 2),
            (0x43, struct.pack("<BBHHHH", 0, 4, 0, 32, 64, 8), 0, False, 3),
            (0x43, struct.pack("<BBHHHH", 16, 0, 0, 32, 64, 8), 0, False, 3),
            (0x44, struct.pack("<BBHHH", 0, 1, 0, 64, 8), 0, False, 3),
            (0x44, struct.pack("<BBHHH", 0, 0, 0, 64, 0), 0, False, 2),
            (0x45, struct.pack("<7H", 0, 32, 64, 65535, 65535, 65535, 0), 0, False, 2),
            (0x45, struct.pack("<7H", 0, 32, 0, 1, 1, 1, 0), 0, False, 2),
            (0x43, struct.pack("<BBHHHH", 0, 0, 0, 32, 64, 8), 1, False, 3),
            (0x41, struct.pack("<HHI", 64, 1, 0xdeadbeef), 0, True, 1),
            (0x43, struct.pack("<BBHHHH", 0, 0, 0, 32, 64, 8), 0, True, 1),
            (0x45, struct.pack("<7H", 0, 32, 64, 1, 1, 1, 0), 0, True, 1),
        ]
        statuses, wanted = [], []
        for opcode, payload, flags, corrupt, expected in cases:
            status, _ = raw_status(backend.link, opcode, payload, flags, corrupt)
            statuses.append(status)
            wanted.append(expected)
            if not np.array_equal(backend.read_words(0, 128), guard) or backend.read_words(32767, 1)[0] != 0x1234abcd:
                raise AssertionError("rejected/CRC command changed SRAM")
        return compare("range_alias_crc_no_execution", statuses, wanted, note="Every rejected command checked for unchanged SRAM; no stateful retry")
    run("range_alias_crc_no_execution", rejections)

    def conversions():
        values = np.array([-(1 << 47), -(1 << 40) - 1, -32768, -1, 0, 1, 32767, (1 << 40) + 1, (1 << 47)-1], np.int64)
        return compare("vec_i48_two_inputs", backend.int48_to_float(values), values.astype(np.float32))
    run("vec_i48_two_inputs", conversions)
    zero = np.array(0, np.int16)
    ties = np.array([-40000, -32768.5, -32767.5, -3.5, -2.5, -1.5, -.5, .5, 1.5, 2.5, 3.5, 32766.5, 32767.5, 40000], np.float32)
    run("quantize_ties_saturation", lambda: node("quantize_ties_saturation", "QuantizeLinear", [ties, np.array(1, np.float32), zero]))
    qq = np.array([[-32768, -13, -1, 0, 1, 32767]], np.int16)
    run("dequantize_resident", lambda: node("dequantize_resident", "DequantizeLinear", [qq, np.array(.125, np.float32), zero]))

    rng = np.random.default_rng(20260922)
    def matrix(m, k, n, name, worst=False):
        a = np.full((m, k), -32768, np.int16) if worst else rng.integers(-32768, 32768, (m, k), dtype=np.int16)
        b = np.full((k, n), -32768, np.int16) if worst else rng.integers(-32768, 32768, (k, n), dtype=np.int16)
        return compare(name, backend.matmul_i16(a, b), a.astype(np.int64) @ b.astype(np.int64), note="Independent NumPy integer reference; RTL signed48 C retained across K tiles")
    run("mm_random_fullrange_k513", lambda: matrix(3, 513, 5, "mm_random_fullrange_k513"))
    run("mm_worst_k9728", lambda: matrix(1, 9728, 1, "mm_worst_k9728", True))
    run("mm_random_k9728", lambda: matrix(1, 9728, 2, "mm_random_k9728"))

    def qdq_matrix():
        qa = rng.integers(-32768, 32768, (2, 5), dtype=np.int16)
        qb = rng.integers(-32768, 32768, (5, 3), dtype=np.int16)
        sa, sb = np.array(.125, np.float32), np.array(.0625, np.float32)
        a = Tensor(qa, qa, sa)
        b = Tensor(qb, qb, sb)
        return node("onnx_qdq_matmul_v2_dispatch", "MatMul", [a, b])
    run("onnx_qdq_matmul_v2_dispatch", qdq_matrix)
    soft = np.array([[-8, -2.5, -.25, 0, 1.75, 3.5, 7], [0, 0, 0, 0, 0, 0, 0]], np.float32)
    run("resident_softmax", lambda: node("resident_softmax", "Softmax", [soft], atol=3e-6, rtol=2e-5, axis=-1))
    run("resident_logsoftmax", lambda: node("resident_logsoftmax", "LogSoftmax", [soft], atol=3e-6, rtol=2e-5, axis=-1))
    sigmoid_x = np.array([-100, -20, -8, -1, -0., 0, 1, 8, 20, 100], np.float32)
    run("resident_sigmoid", lambda: node("resident_sigmoid", "Sigmoid", [sigmoid_x], atol=3e-6, rtol=2e-5))
    ln = (rng.standard_normal((1, 512))*1.5 + 2).astype(np.float32)
    gamma, beta = np.linspace(.5, 1.5, 512, dtype=np.float32), np.linspace(-.2, .3, 512, dtype=np.float32)
    run("resident_layernorm512", lambda: node("resident_layernorm512", "LayerNormalization", [ln, gamma, beta], atol=1e-5, rtol=1e-5, axis=-1, epsilon=1e-12))

    def generic_crosscheck():
        # Exercise both resident and generic buffered paths independently.
        shift = backend.binary("Sub", soft, backend.reduce_max(soft, [-1], True))
        exp = backend.unary("Exp", shift)
        generic = backend.binary("Div", exp, backend.reduce_sum(exp, [-1], True))
        return compare("resident_vs_generic_softmax_bitexact", backend.softmax(soft), generic)
    run("resident_vs_generic_softmax_bitexact", generic_crosscheck)
    if extended:
        run("mm_full_tile_31x256x64", lambda: matrix(31, 256, 64, "mm_full_tile_31x256x64"))
        run("mm_partial_mn_tiles", lambda: matrix(32, 3, 65, "mm_partial_mn_tiles"))
        def long_reduce():
            # Non-associative witness across SRAM boundary. A partial-reduction
            # tree or sum-of-chunk-sums would lose the required sequential value.
            data = np.ones(32770, np.float32)
            data[0], data[32767], data[32768] = np.float32(1 << 25), np.float32(-(1 << 25)), np.float32(3)
            expect = data[0]
            for value in data[1:]:
                expect = np.float32(expect + value)
            return compare("reduce_left_to_right_across_sram", backend.reduce_sum(data), expect)
        run("reduce_left_to_right_across_sram", long_reduce)
    return results
