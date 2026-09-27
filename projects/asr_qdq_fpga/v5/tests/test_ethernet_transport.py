"""In-memory transport tests. No network socket, COM port or JTAG is opened."""
import socket
import struct
import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'host'))
import ethernet_transport as et


class Device:
    def __init__(self):
        self.session = None
        self.last_packet = self.last_reply = None
        self.last_sequence = 0
        self.executions = 0
        self.memory = np.zeros(32768, np.uint32)
        self.inner_status = 0

    def process(self, packet):
        session, sequence, kind, _, body = et.decode_packet(packet)
        if kind == et.HELLO:
            if self.session not in (None, session):
                return et.encode_packet(session, sequence, kind | 0x80, status=2)
            self.session = session
            return et.encode_packet(session, sequence, kind | 0x80,
                                    struct.pack('<4sIII', b'ASR4', 4, 32768, et.MAX_BODY))
        if session != self.session:
            return et.encode_packet(session, sequence, kind | 0x80, status=2)
        if sequence == self.last_sequence:
            return self.last_reply if packet == self.last_packet else et.encode_packet(session, sequence, kind | 0x80, status=5)
        if sequence != self.last_sequence + 1:
            return et.encode_packet(session, sequence, kind | 0x80, status=3)
        if kind == et.CLOSE:
            self.session = None
            return et.encode_packet(session, sequence, kind | 0x80)
        replies, cursor = [], 0
        while cursor < len(body):
            seq, op, flags, size = struct.unpack_from('<HBBH', body, cursor+2)
            payload = body[cursor+8:cursor+8+size]
            self.executions += 1
            if op == 0:
                reply = b'ASR1\x01\x00\x00\x00'
            elif op == 0x40:
                reply = struct.pack('<4sII', b'ASR2', 2, 32768)
            elif op == 0x41:
                base, count = struct.unpack_from('<HH', payload)
                self.memory[base:base+count] = np.frombuffer(payload[4:], dtype='<u4')
                reply = b''
            elif op == 0x42:
                base, count = struct.unpack('<HH', payload)
                reply = self.memory[base:base+count].astype('<u4').tobytes()
            else:
                reply = struct.pack('<BI', 0, 100)
            replies.append(et.encode_inner(seq, op, reply, self.inner_status, b'\x5a\xa5'))
            cursor += 10 + size
        self.last_sequence, self.last_packet = sequence, packet
        self.last_reply = et.encode_packet(session, sequence, kind | 0x80, b''.join(replies))
        return self.last_reply


class FakeSocket:
    def __init__(self, device=None):
        self.device = device or Device()
        self.sent = []
        self.received = []
        self.drop_next = 0
        self.mutate = None
        self.closed = False

    def send(self, packet):
        self.sent.append(packet)
        response = self.device.process(packet)
        if self.drop_next:
            self.drop_next -= 1
        else:
            if self.mutate:
                response = self.mutate(response)
            self.received.append(response)
        return len(packet)

    def recv(self, maximum):
        if not self.received:
            raise socket.timeout()
        return self.received.pop(0)

    def settimeout(self, timeout):
        assert timeout > 0

    def close(self):
        self.closed = True


class CodecTests(unittest.TestCase):
    def test_crc_known_vector(self):
        self.assertEqual(et.crc16(b'123456789'), 0x29b1)

    def test_frozen_crc_equivalence(self):
        for length in (0, 1, 6, 255, 1024):
            payload = bytes(i & 255 for i in range(length))
            self.assertEqual(et.encode_inner(65535, 0x41, payload), et.v1.encode_frame(65535, 0x41, 0, payload))

    def test_packet_roundtrip_maximum(self):
        for length in (0, 1, 1024, et.MAX_BODY):
            data = b'X' * length
            self.assertEqual(et.decode_packet(et.encode_packet(1, 2, 1, data)), (1, 2, 1, 0, data))

    def test_bad_lengths_and_crc(self):
        packet = et.encode_packet(1, 1, 1, b'test')
        for malformed in (packet[:-1], packet+b'X', b'bad', packet[:-1]+bytes([packet[-1]^1])):
            with self.assertRaises(et.ProtocolError):
                et.decode_packet(malformed)

    def test_size_and_session_limits(self):
        for session, sequence, body in ((0, 0, b''), (1, -1, b''), (1, 2**32, b''), (1, 0, b'X'*1383)):
            with self.assertRaises(ValueError):
                et.encode_packet(session, sequence, 0, body)

    def test_reply_capacity(self):
        self.assertEqual(et.reply_bound(0x42, struct.pack('<HH', 0, 168)), 682)
        with self.assertRaises(ValueError):
            et.reply_bound(0x42, struct.pack('<HH', 0, 257))


