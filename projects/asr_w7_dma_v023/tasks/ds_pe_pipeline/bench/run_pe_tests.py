#!/usr/bin/env python3
"""Generate PE vectors, run Icarus Verilog, and compare:
   historical pe_direct_v020 + pe_w7_c48_cfg(3/4/5/6) + CSA
against the independent integer golden model and directed event semantics.
"""
from __future__ import annotations

import json
import math
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT
PROJ = TASK.parents[1]
BENCH = TASK / "bench"
VEC = BENCH / "vectors"
LOG = BENCH / "logs"
sys.path.insert(0, str(TASK / "candidate"))
from golden_w7_c48 import product32, sum_products, to_s48  # noqa: E402

BASE_PE = PROJ / "work" / "rtl" / "pe_direct_v020.sv"
CFG_PE = TASK / "candidate" / "pe_w7_c48_cfg.sv"
TB = BENCH / "tb_pe_cfg_compare.sv"
VVP = BENCH / "pe_cfg_sim.vvp"

A_CORNERS = [-32768, -32767, -16384, -1, 0, 1, 16384, 32767]
RNG = random.Random(0x57504348)  # "WPHC"


def line(a=0, w=0, pos=0, clip=0, av=0, wv=0, reset=0, flush=0, clear=0):
    return (a & 0xFFFF, w & 0x7F, pos & 0xFFFF, int(clip), int(av), int(wv),
            int(reset), int(flush), int(clear))


def write_vectors(path: Path, rows):
    with path.open("w") as f:
        for a, w, pos, clip, av, wv, reset, flush, clear in rows:
            f.write(f"{a:04x} {w:02x} {pos:04x} {clip:b} {av:b} {wv:b} "
                    f"{reset:b} {flush:b} {clear:b}\n")
    return len(rows)


def compile_sim():
    # Icarus Verilog has no -j option; the task's "-j2" build budget is honored
    # by the top-level make/run_all wrapper, not by iverilog itself.
    cmd = ["iverilog", "-g2012", "-o", str(VVP), str(TB), str(CFG_PE), str(BASE_PE)]
    r = subprocess.run(cmd, cwd=TASK, text=True, capture_output=True)
    (LOG / "compile_pe.log").write_text(" ".join(cmd) + "\n" + r.stdout + r.stderr)
    if r.returncode != 0:
        raise SystemExit("compile failed; see bench/logs/compile_pe.log")


def run_sim(vec_path: Path, out_path: Path):
    # Icarus plusargs use a byte-string; keep the paths relative and ASCII so
    # the non-ASCII project directory is not corrupted by the simulator.
    vrel = vec_path.relative_to(TASK)
    orel = out_path.relative_to(TASK)
    cmd = ["vvp", str(VVP), f"+VEC={vrel}", f"+OUT={orel}"]
    r = subprocess.run(cmd, cwd=TASK, text=True, capture_output=True)
    (LOG / (out_path.stem + ".vvp.log")).write_text(r.stdout + r.stderr)
    if r.returncode != 0:
        raise SystemExit(f"vvp failed: {r.stderr}")
    return r.stdout


def read_out(path: Path):
    rows = []
    with path.open() as f:
        for ln in f:
            parts = ln.split()
            if len(parts) != 6:
                continue
            vals = []
            for h in parts:
                u = int(h, 16)
                vals.append(u - (1 << 48) if u & (1 << 47) else u)
            rows.append(vals)
    return rows


def check_base_s3_trace(rows, label, failures):
    """3-stage is the baseline-shape candidate: it must match baseline every cycle."""
    for i, row in enumerate(rows):
        if row[0] != row[1]:
            failures.append(f"{label}: base/s3 cycle {i} {row[0]:#x} != {row[1]:#x}")
            return


def check_rows(rows, checks, label, failures):
    # rows: per-cycle [base,s3,s4,s5,s6,csa]
    names = ["baseline", "s3", "s4", "s5", "s6", "csa"]
    for idx, expected in checks:
        if idx >= len(rows):
            failures.append(f"{label}: missing output index {idx}")
            continue
        got = rows[idx]
        for j, name in enumerate(names):
            if got[j] != expected:
                failures.append(f"{label}: idx={idx} {name}={got[j]:#x} expected={expected:#x}")
                if len(failures) > 40:
                    return


