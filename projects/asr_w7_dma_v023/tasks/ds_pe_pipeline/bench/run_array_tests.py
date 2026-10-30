#!/usr/bin/env python3
"""16x16 wavefront test for array16_w7_c48_cfg (3/4/5/6 + CSA) versus
the historical array16_direct_v020 and an independent integer golden model."""
from __future__ import annotations

import json
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
from golden_w7_c48 import product32, to_s48  # noqa: E402

BASE_ARRAY = PROJ / "work" / "rtl" / "array16_direct_v020.sv"
BASE_PE = PROJ / "work" / "rtl" / "pe_direct_v020.sv"
CFG_ARRAY = TASK / "candidate" / "array16_w7_c48_cfg.sv"
CFG_PE = TASK / "candidate" / "pe_w7_c48_cfg.sv"
TB = BENCH / "tb_array_cfg_compare.sv"
VVP = BENCH / "array_cfg_sim.vvp"

K = 32
RNG = random.Random(0x41525259)  # "ARRY"


def aline(a_left=0, w_top=0, av=0, wv=0, pos=0, clip=0,
          reset=0, flush=0, clear=0, dump=0):
    return (a_left, w_top, av & 0xFFFF, wv & 0xFFFF, pos & 0xFFFF,
            int(clip), int(reset), int(flush), int(clear), int(dump))


def write_vectors(path: Path, rows):
    with path.open("w") as f:
        for (a, w, av, wv, pos, clip, reset, flush, clear, dump) in rows:
            f.write(f"{a:064x} {w:028x} {av:04x} {wv:04x} {pos:04x} "
                    f"{clip:b} {reset:b} {flush:b} {clear:b} {dump:b}\n")
    return len(rows)


def compile_sim():
    cmd = ["iverilog", "-g2012", "-o", str(VVP), str(TB), str(CFG_ARRAY),
           str(CFG_PE), str(BASE_ARRAY), str(BASE_PE)]
    r = subprocess.run(cmd, cwd=TASK, text=True, capture_output=True)
    (LOG / "compile_array.log").write_text(" ".join(cmd) + "\n" + r.stdout + r.stderr)
    if r.returncode != 0:
        raise SystemExit("array compile failed; see bench/logs/compile_array.log")


def run_sim(vec_path: Path, out_path: Path):
    vrel = vec_path.relative_to(TASK)
    orel = out_path.relative_to(TASK)
    cmd = ["vvp", str(VVP), f"+VEC={vrel}", f"+OUT={orel}"]
    r = subprocess.run(cmd, cwd=TASK, text=True, capture_output=True)
    (LOG / (out_path.stem + ".vvp.log")).write_text(r.stdout + r.stderr)
    if r.returncode != 0:
        raise SystemExit(f"array vvp failed: {r.stderr}")
    return r.stdout


def expected_tile(a_rows, w_rows, a_mask, w_mask, positions, clip):
    out = [[0] * 16 for _ in range(16)]
    for r in range(16):
        for c in range(16):
            s = 0
            for k in range(K):
                if a_mask[r][k] and w_mask[k][c]:
                    s = to_s48(s + product32(a_rows[r][k], w_rows[k][c], positions, clip))
            out[r][c] = s
    return out


def add_tile(rows, a_rows, w_rows, a_mask, w_mask, positions, clip, drain=30,
             event_index=None, event=None):
    rows += [aline(reset=1), aline(reset=1)] + [aline() for _ in range(6)]
    for t in range(15 + K):
        a_left = 0
        w_top = 0
        av = 0
        wv = 0
        for r in range(16):
            k = t - r
            if 0 <= k < K and a_mask[r][k]:
                a_left |= (a_rows[r][k] & 0xFFFF) << (r * 16)
                av |= 1 << r
        for c in range(16):
            k = t - c
            if 0 <= k < K and w_mask[k][c]:
                w_top |= (w_rows[k][c] & 0x7F) << (c * 7)
                wv |= 1 << c
        rows.append(aline(a_left, w_top, av, wv, positions, clip))
    for i in range(drain):
        # Keep positions/clip stable during the drain: PEs deep in the array
        # capture their operands after the external wavefront has stopped.
        if event_index is not None and i == event_index:
            rows.append(aline(pos=positions, clip=clip, **(event or {})))
        else:
            rows.append(aline(pos=positions, clip=clip,
                              dump=1 if i == drain - 1 else 0))