class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.sock = FakeSocket()
        self.link = et.EthernetLink(self.sock, timeout=.01, retries=2, session=123)
        self.link.hello()

    def test_hello_ping_info_close(self):
        self.link.ping()
        backend = et.EthernetBackend(self.link)
        self.assertEqual(backend.memory_words, 32768)
        backend.close()
        self.assertTrue(self.sock.closed)

    def test_lost_reply_identical_replay_executes_once(self):
        self.sock.drop_next = 1
        before = self.sock.device.executions
        self.link.request(0x43, bytes(10))
        self.assertEqual(self.sock.device.executions-before, 1)
        self.assertEqual(self.sock.sent[-2], self.sock.sent[-1])
        self.assertEqual(self.link.retransmissions, 1)

    def test_exhausted_retries_poison_and_no_reopen(self):
        self.sock.drop_next = 10
        with self.assertRaises(TimeoutError):
            self.link.request(0x43, bytes(10))
        self.assertTrue(self.link.poisoned)
        count = len(self.sock.sent)
        with self.assertRaises(et.ProtocolError):
            self.link.hello()
        with self.assertRaises(et.ProtocolError):
            self.link.request(0)
        self.assertEqual(len(self.sock.sent), count)
        self.link.close()
        self.assertEqual(len(self.sock.sent), count)

    def test_reset_session_rejection_does_not_reexecute(self):
        self.sock.device.session = None
        before = self.sock.device.executions
        with self.assertRaisesRegex(et.ProtocolError, 'status=2'):
            self.link.request(0x45, bytes(14))
        self.assertEqual(before, self.sock.device.executions)
        self.assertTrue(self.link.poisoned)

    def test_outer_engine_failure_never_masked(self):
        def failed(packet):
            session, sequence, kind, _, body = et.decode_packet(packet)
            return et.encode_packet(session, sequence, kind, status=6)
        self.sock.mutate = failed
        with self.assertRaisesRegex(et.ProtocolError, 'status=6'):
            self.link.request(0x43, bytes(10), allow_arithmetic=True)
        self.assertTrue(self.link.poisoned)

    def test_corrupt_then_good_response(self):
        good = et.encode_packet(self.link.session, self.link.sequence, 0x81,
                                et.encode_inner(0, 0, b'ASR1\x01\x00\x00\x00', magic=b'\x5a\xa5'))
        self.sock.received.append(good[:-1] + bytes([good[-1]^1]))
        self.link.ping()
        self.assertEqual(self.link.discarded_datagrams, 1)

    def test_stale_response_discarded(self):
        self.sock.received.append(et.encode_packet(123, 0, 0x80))
        self.link.ping()
        self.assertEqual(self.link.discarded_datagrams, 1)

    def test_future_response_poison(self):
        self.sock.received.append(et.encode_packet(123, 999, 0x81))
        with self.assertRaises(et.ProtocolError):
            self.link.ping()
        self.assertTrue(self.link.poisoned)

    def test_inner_error_poison(self):
        self.sock.device.inner_status = 3
        with self.assertRaises(et.ProtocolError):
            self.link.request(0x43, bytes(10))
        self.assertTrue(self.link.poisoned)

    def test_bad_inner_crc_with_valid_outer(self):
        def broken(packet):
            session, sequence, kind, status, body = et.decode_packet(packet)
            body = body[:-1] + bytes([body[-1]^1])
            return et.encode_packet(session, sequence, kind, body, status)
        self.sock.mutate = broken
        with self.assertRaisesRegex(et.ProtocolError, 'V2 reply CRC'):
            self.link.ping()

    def test_local_batch_overflow_sends_nothing(self):
        before = len(self.sock.sent)
        with self.assertRaises(ValueError):
            self.link.request_many([(0x42, struct.pack('<HH', 0, 256))]*2)
        with self.assertRaises(ValueError):
            self.link.request_many([])
        with self.assertRaises(ValueError):
            self.link.request_many([(0, b'')]*65)
        self.assertEqual(len(self.sock.sent), before)
        self.assertFalse(self.link.poisoned)

    def test_inner_sequence_wrap_is_independent_of_outer_sequence(self):
        self.link.inner_sequence = 65535
        result = self.link.request_many([(0, b''), (0, b'')])
        self.assertEqual(len(result), 2)
        self.assertEqual(self.link.inner_sequence, 1)
        self.assertEqual(self.link.sequence, 2)

    def test_full_sram_roundtrip_and_exact_batch_mtu(self):
        backend = et.EthernetBackend(self.link)
        data = np.arange(32768, dtype=np.uint32) ^ np.uint32(0xa5a5a5a5)
        backend.write_words(0, data)
        np.testing.assert_array_equal(backend.read_words(0, 32768), data)
        self.assertLessEqual(max(map(len, self.sock.sent)), 1400)
        self.assertEqual(self.link.max_batch_commands, 2)

    def test_varied_tail_lengths_and_sram_boundary(self):
        backend = et.EthernetBackend(self.link)
        for count in (0, 1, 167, 168, 169, 255, 256, 257, 335, 336, 337, 671, 672, 673):
            data = np.arange(count, dtype=np.uint32)
            backend.write_words(32768-count, data)
            np.testing.assert_array_equal(backend.read_words(32768-count, count), data)
        with self.assertRaises(ValueError):
            backend.write_words(32768, [1])
        with self.assertRaises(ValueError):
            backend.read_words(0, 32769)

    def test_numeric_methods_are_frozen_inherited(self):
        for method in ('binary', 'unary', 'quantize', 'dequantize', 'matmul_i16', 'layer_norm', 'softmax', 'mm_tile'):
            self.assertIs(getattr(et.EthernetBackend, method), getattr(et.v2.BufferedBackend, method))


if __name__ == '__main__':
    unittest.main()
