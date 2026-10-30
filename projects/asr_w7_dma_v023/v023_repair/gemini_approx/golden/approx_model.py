#!/usr/bin/env python3
"""High-precision Python golden model and numerical verification suite for approx_div_sqrt.

Provides:
- Exact IEEE-754 FP32 baseline
- Tier 0 (Low-Latency: LUT seed / PWL)
- Tier 1 (High-Throughput: LUT + 1-step Newton-Raphson, pipelined II=1)
- Tier 2 (Low-Error: LUT + 2-step Newton-Raphson)
- Edge case handling (FTZ, NaN, Inf, 0, -0, negative sqrt, epsilon=1e-6)
- INT16 QDQ code error evaluation and distribution
- LayerNorm and Softmax domain tests
"""

import struct
import math
import numpy as np
from typing import Tuple, Dict, Any, List

# Bit definitions
NAN_FP32 = 0x7fc00000
POS_INF_FP32 = 0x7f800000
NEG_INF_FP32 = 0xff800000
POS_ZERO_FP32 = 0x00000000
NEG_ZERO_FP32 = 0x80000000

# Flag bit positions matching asr_fp32_alu and INTERFACE.md
FLAG_INVALID   = 0x01  # [0] NaN, negative sqrt, 0/0, inf/inf
FLAG_DIV_BY_0  = 0x02  # [1] b == 0 in DIV, or RSQRT(+0)
FLAG_OVERFLOW  = 0x04  # [2] Exponent overflow
FLAG_UNDERFLOW = 0x08  # [3] Subnormal / FTZ
FLAG_APPROX    = 0x10  # [4] Approximate operation marker


def float_to_u32(val: float) -> int:
    return struct.unpack('>I', struct.pack('>f', float(val)))[0]


def u32_to_float(bits: int) -> float:
    return struct.unpack('>f', struct.pack('>I', bits & 0xffffffff))[0]


def is_nan(bits: int) -> bool:
    exp = (bits >> 23) & 0xff
    mant = bits & 0x7fffff
    return exp == 0xff and mant != 0


def is_inf(bits: int) -> bool:
    exp = (bits >> 23) & 0xff
    mant = bits & 0x7fffff
    return exp == 0xff and mant == 0


def is_zero(bits: int) -> bool:
    return (bits & 0x7fffffff) == 0


def is_subnormal(bits: int) -> bool:
    exp = (bits >> 23) & 0xff
    mant = bits & 0x7fffff
    return exp == 0 and mant != 0


def ftz(bits: int) -> Tuple[int, bool]:
    """Flush to signed zero if subnormal."""
    if is_subnormal(bits):
        sign = bits & 0x80000000
        return sign, True
    return bits, False


def pack_fp32(sign: int, exp: int, mant23: int) -> int:
    """Pack IEEE-754 binary32."""
    if exp <= 0:
        return (sign << 31)  # FTZ to zero
    if exp >= 255:
        return (sign << 31) | 0x7f800000  # Inf
    return (sign << 31) | ((exp & 0xff) << 23) | (mant23 & 0x7fffff)


# -----------------------------------------------------------------------------
# Precomputed Lookup Tables (7-bit / 8-bit indexing for hardware synthesizability)
# -----------------------------------------------------------------------------
# Reciprocal table: 128 entries for mantissa in [1.0, 2.0)
# Index is mantissa[22:16].
# Value: seed for 1.0 / (1.0 + (index + 0.5)/128.0)
# Scaled to Q15 or Q24 for fixed-point integer DSP arithmetic.
RECIP_LUT_ENTRIES = 128
RECIP_LUT = []
for i in range(RECIP_LUT_ENTRIES):
    # Midpoint of bin: x = 1.0 + (i + 0.5) / 128.0
    x = 1.0 + (i + 0.5) / float(RECIP_LUT_ENTRIES)
    y = 1.0 / x  # y in (0.5, 1.0]
    # Store mantissa in Q16: y_val in [32768, 65536)
    # y = y_val * 2^-16
    y_q16 = int(round(y * 65536.0))
    if y_q16 >= 65536:
        y_q16 = 65535
    RECIP_LUT.append(y_q16)

