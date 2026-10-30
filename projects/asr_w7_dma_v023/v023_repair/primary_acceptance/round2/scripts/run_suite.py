"""Run the independent numeric acceptance suite against a source set.

Only logic simulation (Icarus Verilog).  Each simulation is launched in its own
process group with a wall-clock watchdog, and the testbench itself also has a
cycle watchdog that prints diagnostics before exiting with code 2.
"""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from collections import Counter, defaultdict
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ref"))
import refmodel as R  # noqa: E402

VEC = os.path.join(ROOT, "vectors")
BUILD = os.path.join(ROOT, "build")
LOGS = os.path.join(ROOT, "logs")
os.makedirs(BUILD, exist_ok=True)
os.makedirs(LOGS, exist_ok=True)

OLD = {
    "i48": "/home/yang/Desktop/项目/v023_repair/gemini_epilogue/epilogue_i48_to_f32.sv",
    "fma": "/home/yang/Desktop/项目/v023_repair/gemini_epilogue/epilogue_fma_stage.sv",
    "f32i16": "/home/yang/Desktop/项目/v023_repair/gemini_epilogue/epilogue_f32_to_i16.sv",
    "relu": "/home/yang/Desktop/项目/v023_repair/gemini_epilogue/epilogue_relu.sv",
    "lane": "/home/yang/Desktop/项目/v023_repair/gemini_epilogue/epilogue_lane.sv",
    "stream": "/home/yang/Desktop/项目/v023_repair/gemini_epilogue/epilogue_stream_engine_v023.sv",
    "approx": "/home/yang/Desktop/项目/v023_repair/gemini_approx/rtl/approx_div_sqrt.sv",
    "recip": "/home/yang/Desktop/项目/v023_repair/gemini_approx/rtl/approx_recip_lut.sv",
    "rsqrt": "/home/yang/Desktop/项目/v023_repair/gemini_approx/rtl/approx_rsqrt_lut.sv",
    "fma_pipe": None,
    "asr_fma": None,
}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_cmd(cmd, log_path, timeout, cwd=None):
    """Run a command with a wall-clock watchdog; return (rc, stdout, stderr)."""
    with open(log_path, "w") as lf:
        lf.write("CMD: " + " ".join(cmd) + "\n")
        lf.flush()
        p = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT,
                             start_new_session=True, cwd=cwd)
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            lf.write(f"\nWATCHDOG: wall-clock timeout after {timeout}s; killing pid {p.pid}\n")
            lf.flush()
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGKILL)
            except Exception:
                pass
            p.wait()
            return 124, "WATCHDOG_TIMEOUT", ""
        lf.flush()
    with open(log_path, "r", errors="replace") as f:
        out = f.read()
    return rc, out, ""


def compile_tb(name, sources, top, params=None, defines=None):
    exe = os.path.join(BUILD, name)
    cmd = ["iverilog", "-g2012", "-o", exe]
    if defines:
        for d in defines:
            cmd += ["-D", d]
    if params:
        for k, v in params.items():
            cmd += ["-P", f"{top}.{k}={v}"]
    cmd += sources
    rc, out, err = run_cmd(cmd, os.path.join(LOGS, f"compile_{name}.log"), 120)
    if rc != 0:
        raise RuntimeError(f"compile {name} failed rc={rc}\n{out}")
    return exe


def read_hex_lines(path, ncols):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != ncols:
                continue
            rows.append(parts)
    return rows


def parse_stability(out):
    for line in out.splitlines():
        if line.startswith("STABILITY_ERRORS="):
            try:
                return int(line.split("=")[1])
            except Exception:
                return None
    return None


def summarize_mismatches(mism, limit=12):
    return mism[:limit]


def fma_sources(src):
    out = [src["fma"]]
    if src.get("fma_pipe"):
        out.append(src["fma_pipe"])
    if src.get("asr_fma"):
        out.append(src["asr_fma"])
    return out


