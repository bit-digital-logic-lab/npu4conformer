#!/usr/bin/env python3
"""
fma_reference.py
Independent trusted reference model for IEEE-754 binary32 Fused Multiply-Add (FMA).
Implements:
1. Exact rational arithmetic with Round-to-Nearest-Even (RNE) without floating-point precision loss.
2. Hardware/glibc C99 libm.fmaf verification via ctypes.
3. Full handling of NaN, Inf, signed zero, subnormal/FTZ, tie-breaking, and cancellation.
"""

import sys
import struct
import ctypes
from fractions import Fraction

# C99 libm fmaf interface
_libm = ctypes.CDLL('libm.so.6')
_fmaf = _libm.fmaf
_fmaf.argtypes = [ctypes.c_float, ctypes.c_float, ctypes.c_float]
_fmaf.restype = ctypes.c_float

def u32_to_f32(u: int) -> float:
    return struct.unpack('>f', struct.pack('>I', u & 0xffffffff))[0]

def f32_to_u32(f: float) -> int:
    return struct.unpack('>I', struct.pack('>f', f))[0]

def fma_c99(u_a: int, u_b: int, u_c: int) -> int:
    """Evaluate FMA using platform C99 single-precision fmaf."""
    fa = u32_to_f32(u_a)
    fb = u32_to_f32(u_b)
    fc = u32_to_f32(u_c)
    res = _fmaf(fa, fb, fc)
    return f32_to_u32(res)

def fma_exact_rational(u_a: int, u_b: int, u_c: int, ftz: bool = True) -> int:
    """
    Evaluate FMA (a * b + c) using exact rational arithmetic with RNE.
    ftz: if True, flush subnormal inputs and subnormal outputs to signed zero.
    """
    s_a = (u_a >> 31) & 1
    e_a = (u_a >> 23) & 0xff
    m_a = u_a & 0x7fffff
    
    s_b = (u_b >> 31) & 1
    e_b = (u_b >> 23) & 0xff
    m_b = u_b & 0x7fffff
    
    s_c = (u_c >> 31) & 1
    e_c = (u_c >> 23) & 0xff
    m_c = u_c & 0x7fffff

    # 1. NaN Handling
    is_nan_a = (e_a == 255 and m_a != 0)
    is_nan_b = (e_b == 255 and m_b != 0)
    is_nan_c = (e_c == 255 and m_c != 0)
    if is_nan_a or is_nan_b or is_nan_c:
        return 0x7fc00000 # canonical quiet NaN

    # 2. Inf / Zero Handling
    is_inf_a = (e_a == 255 and m_a == 0)
    is_inf_b = (e_b == 255 and m_b == 0)
    is_inf_c = (e_c == 255 and m_c == 0)

    is_zero_a = (e_a == 0 and m_a == 0) or (ftz and e_a == 0)
    is_zero_b = (e_b == 0 and m_b == 0) or (ftz and e_b == 0)
    is_zero_c = (e_c == 0 and m_c == 0) or (ftz and e_c == 0)

    # 0 * Inf is invalid -> NaN
    if (is_inf_a and is_zero_b) or (is_zero_a and is_inf_b):
        return 0x7fc00000

    s_p = s_a ^ s_b
    is_inf_p = is_inf_a or is_inf_b
    is_zero_p = is_zero_a or is_zero_b

    # Inf + Inf with different signs -> NaN
    if is_inf_p and is_inf_c:
        if s_p != s_c:
            return 0x7fc00000
        return (s_p << 31) | 0x7f800000
    if is_inf_p:
        return (s_p << 31) | 0x7f800000
    if is_inf_c:
        return (s_c << 31) | 0x7f800000

    # Zero + Zero
    if is_zero_p and is_zero_c:
        res_s = s_p if (s_p == s_c) else 0
        return res_s << 31

    # Exact rational value extraction
    def to_rational(sign, exp, mant):
        if exp == 0:
            if mant == 0 or ftz:
                return Fraction(0)
            # subnormal
            return Fraction(((-1)**sign) * mant, 1 << 23) * Fraction(1, 1 << 126)
        # normal
        return Fraction(((-1)**sign) * (mant | 0x800000), 1 << 23) * (Fraction(2)**(exp - 127))

    val_a = to_rational(s_a, e_a, m_a)
    val_b = to_rational(s_b, e_b, m_b)
    val_c = to_rational(s_c, e_c, m_c)

    exact_res = val_a * val_b + val_c
    if exact_res == 0:
        # IEEE-754: (+0) + (-0) = +0
        return 0

    res_sign = 1 if exact_res < 0 else 0
    abs_res = abs(exact_res)

    num, den = abs_res.numerator, abs_res.denominator
    # Find E such that 2^E <= num/den < 2^(E+1)
    E = (num.bit_length() - den.bit_length()) - 1
    def p2(k):
        return (1 << k) if k >= 0 else Fraction(1, 1 << (-k))

    while den * p2(E + 1) <= num:
        E += 1
    while den * p2(E) > num:
        E -= 1

    # Check underflow / subnormals
    exp_field = E + 127
    if exp_field <= 0:
        if ftz:
            return res_sign << 31
        # Subnormal RNE representation
        # val = M_sub * 2^(-126 - 23) = M_sub * 2^(-149)
        # M_sub = abs_res * 2^149
        scaled_num = num << 149
        scaled_den = den
        M_int = scaled_num // scaled_den
        rem = scaled_num % scaled_den
        round_up = (2 * rem > scaled_den) or (2 * rem == scaled_den and (M_int & 1) == 1)
        if round_up:
            M_int += 1
        if M_int >= (1 << 23): # carried into normal
            return (res_sign << 31) | (1 << 23) | (M_int & 0x7fffff)
        elif M_int == 0:
            return res_sign << 31
        else:
            return (res_sign << 31) | (M_int & 0x7fffff)

    # Normal RNE representation
    shift = 23 - E
    if shift >= 0:
        scaled_num = num << shift
        scaled_den = den
    else:
        scaled_num = num
        scaled_den = den << (-shift)

    M_int = scaled_num // scaled_den
    rem = scaled_num % scaled_den

    round_up = False
    if 2 * rem > scaled_den:
        round_up = True
    elif 2 * rem == scaled_den:
        # Tie-break to even LSB
        round_up = (M_int & 1) == 1

    if round_up:
        M_int += 1
        if M_int == (1 << 24):
            M_int = 1 << 23
            E += 1
            exp_field = E + 127

    if exp_field >= 255:
        return (res_sign << 31) | 0x7f800000 # Overflow to Inf

    return (res_sign << 31) | (exp_field << 23) | (M_int & 0x7fffff)

