"""At-most-once V4.0 UDP transport for the unchanged frozen V2 backend.

No socket is opened at import. One batch is outstanding; only the exact same
session/sequence/datagram may be retried. A failed/uncertain session is poisoned,
never transparently reopened. The FPGA must implement PROTOCOL_V4.md dedup.
"""
from __future__ import annotations
import binascii
from collections import Counter
import secrets
import socket
import struct
import time
import numpy as np
from frozen_imports import require_frozen_modules

v1, v2, _ = require_frozen_modules()
ProtocolError = v1.ProtocolError
MAX_BODY = 1382
MAX_COMMANDS = 64
PORT = 49152
HEADER = struct.Struct('<4sIIBBH')
HELLO, EXEC, CLOSE = 0, 1, 2


def crc16(data):
    return binascii.crc_hqx(data, 0xffff)


def encode_packet(session, sequence, kind, body=b'', status=0):
    body = bytes(body)
    if not 0 < session <= 0xffffffff or not 0 <= sequence <= 0xffffffff:
        raise ValueError('session must be nonzero u32; sequence must be u32')
    if not 0 <= kind <= 255 or not 0 <= status <= 255 or len(body) > MAX_BODY:
        raise ValueError('invalid V4 header or payload size')
    packet = HEADER.pack(b'ASR4', session, sequence, kind, status, len(body)) + body
    return packet + struct.pack('<H', crc16(packet))


def decode_packet(packet):
    if len(packet) < 18 or len(packet) > MAX_BODY + 18:
        raise ProtocolError('V4 datagram size invalid')
    magic, session, sequence, kind, status, size = HEADER.unpack_from(packet)
    if magic != b'ASR4' or size > MAX_BODY or len(packet) != size + 18:
        raise ProtocolError('V4 header/length mismatch')
    if crc16(packet[:-2]) != struct.unpack_from('<H', packet, len(packet)-2)[0]:
        raise ProtocolError('V4 CRC mismatch')
    return session, sequence, kind, status, bytes(packet[16:-2])


def encode_inner(seq, opcode, payload=b'', flags=0, magic=b'\xa5\x5a'):
    payload = bytes(payload)
    if len(payload) > 1024 or not 0 <= opcode <= 255 or not 0 <= flags <= 255:
        raise ValueError('invalid frozen V2 command')
    body = struct.pack('<HBBH', seq & 0xffff, opcode, flags, len(payload)) + payload
    return magic + body + struct.pack('<H', crc16(body))


def reply_bound(opcode, payload):
    """Full V2 reply length for every operation used by the frozen backend."""
    if opcode == 0:
        return 18
    if opcode in (0x40,0x4f):
        return 22
    if opcode == 0x41:
        if len(payload) < 4 or len(payload) != 4 + 4*struct.unpack_from('<H', payload, 2)[0]:
            raise ValueError('WRITE payload format')
        return 10
    if opcode == 0x42:
        if len(payload) != 4:
            raise ValueError('READ payload format')
        count = struct.unpack_from('<H', payload, 2)[0]
        if not 1 <= count <= 256:
            raise ValueError('READ count must be 1..256')
        return 10 + 4*count
    if opcode in (0x43, 0x44, 0x45, 0x46, 0x47, 0x48) or 0x20 <= opcode <= 0x2f:
        return 15
    raise ValueError(f'Opcode 0x{opcode:02x} is not in the V4 frozen V2 contract')


