"""Host-only transport tests: mock bytes and fake arithmetic, NOT FPGA validation.

The fake arithmetic peer only checks marshalling, graph delegation, shapes,
rounding requests, and chunk/reset control. Numeric RTL evidence comes from the
separate HDL simulations. No serial port is opened by this suite.
Run with PYTHONPATH containing the deployed asr root and its host directory.
"""
from collections import Counter
import struct
import unittest
from unittest.mock import patch

import numpy as np
from host import transport


def reply_for(request, *, data=b"OK", sequence=None, opcode=None, status=0):
    seq, op, _, _ = struct.unpack("<HBBH", request[2:8])
    return transport.encode_frame(seq if sequence is None else sequence,
                                  op if opcode is None else opcode, status,
                                  data, magic=b"\x5a\xa5")


class ByteStream:
    """Fragmented in-memory stream, with exactly one scripted reply per write."""
    def __init__(self, responder=None, fragment=3, partial=False):
        self.responder = responder or (lambda frame: reply_for(frame))
        self.fragment, self.partial = fragment, partial
        self.writes, self.pending = [], bytearray()
        self.reads = 0

    def write(self, frame):
        self.writes.append(bytes(frame))
        if self.partial:
            return len(frame)-1
        self.pending.extend(self.responder(frame))
        return len(frame)

    def read(self, size):
        self.reads += 1
        size = min(size, self.fragment, len(self.pending))
        data = bytes(self.pending[:size])
        del self.pending[:size]
        return data


def float_word(value):
    return struct.unpack("<I", struct.pack("<f", np.float32(value)))[0]


def word_float(value):
    return np.float32(struct.unpack("<f", struct.pack("<I", value))[0])


class FakeMathLink:
    """Test-only CPU peer. Deliberately not a hardware execution backend."""
    def __init__(self):
        self.calls = []
        self.commands = Counter()
        self.bytes_sent = self.bytes_received = 0
        self.accumulator = 0
        self.return_flags = 0
        self.bad_reply = None

    def request(self, opcode, payload=b"", flags=0, **kwargs):
        self.calls.append((opcode, bytes(payload), flags))
        self.commands[opcode] += 1
        if self.bad_reply is not None:
            return self.bad_reply
        if opcode == 1:
            self.accumulator = int.from_bytes(payload, "little", signed=True)
            return self.accumulator.to_bytes(6, "little", signed=True)
        if opcode == 5:
            if flags & 1:
                self.accumulator = 0
            pairs = np.frombuffer(payload, dtype="<i2").reshape(-1, 2)
            self.accumulator += sum(int(x)*int(y) for x, y in pairs)
            return self.accumulator.to_bytes(6, "little", signed=True)
        self.assert_scalar_packet(opcode, payload)
        operation = opcode-0x20
        a, b = struct.unpack("<II", payload)
        x, y = word_float(a), word_float(b)
        with np.errstate(all="ignore"):
            if operation == 0: value = float_word(x+y)
            elif operation == 1: value = float_word(x-y)
            elif operation == 2: value = float_word(x*y)
            elif operation == 3: value = float_word(x/y)
            elif operation == 4: value = float_word(np.sqrt(x))
            elif operation == 5: value = float_word(np.exp(x))
            elif operation == 6: value = float_word(np.log(x))
            elif operation == 9: value = float_word(np.maximum(x, y))
            elif operation == 10: value = int(x < y)
            elif operation == 11: value = int(x == y)
            elif operation == 12: value = a & 0x7fffffff
            elif operation == 13: value = a ^ 0x80000000
            elif operation == 14:
                integer = ((b&0xffff) << 32) | a
                if integer & (1 << 47): integer -= 1 << 48
                value = float_word(integer)
            elif operation == 15:
                value = int(np.clip(np.rint(x), -32768, 32767)) & 0xffffffff
            else:
                raise AssertionError(f"Unimplemented fake opcode {operation}")
        return struct.pack("<IB", value, self.return_flags)

    @staticmethod
    def assert_scalar_packet(opcode, payload):
        if not 0x20 <= opcode <= 0x2f or len(payload) != 8:
            raise AssertionError("Malformed scalar request emitted by host")


