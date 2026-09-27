"""Pure host contract tests. CountingLink is NOT arithmetic or FPGA evidence."""
import struct
import unittest
from collections import Counter
import numpy as np
from host.transport import ProtocolError
from v2.host.transport import BufferedBackend, tile_shape


class CountingStream:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


class CountingLink:
    """Returns dummy bits exclusively for packet/layout assertions."""
    def __init__(self, info=b"ASR2" + struct.pack("<II", 2, 32768)):
        self.info = info
        self.stream = CountingStream()
        self.commands, self.calls = Counter(), []
        self.bytes_sent = self.bytes_received = 0

    def request(self, opcode, payload=b"", flags=0):
        self.calls.append((opcode, bytes(payload), flags))
        self.commands[opcode] += 1
        self.bytes_sent += 10 + len(payload)
        if opcode == 0x40:
            response = self.info
        elif opcode == 0x41:
            response = b""
        elif opcode == 0x42:
            _, count = struct.unpack("<HH", payload)
            response = bytes(count*4)
        elif opcode in (0x43, 0x44, 0x45):
            response = bytes(5)
        else:
            raise AssertionError(f"unexpected opcode {opcode}")
        self.bytes_received += 10 + len(response)
        return response


class TransportContractTests(unittest.TestCase):
    def setUp(self):
        self.link = CountingLink()
        self.backend = BufferedBackend(self.link)

    def tearDown(self):
        self.backend.close()

    def test_info_mismatch_closes_stream(self):
        for reply in (b"", b"ASR1" + bytes(8), b"ASR2" + struct.pack("<II", 3, 32768), b"ASR2" + struct.pack("<II", 2, 1)):
            link = CountingLink(reply)
            with self.assertRaises(ProtocolError):
                BufferedBackend(link)
            self.assertTrue(link.stream.closed)

    def test_memory_first_last_range(self):
        self.backend.write_words(0, [1])
        self.backend.write_words(32767, [0xffffffff])
        self.assertEqual(self.backend.read_words(32767, 1).shape, (1,))
        for base, count in ((-1, 1), (32768, 1), (32767, 2), (0, -1)):
            with self.assertRaises(ValueError):
                self.backend.read_words(base, count)

    def test_write_chunking_payload_and_read_chunking(self):
        words = np.arange(769, dtype=np.uint32)
        self.backend.write_words(100, words)
        writes = [payload for op, payload, _ in self.link.calls if op == 0x41]
        self.assertEqual([struct.unpack("<HH", p[:4]) for p in writes], [(100,255),(355,255),(610,255),(865,4)])
        np.testing.assert_array_equal(np.concatenate([np.frombuffer(p[4:], "<u4") for p in writes]), words)
        self.backend.read_words(100, 769)
        reads = [struct.unpack("<HH", p) for op,p,_ in self.link.calls if op == 0x42]
        self.assertEqual(reads, [(100,256),(356,256),(612,256),(868,1)])

    def test_alias_checks_before_packet(self):
        before = len(self.link.calls)
        for args in ((0,0,32,1,8,0),(0,0,32,0,8,1),(0,0,32,32,8,2)):
            with self.assertRaises(ValueError):
                self.backend.vec(*args)
        self.assertEqual(len(self.link.calls), before)
        self.backend.vec(0, 0, 32, 0, 8)
        self.backend.vec(0, 0, 0, 0, 8)
        self.backend.vec(0, 0, 32, 64, 8, 3)

    def test_mm_range_wide_product(self):
        before = len(self.link.calls)
        for args in ((0,32,64,65535,65535,65535),(0,32,0,1,1,1),(0,32,64,0,1,1)):
            with self.assertRaises(ValueError):
                self.backend.mm_tile(*args)
        self.assertEqual(len(self.link.calls), before)

    def test_typical_residency_and_k_preservation(self):
        self.assertEqual(tile_shape(31,64,9728), (31,64,256))
        self.assertEqual(((31+64)*256 + 2*31*64)*4, 113152)
        a = np.zeros((2,513), np.int16)
        b = np.zeros((513,3), np.int16)
        result = self.backend.matmul_i16(a,b)
        self.assertEqual(result.shape, (2,3))
        mm = [struct.unpack("<7H",p) for op,p,_ in self.link.calls if op == 0x45]
        self.assertEqual(mm, [(0,512,1280,2,3,256,0),(0,512,1280,2,3,256,1),(0,512,1280,2,3,1,1)])
        reads = [struct.unpack("<HH",p) for op,p,_ in self.link.calls if op == 0x42]
        self.assertEqual(reads, [(1280,12)])
        # No explicit C initialize/readback between K tiles.
        writes = [struct.unpack("<HH",p[:4]) for op,p,_ in self.link.calls if op == 0x41]
        self.assertTrue(all(base + count <= 1280 for base,count in writes))

    def test_bt_transpose_and_low16_transport(self):
        a = np.array([[-32768,1],[-2,32767]],np.int16)
        b = np.array([[2,-3],[4,-5]],np.int16)
        self.backend.matmul_i16(a,b)
        writes = [p for op,p,_ in self.link.calls if op == 0x41]
        np.testing.assert_array_equal(np.frombuffer(writes[0][4:],"<u4"),a.reshape(-1).view(np.uint16))
        np.testing.assert_array_equal(np.frombuffer(writes[1][4:],"<u4"),np.ascontiguousarray(b.T).reshape(-1).view(np.uint16))

    def test_batched_matrix_broadcast_layout(self):
        result = self.backend.matmul_i16(np.zeros((2,1,2,3),np.int16),np.zeros((4,3,5),np.int16))
        self.assertEqual(result.shape,(2,4,2,5))
        self.assertEqual(self.link.commands[0x45],8)

    def test_i48_two_inputs_full_range(self):
        values = np.array([-(1<<47),-1,0,(1<<47)-1],np.int64)
        self.backend.int48_to_float(values)
        writes = [p for op,p,_ in self.link.calls if op == 0x41]
        np.testing.assert_array_equal(np.frombuffer(writes[0][4:],"<u4"),[0,0xffffffff,0,0xffffffff])
        np.testing.assert_array_equal(np.frombuffer(writes[1][4:],"<u4"),[0x8000,0xffff,0,0x7fff])
        with self.assertRaises(OverflowError):
            self.backend.int48_to_float([1<<47])

    def test_quantize_and_dq_intermediate_never_read(self):
        self.backend.quantize(np.ones(32,np.float32),np.float32(.125))
        ops = [op for op,_,_ in self.link.calls]
        self.assertEqual(ops,[0x40,0x41,0x41,0x43,0x43,0x42])
        self.link.calls.clear()
        self.backend.dequantize(np.zeros(32,np.int16),np.float32(.125))
        self.assertEqual([op for op,_,_ in self.link.calls],[0x41,0x41,0x43,0x43,0x42])

    def test_scalar_shapes_and_empty_shapes(self):
        self.assertEqual(self.backend.binary("Add",np.float32(1),np.float32(2)).shape,())
        self.assertEqual(self.backend.quantize(np.float32(1),np.float32(2)).shape,())
        self.assertEqual(self.backend.int48_to_float(np.array([],np.int64)).shape,(0,))
        self.assertEqual(self.backend.binary("Add",np.empty((0,3),np.float32),np.float32(2)).shape,(0,3))

    def test_row_resident_softmax_lognorm_shapes(self):
        self.assertEqual(self.backend.softmax(np.zeros((2,3,4),np.float32),axis=1).shape,(2,3,4))
        self.assertEqual(self.backend.softmax(np.zeros((2,3,4),np.float32),axis=1,logarithmic=True).shape,(2,3,4))
        out,mean,inv=self.backend.layer_norm(np.zeros((2,3,4),np.float32),np.ones((3,4),np.float32),axis=1)
        self.assertEqual(out.shape,(2,3,4))
        self.assertEqual(mean.shape,(2,1,1))
        self.assertEqual(inv.shape,(2,1,1))


if __name__ == "__main__":
    unittest.main()
