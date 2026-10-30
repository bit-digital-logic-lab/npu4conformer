#!/usr/bin/env python3
"""
Independent Python Integer Golden Model for pe_direct_v020 and its pipeline variants.
Preserves exact W7p8 / A16 / C48 numeric semantics, positions/clip saturation,
and INT48 2's complement wrap-around accumulation.
"""

def compute_pe_single(a_in: int, w_in: int, positions: int, clip: int) -> int:
    """
    Computes single-product product2 (32-bit signed) matching pe_direct_v020.
    a_in: 16-bit signed integer (-32768 .. 32767) or unsigned uint16 (0 .. 65535)
    w_in: 7-bit unsigned integer (0 .. 127)
    positions: 16-bit unsigned (four 4-bit shift amounts)
    clip: 0 or 1
    Returns: product2 as a 32-bit signed integer (-2^31 .. 2^31 - 1)
    """
    # 1. Unpack A16
    a_u16 = a_in & 0xFFFF
    a_sign = (a_u16 >> 15) & 1
    if a_sign:
        mag0 = (~a_u16 + 1) & 0xFFFF  # In Verilog: ~a_in + 16'd1
    else:
        mag0 = a_u16

    # 2. Unpack W7 and positions
    w_u7 = w_in & 0x7F
    w_sign = (w_u7 >> 6) & 1
    w_j = (w_u7 >> 4) & 0x3  # w_in[5:4]
    w_m = w_u7 & 0xF        # w_in[3:0]

    shift_amount = (positions >> (w_j * 4)) & 0xF
    saturated = 1 if (clip and (shift_amount == 12) and (w_m >= 8)) else 0

    m0 = 8 if saturated else w_m
    p0 = shift_amount
    neg0 = a_sign ^ w_sign
    sat0 = saturated

    # Stage 1: raw product (20-bit)
    raw_product = (mag0 * m0) & 0xFFFFF

    # Stage 2: aligned, magnitude, product2
    aligned = (raw_product << p0) & 0xFFFFFFFF  # 32-bit shift
    sat_offset = mag0 if sat0 else 0
    magnitude = (aligned - sat_offset) & 0xFFFFFFFF

    # product2 = neg1 ? -$signed(magnitude) : $signed(magnitude)
    # Convert magnitude (uint32) to signed int32
    if magnitude >= 0x80000000:
        signed_mag = magnitude - 0x100000000
    else:
        signed_mag = magnitude

    if neg0:
        # In Verilog: -$signed(magnitude) is -(signed_mag) mod 2^32
        prod32 = (-signed_mag)
        # convert to signed 32-bit range
        prod32 = ((prod32 + 0x80000000) & 0xFFFFFFFF) - 0x80000000
    else:
        prod32 = signed_mag

    return prod32

def accumulate_c48(current_sum: int, prod32: int) -> int:
    """
    Accumulates a 32-bit signed product into 48-bit signed accumulator with INT48 wrap-around.
    Returns: new 48-bit signed integer (-2^47 .. 2^47 - 1)
    """
    # Sign extend prod32 to 48-bit
    new_sum = current_sum + prod32
    # 48-bit 2's complement wrap
    u48 = new_sum & 0xFFFFFFFFFFFF
    if u48 >= 0x800000000000:
        return u48 - 0x1000000000000
    else:
        return u48

if __name__ == "__main__":
    import random
    print("Testing Python Golden Model for PE...")
    # Corner test cases
    # Test case 1: -32768 with saturated clip
    pos = 0xC000  # p3 = 12
    p = compute_pe_single(-32768, 0x3F, pos, 1) # w_in = 0011 1111 -> j=3, m=15, sign=0. saturated!
    print(f"Corner 1 (-32768, w=0x3F, p=12, clip=1): {p}")

    # Test case 2: -32768 with sign=1
    p2 = compute_pe_single(-32768, 0x7F, pos, 1) # w_in = 0111 1111 -> j=3, m=15, sign=1. saturated!
    print(f"Corner 2 (-32768, w=0x7F, p=12, clip=1): {p2}")

    # Exhaustive test of all 128 W7 codes for multiple A values
    print("Running initial sanity check...")
    for a in [0, 1, -1, 32767, -32767, -32768, 1234, -5678]:
        for clip in [0, 1]:
            for pos_val in [0, 1, 4, 8, 12]:
                positions = (pos_val) | (pos_val << 4) | (pos_val << 8) | (pos_val << 12)
                for w in range(128):
                    prod = compute_pe_single(a, w, positions, clip)
    print("Initial sanity check passed!")