# RSQRT table: 256 entries for x in [1.0, 4.0)
# Index: bit 7 = exp_is_odd, bits 6:0 = mantissa[22:16]
# If exp_is_odd (b=1), x = 2.0 * (1.0 + (m + 0.5)/128.0) in [2.0, 4.0)
# If not (b=0), x = 1.0 * (1.0 + (m + 0.5)/128.0) in [1.0, 2.0)
# Seed y = 1.0 / sqrt(x) in (0.5, 1.0]
RSQRT_LUT_ENTRIES = 256
RSQRT_LUT = []
for i in range(RSQRT_LUT_ENTRIES):
    is_odd = (i >> 7) & 1
    m_idx = i & 0x7f
    scale = 2.0 if is_odd else 1.0
    x = scale * (1.0 + (m_idx + 0.5) / 128.0)
    y = 1.0 / math.sqrt(x)  # y in [0.5, 1.0]
    y_q16 = int(round(y * 65536.0))
    if y_q16 >= 65536:
        y_q16 = 65535
    RSQRT_LUT.append(y_q16)


# -----------------------------------------------------------------------------
# Exact IEEE-754 Baseline Reference
# -----------------------------------------------------------------------------
def baseline_exact(op: int, a_bits: int, b_bits: int) -> Tuple[int, int]:
    """Baseline calculation using exact FP32 arithmetic matching asr_fp32_alu."""
    a_bits, a_sub = ftz(a_bits)
    b_bits, b_sub = ftz(b_bits)
    flags = 0
    if a_sub or (op == 0 and b_sub):
        flags |= FLAG_UNDERFLOW

    a_sign = (a_bits >> 31) & 1
    b_sign = (b_bits >> 31) & 1

    if op == 0:  # DIV (A / B)
        if is_nan(a_bits) or is_nan(b_bits) or (is_zero(a_bits) and is_zero(b_bits)) or (is_inf(a_bits) and is_inf(b_bits)):
            return NAN_FP32, flags | FLAG_INVALID
        if is_zero(b_bits):
            res_sign = a_sign ^ b_sign
            res = NEG_INF_FP32 if res_sign else POS_INF_FP32
            return res, flags | (0 if is_inf(a_bits) else FLAG_DIV_BY_0)
        if is_inf(a_bits):
            res_sign = a_sign ^ b_sign
            return (NEG_INF_FP32 if res_sign else POS_INF_FP32), flags
        if is_zero(a_bits) or is_inf(b_bits):
            res_sign = a_sign ^ b_sign
            return (NEG_ZERO_FP32 if res_sign else POS_ZERO_FP32), flags

        # Finite non-zero
        fa = u32_to_float(a_bits)
        fb = u32_to_float(b_bits)
        fres = fa / fb
        rbits = float_to_u32(np.float32(fres))
        if is_inf(rbits):
            flags |= FLAG_OVERFLOW
        elif is_zero(rbits) and not (fa == 0):
            flags |= FLAG_UNDERFLOW
        return rbits, flags

    elif op == 1:  # SQRT(A)
        if is_nan(a_bits) or (a_sign and not is_zero(a_bits)):
            return NAN_FP32, flags | FLAG_INVALID
        if is_zero(a_bits) or is_inf(a_bits):
            return a_bits, flags

        fa = u32_to_float(a_bits)
        fres = math.sqrt(fa)
        rbits = float_to_u32(np.float32(fres))
        return rbits, flags

    elif op == 2:  # RSQRT(A) = 1 / sqrt(A)
        if is_nan(a_bits) or (a_sign and not is_zero(a_bits)):
            return NAN_FP32, flags | FLAG_INVALID
        if is_zero(a_bits):
            return POS_INF_FP32, flags | FLAG_DIV_BY_0
        if is_inf(a_bits):
            return POS_ZERO_FP32, flags

        fa = u32_to_float(a_bits)
        fres = 1.0 / math.sqrt(fa)
        rbits = float_to_u32(np.float32(fres))
        if is_zero(rbits):
            flags |= FLAG_UNDERFLOW
        return rbits, flags

    return NAN_FP32, FLAG_INVALID