class EthernetLink:
    def __init__(self, sock, timeout=5.0, retries=2, session=None, deadline=None):
        if timeout <= 0 or not 0 <= retries <= 10:
            raise ValueError('invalid timeout/retries')
        self.socket = sock
        self.stream = self  # Frozen backend close/error cleanup compatibility.
        self.timeout = float(timeout)
        self.retries = int(retries)
        self.session = session if session is not None else secrets.randbelow(0xffffffff) + 1
        if not 0 < self.session <= 0xffffffff:
            raise ValueError('session must be a nonzero u32')
        self.deadline = deadline
        self.sequence = 0
        self.inner_sequence = 0
        self.active = False
        self.poisoned = False
        self.closed = False
        self.close_confirmed = False
        self.commands = Counter()
        self.bytes_sent = self.bytes_received = 0
        self.datagrams_sent = self.datagrams_received = 0
        self.retransmissions = self.discarded_datagrams = 0
        self.batches = self.max_batch_commands = 0

    def _check_open(self):
        if self.closed or self.poisoned:
            raise ProtocolError('Ethernet session closed or uncertain; do not replay stateful work')
        if self.deadline is not None and time.perf_counter() >= self.deadline:
            raise TimeoutError('Global Ethernet deadline expired')

    def exchange(self, kind, body=b''):
        self._check_open()
        if kind == HELLO:
            if self.active or self.sequence != 0:
                raise ProtocolError('No re-HELLO within an existing session')
        elif kind not in (EXEC, CLOSE) or not self.active:
            raise ProtocolError('HELLO must establish the session before execution')
        if self.sequence > 0xffffffff:
            raise ProtocolError('Sequence exhausted; explicit new job/session required')
        sequence = self.sequence
        packet = encode_packet(self.session, sequence, kind, body)
        sent_any = False
        try:
            for attempt in range(self.retries + 1):
                self._check_open()
                sent_any = True
                count = self.socket.send(packet)
                if count != len(packet):
                    raise ProtocolError('Partial UDP send; execution state uncertain')
                self.bytes_sent += count
                self.datagrams_sent += 1
                self.retransmissions += int(attempt != 0)
                until = time.perf_counter() + self.timeout
                if self.deadline is not None:
                    until = min(until, self.deadline)
                while True:
                    remaining = until - time.perf_counter()
                    if remaining <= 0:
                        break
                    self.socket.settimeout(remaining)
                    try:
                        received = self.socket.recv(2048)
                    except socket.timeout:
                        break
                    self.bytes_received += len(received)
                    self.datagrams_received += 1
                    try:
                        rs, rq, rk, status, data = decode_packet(received)
                    except ProtocolError:
                        self.discarded_datagrams += 1
                        continue
                    if rs != self.session or rq < sequence:
                        self.discarded_datagrams += 1
                        continue
                    if rq != sequence or rk != kind | 0x80:
                        raise ProtocolError('Unexpected future sequence or response kind')
                    if status:
                        raise ProtocolError(f'V4 transport status={status}; session not reopened')
                    self.sequence += 1
                    return data
            raise TimeoutError('UDP response missing after identical-packet retries; job state uncertain')
        except BaseException:
            if sent_any:
                self.poisoned = True
            raise

    def hello(self):
        data = self.exchange(HELLO)
        if data != struct.pack('<4sIII', b'ASR4', 4, 32768, MAX_BODY):
            self.poisoned = True
            raise ProtocolError(f'Unsupported V4 HELLO: {data!r}')
        self.active = True
        return data

    def request_many(self, commands):
        """commands: (opcode, payload[, flags[, allow_arithmetic]]), in order."""
        if not 1 <= len(commands) <= MAX_COMMANDS:
            raise ValueError('A batch requires 1..64 commands')
        frames, expected, bound = [], [], 0
        next_inner = self.inner_sequence
        for command in commands:
            if not 2 <= len(command) <= 4:
                raise ValueError('Invalid command tuple')
            op, data = command[:2]
            flags = command[2] if len(command) >= 3 else 0
            arithmetic = command[3] if len(command) >= 4 else False
            frame = encode_inner(next_inner, op, data, flags)
            bound += reply_bound(op, data)
            frames.append(frame)
            expected.append((next_inner, op, arithmetic))
            next_inner = (next_inner + 1) & 0xffff
        body = b''.join(frames)
        if len(body) > MAX_BODY or bound > MAX_BODY:
            raise ValueError('Batch exceeds request or response MTU budget')
        response = self.exchange(EXEC, body)
        self.inner_sequence = next_inner
        self.batches += 1
        self.max_batch_commands = max(self.max_batch_commands, len(commands))
        replies, errors, cursor = [], [], 0
        try:
            for seq, op, allow_arithmetic in expected:
                if len(response) - cursor < 10 or response[cursor:cursor+2] != b'\x5a\xa5':
                    raise ProtocolError('Frozen V2 reply sync/size mismatch')
                rseq, rop, status, size = struct.unpack_from('<HBBH', response, cursor+2)
                end = cursor + 10 + size
                if size > 1024 or end > len(response):
                    raise ProtocolError('Frozen V2 reply length mismatch')
                if crc16(response[cursor+2:end-2]) != struct.unpack_from('<H', response, end-2)[0]:
                    raise ProtocolError('Frozen V2 reply CRC mismatch')
                if (rseq, rop) != (seq, op):
                    raise ProtocolError('Frozen V2 reply command ID mismatch')
                self.commands[op] += 1
                if status and not (allow_arithmetic and status == 4):
                    errors.append(f'opcode=0x{op:02x} status={status}')
                replies.append(response[cursor+8:end-2])
                cursor = end
            if cursor != len(response):
                raise ProtocolError('Unexpected trailing V2 reply bytes')
            if errors:
                raise ProtocolError('Frozen V2 execution rejected: ' + '; '.join(errors))
        except BaseException:
            self.poisoned = True
            raise
        return replies

    def request(self, opcode, payload=b'', flags=0, allow_arithmetic=False):
        return self.request_many([(opcode, payload, flags, allow_arithmetic)])[0]

    def ping(self):
        result = self.request(0)
        if result != b'ASR1\x01\x00\x00\x00':
            self.poisoned = True
            raise ProtocolError('Frozen V2 PING identity mismatch')
        return result

    def report(self):
        return dict(transport='udp-v4', session=self.session, next_sequence=self.sequence,
                    active=self.active, poisoned=self.poisoned, closed=self.closed,
                    close_confirmed=self.close_confirmed, one_outstanding_batch=True,
                    batches=self.batches, max_batch_commands=self.max_batch_commands,
                    datagrams_sent=self.datagrams_sent, datagrams_received=self.datagrams_received,
                    retransmissions=self.retransmissions, discarded_datagrams=self.discarded_datagrams,
                    bytes_sent=self.bytes_sent, bytes_received=self.bytes_received)

    def close(self):
        if self.closed:
            return
        try:
            if self.active and not self.poisoned:
                result = self.exchange(CLOSE)
                if result:
                    self.poisoned = True
                else:
                    self.close_confirmed = True
        except (OSError, ProtocolError, TimeoutError):
            self.poisoned = True  # Cleanup does not turn a successful run into silent re-execution.
        finally:
            self.active = False
            self.closed = True
            self.socket.close()