if __name__ == '__main__':
    print("Testing fma_reference.py...")
    # Test 1: Acceptance counterexample probe
    probe_a = 0x3f800001
    probe_b = 0x3fc00000
    probe_c = 0x00000000
    r_exact = fma_exact_rational(probe_a, probe_b, probe_c)
    r_c = fma_c99(probe_a, probe_b, probe_c)
    assert r_exact == 0x3fc00002, f"Probe fail exact: {hex(r_exact)}"
    assert r_c == 0x3fc00002, f"Probe fail C99: {hex(r_c)}"
    print("  Test 1: Acceptance counterexample probe PASS (0x3fc00002)")

    # Test 2: FMA cancellation test from work/tests/fma_fixture
    a_canc = 0x3f800001 # 1 + 2^-23
    b_canc = 0x3f7ffffe # 1 - 2^-23
    c_canc = 0xbf800000 # -1.0
    r_exact_canc = fma_exact_rational(a_canc, b_canc, c_canc)
    r_c_canc = fma_c99(a_canc, b_canc, c_canc)
    assert r_exact_canc == 0xa8800000, f"Canc fail exact: {hex(r_exact_canc)}"
    assert r_c_canc == 0xa8800000, f"Canc fail C99: {hex(r_c_canc)}"
    print("  Test 2: FMA cancellation test PASS (0xa8800000, -2^-46)")

    # Test 3: Tie-breaking test (halfway rounding to even)
    # Construct exact halfway: 1.0 (0x3f800000) * (1.0 + 2^-24)
    # In FP32, 1.0 + 2^-24 is halfway between 1.0 and 1.0 + 2^-23.
    # LSB of 1.0 is 0 (even), so rounds down to 1.0!
    # If 1.0 + 2^-23 + 2^-24, LSB is 1 (odd), so rounds up to 1.0 + 2^-22!
    a_tie1 = 0x3f800000 # 1.0
    # 1.0 * (1.0) + 2^-24 = 1.0 + 2^-24.
    # 2^-24 is 0x33800000.
    r_tie1 = fma_exact_rational(a_tie1, 0x3f800000, 0x33800000) # 1.0 + 2^-24
    assert r_tie1 == 0x3f800000, f"Tie1 fail: {hex(r_tie1)}" # rounded down to even
    
    # 1.0000001192092896 (0x3f800001, LSB=1) + 2^-24 (0x33800000)
    # Value is 1.0 + 2^-23 + 2^-24 -> halfway between 0x3f800001 and 0x3f800002.
    # Since 0x3f800001 has LSB=1, it must round UP to 0x3f800002 (LSB=0)!
    r_tie2 = fma_exact_rational(0x3f800001, 0x3f800000, 0x33800000)
    assert r_tie2 == 0x3f800002, f"Tie2 fail: {hex(r_tie2)}"
    print("  Test 3: Tie-breaking (halfway to even) PASS")

    print("ALL REFERENCE TESTS PASSED.")