# -----------------------------------------------------------------------------
# Approximate Core: Multi-Tier Implementation
# -----------------------------------------------------------------------------
def approx_calc(op: int, a_bits: int, b_bits: int, tier: int = 1) -> Tuple[int, int]:
    """Approximate DIV / SQRT / RSQRT with selectable tiers.

    Tier 0: Pure LUT seed / PWL (fastest, lowest logic, ~0.4% error)
    Tier 1: LUT + 1-step Newton-Raphson (~0.003% error, default)
    Tier 2: LUT + 2-step Newton-Raphson (~0.00001% error, near-exact)
    """
    a_bits, a_sub = ftz(a_bits)
    b_bits, b_sub = ftz(b_bits)
    flags = FLAG_APPROX  # Mark approximate
    if a_sub or (op == 0 and b_sub):
        flags |= FLAG_UNDERFLOW

    a_sign = (a_bits >> 31) & 1
    b_sign = (b_bits >> 31) & 1
    a_exp = (a_bits >> 23) & 0xff
    b_exp = (b_bits >> 23) & 0xff
    a_mant = a_bits & 0x7fffff
    b_mant = b_bits & 0x7fffff

    # Edge cases
    if op == 0:  # DIV
        if is_nan(a_bits) or is_nan(b_bits) or (is_zero(a_bits) and is_zero(b_bits)) or (is_inf(a_bits) and is_inf(b_bits)):
            return NAN_FP32, (flags & ~FLAG_APPROX) | FLAG_INVALID
        if is_zero(b_bits):
            res_sign = a_sign ^ b_sign
            res = NEG_INF_FP32 if res_sign else POS_INF_FP32
            return res, (flags & ~FLAG_APPROX) | (0 if is_inf(a_bits) else FLAG_DIV_BY_0)
        if is_inf(a_bits):
            res_sign = a_sign ^ b_sign
            return (NEG_INF_FP32 if res_sign else POS_INF_FP32), (flags & ~FLAG_APPROX)
        if is_zero(a_bits) or is_inf(b_bits):
            res_sign = a_sign ^ b_sign
            return (NEG_ZERO_FP32 if res_sign else POS_ZERO_FP32), (flags & ~FLAG_APPROX)

    elif op in (1, 2):  # SQRT / RSQRT
        if is_nan(a_bits) or (a_sign and not is_zero(a_bits)):
            return NAN_FP32, (flags & ~FLAG_APPROX) | FLAG_INVALID
        if is_zero(a_bits):
            if op == 1:
                return a_bits, flags & ~FLAG_APPROX
            else:  # RSQRT(0) = +inf
                return POS_INF_FP32, (flags & ~FLAG_APPROX) | FLAG_DIV_BY_0
        if is_inf(a_bits):
            if op == 1:
                return POS_INF_FP32, flags & ~FLAG_APPROX
            else:
                return POS_ZERO_FP32, flags & ~FLAG_APPROX

    # Normal computation
    if op == 0:  # DIV: A / B
        sign = a_sign ^ b_sign
        lut_idx = (b_mant >> 16) & 0x7f
        y0 = RECIP_LUT[lut_idx] / 65536.0  # y0 in (0.5, 1.0]

        # Normalized divisor x in [1.0, 2.0)
        xb = 1.0 + float(b_mant) / 8388608.0
        xa = 1.0 + float(a_mant) / 8388608.0

        if tier == 0:
            y = y0
        elif tier == 1:
            # 1 Newton-Raphson step: y1 = y0 * (2.0 - xb * y0)
            y = y0 * (2.0 - xb * y0)
        else:  # Tier 2
            y1 = y0 * (2.0 - xb * y0)
            y = y1 * (2.0 - xb * y1)

        # Result = xa * y
        res_m = xa * y  # in (0.5, 2.0)
        exp = a_exp - b_exp + 127

        if res_m >= 1.0:
            final_m = res_m - 1.0
        else:
            final_m = (res_m * 2.0) - 1.0
            exp -= 1

        mant23 = int(round(final_m * 8388608.0))
        if mant23 >= 8388608:
            mant23 = 0
            exp += 1
        elif mant23 < 0:
            mant23 = 0

        res_bits = pack_fp32(sign, exp, mant23)
        if exp >= 255:
            flags |= FLAG_OVERFLOW
        elif exp <= 0:
            flags |= FLAG_UNDERFLOW
        return res_bits, flags

    elif op == 2:  # RSQRT: 1 / sqrt(A)
        sign = 0
        unbiased_exp = a_exp - 127
        is_odd = (unbiased_exp & 1) != 0
        lut_idx = (int(is_odd) << 7) | ((a_mant >> 16) & 0x7f)
        y0 = RSQRT_LUT[lut_idx] / 65536.0  # y0 in [0.5, 1.0]

        scale = 2.0 if is_odd else 1.0
        xa = scale * (1.0 + float(a_mant) / 8388608.0)  # xa in [1.0, 4.0)

        if tier == 0:
            y = y0
        elif tier == 1:
            # 1 Newton-Raphson step: y1 = y0 * (1.5 - 0.5 * xa * y0 * y0)
            y = y0 * (1.5 - 0.5 * xa * y0 * y0)
        else:
            y1 = y0 * (1.5 - 0.5 * xa * y0 * y0)
            y = y1 * (1.5 - 0.5 * xa * y1 * y1)

        # Exponent for 1 / sqrt(A)
        # A = 2^(2k + b) * m -> 1/sqrt(A) = 2^(-k) * 1/sqrt(2^b * m)
        # where unbiased_exp = 2k + b (with b in {0, 1})
        # If unbiased_exp is negative, e.g. -1 = 2*(-1) + 1 -> k = -1, b = 1
        k = unbiased_exp >> 1  # arithmetic shift
        exp = 127 - k

        # y is in [0.5, 1.0]. Normalize to [1.0, 2.0)
        if y < 1.0:
            y_norm = y * 2.0
            exp -= 1
        else:
            y_norm = y

        final_m = y_norm - 1.0
        mant23 = int(round(final_m * 8388608.0))
        if mant23 >= 8388608:
            mant23 = 0
            exp += 1
        elif mant23 < 0:
            mant23 = 0

        res_bits = pack_fp32(sign, exp, mant23)
        if exp >= 255:
            flags |= FLAG_OVERFLOW
        elif exp <= 0:
            flags |= FLAG_UNDERFLOW
        return res_bits, flags

    elif op == 1:  # SQRT: sqrt(A) = A * (1 / sqrt(A))
        # Compute RSQRT first, then multiply by A
        rsqrt_bits, rflags = approx_calc(2, a_bits, 0, tier)
        if is_nan(rsqrt_bits) or is_zero(rsqrt_bits) or is_inf(rsqrt_bits):
            return rsqrt_bits, rflags

        fa = u32_to_float(a_bits)
        frsqrt = u32_to_float(rsqrt_bits)
        fsqrt = fa * frsqrt
        res_bits = float_to_u32(np.float32(fsqrt))
        return res_bits, rflags

    return NAN_FP32, FLAG_INVALID