def open_link(host='169.254.35.4', port=PORT, *, local_host='169.254.147.66',
              timeout=5.0, retries=2, deadline=None):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024*1024)
        sock.bind((local_host, 0))
        sock.connect((host, port))  # OS filters replies by peer IP and UDP port.
        link = EthernetLink(sock, timeout, retries, deadline=deadline)
        link.hello()
        link.ping()
        return link
    except BaseException:
        sock.close()
        raise


class EthernetBackend(v2.BufferedBackend):
    """Frozen V2 arithmetic, with bounded pairwise SRAM transfers over UDP."""
    name = 'hardware-v4-ethernet'

    def write_words(self, base, values):
        words = np.asarray(values, dtype='<u4').reshape(-1)
        self._range(base, words.size)
        for batch_start in range(0, words.size, 336):
            count = min(336, words.size-batch_start)
            chunks = []
            width = 255 if count <= 255 else 168
            for offset in range(0, count, width):
                start = batch_start + offset
                chunk = words[start:start+min(width, count-offset)]
                chunks.append((0x41, struct.pack('<HH', int(base+start), chunk.size) + chunk.tobytes()))
            if any(self.link.request_many(chunks)):
                raise ProtocolError('WRITE response must be empty')

    def read_words(self, base, count):
        self._range(base, count)
        words = np.empty(count, np.uint32)
        for batch_start in range(0, count, 336):
            size = min(336, count-batch_start)
            width = 256 if size <= 256 else 168
            commands, spans = [], []
            for offset in range(0, size, width):
                start, take = batch_start+offset, min(width, size-offset)
                commands.append((0x42, struct.pack('<HH', int(base+start), take)))
                spans.append((start, take))
            for reply, (start, take) in zip(self.link.request_many(commands), spans):
                if len(reply) != take*4:
                    raise ProtocolError('READ reply length mismatch')
                words[start:start+take] = np.frombuffer(reply, dtype='<u4')
        return words

    def report(self):
        result = super().report()
        result['ethernet'] = self.link.report()
        result['numerical_backend'] = 'unmodified frozen V2; Ethernet write/read overrides only'
        result['max_transfer_words_per_batch'] = 336
        return result