# ------------------------------------------------------------------ i48
def test_i48(src, label, bp=0):
    exe = compile_tb(f"{label}_i48", [os.path.join(ROOT, "tb/tb_i48_to_f32.sv"), src["i48"]],
                     "tb_i48_to_f32")
    out_file = os.path.join(LOGS, f"{label}_i48.out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/i48.vec", f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          f"+BP={bp}", "+MAX_CYCLES=5000000"],
                         os.path.join(LOGS, f"{label}_i48.log"), 300, cwd=ROOT)
    res = {"rc": rc, "vectors": 0, "mismatches": 0, "tag_errors": 0,
           "last_errors": 0, "stability_errors": parse_stability(out), "examples": [], "pass": False}
    if rc != 0:
        res["error"] = out[-2000:]
        return res
    vecs = read_hex_lines(os.path.join(VEC, "i48.vec"), 3)
    outs = read_hex_lines(out_file, 5)
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != {len(vecs)}"
        return res
    mism = []
    for i, (v, o) in enumerate(zip(vecs, outs)):
        data = int(v[0], 16)
        tag = int(v[1], 16)
        last = int(v[2])
        got = int(o[2], 16)
        exp = R.i48_to_f32_bits(data if data < (1 << 47) else data - (1 << 48))
        if got != exp:
            res["mismatches"] += 1
            if len(mism) < 20:
                mism.append({"i": i, "in": v[0], "got": f"{got:08x}",
                             "exp": f"{exp:08x}",
                             "got_f": R.f32_str(got), "exp_f": R.f32_str(exp)})
        if int(o[3], 16) != tag:
            res["tag_errors"] += 1
        if int(o[4]) != last:
            res["last_errors"] += 1
    res["examples"] = mism
    res["pass"] = (res["mismatches"] == 0 and res["tag_errors"] == 0
                   and res["last_errors"] == 0 and (res["stability_errors"] or 0) == 0)
    return res


# ------------------------------------------------------------------ fma
def test_fma(src, label, bp=0):
    exe = compile_tb(f"{label}_fma", [os.path.join(ROOT, "tb/tb_fma.sv")] + fma_sources(src),
                     "tb_fma")
    out_file = os.path.join(LOGS, f"{label}_fma.out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/fma.vec", f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          f"+BP={bp}", "+MAX_CYCLES=5000000"],
                         os.path.join(LOGS, f"{label}_fma.log"), 300, cwd=ROOT)
    res = {"rc": rc, "vectors": 0, "mismatches": 0, "tag_errors": 0,
           "last_errors": 0, "by_mode": {}, "stability_errors": parse_stability(out),
           "examples": [], "pass": False}
    if rc != 0:
        res["error"] = out[-2000:]
        return res
    vecs = read_hex_lines(os.path.join(VEC, "fma.vec"), 6)
    outs = read_hex_lines(out_file, 5)
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != {len(vecs)}"
        return res
    mism = []
    by_mode = defaultdict(lambda: [0, 0])
    by_class = defaultdict(lambda: [0, 0])

    def fcls(x, sc, bi):
        if R.is_nan(x) or R.is_nan(sc) or R.is_nan(bi):
            return "nan"
        if R.is_inf(x) or R.is_inf(sc) or R.is_inf(bi):
            return "inf"
        if R.is_sub(x) or R.is_sub(sc) or R.is_sub(bi):
            return "subnormal"
        if R.is_zero(x) or R.is_zero(sc):
            return "zero"
        return "normal"
    for i, (v, o) in enumerate(zip(vecs, outs)):
        mode = int(v[0], 16)
        s = int(v[1], 16)
        b = int(v[2], 16)
        x = int(v[3], 16)
        tag = int(v[4], 16)
        got = int(o[2], 16)
        if mode == 0:
            exp = x
        elif mode == 2:
            exp = R.fma_bits(x, s, 0, ftz=True)
        else:
            exp = R.fma_bits(x, s, b, ftz=True)
        by_mode[mode][1] += 1
        c = fcls(x, s, b)
        by_class[c][1] += 1
        if got != exp:
            by_class[c][0] += 1
            by_mode[mode][0] += 1
            res["mismatches"] += 1
            if len(mism) < 30:
                mism.append({"i": i, "mode": mode, "x": f"{x:08x}",
                             "scale": f"{s:08x}", "bias": f"{b:08x}",
                             "got": f"{got:08x}", "exp": f"{exp:08x}",
                             "got_f": R.f32_str(got), "exp_f": R.f32_str(exp)})
        if int(o[3], 16) != tag:
            res["tag_errors"] += 1
        if int(o[4]) != int(v[5]):
            res["last_errors"] += 1
    res["by_mode"] = {str(k): {"mismatch": v[0], "total": v[1]}
                      for k, v in sorted(by_mode.items())}
    res["by_class"] = {k: {"mismatch": v[0], "total": v[1]}
                       for k, v in sorted(by_class.items())}
    res["primary_counterexample"] = {
        "x": "3f800001", "scale": "3fc00000", "bias": "00000000",
        "expected_rne": f"{R.fma_bits(0x3f800001, 0x3fc00000, 0):08x}"}
    res["examples"] = mism
    res["pass"] = (res["mismatches"] == 0 and res["tag_errors"] == 0
                   and res["last_errors"] == 0
                   and (res["stability_errors"] or 0) == 0)
    return res