def parse_out(path: Path):
    """Return (dumps, statuses).

    Each dump is {'sums': {array_id: [256]}, 'e': {id:(...)} }.
    statuses is a list of (cycle, e3,d3,e4,d4,e5,d5,e6,d6,ecsa,dcsa).
    """
    dumps = []
    statuses = []
    cur = None
    with path.open() as f:
        for ln in f:
            if ln.startswith("#S "):
                p = ln.split()
                statuses.append((int(p[1]), *[int(x) for x in p[2:]]))
                continue
            if ln.startswith("#E "):
                if cur is None:
                    cur = {"sums": {}, "e": {}}
                p = ln.split()
                aid = int(p[1])
                cur["e"][aid] = (int(p[2]), int(p[3]), int(p[4]), int(p[5]))
                # #E is written after all 1536 sum lines; close this dump when
                # the CSA status is seen.
                if aid == 5:
                    dumps.append(cur)
                    cur = None
            else:
                p = ln.split()
                if len(p) != 3:
                    continue
                if cur is None:
                    cur = {"sums": {}, "e": {}}
                aid = int(p[0])
                pe = int(p[1])
                u = int(p[2], 16)
                v = u - (1 << 48) if u & (1 << 47) else u
                cur["sums"].setdefault(aid, [None] * 256)[pe] = v
    return dumps, statuses


