"""Bit-exact integer datapath contract, not an ASR model executor.

The ONNX QDQ graph does not define integer bias conversion or multiplier/shift
approximation. A model compiler must derive those separately. Python integers
are used here so that the host reference has no implicit overflow semantics.
"""
from __future__ import annotations

INT16_MIN = -(1 << 15)
INT16_MAX = (1 << 15) - 1
INT48_MIN = -(1 << 47)
INT48_MAX = (1 << 47) - 1


def _signed(value: int, width: int, name: str) -> int:
    value = int(value)
    if not -(1 << (width - 1)) <= value < (1 << (width - 1)):
        raise ValueError(f"{name} does not fit signed {width} bits: {value}")
    return value


def wrap_signed(value: int, width: int) -> int:
    return ((int(value) + (1 << (width - 1))) % (1 << width)) - (1 << (width - 1))


def mac_step(accumulator: int, a: int, b: int, overflow: bool = False) -> tuple[int, bool]:
    """One accepted product. Overflow is sticky until hardware clear/reset."""
    accumulator = _signed(accumulator, 48, "accumulator")
    a = _signed(a, 16, "a")
    b = _signed(b, 16, "b")
    exact = accumulator + a * b
    return wrap_signed(exact, 48), bool(overflow or not INT48_MIN <= exact <= INT48_MAX)


def round_shift_even(value: int, shift: int) -> int:
    """Divide a signed integer by 2**shift, rounding half-way values to even."""
    if not 0 <= shift <= 127:
        raise ValueError("shift must be in [0, 127]")
    magnitude = abs(int(value))
    if shift:
        quotient, remainder = divmod(magnitude, 1 << shift)
        halfway = 1 << (shift - 1)
        magnitude = quotient + int(remainder > halfway or (remainder == halfway and quotient & 1))
    return -magnitude if value < 0 else magnitude


def requantize(acc: int, multiplier: int, shift: int, bias: int = 0) -> int:
    """RTL: sat16(RNE(((signed48(acc)+signed48(bias))*signed32(m))/2**s))."""
    acc = _signed(acc, 48, "acc")
    bias = _signed(bias, 48, "bias")
    multiplier = _signed(multiplier, 32, "multiplier")
    result = round_shift_even((acc + bias) * multiplier, shift)
    return min(INT16_MAX, max(INT16_MIN, result))


def self_test() -> None:
    assert [round_shift_even(v, 1) for v in range(-7, 8, 2)] == [-4, -2, -2, 0, 0, 2, 2, 4]
    assert requantize(INT48_MAX, -(1 << 31), 127, INT48_MAX) == 0
    assert requantize(INT48_MIN, -(1 << 31), 79, INT48_MIN) == 1
    assert requantize(INT48_MAX, 1, 0) == INT16_MAX
    assert requantize(INT48_MIN, 1, 0) == INT16_MIN
    assert requantize(1, 3, 1, 2) == 4
    accumulator, overflow = 0, False
    for _ in range(9728):
        accumulator, overflow = mac_step(accumulator, INT16_MIN, INT16_MIN, overflow)
    assert accumulator == 9728 * (1 << 30) and not overflow
    assert mac_step(INT48_MAX, 1, 1) == (INT48_MIN, True)
    assert mac_step(INT48_MIN, -1, 1) == (INT48_MAX, True)


if __name__ == "__main__":
    self_test()
    print("PASS integer_reference: ties, limits, K=9728, overflow")