# ------------------------------------------------------------------ f32 -> i16
def test_f32i16(src, label, bp=0):
    exe = compile_tb(f"{label}_f32i16",
                     [os.path.join(ROOT, "tb/tb_f32_to_i16.sv"), src["f32i16"]],
                     "tb_f32_to_i16")
    out_file = os.path.join(LOGS, f"{label}_f32i16.out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/f32_i16.vec", f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          f"+BP={bp}", "+MAX_CYCLES=20000000"],
                         os.path.join(LOGS, f"{label}_f32i16.log"), 600, cwd=ROOT)
    res = {"rc": rc, "vectors": 0, "mismatches": 0, "tag_errors": 0,
           "last_errors": 0, "by_class": {}, "stability_errors": parse_stability(out),
           "examples": [], "pass": False}
    if rc != 0:
        res["error"] = out[-2000:]
        return res
    vecs = read_hex_lines(os.path.join(VEC, "f32_i16.vec"), 3)
    outs = read_hex_lines(out_file, 5)
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != {len(vecs)}"
        return res
    mism = []
    by_class = defaultdict(lambda: [0, 0])

    def cls(b):
        if R.is_nan(b):
            return "nan"
        if R.is_inf(b):
            return "inf"
        if R.is_sub(b):
            return "subnormal"
        e = (b >> 23) & 0xFF
        if e == 0:
            return "zero"
        if e >= 158:  # >= 2^31
            return "huge"
        if e >= 142:  # >= 2^15
            return "clamp"
        return "normal"

    for i, (v, o) in enumerate(zip(vecs, outs)):
        b = int(v[0], 16)
        tag = int(v[1], 16)
        got_u = int(o[2], 16)
        got = got_u - 65536 if got_u & 0x8000 else got_u
        exp = R.f32_to_i16(b)
        c = cls(b)
        by_class[c][1] += 1
        if got != exp:
            by_class[c][0] += 1
            res["mismatches"] += 1
            if len(mism) < 30:
                mism.append({"i": i, "in": f"{b:08x}", "class": c,
                             "got": got, "exp": exp,
                             "in_f": R.f32_str(b)})
        if int(o[3], 16) != tag:
            res["tag_errors"] += 1
        if int(o[4]) != int(v[2]):
            res["last_errors"] += 1
    res["by_class"] = {k: {"mismatch": v[0], "total": v[1]}
                       for k, v in sorted(by_class.items())}
    res["examples"] = mism
    res["pass"] = (res["mismatches"] == 0 and res["tag_errors"] == 0
                   and res["last_errors"] == 0
                   and (res["stability_errors"] or 0) == 0)
    return res


# ------------------------------------------------------------------ approx
def expected_special(op, a, b):
    """Return (result_bits, flags) for a special/FTZ-input case, or None."""
    FLAG_INVALID, FLAG_DIV0, FLAG_OVER, FLAG_UNDER, FLAG_APPROX = 1, 2, 4, 8, 0x10
    a_sub, b_sub = R.is_sub(a), R.is_sub(b)
    under = FLAG_UNDER if (a_sub or (op == 0 and b_sub)) else 0
    # FTZ operands
    if a_sub:
        a = (a & 0x80000000)
    if b_sub:
        b = (b & 0x80000000)
    if op == 0:
        if R.is_nan(a) or R.is_nan(b) or (R.is_zero(a) and R.is_zero(b)) or (
                R.is_inf(a) and R.is_inf(b)):
            return R.FP32_QNAN, under | FLAG_INVALID
        if R.is_zero(b):
            return ((R.FP32_NEG_INF if (a >> 31) ^ (b >> 31) else R.FP32_POS_INF),
                    under | (0 if R.is_inf(a) else FLAG_DIV0))
        if R.is_inf(a):
            return ((R.FP32_NEG_INF if (a >> 31) ^ (b >> 31) else R.FP32_POS_INF), under)
        if R.is_zero(a) or R.is_inf(b):
            return ((R.FP32_NEG_ZERO if (a >> 31) ^ (b >> 31) else R.FP32_POS_ZERO), under)
        return None
    # sqrt / rsqrt
    if R.is_nan(a) or ((a >> 31) and not R.is_zero(a)):
        return R.FP32_QNAN, under | FLAG_INVALID
    if R.is_zero(a):
        if op == 1:
            return a, under
        # IEEE: 1/sqrt(-0) = -inf
        return ((R.FP32_NEG_INF if (a >> 31) else R.FP32_POS_INF), under | FLAG_DIV0)
    if R.is_inf(a):
        return (R.FP32_POS_INF if op == 1 else R.FP32_POS_ZERO), under
    return None


