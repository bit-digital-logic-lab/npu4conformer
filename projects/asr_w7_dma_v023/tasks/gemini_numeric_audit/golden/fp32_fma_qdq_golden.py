#!/usr/bin/env python3
"""
fp32_fma_qdq_golden.py
Independent reference for FP32 arithmetic, FMA (Fused Multiply-Add),
FTZ (Flush-To-Zero), RNE (Round-to-Nearest-Even), and QDQ conversions.
Uses true IEEE 754 arithmetic with single-rounding fused multiply-add via libm fmaf.
"""

import struct
import math
import ctypes

# Bind glibc C99 standard fmaf (single-precision fused multiply-add)
_libm = ctypes.CDLL('libm.so.6')
_libm.fmaf.restype = ctypes.c_float
_libm.fmaf.argtypes = [ctypes.c_float, ctypes.c_float, ctypes.c_float]

def float32_to_bits(f: float) -> int:
    return struct.unpack('>I', struct.pack('>f', f))[0]

def bits_to_float32(b: int) -> float:
    return struct.unpack('>f', struct.pack('>I', b & 0xFFFFFFFF))[0]

def ftz_float32(val: float) -> float:
    """Flushes denormal / subnormal inputs/outputs to signed zero."""
    bits = float32_to_bits(val)
    exp = (bits >> 23) & 0xFF
    if exp == 0:
        sign = bits & 0x80000000
        return bits_to_float32(sign)
    return val

def exact_fma(a: float, b: float, c: float, ftz: bool = True) -> float:
    """
    Computes true fused multiply-add: (a * b + c) with a SINGLE rounding.
    Applies FTZ if ftz is True.
    """
    a_f = ftz_float32(a) if ftz else a
    b_f = ftz_float32(b) if ftz else b
    c_f = ftz_float32(c) if ftz else c
    
    res = _libm.fmaf(ctypes.c_float(a_f), ctypes.c_float(b_f), ctypes.c_float(c_f))
    if ftz:
        res = ftz_float32(res)
    return res

def non_fused_mul_add(a: float, b: float, c: float) -> float:
    """Standard non-fused (mul with round, then add with round) for comparison."""
    prod = bits_to_float32(float32_to_bits(a * b))
    res = bits_to_float32(float32_to_bits(prod + c))
    return res

def i48_to_f32(val_i48: int) -> float:
    """
    Converts 48-bit signed integer to float32 with RNE rounding.
    Matches asr_fp32_alu.sv op 14 (I48_F32).
    """
    assert -(1 << 47) <= val_i48 < (1 << 47), f"Out of int48 range: {val_i48}"
    return bits_to_float32(float32_to_bits(float(val_i48)))

def f32_to_i16(val_f32: float) -> int:
    """
    Converts float32 to signed 16-bit integer with RNE rounding and saturation [-32768, 32767].
    Matches asr_fp32_alu.sv op 15 (F32_I16).
    """
    f = ftz_float32(val_f32)
    if math.isnan(f):
        return 0
    rounded = round(f)
    if rounded > 32767:
        return 32767
    elif rounded < -32768:
        return -32768
    return int(rounded)

if __name__ == "__main__":
    print("Testing FMA vs non-fused mul-add differentiation...")
    # Known classic cancellation test: (1 + 2^-23) * (1 - 2^-23) - 1 = -2^-46
    a = bits_to_float32(float32_to_bits(1.0 + 2**-23))
    b = bits_to_float32(float32_to_bits(1.0 - 2**-23))
    c = -1.0
    
    fused_res = exact_fma(a, b, c, ftz=False)
    non_fused_res = non_fused_mul_add(a, b, c)
    
    print(f"a = {a:0.10f}, b = {b:0.10f}, c = {c}")
    print(f"Fused FMA result     : {fused_res} (bits: 0x{float32_to_bits(fused_res):08x})")
    print(f"Non-fused Mul+Add    : {non_fused_res} (bits: 0x{float32_to_bits(non_fused_res):08x})")
    assert fused_res != non_fused_res, "Fused FMA must differ from non-fused mul-add on cancellation test!"
    assert float32_to_bits(fused_res) == 0xa8800000, f"Expected 0xa8800000 (-2^-46), got 0x{float32_to_bits(fused_res):08x}"
    print("FMA numerical golden verified!")
