#!/usr/bin/env python3
"""
golden_epilogue.py
Pure Python mathematical golden reference for Epilogue Fusion:
C48 -> I48_F32 -> FMA(scale, bias) -> ReLU -> F32_I16.

Matches the numerical semantics of asr_fp32_alu.sv (FTZ, RNE, banker's rounding,
saturation clamp) bit-for-bit.
"""

import struct
import numpy as np

def u32_to_f32(u):
    return struct.unpack('>f', struct.pack('>I', u & 0xffffffff))[0]

def f32_to_u32(f):
    return struct.unpack('>I', struct.pack('>f', f))[0]

def pack_rne(sign, exp, sig27):
    """
    sign: 0 or 1
    exp: integer exponent (with bias 127)
    sig27: 27-bit significand [26:0]
           sig[26] is hidden 1 (or 0 for zero)
           sig[25:3] are 23 mantissa bits
           sig[2] is round bit
           sig[1] is guard bit
           sig[0] is sticky bit
    """
    if sig27 == 0 or exp <= 0:
        return (sign << 31)
    
    round_bit = (sig27 >> 2) & 1
    sticky_bits = sig27 & 3
    lsb = (sig27 >> 3) & 1
    
    mant = (sig27 >> 3) & 0x7fffff
    e = exp
    
    # RNE: round to nearest even
    if round_bit and (sticky_bits != 0 or lsb != 0):
        mant += 1
        if mant == 0x800000:  # overflow into hidden bit
            mant = 0
            e += 1
            
    if e >= 255:
        # Overflow to infinity
        return (sign << 31) | 0x7f800000
    
    return (sign << 31) | ((e & 0xff) << 23) | (mant & 0x7fffff)

def i48_to_f32(val_i48):
    """
    Converts 48-bit signed integer to FP32 bit-exact with asr_fp32_alu.sv int48_float.
    """
    # Sign extend to 48-bit signed integer
    val_i48 = val_i48 & 0xffffffffffff
    if val_i48 & (1 << 47):
        sign = 1
        mag = ((~val_i48) + 1) & 0xffffffffffff
    else:
        sign = 0
        mag = val_i48

    if mag == 0:
        return 0

    # Find highest set bit (0..47)
    top = 0
    for i in range(48):
        if (mag >> i) & 1:
            top = i

    if top > 26:
        sh = top - 26
        sig = (mag >> sh) & 0x7ffffff
        sticky = 1 if (mag & ((1 << sh) - 1)) else 0
        sig |= sticky
    else:
        sig = (mag << (26 - top)) & 0x7ffffff

    exp = 127 + top
    return pack_rne(sign, exp, sig)

def f32_relu(u32_in):
    """
    ReLU on FP32 representation: max(0.0, x)
    """
    sign = (u32_in >> 31) & 1
    exp = (u32_in >> 23) & 0xff
    mant = u32_in & 0x7fffff
    if exp == 0xff and mant != 0:
        # NaN
        return 0x7fc00000
    if sign == 1 or (exp == 0 and mant == 0):
        return 0x00000000
    return u32_in

def f32_to_i16(u32_in):
    """
    Converts FP32 to INT16 with Banker's Rounding (RNE) and [-32768, 32767] clamp.
    Matches asr_fp32_alu.sv float_int32 clamped to 16 bits.
    """
    sign = (u32_in >> 31) & 1
    exp = (u32_in >> 23) & 0xff
    mant = u32_in & 0x7fffff
    
    if exp == 0xff and mant != 0:
        # NaN returns 0
        return 0

    e = exp - 127
    mant_full = (1 << 23) | mant

    if e < -1 or exp == 0:
        return 0
    elif e >= 31:
        return -32768 if sign else 32767
    else:
        if e >= 23:
            mag = mant_full << (e - 23)
        else:
            shift = 23 - e
            mag = mant_full >> shift
            discard = mant_full - (mag << shift)
            halfway = 1 << (shift - 1)
            # Banker's rounding
            if discard > halfway or (discard == halfway and (mag & 1)):
                mag += 1
                
        val = -mag if sign else mag
        
        # Clamp to INT16
        if val > 32767:
            return 32767
        elif val < -32768:
            return -32768
        return val

def epilogue_reference(c48_val, scale_f32=None, bias_f32=None, relu=False):
    """
    Full reference chain:
    c48 -> i48_to_f32 -> FMA -> (ReLU) -> f32_to_i16
    """
    f32_raw = i48_to_f32(c48_val)
    
    if scale_f32 is not None or bias_f32 is not None:
        # Numerical conversion
        f_val = u32_to_f32(f32_raw)
        scale_val = u32_to_f32(scale_f32) if scale_f32 is not None else 1.0
        bias_val = u32_to_f32(bias_f32) if bias_f32 is not None else 0.0
        f_out = f_val * scale_val + bias_val
        f32_post = f32_to_u32(f_out)
    else:
        f32_post = f32_raw
        
    if relu:
        f32_relu_out = f32_relu(f32_post)
    else:
        f32_relu_out = f32_post
        
    i16_out = f32_to_i16(f32_relu_out)
    return {
        "c48": c48_val,
        "f32_raw": f32_raw,
        "f32_post": f32_post,
        "f32_relu": f32_relu_out,
        "i16": i16_out & 0xffff
    }

if __name__ == '__main__':
    # Test cases
    test_c48 = [
        0, 1, -1, 32767, -32768, 65536, -65536,
        0x7fffffffffff, # max positive 48-bit
        0x800000000000, # min negative 48-bit (-2^47)
        100, -100, 123456789, -987654321
    ]
    print("Testing Golden Model on boundary C48 values:")
    for v in test_c48:
        res = epilogue_reference(v, relu=True)
        print(f"C48: {v:#014x} ({v:+d}) -> F32: {res['f32_raw']:#010x} -> ReLU: {res['f32_relu']:#010x} -> I16: {res['i16']:#06x} ({res['i16'] if res['i16'] < 32768 else res['i16'] - 65536:+d})")