class TestPacketCodec(unittest.TestCase):
    def test_crc_ccitt_false_known_vector(self):
        self.assertEqual(transport.crc16(b"123456789"), 0x29b1)
        self.assertEqual(transport.crc16(b""), 0xffff)

    def test_little_endian_layout_and_payload_limit(self):
        frame = transport.encode_frame(0x1234, 5, 1, b"\x00\x80")
        self.assertEqual(frame[:10], b"\xa5\x5a\x34\x12\x05\x01\x02\x00\x00\x80")
        self.assertEqual(int.from_bytes(frame[-2:], "little"), transport.crc16(frame[2:-2]))
        self.assertEqual(len(transport.encode_frame(0, 5, 0, bytes(1024))), 1034)
        with self.assertRaises(ValueError):
            transport.encode_frame(0, 5, 0, bytes(1025))


class TestLinkProtocol(unittest.TestCase):
    def test_fragmented_read_and_counters(self):
        stream = ByteStream(fragment=1)
        link = transport.Link(stream)
        self.assertEqual(link.request(5, b"payload", flags=1), b"OK")
        self.assertEqual(len(stream.writes), 1)
        self.assertGreater(stream.reads, 3)
        self.assertEqual(link.commands[5], 1)
        self.assertEqual(link.bytes_sent, 17)
        self.assertEqual(link.bytes_received, 12)

    def test_sequence_wrap(self):
        stream = ByteStream(); link = transport.Link(stream)
        link.sequence = 65535
        link.request(0); link.request(0)
        self.assertEqual([int.from_bytes(f[2:4], "little") for f in stream.writes], [65535, 0])
        self.assertEqual(link.sequence, 1)

    def test_ping_checks_protocol_version(self):
        version = b"ASR1\x01\x00\x00\x00"
        link = transport.Link(ByteStream(lambda frame: reply_for(frame, data=version)))
        self.assertEqual(link.ping(), version)
        with self.assertRaises(transport.ProtocolError):
            transport.Link(ByteStream()).ping()

    def test_crc_sequence_opcode_and_sync_fail_without_retry(self):
        def wrong_crc(frame):
            reply = bytearray(reply_for(frame)); reply[-1] ^= 0x40
            return reply
        responders = [wrong_crc,
                      lambda f: reply_for(f, sequence=7),
                      lambda f: reply_for(f, opcode=0x2e),
                      lambda f: b"\x00\x00" + reply_for(f)[2:]]
        for responder in responders:
            with self.subTest(responder=responder):
                stream = ByteStream(responder); link = transport.Link(stream)
                with self.assertRaises(transport.ProtocolError): link.request(5, b"abcd")
                self.assertEqual(len(stream.writes), 1)

    def test_invalid_reply_length_fails_before_body_read(self):
        stream = ByteStream(lambda f: b"\x5a\xa5"+struct.pack("<HBBH", 0, 5, 0, 1025))
        with self.assertRaises(transport.ProtocolError): transport.Link(stream).request(5)
        self.assertEqual(len(stream.writes), 1)

    def test_status_errors_and_explicit_arithmetic_override(self):
        for status in (1,2,3,4,5,255):
            stream = ByteStream(lambda f, s=status: reply_for(f, status=s))
            with self.subTest(status=status):
                with self.assertRaises(transport.ProtocolError): transport.Link(stream).request(5)
                self.assertEqual(len(stream.writes), 1)
        link = transport.Link(ByteStream(lambda f: reply_for(f, status=4)))
        self.assertEqual(link.request(5, allow_arithmetic=True), b"OK")
        link = transport.Link(ByteStream(lambda f: reply_for(f, status=3)))
        with self.assertRaises(transport.ProtocolError): link.request(5, allow_arithmetic=True)

    def test_partial_write_never_retries_or_reads(self):
        stream = ByteStream(partial=True)
        with self.assertRaises(transport.ProtocolError): transport.Link(stream).request(5, b"abcd")
        self.assertEqual(len(stream.writes), 1)
        self.assertEqual(stream.reads, 0)

    def test_timeout_never_retries_stateful_packet(self):
        stream = ByteStream(lambda frame: b"")
        with patch.object(transport.time, "monotonic", side_effect=[0.0, 0.01, 0.03, 0.2]):
            with self.assertRaises(TimeoutError): transport.Link(stream, timeout=0.1).request(5, b"abcd")
        self.assertEqual(len(stream.writes), 1)
        self.assertEqual(stream.reads, 2)

    def test_mid_reply_timeout_does_not_resend(self):
        stream = ByteStream(lambda frame: b"\x5a\xa5", fragment=2)
        with patch.object(transport.time, "monotonic", side_effect=[0.0, 0.01, 0.02, 0.2]):
            with self.assertRaises(TimeoutError): transport.Link(stream, timeout=0.1).request(5)
        self.assertEqual(len(stream.writes), 1)


