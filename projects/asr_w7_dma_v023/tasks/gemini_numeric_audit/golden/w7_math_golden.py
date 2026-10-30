#!/usr/bin/env python3
"""
w7_math_golden.py
Independent mathematical reference for W7(S/J/M) * A16 -> C48 integer arithmetic.
Derived from first-principles integer math & quantization specifications,
NOT copied from RTL implementation.
"""

import sys
from typing import Tuple, List

def decode_w7_spec(w_code: int, p_val: int, clip: bool) -> Tuple[int, int, bool]:
    """
    Decodes 7-bit W code according to neural network weight format specification.
    Bits [6]: Sign (0 = positive, 1 = negative)
    Bits [5:4]: Position index (already looked up as p_val in [0..15])
    Bits [3:0]: Magnitude multiplier M in [0..15]
    
    Returns: (signed_effective_weight, raw_magnitude, is_clipped)
    """
    assert 0 <= w_code <= 127, f"Invalid W7 code: {w_code}"
    assert 0 <= p_val <= 15, f"Invalid position: {p_val}"
    
    sign = (w_code >> 6) & 1
    m = w_code & 15
    raw_mag = m << p_val  # Exact integer scale
    
    # Mathematical clipping contract:
    # 16-bit signed weights are bounded within [-32767, +32767] if clip is active.
    if clip and raw_mag > 32767:
        eff_mag = 32767
        clipped = True
    else:
        eff_mag = raw_mag
        clipped = False
        
    signed_w = -eff_mag if sign else eff_mag
    return signed_w, raw_mag, clipped

def compute_product_pure_math(a_in: int, w_code: int, p_val: int, clip: bool) -> int:
    """
    Computes exact mathematical product: a_in * decode_w7_spec(...)
    a_in: signed 16-bit integer [-32768, 32767]
    """
    assert -32768 <= a_in <= 32767, f"Invalid A16 input: {a_in}"
    signed_w, _, _ = decode_w7_spec(w_code, p_val, clip)
    return a_in * signed_w

def compute_c48_accum(acc_prev: int, prod_val: int) -> int:
    """
    Computes 48-bit signed two's complement accumulation.
    Wraps modulo 2^48 into signed range [-2^47, 2^47 - 1].
    """
    # Cast prod_val to signed 32-bit if it was wider, then sign-extend to 48-bit
    p32 = prod_val & 0xFFFFFFFF
    if p32 & 0x80000000:
        p32_signed = p32 - 0x100000000
    else:
        p32_signed = p32
        
    total = acc_prev + p32_signed
    # Modulo 2^48
    wrapped = total % (1 << 48)
    if wrapped >= (1 << 47):
        wrapped -= (1 << 48)
    return wrapped

def rtl_model_pe(a_in: int, w_code: int, p_val: int, clip: bool) -> Tuple[int, int]:
    """
    Exact behavioral emulation of pe_direct_v020.sv arithmetic datapath.
    Returns: (signed_32bit_product, magnitude)
    """
    # Line 11: wire [3:0] p = positions[...];
    # Line 12: wire saturated = clip && p == 12 && w_in[3:0] >= 8;
    saturated = 1 if (clip and p_val == 12 and (w_code & 15) >= 8) else 0
    
    # Line 31: mag0 <= a_in[15] ? (~a_in + 16'd1) : a_in;
    u_a = a_in & 0xFFFF
    if u_a & 0x8000:
        mag0 = ((~u_a + 1) & 0xFFFF)
    else:
        mag0 = u_a
        
    # Line 32: m0 <= saturated ? 4'd8 : w_in[3:0]; p0 <= p;
    m0 = 8 if saturated else (w_code & 15)
    
    # Line 33: neg0 <= a_in[15] ^ w_in[6]; sat0 <= saturated;
    neg = ((u_a >> 15) & 1) ^ ((w_code >> 6) & 1)
    
    # Line 19: wire [19:0] raw_product = mag0 * m0;
    raw_product = (mag0 * m0) & 0xFFFFF
    
    # Line 20: wire [31:0] aligned = {12'd0, raw1} << p1;
    # Note: 32-bit shift in Verilog truncates bits shifted past bit 31
    aligned = (raw_product << p_val) & 0xFFFFFFFF
    
    # Line 21: wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);
    sub = mag0 if saturated else 0
    magnitude = (aligned - sub) & 0xFFFFFFFF
    
    # Line 36: product2 <= neg1 ? -$signed(magnitude) : $signed(magnitude);
    # Verilog $signed(magnitude) interprets 32-bit vector as two's complement signed:
    if magnitude & 0x80000000:
        signed_mag = magnitude - 0x100000000
    else:
        signed_mag = magnitude
        
    if neg:
        prod = (-signed_mag) & 0xFFFFFFFF
    else:
        prod = signed_mag & 0xFFFFFFFF
        
    if prod & 0x80000000:
        signed_prod = prod - 0x100000000
    else:
        signed_prod = prod
        
    return signed_prod, magnitude

if __name__ == "__main__":
    print("Self-testing W7 math golden definitions...")
    # Test boundary case: A = -32768, saturated clip p=12, m=8, sign=0
    a = -32768
    w = 0x28  # sign=0, j=2, m=8
    p = 12
    clip = True
    
    w_spec, raw_mag, is_clipped = decode_w7_spec(w, p, clip)
    math_p = compute_product_pure_math(a, w, p, clip)
    rtl_p, mag = rtl_model_pe(a, w, p, clip)
    
    print(f"Spec weight: {w_spec}, Clipped: {is_clipped}")
    print(f"Math product: {math_p}")
    print(f"RTL  product: {rtl_p}")
    assert math_p == rtl_p, f"Mismatch: {math_p} != {rtl_p}"
    print("W7 golden self-test PASSED!")