def test_approx(src, label, tier, bp=0, has_flush=False):
    exe = compile_tb(f"{label}_approx_t{tier}",
                     [os.path.join(ROOT, "tb/tb_approx.sv"), src["approx"],
                      src["recip"], src["rsqrt"]],
                     "tb_approx", {"TIER": tier},
                     defines=["HAS_FLUSH"] if has_flush else None)
    out_file = os.path.join(LOGS, f"{label}_approx_t{tier}_bp{bp}.out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/approx.vec", f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          f"+BP={bp}", "+MAX_CYCLES=10000000"],
                         os.path.join(LOGS, f"{label}_approx_t{tier}_bp{bp}.log"), 300, cwd=ROOT)
    res = {"rc": rc, "tier": tier, "bp": bp, "has_flush": has_flush, "vectors": 0, "special_mismatch": 0,
           "tag_errors": 0, "order_errors": 0, "flags_errors": 0,
           "flag_semantic_errors": 0, "underflow_results": 0, "overflow_results": 0,
           "max_rel_err": {}, "mean_rel_err": {}, "latency": {},
           "ii": {}, "stability_errors": parse_stability(out), "examples": [], "pass": False}
    if rc != 0:
        res["error"] = out[-2000:]
        return res
    vecs = read_hex_lines(os.path.join(VEC, "approx.vec"), 4)
    outs = read_hex_lines(out_file, 5)
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != {len(vecs)}"
        return res
    by_tag = {}
    for o in outs:
        in_cyc, out_cyc = int(o[0]), int(o[1])
        result = int(o[2], 16)
        flags = int(o[3], 16)
        tag = int(o[4], 16)
        by_tag[tag] = (in_cyc, out_cyc, result, flags)
    from decimal import Decimal
    max_rel = defaultdict(lambda: Decimal(0))
    sum_rel = defaultdict(lambda: Decimal(0))
    cnt_rel = defaultdict(int)
    lat = defaultdict(list)
    in_cycles = []
    mism = []
    for i, v in enumerate(vecs):
        op = int(v[0], 16)
        a = int(v[1], 16)
        b = int(v[2], 16)
        tag = int(v[3], 16)
        if tag not in by_tag:
            res["order_errors"] += 1
            continue
        in_cyc, out_cyc, got, flags = by_tag[tag]
        lat[op].append(out_cyc - in_cyc)
        in_cycles.append(in_cyc)
        exp = expected_special(op, a, b)
        if exp is not None:
            eres, eflags = exp
            if got != eres or (flags & 0xEF) != eflags:
                res["special_mismatch"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "exp": f"{eres:08x}",
                                 "flags": f"{flags:02x}", "exp_flags": f"{eflags:02x}"})
            continue
        # normal path: result must be finite (or inf/zero on overflow/underflow)
        if R.is_nan(got):
            res["special_mismatch"] += 1
            continue
        if op == 0:
            true = R.true_div_decimal(a, b)
        elif op == 1:
            true = R.true_sqrt_decimal(a)
        else:
            true = R.true_rsqrt_decimal(a)
        if R.is_zero(got):
            res["underflow_results"] += 1
            if not (flags & 0x08):
                res["flag_semantic_errors"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "flags": f"{flags:02x}",
                                 "note": "zero result without UNDERFLOW"})
        elif R.is_inf(got):
            res["overflow_results"] += 1
            if not (flags & 0x04):
                res["flag_semantic_errors"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "flags": f"{flags:02x}",
                                 "note": "inf result without OVERFLOW"})
        else:
            err = R.rel_error(got, true)
            if err is not None:
                max_rel[op] = max(max_rel[op], err)
                sum_rel[op] += err
                cnt_rel[op] += 1
            if flags != 0x10:
                res["flag_semantic_errors"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "flags": f"{flags:02x}",
                                 "note": "normal result flags != 0x10"})
    res["examples"] = mism
    for op, name in ((0, "div"), (1, "sqrt"), (2, "rsqrt")):
        if cnt_rel[op]:
            res["max_rel_err"][name] = float(max_rel[op])
            res["mean_rel_err"][name] = float(sum_rel[op] / cnt_rel[op])
        if lat[op]:
            ls = sorted(lat[op])
            res["latency"][name] = {"min": ls[0], "median": ls[len(ls)//2],
                                    "max": ls[-1], "n": len(ls)}
    if len(in_cycles) > 1:
        diffs = [in_cycles[i+1] - in_cycles[i] for i in range(len(in_cycles)-1)]
        c = Counter(diffs)
        res["ii"] = {"min": min(diffs), "max": max(diffs),
                     "common": c.most_common(5)}
    res["pass"] = (res["special_mismatch"] == 0 and res["tag_errors"] == 0
                   and res["order_errors"] == 0 and res["flags_errors"] == 0
                   and res["flag_semantic_errors"] == 0
                   and (res["stability_errors"] or 0) == 0)
    return res


# ------------------------------------------------------------------ stream
def parse_stream_out(path):
    a16, packed, spill = [], [], []
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "A":
                a16.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
            elif p[0] == "P":
                packed.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
            elif p[0] == "S":
                spill.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
    return a16, packed, spill


def test_stream(src, label, mode, relu, spill, scale, bias, bp=0, abort_at=-1,
                param_en=0, param_addr=0, param_data=0, ref_scale=None):
    sources = ([os.path.join(ROOT, "tb/tb_stream.sv"), src["i48"]]
               + fma_sources(src) + [src["f32i16"], src["relu"], src["lane"],
                                      src["stream"]])
    tag_name = f"{label}_stream_m{mode}_r{relu}_s{spill}_a{abort_at}_bp{bp}_pe{param_en}"
    exe = compile_tb(tag_name, sources, "tb_stream")
    out_file = os.path.join(LOGS, f"{label}_stream_m{mode}_r{relu}_s{spill}_a{abort_at}_bp{bp}.out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/stream.vec", f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          f"+MODE={mode}", f"+RELU={relu}", f"+SPILL={spill}",
                          f"+SCALE={scale:08x}", f"+BIAS={bias:08x}",
                          f"+BP={bp}", f"+ABORT_AT={abort_at}",
                          "+MAX_CYCLES=1000000"],
                         os.path.join(LOGS, f"{label}_stream_m{mode}_r{relu}_s{spill}_a{abort_at}_bp{bp}.log"),
                         300)
    res = {"rc": rc, "mode": mode, "relu": relu, "spill": spill, "bp": bp,
           "abort_at": abort_at, "a16_beats": 0, "packed_beats": 0,
           "spill_beats": 0, "a16_mismatch": 0, "packed_mismatch": 0,
           "spill_mismatch": 0, "tag_mismatch": 0, "post_abort_outputs": 0,
           "a16_count_mismatch": None, "packed_count_mismatch": None,
           "abort_cycle": None, "tag_examples": [], "examples": [],
           "pass": False}
    if rc != 0:
        res["error"] = out[-2000:]
        return res
    a16, packed, spill_out = parse_stream_out(out_file)
    res["a16_beats"] = len(a16)
    res["packed_beats"] = len(packed)
    res["spill_beats"] = len(spill_out)
    beats = read_hex_lines(os.path.join(VEC, "stream.vec"), 6)
    if abort_at < 0:
        res["a16_count_mismatch"] = len(a16) - len(beats)
        res["packed_count_mismatch"] = len(packed) - ((len(beats) + 1) // 2)
    # Reference chain
    if ref_scale is not None:
        scale = ref_scale
    exp_a16 = []
    for v in beats:
        lanes = [int(x, 16) for x in v[:4]]
        tag = int(v[4], 16)
        last = int(v[5])
        outs = []
        for raw in lanes:
            sval = raw if raw < (1 << 47) else raw - (1 << 48)
            f = R.i48_to_f32_bits(sval)
            if mode == 0:
                pass
            elif mode == 2:
                f = R.fma_bits(f, scale, 0, ftz=True)
            else:
                f = R.fma_bits(f, scale, bias, ftz=True)
            if relu and (f >> 31) and not R.is_nan(f):
                f = 0
            if relu and R.is_nan(f):
                f = R.FP32_QNAN
            outs.append(R.f32_to_i16(f) & 0xFFFF)
        exp_a16.append((tag, last, outs))
    # Compare A16 (only up to abort point if abort)
    n = min(len(a16), len(exp_a16))
    for i in range(n):
        cyc, data, tag, last = a16[i]
        etag, elast, eouts = exp_a16[i]
        got = [(data >> (16*k)) & 0xFFFF for k in range(4)]
        if got != eouts:
            res["a16_mismatch"] += 1
            if len(res["examples"]) < 20:
                res["examples"].append({"i": i, "got": [f"{x:04x}" for x in got],
                                        "exp": [f"{x:04x}" for x in eouts]})
        if tag != etag or last != elast:
            res["tag_mismatch"] += 1
            if len(res["tag_examples"]) < 8:
                res["tag_examples"].append({"i": i, "got_tag": f"{tag:04x}",
                                            "exp_tag": f"{etag:04x}",
                                            "got_last": last, "exp_last": elast})
    # Packed: reconstruct from A16
    exp_packed = []
    for i in range(0, len(exp_a16), 2):
        tag, last, outs0 = exp_a16[i]
        if i + 1 < len(exp_a16):
            _, last2, outs1 = exp_a16[i+1]
            data = 0
            for k, x in enumerate(outs0 + outs1):
                data |= (x & 0xFFFF) << (16*k)
            exp_packed.append((tag, last2, data))
        else:
            data = 0
            for k, x in enumerate(outs0):
                data |= (x & 0xFFFF) << (16*k)
            exp_packed.append((tag, 1, data))
    for i in range(min(len(packed), len(exp_packed))):
        cyc, data, tag, last = packed[i]
        etag, elast, edata = exp_packed[i]
        if data != edata:
            res["packed_mismatch"] += 1
        if tag != etag or last != elast:
            res["tag_mismatch"] += 1
    # Spill
    if spill:
        for i in range(min(len(spill_out), len(beats))):
            cyc, data, tag, last = spill_out[i]
            lanes = [int(x, 16) for x in beats[i][:4]]
            edata = sum((lanes[k] & ((1 << 48)-1)) << (48*k) for k in range(4))
            if data != edata:
                res["spill_mismatch"] += 1
            if tag != int(beats[i][4], 16) or last != int(beats[i][5]):
                res["tag_mismatch"] += 1
    # Abort must not produce handshakes after the abort cycle
    import re as _re
    m = _re.search(r"abort_cycle=(-?\d+)", out)
    if m:
        res["abort_cycle"] = int(m.group(1))
        ac = res["abort_cycle"]
        if ac >= 0:
            post = [x for x in a16 + packed + spill_out if x[0] > ac]
            res["post_abort_outputs"] = len(post)
    res["pass"] = (res["a16_mismatch"] == 0 and res["packed_mismatch"] == 0
                   and res["spill_mismatch"] == 0 and res["tag_mismatch"] == 0
                   and res["post_abort_outputs"] == 0
                   and (res["a16_count_mismatch"] in (None, 0))
                   and (res["packed_count_mismatch"] in (None, 0)))
    return res



# ------------------------------------------------------------------ flush
def test_flush(src, label):
    sources = ([os.path.join(ROOT, "tb/tb_flush.sv"), src["i48"]]
               + fma_sources(src) + [src["f32i16"], src["relu"], src["lane"]])
    exe = compile_tb(f"{label}_flush", sources, "tb_flush")
    rc, out, _ = run_cmd([exe], os.path.join(LOGS, f"{label}_flush.log"), 60, cwd=ROOT)
    res = {"rc": rc, "flush_errors": None, "pass": False, "log": out[-1500:]}
    for line in out.splitlines():
        if line.startswith("FLUSH_ERRORS="):
            res["flush_errors"] = int(line.split("=")[1])
    res["pass"] = (rc == 0 and res["flush_errors"] == 0)
    return res



# ------------------------------------------------------------------ approx flush / param rejection
def test_approx_flush(src, label):
    sources = [os.path.join(ROOT, "tb/tb_approx_flush.sv"), src["approx"],
               src["recip"], src["rsqrt"]]
    exe = compile_tb(f"{label}_approx_flush", sources, "tb_approx_flush")
    rc, out, _ = run_cmd([exe], os.path.join(LOGS, f"{label}_approx_flush.log"), 60, cwd=ROOT)
    res = {"rc": rc, "flush_errors": None, "pass": False, "log": out[-1500:]}
    for line in out.splitlines():
        if line.startswith("APPROX_FLUSH_ERRORS="):
            res["flush_errors"] = int(line.split("=")[1])
    res["pass"] = (rc == 0 and res["flush_errors"] == 0)
    return res


def test_approx_param_rejection(src, label):
    """Unsupported TIER/LATENCY must fail elaboration, not silently run."""
    results = {}
    cases = [("TIER", 0), ("TIER", 2), ("LATENCY", 4), ("LATENCY", 7)]
    for name, val in cases:
        exe = os.path.join(BUILD, f"{label}_reject_{name}_{val}")
        cmd = ["iverilog", "-g2012", "-DHAS_FLUSH", "-Ptb_approx.%s=%d" % (name, val),
               "-o", exe, os.path.join(ROOT, "tb/tb_approx.sv"), src["approx"],
               src["recip"], src["rsqrt"]]
        rc, out, _ = run_cmd(cmd, os.path.join(LOGS, f"{label}_reject_{name}_{val}.log"),
                             120, cwd=ROOT)
        results[f"{name}={val}"] = {"rc": rc, "rejected": rc != 0}
    res = {"cases": results,
           "pass": all(v["rejected"] for v in results.values())}
    return res



# ------------------------------------------------------------------ stream reconfig hazard
def test_stream_reconfig(src, label):
    sources = ([os.path.join(ROOT, "tb/tb_stream.sv"), src["i48"]]
               + fma_sources(src) + [src["f32i16"], src["relu"], src["lane"],
                                      src["stream"]])
    tag_name = f"{label}_stream_reconfig"
    exe = compile_tb(tag_name, sources, "tb_stream")
    out_file = os.path.join(LOGS, tag_name + ".out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/stream_reconfig.vec",
                          f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          "+MODE=1", "+RELU=0", "+SPILL=0",
                          "+SCALE=3f800000", "+BIAS=00000000",
                          "+RECFG_AT=2", "+RECFG_SCALE=40400000",
                          "+RECFG_BIAS=00000000", "+MAX_CYCLES=1000"],
                         os.path.join(LOGS, tag_name + ".log"), 120, cwd=ROOT)
    res = {"rc": rc, "a16": [], "in_flight_corrupted": False, "pass": False}
    if rc != 0:
        res["error"] = out[-1000:]
        return res
    a16, packed, spill = parse_stream_out(out_file)
    res["a16"] = [f"{x[1]:016x}" for x in a16]
    # beat0 = 1, beat1 accepted under old scale 1.0 should be 2; 6 means the
    # new cfg (scale 3.0) was applied to an in-flight beat.
    if len(a16) >= 2 and a16[1][1] == 0x0006000600060006:
        res["in_flight_corrupted"] = True
    res["pass"] = (len(a16) == 2 and a16[0][1] == 0x0001000100010001
                   and a16[1][1] == 0x0002000200020002)
    return res



