#!/usr/bin/env python3
"""Independent checker for one ds_vector_fma case.

Recomputes every expected word from inputs.txt with refmodel (FMA / relation
helpers / f32->i16), checks that the generator's gold.hex agrees with this
recomputation, then checks the RTL dump.  Exits non-zero on any mismatch.
"""
import argparse, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
DS = Path('/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial')
sys.path.insert(0, str(DS / 'ref'))
import refmodel as R

OP_ADD, OP_MUL, OP_F32_I16, OP_FMA = 0, 2, 15, 17


def read_words(path):
    return [int(x, 16) for x in Path(path).read_text().split()]


def read_rows(path):
    rows = []
    for ln in Path(path).read_text().splitlines():
        if ln.strip():
            rows.append(tuple(int(x, 16) for x in ln.split()))
    return rows


def f32_mul_bits(a, b):
    if R.is_nan(a) or R.is_nan(b):
        return R.FP32_QNAN
    if (R.is_inf(a) and R.is_zero(b)) or (R.is_inf(b) and R.is_zero(a)):
        return R.FP32_QNAN
    if R.is_inf(a) or R.is_inf(b):
        return (((a >> 31) ^ (b >> 31)) << 31) | R.FP32_POS_INF
    if R.is_zero(a) or R.is_zero(b):
        return (((a >> 31) ^ (b >> 31)) << 31) & 0x80000000
    return R.round_f32(R.f32_to_frac(a) * R.f32_to_frac(b))


def f32_add_bits(a, b):
    if R.is_nan(a) or R.is_nan(b):
        return R.FP32_QNAN
    if R.is_inf(a) and R.is_inf(b) and ((a >> 31) != (b >> 31)):
        return R.FP32_QNAN
    if R.is_inf(a):
        return a
    if R.is_inf(b):
        return b
    if R.is_zero(a) and R.is_zero(b):
        return ((a >> 31) & (b >> 31)) << 31
    if R.is_zero(a):
        return b
    if R.is_zero(b):
        return a
    return R.round_f32(R.f32_to_frac(a) + R.f32_to_frac(b))


def pack_i16(vals):
    out = []
    for i in range(0, len(vals), 2):
        lo = vals[i] & 0xffff
        hi = (vals[i + 1] & 0xffff) if i + 1 < len(vals) else 0
        out.append(lo | (hi << 16))
    return out


def recompute(meta, rows):
    op = meta['op']
    if op == OP_FMA:
        return [R.fma_bits(x, s, b) for (x, s, b) in rows]
    if op == OP_MUL:
        return [f32_mul_bits(a, b) for (a, b) in rows]
    if op == OP_ADD:
        return [f32_add_bits(a, b) for (a, b) in rows]
    if op == OP_F32_I16:
        return pack_i16([R.f32_to_i16(a) for (a,) in rows])
    raise SystemExit(f'unknown op {op}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--case', required=True)
    ap.add_argument('--dump', required=True)
    ap.add_argument('--log', default=None)
    ap.add_argument('--negative', action='store_true',
                    help='flip one expected word; the check MUST fail')
    args = ap.parse_args()

    cdir = Path(args.case)
    meta = json.loads((cdir / 'meta.json').read_text())
    rows = read_rows(cdir / 'inputs.txt')
    gen_gold = read_words(cdir / 'gold.hex')
    exp = recompute(meta, rows)

    fails = []
    if len(rows) != meta['total']:
        fails.append(f'input rows {len(rows)} != total {meta["total"]}')
    if len(exp) != len(gen_gold):
        fails.append(f'recomputed {len(exp)} != generator gold {len(gen_gold)}')
    else:
        for i, (a, b) in enumerate(zip(exp, gen_gold)):
            if a != b:
                fails.append(f'generator/reference disagreement at {i}: {a:08x} != {b:08x}')
                break

    if not Path(args.dump).exists():
        fails.append(f'missing dump {args.dump}')
        got = []
    else:
        got = read_words(args.dump)

    if args.negative:
        if not exp:
            fails.append('negative control has empty reference')
        else:
            exp = list(exp)
            exp[0] ^= 0x1  # must mismatch the RTL/gold

    if len(got) < meta['outwords']:
        fails.append(f'dump words {len(got)} < expected {meta["outwords"]}')
    else:
        for i in range(meta['outwords']):
            if got[i] != exp[i]:
                fails.append(f'dump mismatch at word {i}: got {got[i]:08x} exp {exp[i]:08x}')
                break

    if args.log and Path(args.log).exists():
        text = Path(args.log).read_text()
        if 'VEC_FMA_PLAN PASS' not in text and 'VEC_FMA_ABORT_RESET PASS' not in text:
            fails.append('simulation log has no PASS line')

    if args.negative:
        # inverted success criterion: a mismatch is the expected result
        if not fails:
            print(f'CHECK_NEGATIVE_UNEXPECTED_PASS case={meta["name"]}')
            return 0
        print(f'CHECK_NEGATIVE_OK case={meta["name"]} (expected failure observed)')
        return 1

    if fails:
        print(f'CHECK FAIL case={meta["name"]}')
        for f in fails:
            print('  ' + f)
        return 1
    print(f'CHECK OK case={meta["name"]} op={meta["op"]} total={meta["total"]} '
          f'words={meta["outwords"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