def main():
    VEC.mkdir(parents=True, exist_ok=True)
    LOG.mkdir(parents=True, exist_ok=True)
    if "--no-compile" not in sys.argv:
        compile_sim()

    summary = {}
    failures = []

    # ------------------------------------------------------------------
    # 1. Exhaustive W7 x A corner x P x clip, one product per reset window.
    # ------------------------------------------------------------------
    rows = []
    checks = []
    for w in range(128):
        for a in A_CORNERS:
            for p in range(16):
                for clip in (0, 1):
                    rows += [line(reset=1), line(reset=1)] + [line() for _ in range(6)]
                    rows.append(line(a=a, w=w, pos=p * 0x1111, clip=clip, av=1, wv=1))
                    rows += [line() for _ in range(10)]
                    checks.append((len(rows) - 1, product32(a, w, p * 0x1111, clip)))
    vec = VEC / "pe_exhaustive.vec"
    out = LOG / "pe_exhaustive.out"
    n = write_vectors(vec, rows)
    stdout = run_sim(vec, out)
    import re
    m = re.search(r"DRAIN base=4 s3=(\d+) s4=(\d+) s5=(\d+) s6=(\d+) csa=(\d+)", stdout)
    pe_drain = None
    if not m:
        failures.append("could not parse PE DRAIN constants")
    else:
        pe_drain = [int(m.group(i)) for i in range(1, 6)]
        if pe_drain != [4, 5, 6, 7, 6]:
            failures.append(f"PE DRAIN constants {pe_drain} expected [4,5,6,7,6]")
    got = read_out(out)
    check_base_s3_trace(got, "exhaustive", failures)
    check_rows(got, checks, "exhaustive", failures)
    summary["exhaustive"] = {"vectors": n, "products": len(checks),
                             "outputs": len(got), "drain_constants": pe_drain}
    print(f"exhaustive: {len(checks)} products, {n} cycles, mismatches={len(failures)}")

    # ------------------------------------------------------------------
    # 2. Random K=32 tasks: valid bubbles, dynamic positions/clip,
    #    -32768, C48 accumulation order.
    # ------------------------------------------------------------------
    rows = []
    checks = []
    ntasks = 300
    for _ in range(ntasks):
        items = []
        rows += [line(reset=1), line(reset=1)] + [line() for _ in range(6)]
        for _k in range(32):
            av = 1 if RNG.random() < 0.80 else 0
            wv = 1 if RNG.random() < 0.80 else 0
            if RNG.random() < 0.12:
                a = -32768
            else:
                a = RNG.randint(-32768, 32767)
            w = RNG.randrange(128)
            pos = RNG.randrange(0x10000)
            clip = RNG.randrange(2)
            rows.append(line(a=a, w=w, pos=pos, clip=clip, av=av, wv=wv))
            if av and wv:
                items.append((a, w, pos, clip))
        rows += [line() for _ in range(12)]
        checks.append((len(rows) - 1, sum_products(items)))
    vec = VEC / "pe_random_tasks.vec"
    out = LOG / "pe_random_tasks.out"
    n = write_vectors(vec, rows)
    run_sim(vec, out)
    got = read_out(out)
    check_base_s3_trace(got, "random_tasks", failures)
    check_rows(got, checks, "random_tasks", failures)
    summary["random_tasks"] = {"vectors": n, "tasks": ntasks,
                               "outputs": len(got)}
    print(f"random_tasks: {ntasks} tasks, {n} cycles, cumulative mismatches={len(failures)}")

    # ------------------------------------------------------------------
    # 3. Directed reset / flush / clear / in-flight / valid-bubble cases.
    #    Each scenario ends with a long settle window; expected is explicit.
    # ------------------------------------------------------------------
    rows = []
    checks = []

    def scenario(name, body, expected):
        rows.extend([line(reset=1), line(reset=1)] + [line() for _ in range(6)])
        body()
        rows.extend([line() for _ in range(12)])
        checks.append((len(rows) - 1, expected, name))

    P0 = (-32768, 0x3F, 0xC000, 1)   # max positive 32768*32767
    P1 = (12345, 0x1F, 0x1111, 0)    # positive small
    P2 = (-23456, 0x6A, 0x4321, 0)   # negative

    def inp(p, av=1, wv=1):
        rows.append(line(a=p[0], w=p[1], pos=p[2], clip=p[3], av=av, wv=wv))

    def idle(n):
        rows.extend([line() for _ in range(n)])

    def ev_reset_inflight():
        inp(P0); idle(10); inp(P1); idle(2); rows.append(line(reset=1)); idle(8)

    def ev_flush_inflight():
        inp(P0); idle(10); inp(P1); idle(2); rows.append(line(flush=1)); idle(8)

    def ev_flush_then_new():
        inp(P0); idle(10); inp(P1); idle(2); rows.append(line(flush=1)); idle(4)
        inp(P2); idle(8)

    def ev_clear_settled():
        inp(P0); idle(10); rows.append(line(clear=1)); idle(8)

    def ev_clear_inflight():
        inp(P0); idle(1); rows.append(line(clear=1)); idle(8)

    def ev_clear_inflight_then_new():
        inp(P0); idle(1); rows.append(line(clear=1)); idle(4); inp(P1); idle(8)

    def ev_clear_flush():
        inp(P0); idle(10); inp(P1); idle(1); rows.append(line(clear=1, flush=1)); idle(8)

    def ev_bubbles():
        inp(P0, av=0, wv=1); inp(P1, av=1, wv=0); idle(8)

    def ev_clear_plus_late():
        inp(P0); idle(10); rows.append(line(clear=1)); idle(8); inp(P1); idle(8)

    scenario("reset_inflight", ev_reset_inflight, 0)
    scenario("flush_inflight_preserves_sum", ev_flush_inflight,
             product32(*P0))
    scenario("flush_then_new", ev_flush_then_new,
             to_s48(product32(*P0) + product32(*P2)))
    scenario("clear_settled", ev_clear_settled, 0)
    scenario("clear_inflight_keeps_product", ev_clear_inflight, product32(*P0))
    scenario("clear_inflight_then_new", ev_clear_inflight_then_new,
             to_s48(product32(*P0) + product32(*P1)))
    scenario("clear_flush", ev_clear_flush, 0)
    scenario("valid_bubbles", ev_bubbles, 0)
    scenario("clear_then_late_product", ev_clear_plus_late, product32(*P1))

    vec = VEC / "pe_events.vec"
    out = LOG / "pe_events.out"
    n = write_vectors(vec, rows)
    run_sim(vec, out)
    got = read_out(out)
    check_base_s3_trace(got, "events", failures)
    check_rows(got, [(i, e) for i, e, _ in checks], "events", failures)
    summary["directed_events"] = {
        "vectors": n,
        "scenarios": [{"name": nm, "expected": e, "index": i} for i, e, nm in checks],
        "outputs": len(got),
    }
    print(f"directed_events: {len(checks)} scenarios, {n} cycles, "
          f"cumulative mismatches={len(failures)}")

    # ------------------------------------------------------------------
    # 4. Long INT48 overflow/wrap streak (back-to-back accepted products).
    # ------------------------------------------------------------------
    nprod = 135_000
    rows = [line(reset=1), line(reset=1)] + [line() for _ in range(6)]
    acc = 0
    p = product32(*P0)
    for _ in range(nprod):
        rows.append(line(a=P0[0], w=P0[1], pos=P0[2], clip=P0[3], av=1, wv=1))
        acc = to_s48(acc + p)
    rows += [line() for _ in range(12)]
    vec = VEC / "pe_overflow.vec"
    out = LOG / "pe_overflow.out"
    n = write_vectors(vec, rows)
    run_sim(vec, out)
    got = read_out(out)
    check_base_s3_trace(got, "overflow", failures)
    check_rows(got, [(len(got) - 1, acc)], "overflow", failures)
    summary["overflow"] = {"vectors": n, "products": nprod,
                           "product": p, "expected": acc, "outputs": len(got)}
    print(f"overflow: {nprod} products, expected={acc:#x}, "
          f"cumulative mismatches={len(failures)}")

    result = {
        "task": "ds_pe_pipeline",
        "unit": "PE",
        "summary": summary,
        "failures": failures[:100],
        "pass": not failures,
    }
    (LOG / "pe_tests_result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps({k: ("PASS" if not failures else "FAIL") for k in ["PE"]}, indent=2))
    if failures:
        print("\n".join(failures[:40]))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