def main():
    VEC.mkdir(parents=True, exist_ok=True)
    LOG.mkdir(parents=True, exist_ok=True)
    if "--no-compile" not in sys.argv:
        compile_sim()

    rows = []
    tiles = []

    def add(name, a_rows, w_rows, a_mask, w_mask, positions, clip):
        start = len(rows)
        add_tile(rows, a_rows, w_rows, a_mask, w_mask, positions, clip)
        last_input = max(i for i in range(start, len(rows))
                         if (rows[i][2] | rows[i][3]) != 0)
        tiles.append({
            "name": name,
            "a": a_rows, "w": w_rows, "am": a_mask, "wm": w_mask,
            "pos": positions, "clip": clip,
            "start": start,
            "last_input": last_input,
            "end": len(rows) - 1,
        })

    def add_event(name, event, expected_value):
        a = [[1] * K for _ in range(16)]
        w = [[0x01] * 16 for _ in range(K)]
        am = [[True] * K for _ in range(16)]
        wm = [[True] * 16 for _ in range(K)]
        start = len(rows)
        add_tile(rows, a, w, am, wm, 0, 0, drain=55, event_index=25, event=event)
        last_input = max(i for i in range(start, len(rows))
                         if (rows[i][2] | rows[i][3]) != 0)
        event_cycle = min(i for i in range(start, len(rows))
                          if (rows[i][6] | rows[i][7] | rows[i][8]))
        tiles.append({
            "name": name, "a": a, "w": w, "am": am, "wm": wm,
            "pos": 0, "clip": 0, "start": start,
            "last_input": last_input, "end": len(rows) - 1,
            "event_cycle": event_cycle,
            "expected": [[expected_value] * 16 for _ in range(16)],
        })

    full_a = [[1] * K for _ in range(16)]
    full_w = [[1] * 16 for _ in range(K)]

    # Tile 0: ordinary random dense tile.
    a0 = [[RNG.randint(-32768, 32767) for _ in range(K)] for _ in range(16)]
    w0 = [[RNG.randrange(128) for _ in range(16)] for _ in range(K)]
    add("random_dense_p1", a0, w0, full_a, full_w, 0x1111, 0)

    # Tile 1: -32768 and clip saturation, P=12, maximum positive magnitude.
    a1 = [[-32768] * K for _ in range(16)]
    w1 = [[0x3F] * 16 for _ in range(K)]  # S=0, J=3, M=15
    add("minus32768_clip_p12_max", a1, w1, full_a, full_w, 0xC000, 1)

    # Tile 2: mixed signs at P=12 with clip on.
    a2 = [[(-32768 if (r + k) % 3 == 0 else RNG.randint(-32768, 32767))
           for k in range(K)] for r in range(16)]
    w2 = [[(0x3F if (k + c) % 2 == 0 else 0x7F) for c in range(16)]
          for k in range(K)]
    add("mixed_sign_clip_p12", a2, w2, full_a, full_w, 0xC000, 1)

    # Tile 3: four different position nibbles and clip, dynamic across J.
    a3 = [[RNG.randint(-32768, 32767) for _ in range(K)] for _ in range(16)]
    w3 = [[RNG.randrange(128) for _ in range(16)] for _ in range(K)]
    add("positions_ba98_clip1", a3, w3, full_a, full_w, 0xBA98, 1)

    # Tile 4: valid bubbles / holes in both A rows and W columns.
    a4 = [[RNG.randint(-32768, 32767) for _ in range(K)] for _ in range(16)]
    w4 = [[RNG.randrange(128) for _ in range(16)] for _ in range(K)]
    am4 = [[RNG.random() < 0.72 for _ in range(K)] for _ in range(16)]
    wm4 = [[RNG.random() < 0.72 for _ in range(16)] for _ in range(K)]
    # Ensure some PEs see zero and some see many products.
    for k in range(0, K, 5):
        for r in range(16):
            am4[r][k] = False
        for c in range(16):
            wm4[k][c] = False
    add("valid_bubbles_holes", a4, w4, am4, wm4, 0x4321, 0)

    # Tile 5: P=12 with clip off (no saturation), -32768 corner.
    a5 = [[-32768] * K for _ in range(16)]
    w5 = [[0x3F] * 16 for _ in range(K)]
    add("minus32768_clip_off_p12", a5, w5, full_a, full_w, 0xC000, 0)

    # Array-level post-completion event checks: all 256 sums are 32 for the
    # A=1/W=0x01 tile.  Flush preserves sum, clear_sum and reset clear it.
    add_event("post_flush_preserves", {"flush": 1}, 32)
    add_event("post_clear_zeros", {"clear": 1}, 0)
    add_event("post_reset_zeros", {"reset": 1}, 0)

    vec = VEC / "array_tiles.vec"
    out = LOG / "array_tiles.out"
    n = write_vectors(vec, rows)
    stdout = run_sim(vec, out)
    dumps, statuses = parse_out(out)

    failures = []
    if len(dumps) != len(tiles):
        failures.append(f"expected {len(tiles)} dumps, got {len(dumps)}")
    names = {0: "baseline", 1: "s3", 2: "s4", 3: "s5", 4: "s6", 5: "csa"}
    for ti, tile in enumerate(tiles):
        if ti >= len(dumps):
            break
        if "expected" in tile:
            exp = tile["expected"]
        else:
            exp = expected_tile(tile["a"], tile["w"], tile["am"], tile["wm"],
                                tile["pos"], tile["clip"])
        d = dumps[ti]
        for aid, nm in names.items():
            arr = d["sums"].get(aid)
            if arr is None or any(v is None for v in arr):
                failures.append(f"{tile['name']}: {nm} missing sums")
                continue
            for pe in range(256):
                if arr[pe] != exp[pe // 16][pe % 16]:
                    failures.append(
                        f"{tile['name']}: {nm} pe={pe} got={arr[pe]:#x} "
                        f"exp={exp[pe // 16][pe % 16]:#x}")
                    if len(failures) > 40:
                        break
            if len(failures) > 40:
                break
        # Drain-status contract: all candidate arrays must report empty/done.
        for aid in range(1, 6):
            e = d["e"].get(aid)
            if e is None:
                failures.append(f"{tile['name']}: missing #E for array {aid}")
            elif e[1] != 1:
                failures.append(f"{tile['name']}: array {aid} drain_done={e[1]} at dump")
        if len(failures) > 40:
            break

    # Check the reported constants against the documented formula.
    expect_const = {1: (4, 19), 2: (5, 20), 3: (6, 21), 4: (7, 22), 5: (6, 21)}
    for aid, (ped, ard) in expect_const.items():
        if dumps:
            e = dumps[0]["e"].get(aid)
            if e is not None and (e[2], e[3]) != (ped, ard):
                failures.append(
                    f"array {aid} drain constants got pe={e[2]} array={e[3]} "
                    f"expected {ped}/{ard}")

    # Exact drain_done transition check.  Status index == vector cycle.
    status_idx = {1: (1, 2), 2: (3, 4), 3: (5, 6), 4: (7, 8), 5: (9, 10)}
    drain_done_checks = []
    for tile in tiles:
        li = tile["last_input"]
        for aid, (ped, ard) in expect_const.items():
            ei, di = status_idx[aid]
            exp_cycle = li + ard
            if exp_cycle >= len(statuses):
                failures.append(f"{tile['name']}: no status at {exp_cycle}")
                continue
            before = statuses[exp_cycle - 1][di] if exp_cycle > 0 else 0
            at = statuses[exp_cycle][di]
            if before != 0 or at != 1:
                failures.append(
                    f"{tile['name']}: array {aid} drain_done before/at "
                    f"{exp_cycle-1}/{exp_cycle} = {before}/{at}, expected 0/1")
            drain_done_checks.append({
                "tile": tile["name"], "array": aid,
                "last_input": li, "expected_done_cycle": exp_cycle,
                "before": before, "at": at,
            })
        if "event_cycle" in tile:
            ec = tile["event_cycle"]
            for aid, (ped, ard) in expect_const.items():
                ei, di = status_idx[aid]
                if ec + 1 >= len(statuses) or statuses[ec + 1][di] != 1:
                    failures.append(
                        f"{tile['name']}: array {aid} not empty one cycle after "
                        f"event at {ec}")

    result = {
        "task": "ds_pe_pipeline",
        "unit": "array16",
        "vectors": n,
        "cycles": n,
        "tiles": [t["name"] for t in tiles],
        "dumps": len(dumps),
        "drain_constants": expect_const,
        "drain_done_checks": drain_done_checks,
        "failures": failures[:100],
        "pass": not failures,
        "stdout": stdout.strip().splitlines(),
    }
    (LOG / "array_tests_result.json").write_text(json.dumps(result, indent=2))
    print(f"array tiles: {len(tiles)}, {n} cycles, dumps={len(dumps)}, "
          f"mismatches={len(failures)}")
    if failures:
        print("\n".join(failures[:40]))
        raise SystemExit(1)
    print("ARRAY PASS")


if __name__ == "__main__":
    main()