class TestSerialBackendDelegation(unittest.TestCase):
    """These tests use FakeMathLink, so passing is NOT evidence of HDL execution."""
    def setUp(self):
        self.peer = FakeMathLink()
        self.backend = transport.SerialBackend(self.peer)

    def test_dot_9728_uses_38_chunks_clear_first_only(self):
        a = np.full(9728, -32768, dtype=np.int16)
        b = np.full(9728, 32767, dtype=np.int16)
        expected = 9728*(-32768)*32767
        self.assertEqual(self.backend.dot_i16(a,b), expected)
        self.assertEqual(len(self.peer.calls), 38)
        self.assertEqual([flags for _,_,flags in self.peer.calls], [1]+[0]*37)
        self.assertTrue(all(op==5 and len(payload)==1024 for op,payload,_ in self.peer.calls))
        self.assertEqual(self.peer.calls[0][1][:4], b"\x00\x80\xff\x7f")
        # An independent next dot must clear the previous negative accumulator.
        self.assertEqual(self.backend.dot_i16(np.array([2],np.int16),np.array([3],np.int16)),6)
        self.assertEqual(self.peer.calls[-1][2],1)

    def test_dot_partial_final_chunk_and_empty_reset(self):
        a = np.arange(257,dtype=np.int16); b = np.ones(257,np.int16)
        self.assertEqual(self.backend.dot_i16(a,b), sum(range(257)))
        self.assertEqual([len(payload) for _,payload,_ in self.peer.calls], [1024,4])
        self.assertEqual(self.backend.dot_i16(np.array([],np.int16),np.array([],np.int16)),0)
        self.assertEqual(self.peer.calls[-1], (1, bytes(6), 0))

    def test_dot_rejects_dtype_shape_and_bad_reply(self):
        for a,b in [(np.ones(2,np.int32),np.ones(2,np.int16)),
                    (np.ones((1,2),np.int16),np.ones((1,2),np.int16)),
                    (np.ones(2,np.int16),np.ones(3,np.int16))]:
            with self.subTest(shape=(a.shape,b.shape)):
                with self.assertRaises(ValueError): self.backend.dot_i16(a,b)
        self.peer.bad_reply = bytes(5)
        with self.assertRaises(transport.ProtocolError):
            self.backend.dot_i16(np.ones(1,np.int16),np.ones(1,np.int16))

    def test_scalar_flags_accept_ftz_and_approx_but_reject_exceptions(self):
        for flags in (0,8,16,24):
            self.peer.return_flags = flags
            self.assertEqual(self.backend.binary("Add",1,2),np.float32(3))
        for flags in (1,2,3,4,7,17,26):
            self.peer.return_flags = flags
            with self.subTest(flags=flags):
                with self.assertRaises(ArithmeticError): self.backend.binary("Add",1,2)
        self.assertEqual(sum(self.backend.arithmetic_flags.values()),11)
        for size in (0,4,6):
            self.peer.bad_reply = bytes(size)
            with self.assertRaises(transport.ProtocolError): self.backend.binary("Add",1,2)

    def test_binary_broadcast_and_scalar_shape(self):
        a = np.array([[1],[2]],np.float32); b = np.array([10,20,30],np.float32)
        result = self.backend.binary("Add",a,b)
        np.testing.assert_array_equal(result,a+b)
        self.assertEqual(result.shape,(2,3)); self.assertEqual(len(self.peer.calls),6)
        scalar = self.backend.binary("Mul",np.float32(2),np.float32(3))
        self.assertEqual(scalar.shape,()); self.assertEqual(scalar.dtype,np.float32)
        self.assertEqual(scalar.item(),6)
        np.testing.assert_array_equal(self.backend.binary("Less",a,b),np.ones((2,3),np.float32))
        self.assertEqual(self.backend.binary("Equal",1,2).item(),0)
        with self.assertRaises(NotImplementedError): self.backend.binary("Pow",1,2)

    def test_unary_shapes_and_stable_sigmoid(self):
        scalar = self.backend.unary("Sqrt",np.float32(4))
        self.assertEqual(scalar.shape,()); self.assertEqual(scalar.item(),2)
        values = np.array([-1000,0,1000],np.float32)
        np.testing.assert_array_equal(self.backend.unary("Sigmoid",values),[0,0.5,1])
        exp_arguments = [word_float(struct.unpack("<II",p)[0]) for op,p,_ in self.peer.calls if op==0x25]
        self.assertTrue(all(x<=0 for x in exp_arguments))
        np.testing.assert_array_equal(self.backend.unary("Relu",values),[0,0,1000])
        with self.assertRaises(NotImplementedError): self.backend.unary("Sin",values)

    def test_quantize_ties_saturation_and_scale_broadcast(self):
        x = np.array([-1e6,-32768.5,-2.5,-1.5,-0.5,0.5,1.5,2.5,32767.5,1e6],np.float32)
        q = self.backend.quantize(x,np.float32(1))
        np.testing.assert_array_equal(q,[-32768,-32768,-2,-2,0,0,2,2,32767,32767])
        self.assertEqual(q.dtype,np.int16)
        self.assertEqual([op for op,_,_ in self.peer.calls],[0x23]*10+[0x2f]*10)
        self.assertEqual(self.backend.quantize(np.float32(1.5),np.float32(1)).shape,())
        x = np.array([[1,2],[3,4]],np.float32); scale=np.array([0.5,2],np.float32)
        np.testing.assert_array_equal(self.backend.quantize(x,scale),[[2,1],[6,2]])

    def test_dequantize_and_int48_marshalling(self):
        q=np.array([[-32768,32767],[0,-1]],np.int16)
        scale=np.array([0.25,2],np.float32)
        np.testing.assert_array_equal(self.backend.dequantize(q,scale),q.astype(np.float32)*scale)
        self.assertEqual([op for op,_,_ in self.peer.calls],[0x2e]*4+[0x22]*4)
        values=np.array([-(1<<47),(1<<47)-1,-1,0],np.int64)
        np.testing.assert_array_equal(self.backend.int48_to_float(values),values.astype(np.float32))
        self.assertEqual(self.backend.int48_to_float(np.int64(-1)).shape,())
        for value in (-(1<<47)-1,1<<47):
            with self.assertRaises(OverflowError):self.backend.int48_to_float([value])
        with self.assertRaises(TypeError):self.backend.dequantize(np.ones(2,np.int32),1)

    def test_reductions_axes_keepdims_and_scalar(self):
        x=np.arange(24,dtype=np.float32).reshape(2,3,4)
        np.testing.assert_array_equal(self.backend.reduce_sum(x,axes=(0,2),keepdims=True),np.sum(x,axis=(0,2),keepdims=True))
        np.testing.assert_array_equal(self.backend.reduce_max(x,axes=-1),np.max(x,axis=-1))
        np.testing.assert_array_equal(self.backend.reduce_sum(x),np.sum(x))
        self.assertEqual(self.backend.reduce_sum(np.float32(3)).shape,())
        np.testing.assert_array_equal(self.backend.reduce_sum(x,axes=()),x)
        empty_outer=np.empty((0,3),np.float32)
        self.assertEqual(self.backend.reduce_sum(empty_outer,axes=1).shape,(0,))
        for bad_axis in (3,-4):
            with self.assertRaisesRegex(ValueError,"axis out of range"):
                self.backend.reduce_sum(x,axes=bad_axis)

    def test_empty_reduction_sum_identity_and_max_error(self):
        x=np.empty((2,0),np.float32)
        np.testing.assert_array_equal(self.backend.reduce_sum(x,axes=1),np.zeros(2,np.float32))
        np.testing.assert_array_equal(self.backend.reduce_sum(x,axes=1,keepdims=True),np.zeros((2,1),np.float32))
        with self.assertRaisesRegex(ValueError,"empty max"):
            self.backend.reduce_max(x,axes=1)


if __name__ == "__main__":
    unittest.main()
