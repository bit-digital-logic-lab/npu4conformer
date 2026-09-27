# ASR shared execution engine, protocol version 1

The host stores all model parameters and intermediate tensors. Encoder and
Decoder use the same engine. No CTC graph, reduced model, or DDR is required.
Neural arithmetic is executed by the selected backend; the serial backend
must never silently execute arithmetic on the host.

## Framing

UART is 8N1, default 115200 baud, default input clock 50 MHz. Both are build
parameters. Use stop-and-wait: send one request, wait for the complete reply.

Request: `A5 5A seq:u16 opcode:u8 flags:u8 length:u16 payload CRC:u16`.
Reply:   `5A A5 seq:u16 opcode:u8 status:u8 length:u16 payload CRC:u16`.
All multibyte integers and IEEE binary32 words are little-endian.
CRC-16/CCITT-FALSE: polynomial 0x1021, initial 0xffff, no reflection,
no final XOR. CRC covers the six header bytes starting at sequence and the
payload, not the two synchronization bytes. CRC itself is little-endian.
The maximum request/reply payload is 1024 bytes.

Statuses: 0=success, 1=CRC, 2=invalid length, 3=opcode/flags,
4=arithmetic overflow/invalid. Status 5 is reserved; UART framing errors and
truncated packets are dropped without executing and without a reply. The
receiver returns to synchronization after one second without another byte.
A failing request is not automatically retried: accumulated MAC state could
otherwise be applied twice. On a timeout, explicitly reset/restart the job.

| Opcode | Request payload | Reply payload |
| --- | --- | --- |
| 00 PING | empty, flags=0 | `41 53 52 31 01 00 00 00` (ASR1, version 1) |
| 01 MAC_CLEAR | signed48 initial accumulator | signed48 accumulator |
| 02 MAC_STEP | signed16 A, signed16 B | signed48 accumulator |
| 03 MAC_READ | empty | signed48 accumulator |
| 04 REQUANT | signed48 accumulator, signed32 multiplier, u8 shift, signed48 bias | signed16 result |
| 05 DOT | N pairs of signed16 A/B, 1<=N<=256 | signed48 accumulator |
| 20..2f SCALAR | two 32-bit operand words (8 bytes) | 32-bit result, u8 arithmetic flags |

DOT flag bit 0 clears the accumulator before its first pair; other flags
must be zero. A long dot product is split across DOT requests; first packet
uses flag=1, subsequent packets use flag=0. Partial sums stay 48-bit, with
no per-packet requantization. Each reply exposes the true partial sum.
For SCALAR, the internal operation is opcode minus 0x20:

| Internal op | Meaning |
| --- | --- |
| 0..6 | FP32 Add, Sub, Mul, Div, Sqrt, Exp, Log |
| 7 | signed32 A to FP32 RNE |
| 8 | FP32 A to signed32 RNE, saturating |
| 9..13 | Max, Less, Equal, Abs, Neg |
| 14 | signed48 `{B[15:0], A[31:0]}` to FP32 RNE |
| 15 | FP32 A to signed16 RNE, saturating, sign-extended to 32 bits |

Less/Equal return integer 0/1. Unary operations ignore B. Arithmetic flags:
bit0 invalid, bit1 divide-by-zero, bit2 overflow, bit3 underflow/FTZ,
bit4 approximate EXP/LOG; other bits zero. Bits 0..2 set reply status 4.
Normal saturation in op15 is not an arithmetic error. Subnormal inputs and
outputs are flushed to signed zero. EXP/LOG are approximations, not IEEE
correctly-rounded transcendental functions. Flags describe public inputs and
results, not every internal rounding event. NaN/Inf exceptions fail closed
in the host backend; underflow and approximation remain visible in counters.

REQUANT computes `sat16(RNE(((acc+bias)*multiplier)/2^shift))`, shift=0..127.
Bias is in accumulator units and added BEFORE multiplication. A 49-bit pre-add
and 81-bit product avoid intermediate overflow; saturation is a normal result
and has no separate response flag. This optional fixed-point helper must
not replace the original graph's Q/DQ scale sequence without validating the
numerical transformation.

Board pin locations are intentionally not invented. OOC synthesis is usable
before pins are known; bitstream generation requires a real board XDC.
