# V2 initial implementation contract

V1 is frozen in ../releases/v1_20260922_board_verified. No V1 file is modified.
Original weights, graph, signed INT16 products, signed48 accumulation and V1
FP32 rounding/FTZ/approximation semantics remain unchanged. No DDR.

Same framing/CRC/1024-byte payload and V1 opcodes (including ASR1 PING).
All new commands require header flags=0. Little endian. Memory has 32768
32-bit words (128 KiB). All addresses/counts below are u16 WORD units.
INT16 uses one word per element (low16 signed; upper16 ignored). A signed48
accumulator uses two words: low32, then sign-extended high16. Memory is not
initialized on reset. The host must upload all source operands before use.

| Opcode | Payload | Reply |
| --- | --- | --- |
| 40 INFO | empty | ASCII ASR2, u32 version=2, u32 memory_words=32768 |
| 41 WRITE | base:u16, count:u16, count*u32 data; count 1..255 | empty |
| 42 READ | base:u16, count:u16; count 1..256 | count*u32 data |
| 43 VEC | op:u8, mode:u8, A:u16, B:u16, D:u16, count:u16 | flags:u8, execution_cycles:u32 |
| 44 REDUCE | op:u8, reserved:u8=0, A:u16, D:u16, count:u16 | flags:u8, execution_cycles:u32 |
| 45 MM_TILE | A:u16, BT:u16, C:u16, M:u16, N:u16, K:u16, accumulate:u16 (0/1) | flags:u8, execution_cycles:u32 |

VEC op=V1 scalar internal op0..15. Mode bit0 broadcasts A[0], bit1 broadcasts
B[0]; no other bits allowed. Nonbroadcast stride is 1; D stride always 1.
Results are raw 32-bit scalar results, including integer conversions and
integer comparison 0/1. I48 conversion gets low32 from A, high16 from B.
VEC may overwrite an input only for exact same-base nonbroadcast access;
all other destination/source overlap is rejected (status2). Arithmetic flags
are ORed across elements, severe flags0..2 return status4, not silent success.

REDUCE only op0(Add)/op9(Max). Count >=1. Initialize from A[0], then operate
strictly left-to-right. D may overlap A: write result only after all reads.

MM_TILE uses row-major A[M,K], transposed B as BT[N,K], and row-major C[M,N]
with two words per result. M,N,K >=1. Dimension products/range checks use
wide intermediates; reject any out-of-range or input/output overlap before
execution. If accumulate=0 start each C element at zero; otherwise load its
existing signed48 value. Each partial sum has signed48 overflow detection.
No float conversion, scaling or requantization between K tiles. No numeric
CPU fallback. C is invalid after overflow/status4 or interrupted execution.

VEC/REDUCE/MM return cycle count for execution (excludes packet receive and
reply transmit); count is modulo 2^32. Validation errors and CRC errors must
not execute. Computation exceptions can leave partial destination results;
the host must abort the job, never automatically retry a stateful command.
Statuses retain V1 definitions; all address/length/overlap errors use status2,
unsupported op/mode/reserved/flags use status3.

Initial V2 scope: intra-operator residency. The existing ONNX scheduler still
uses host tensors between nodes. A benchmark or operator test is NOT full
Encoder/Decoder inference acceptance.
