#!/usr/bin/env python3
"""
golden_fusion.py
Independent Python reference generator and numerical contract comparator for
V0.23 Matrix-to-Stream Epilogue Fusion.

Contracts implemented:
1. Matrix integer multiplication (A16 * W7 -> INT48 accumulator)
2. FMA Single-Rounding Gold:
   I48 -> F32 (RNE) -> FMA (F32 * scale + bias with 1-step rounding RNE) -> ReLU -> F32 to INT16 (RNE)
3. Unfused Baseline Double-Rounding Gold:
   I48 -> F32 (RNE) -> MUL (F32 * scale, RNE) -> ADD (+ bias, RNE) -> ReLU -> F32 to INT16 (RNE)
4. Numerical difference analysis separating the two contracts.
"""

import struct
import numpy as np
from pathlib import Path

def f32_to_hex(f):
    return f"{struct.unpack('>I', struct.pack('>f', float(f)))[0]:08x}"

def hex_to_f32(h):
    val = int(h, 16) if isinstance(h, str) else int(h)
    return struct.unpack('>f', struct.pack('>I', val))[0]

def i48_to_f32(val_i48):
    """Exact conversion of INT48 to IEEE-754 float32 using Round-to-Nearest-Even."""
    return np.float32(float(val_i48))

def golden_fma_step(val_i48, scale_f32, bias_f32, relu_en=False):
    """
    IEEE-754 Single-Rounding FMA Contract.
    Intermediate product has infinite precision, rounded ONCE during addition to float32.
    """
    x = float(i48_to_f32(val_i48))
    s = float(scale_f32)
    b = float(bias_f32)
    # 1-step infinite precision product + add, rounded once to float32
    fma_val = np.float32(x * s + b)
    if relu_en:
        fma_val = max(np.float32(0.0), fma_val)
    # Float32 to INT16 with RNE rounding and saturation
    # IEEE RNE rounding:
    rounded = np.rint(fma_val)
    clipped = np.clip(rounded, -32768, 32767)
    return fma_val, int(clipped)

def golden_unfused_step(val_i48, scale_f32, bias_f32, relu_en=False):
    """
    Unfused Double-Rounding Contract.
    Separate MUL stage with float32 rounding, followed by ADD stage with float32 rounding.
    """
    x = float(i48_to_f32(val_i48))
    s = float(scale_f32)
    b = float(bias_f32)
    # Rounding 1: multiply
    mul_val = np.float32(x * s)
    # Rounding 2: add
    add_val = np.float32(float(mul_val) + b)
    if relu_en:
        add_val = max(np.float32(0.0), add_val)
    rounded = np.rint(add_val)
    clipped = np.clip(rounded, -32768, 32767)
    return add_val, int(clipped)

def generate_matrix_fixture(M=32, N=32, K=32, seed=42):
    """Generates matrix A16 and W7 fixtures and computes reference C48."""
    rng = np.random.RandomState(seed)
    # A16: int16 values
    A = rng.randint(-1000, 1000, size=(M, K), dtype=np.int16)
    # W7: int8 values within 7-bit signed range [-64, 63]
    W = rng.randint(-64, 63, size=(K, N), dtype=np.int8)

    # C48: exact integer dot product
    C48 = np.matmul(A.astype(np.int64), W.astype(np.int64))
    return A, W, C48

def generate_stream_vectors(out_dir, num_beats=256, scale_hex=0x3f800000, bias_hex=0x00000000, seed=123):
    """Generates 4-lane C48 stream vectors and corresponding golden results."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.RandomState(seed)

    scale_f32 = hex_to_f32(scale_hex)
    bias_f32 = hex_to_f32(bias_hex)

    vec_lines = []
    gold_fma_lines = []
    gold_unfused_lines = []
    contract_diffs = []

    for beat in range(num_beats):
        last = 1 if beat == num_beats - 1 else 0
        tag = beat & 0xffff
        lanes_c48 = [int(rng.randint(-500000, 500000)) for _ in range(4)]

        # Save input vector: l0, l1, l2, l3, tag, last
        # c48 in 12 hex digits (48-bit 2's complement)
        l_hex = [f"{c & 0xffffffffffff:012x}" for c in lanes_c48]
        vec_lines.append(f"{l_hex[0]} {l_hex[1]} {l_hex[2]} {l_hex[3]} {tag:04x} {last}")

        # Compute goldens
        fma_i16 = []
        unfused_i16 = []
        for lane_idx, c in enumerate(lanes_c48):
            f_val, f_int = golden_fma_step(c, scale_f32, bias_f32)
            u_val, u_int = golden_unfused_step(c, scale_f32, bias_f32)
            fma_i16.append(f_int)
            unfused_i16.append(u_int)
            if f_int != u_int:
                contract_diffs.append({
                    "beat": beat,
                    "lane": lane_idx,
                    "c48": c,
                    "fma_f32": f32_to_hex(f_val),
                    "fma_i16": f_int,
                    "unfused_f32": f32_to_hex(u_val),
                    "unfused_i16": u_int
                })

        # Format INT16 in 4 hex digits
        f_hex = [f"{v & 0xffff:04x}" for v in fma_i16]
        u_hex = [f"{v & 0xffff:04x}" for v in unfused_i16]
        gold_fma_lines.append(f"{f_hex[0]} {f_hex[1]} {f_hex[2]} {f_hex[3]} {tag:04x} {last}")
        gold_unfused_lines.append(f"{u_hex[0]} {u_hex[1]} {u_hex[2]} {u_hex[3]} {tag:04x} {last}")

    return vec_lines, gold_fma_lines, gold_unfused_lines, contract_diffs

if __name__ == '__main__':
    import json
    p = Path('/home/yang/Desktop/项目/v023_repair/gemini_closeout_fusion/vectors')
    p.mkdir(parents=True, exist_ok=True)

    # 1. Standard test: 256 beats (1024 elements), power-of-two scale/bias
    v1, gf1, gu1, cd1 = generate_stream_vectors(p, num_beats=256, scale_hex=0x3a800000, bias_hex=0x3f000000, seed=101) # scale=2^-10, bias=0.5
    (p / 'stream_pow2.vec').write_text('\n'.join(v1) + '\n')
    (p / 'gold_fma_pow2.vec').write_text('\n'.join(gf1) + '\n')
    (p / 'gold_unfused_pow2.vec').write_text('\n'.join(gu1) + '\n')

    # 2. Non-trivial test: 256 beats, scale=0x3f800003, bias=0x3eaaaaab
    v2, gf2, gu2, cd2 = generate_stream_vectors(p, num_beats=256, scale_hex=0x3f800003, bias_hex=0x3eaaaaab, seed=202)
    (p / 'stream_nontrivial.vec').write_text('\n'.join(v2) + '\n')
    (p / 'gold_fma_nontrivial.vec').write_text('\n'.join(gf2) + '\n')
    (p / 'gold_unfused_nontrivial.vec').write_text('\n'.join(gu2) + '\n')
    (p / 'contract_diffs_nontrivial.json').write_text(json.dumps(cd2, indent=2))

    # 3. Odd tail test: 7 beats (28 elements -> odd packed beats)
    v3, gf3, gu3, cd3 = generate_stream_vectors(p, num_beats=7, scale_hex=0x3f800000, bias_hex=0x00000000, seed=303)
    (p / 'stream_oddtail7.vec').write_text('\n'.join(v3) + '\n')
    (p / 'gold_fma_oddtail7.vec').write_text('\n'.join(gf3) + '\n')

    print(f"Generated test vectors. Non-trivial contract differences: {len(cd2)} out of 1024 elements.")