# ------------------------------------------------------------------ asr_fma_ip wrapper
def test_asr_fma_ip(src, label):
    exe = compile_tb(f"{label}_asr_fma_ip",
                     [os.path.join(ROOT, "tb/tb_asr_fma_ip.sv"),
                      src["asr_fma"], src["fma_pipe"]], "tb_asr_fma_ip")
    out_file = os.path.join(LOGS, f"{label}_asr_fma_ip.out")
    rc, out, _ = run_cmd([exe, "+VEC_FILE=vectors/fma.vec",
                          f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
                          "+MAX_CYCLES=5000000"],
                         os.path.join(LOGS, f"{label}_asr_fma_ip.log"), 300, cwd=ROOT)
    res = {"rc": rc, "vectors": 0, "mismatches": 0, "by_class": {},
           "examples": [], "pass": False}
    if rc != 0:
        res["error"] = out[-1000:]
        return res
    vecs = read_hex_lines(os.path.join(VEC, "fma.vec"), 6)
    outs = read_hex_lines(out_file, 2)
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != {len(vecs)}"
        return res
    by_class = defaultdict(lambda: [0, 0])
    mism = []
    for v, o in zip(vecs, outs):
        mode = int(v[0], 16)
        s = int(v[1], 16)
        b = int(v[2], 16)
        x = int(v[3], 16)
        got = int(o[1], 16)
        if mode == 0:
            exp = x
        elif mode == 2:
            exp = R.fma_bits(x, s, 0)
        else:
            exp = R.fma_bits(x, s, b)
        def cls(bits):
            if R.is_nan(bits): return "nan"
            if R.is_inf(bits): return "inf"
            if R.is_sub(bits): return "subnormal"
            if R.is_zero(bits): return "zero"
            return "normal"
        c = cls(x) + "/" + cls(s) + "/" + cls(b)
        by_class[c][1] += 1
        if got != exp:
            by_class[c][0] += 1
            res["mismatches"] += 1
            if len(mism) < 20:
                mism.append({"x": f"{x:08x}", "scale": f"{s:08x}",
                             "bias": f"{b:08x}", "got": f"{got:08x}",
                             "exp": f"{exp:08x}"})
    res["by_class"] = {k: {"mismatch": v[0], "total": v[1]}
                       for k, v in sorted(by_class.items())}
    res["examples"] = mism
    res["pass"] = res["mismatches"] == 0
    return res


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="old")
    ap.add_argument("--only", default="all")
    ap.add_argument("--bp", type=int, default=0)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--i48", default=OLD["i48"])
    ap.add_argument("--fma", default=OLD["fma"])
    ap.add_argument("--f32i16", default=OLD["f32i16"])
    ap.add_argument("--relu", default=OLD["relu"])
    ap.add_argument("--lane", default=OLD["lane"])
    ap.add_argument("--stream", default=OLD["stream"])
    ap.add_argument("--approx", default=OLD["approx"])
    ap.add_argument("--recip", default=OLD["recip"])
    ap.add_argument("--rsqrt", default=OLD["rsqrt"])
    ap.add_argument("--fma-pipe", default=None)
    ap.add_argument("--asr-fma", default=None)
    ap.add_argument("--approx-has-flush", action="store_true")
    args = ap.parse_args()
    src = {k: getattr(args, k) for k in
           ["i48", "fma", "f32i16", "relu", "lane", "stream", "approx",
            "recip", "rsqrt"]}
    src["fma_pipe"] = args.fma_pipe
    src["asr_fma"] = args.asr_fma
    result = {"label": args.label, "bp": args.bp,
              "source_sha256": {k: sha(v) for k, v in src.items() if v},
              "sources": src, "tests": {}, "started": time.time()}
    only = args.only
    t0 = time.time()
    if only in ("all", "i48"):
        result["tests"]["i48"] = test_i48(src, args.label, args.bp)
    if only in ("all", "fma"):
        result["tests"]["fma"] = test_fma(src, args.label, args.bp)
        if src.get("asr_fma") and src.get("fma_pipe"):
            result["tests"]["asr_fma_ip"] = test_asr_fma_ip(src, args.label)
    if only in ("all", "f32i16"):
        result["tests"]["f32i16"] = test_f32i16(src, args.label, args.bp)
    if only in ("all", "approx"):
        tiers = (1,) if args.approx_has_flush else (0, 1, 2)
        for tier in tiers:
            result["tests"][f"approx_t{tier}"] = test_approx(
                src, args.label, tier, args.bp, has_flush=args.approx_has_flush)
        if args.approx_has_flush:
            result["tests"]["approx_flush"] = test_approx_flush(src, args.label)
            result["tests"]["approx_param_rejection"] = test_approx_param_rejection(
                src, args.label)
    if only in ("all", "flush"):
        result["tests"]["flush"] = test_flush(src, args.label)
    if only in ("all", "stream"):
        # Conversion-only path (validates framing independent of FMA)
        result["tests"]["stream_conv"] = test_stream(
            src, args.label, 0, 0, 0, 0x3F800000, 0, args.bp, -1)
        result["tests"]["stream_conv_relu"] = test_stream(
            src, args.label, 0, 1, 0, 0x3F800000, 0, args.bp, -1)
        # Non-trivial real-model-derived scale/bias
        # Adversarial non-trivial scale/bias chosen so the FP32 FMA rounding
        # difference survives the A16 quantizer (see FINDINGS.md).
        result["tests"]["stream_fma"] = test_stream(
            src, args.label, 1, 0, 0, 0x3F000001, 0x3F800000, args.bp, -1)
        result["tests"]["stream_fma_relu"] = test_stream(
            src, args.label, 1, 1, 0, 0x3F000001, 0x3F800000, args.bp, -1)
        # Real-model LayerNorm-derived scale, kept as a domain-coverage run but
        # explicitly non-discriminative for FMA after i16 quantization.
        result["tests"]["stream_fma_real"] = test_stream(
            src, args.label, 1, 0, 0, 0x3A62C0F5, 0x3F400000, args.bp, -1)
        result["tests"]["stream_scale_only"] = test_stream(
            src, args.label, 2, 0, 0, 0x3F000001, 0x3F800000, args.bp, -1)
        result["tests"]["stream_spill"] = test_stream(
            src, args.label, 0, 0, 1, 0x3F800000, 0, args.bp, -1)
        result["tests"]["stream_abort"] = test_stream(
            src, args.label, 0, 0, 0, 0x3F800000, 0, args.bp, 100)
        # The interface claims param_wr_addr can preload per-channel scales.
        # Drive 0.5 via the parameter port while cfg_scale stays 1.0; reference
        # uses 0.5.  A failure here proves the parameter port is inert.
        result["tests"]["stream_param_port"] = test_stream(
            src, args.label, 2, 0, 0, 0x3F800000, 0, args.bp, -1,
            param_en=1, param_addr=0, param_data=0x3F000000, ref_scale=0x3F000000)
        result["tests"]["stream_reconfig"] = test_stream_reconfig(src, args.label)
    result["elapsed_s"] = round(time.time() - t0, 2)
    result["pass"] = all(t.get("pass", False) for t in result["tests"].values())
    out = os.path.join(ROOT, f"result_{args.label}.json")
    with open(out, "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps({k: {"pass": v.get("pass"), "mismatches": v.get("mismatches"),
                          "special_mismatch": v.get("special_mismatch"),
                          "a16_mismatch": v.get("a16_mismatch")}
                      for k, v in result["tests"].items()}, indent=2))
    print("RESULT", out, "PASS" if result["pass"] else "FAIL")


if __name__ == "__main__":
    main()