# -----------------------------------------------------------------------------
# LayerNorm and Softmax Specialized Evaluation
# -----------------------------------------------------------------------------
def eval_layernorm_sample(x: np.ndarray, gamma: np.ndarray, beta: np.ndarray, eps: float = 1e-6, tier: int = 1) -> Dict[str, Any]:
    """Evaluate LayerNorm using exact vs approx RSQRT."""
    mean = np.mean(x)
    var = np.mean((x - mean) ** 2)
    v_eps = float(var + eps)

    # Exact FP32
    exact_rstd = 1.0 / math.sqrt(v_eps)
    exact_y = (x - mean) * exact_rstd * gamma + beta

    # Approx FP32
    v_bits = float_to_u32(np.float32(v_eps))
    approx_rstd_bits, _ = approx_calc(2, v_bits, 0, tier)
    approx_rstd = u32_to_float(approx_rstd_bits)
    approx_y = (x - mean) * approx_rstd * gamma + beta

    # Quantize to INT16 (scale 2^-12 as in KWT LN)
    q_exact = np.clip(np.round(exact_y * 4096.0), -32768, 32767).astype(np.int32)
    q_approx = np.clip(np.round(approx_y * 4096.0), -32768, 32767).astype(np.int32)
    code_diff = np.abs(q_approx - q_exact)

    rel_err = abs(approx_rstd - exact_rstd) / exact_rstd
    return {
        "var": var,
        "exact_rstd": exact_rstd,
        "approx_rstd": approx_rstd,
        "rstd_rel_err": rel_err,
        "max_code_diff": int(np.max(code_diff)),
        "mean_code_diff": float(np.mean(code_diff)),
        "sat_count": int(np.sum(np.abs(q_approx) == 32767))
    }


def eval_softmax_sample(scores: np.ndarray, tier: int = 1) -> Dict[str, Any]:
    """Evaluate Softmax using exact vs approx DIV."""
    max_s = np.max(scores)
    exp_s = np.exp(scores - max_s)
    sum_exp = float(np.sum(exp_s))

    # Exact
    exact_p = exp_s / sum_exp

    # Approx DIV
    sum_bits = float_to_u32(np.float32(sum_exp))
    recip_bits, _ = approx_calc(0, float_to_u32(1.0), sum_bits, tier)
    approx_recip = u32_to_float(recip_bits)
    approx_p = exp_s * approx_recip

    # Quantize to UINT16 (1.0 = 65535)
    q_exact = np.clip(np.round(exact_p * 65535.0), 0, 65535).astype(np.int32)
    q_approx = np.clip(np.round(approx_p * 65535.0), 0, 65535).astype(np.int32)
    code_diff = np.abs(q_approx - q_exact)

    return {
        "sum_exp": sum_exp,
        "max_p_diff": float(np.max(np.abs(approx_p - exact_p))),
        "max_code_diff": int(np.max(code_diff)),
        "mean_code_diff": float(np.mean(code_diff)),
        "sum_p_approx": float(np.sum(approx_p))
    }
