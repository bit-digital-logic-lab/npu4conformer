#!/usr/bin/env python3
"""Reproducible local-logic regression driver for ds_closeout_fusion.

Compiles every test once (Icarus Verilog, -g2012, serial), regenerates the
deterministic fixtures, runs each case under a hard subprocess timeout, compares
the A16 dump with the independent golden, and writes result.json plus a TSV log.
No synthesis / Vivado / STA / board / VNC / push is performed.
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
LOGS = ROOT / "logs"
VEC = ROOT / "vectors"
PY = sys.executable
IVERILOG = "iverilog"
VVP = "vvp"
TIMEOUT = 900

FIXTURES = [
    ("main", 32, 32, 96, 1234),
    ("edge", 17, 19, 33, 99),
    ("n64", 32, 64, 64, 4242),
    ("k32", 32, 32, 32, 77),
]

# label, fixture, top, scale, bias, fma, relu, bp, long_mode, long_period,
# long_len, seed, lat_min, lat_max
FUSED_CASES = [
    ("fused_bp0",        "main", 0x3F000000, 0x3F800000, 1, 0,  0, 0, 240,  96,  7,   8,  32),
    ("fused_bp1_random", "main", 0x3F800001, 0x3F7FFFFF, 1, 0, 25, 0, 240,  96,  7,   8,  64),
    ("fused_bp2_wrlong", "main", 0xBF000000, 0x3F000000, 1, 0,  0, 2, 120,  90,  7,   8,  32),
    ("fused_bp3_rdlong", "main", 0x3F800001, 0xBF800000, 1, 0,  0, 1,  80,  50,  7,   8,  32),
    ("fused_bp4_heavy",  "main", 0x3F000000, 0x3F800000, 1, 1, 40, 3, 200, 150, 11,   8, 200),
    ("fused_edge",       "edge", 0x3F800001, 0xBF000000, 1, 0, 20, 0, 240,  96,  7,   8,  64),
    ("fused_n64",        "n64",  0x3F000000, 0x3F800000, 1, 0, 10, 0, 240,  96,  7,   8,  64),
    ("fused_fma0",       "main", 0x00000000, 0x00000000, 0, 0,  0, 0, 240,  96,  7,   8,  32),
    ("fused_fma2",       "main", 0x3F000000, 0x00000000, 2, 0,  0, 0, 240,  96,  7,   8,  32),
    ("fused_relu",       "main", 0xBF000000, 0x3F000000, 1, 1,  0, 0, 240,  96,  7,   8,  32),
]

UNFUSED_CASES = [
    ("unfused_bp0",        "main", 0x3F000000, 0x3F800000, 1, 0,  0, 0, 240,  96,  7,   8,  32),
    ("unfused_bp1_random", "main", 0x3F800001, 0x3F7FFFFF, 1, 0, 25, 0, 240,  96,  7,   8,  64),
    ("unfused_bp2_wrlong", "main", 0xBF000000, 0x3F000000, 1, 0,  0, 2, 120,  90,  7,   8,  32),
    ("unfused_bp3_rdlong", "main", 0x3F800001, 0xBF800000, 1, 0,  0, 1,  80,  50,  7,   8,  32),
    ("unfused_bp4_heavy",  "main", 0x3F000000, 0x3F800000, 1, 1, 40, 3, 200, 150, 11,   8, 200),
    ("unfused_edge",       "edge", 0x3F800001, 0xBF000000, 1, 0, 20, 0, 240,  96,  7,   8,  64),
    ("unfused_n64",        "n64",  0x3F000000, 0x3F800000, 1, 0, 10, 0, 240,  96,  7,   8,  64),
]

ODDTAIL_CASES = [
    ("oddtail_5w_3b", 5, 3),
    ("oddtail_1w_1b", 1, 1),
    ("oddtail_16w_16b", 16, 16),
    ("oddtail_7w_8b", 7, 8),
]


def sha(path):
    h = hashlib.sha256()
    h.update(Path(path).read_bytes())
    return h.hexdigest()


def run(cmd, log, timeout=TIMEOUT):
    LOGS.mkdir(exist_ok=True)
    t0 = time.time()
    with open(log, "w") as f:
        try:
            p = subprocess.run(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT,
                               timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            f.write("\nDRIVER_TIMEOUT\n")
            rc = 124
    return rc, round(time.time() - t0, 2)


def compile_all():
    out = {}
    cmds = {
        "tb_fused": [IVERILOG, "-g2012", "-s", "tb_fusion_cluster",
                     "-o", "build/tb_fused.vvp", "-f", "filelist_fused.f",
                     "tb/axi128_ddr_bfm_v4.sv", "tb/tb_fusion_cluster.sv"],
        "tb_unfused": [IVERILOG, "-g2012", "-s", "tb_unfused_cluster",
                       "-o", "build/tb_unfused.vvp", "-f", "filelist_unfused.f",
                       "tb/axi128_ddr_bfm_v4.sv", "tb/tb_unfused_cluster.sv"],
        "tb_oddtail": [IVERILOG, "-g2012", "-s", "tb_oddtail_writer",
                       "-o", "build/tb_oddtail.vvp", "-f", "filelist_fused.f",
                       "tb/axi128_ddr_bfm_v4.sv", "tb/tb_oddtail_writer.sv"],
        "tb_contract": [IVERILOG, "-g2012", "-s", "tb_epilogue_contract",
                        "-o", "build/tb_contract.vvp", "-f", "filelist_fused.f",
                        "tb/tb_epilogue_contract.sv"],
        "tb_fifo": [IVERILOG, "-g2012", "-s", "tb_fifo_unit",
                    "-o", "build/tb_fifo.vvp", "rtl/fusion_c48_fifo.sv",
                    "tb/tb_fifo_unit.sv"],
    }
    for name, cmd in cmds.items():
        rc, secs = run(cmd, LOGS / ("compile_%s.log" % name))
        out[name] = {"rc": rc, "seconds": secs}
        print("compile %-12s rc=%d (%.1fs)" % (name, rc, secs))
    return out


def gen_fixtures():
    out = {}
    for name, m, n, k, seed in FIXTURES:
        cmd = [PY, "scripts/gen_engine_vectors.py", "--out", "vectors/%s" % name,
               "--m", str(m), "--n", str(n), "--k", str(k), "--seed", str(seed),
               "--positions", "0x76543210", "--clip", "1", "--c-valid", "0",
               "--a-base", "0x03000000", "--b-base", "0x03002000",
               "--c-base", "0x03010000", "--mem-words", "8192"]
        rc, secs = run(cmd, LOGS / ("gen_%s.log" % name), timeout=120)
        out[name] = rc
        print("fixture %-6s rc=%d" % (name, rc))
    return out


def gold(fixture, scale, bias, fma, relu):
    cmd = [PY, "scripts/gold_fusion.py", "--dir", "vectors/%s" % fixture,
           "--scale", "0x%08x" % scale, "--bias", "0x%08x" % bias,
           "--fma", str(fma), "--relu", str(relu)]
    rc, _ = run(cmd, LOGS / "gold_last.log", timeout=300)
    if rc != 0:
        return rc
    return 0


def compare(dut, goldfile, label):
    cmd = [PY, "scripts/check_a16.py", dut, goldfile, "--label", label]
    rc, _ = run(cmd, LOGS / ("check_%s.log" % label), timeout=120)
    return rc


def parse_metrics(label, top):
    txt = (LOGS / (label + ".log")).read_text(errors="replace")
    m = {}
    if top == "fused":
        for key, pat in {
            "cycles": r"FUSION_DONE .*?cycles=(\d+)",
            "c48_beats": r"FUSION_STATS c48_beats=(\d+)",
            "a16_words": r"FUSION_STATS .*?a16_words=(\d+)",
            "a16_bytes": r"FUSION_STATS .*?a16_bytes=(\d+)",
            "fifo_peak": r"FUSION_ASSERT fifo_peak=(\d+)",
            "c48_ddr_bytes": r"FUSION_STATS .*?c48_ddr_bytes=(\d+)",
            "tiles": r"FUSION_STATS .*?tiles=(\d+)",
            "rd_beats": r"FUSION_AXI rd_beats=(\d+)",
            "rd_bytes": r"FUSION_AXI .*?rd_bytes=(\d+)",
            "wr_beats": r"FUSION_AXI .*?wr_beats=(\d+)",
            "wr_bytes": r"FUSION_AXI .*?wr_bytes=(\d+)",
            "wr_bursts": r"FUSION_AXI .*?wr_bursts=(\d+)",
            "drain_cycles": r"FUSION_DRAIN .*?drain_cycles=(\d+)",
        }.items():
            mm = re.search(pat, txt)
            if mm:
                m[key] = int(mm.group(1))
    else:
        for key, pat in {
            "cycles": r"UNFUSED_DONE .*?cycles=(\d+)",
            "matrix_cycles": r"UNFUSED_DONE .*?matrix_cycles=(\d+)",
            "tiles": r"UNFUSED_DONE .*?tiles=(\d+)",
            "rd_beats": r"UNFUSED_TRAFFIC rd_aw=(\d+)",
            "c48w_bytes": r"UNFUSED_TRAFFIC .*?c48w_bytes=(\d+)",
            "c48r_bytes": r"UNFUSED_TRAFFIC .*?c48r_bytes=(\d+)",
            "a16_bytes": r"UNFUSED_TRAFFIC .*?a16_bytes=(\d+)",
            "a16_beats": r"UNFUSED_TRAFFIC .*?a16_beats=(\d+)",
        }.items():
            mm = re.search(pat, txt)
            if mm:
                m[key] = int(mm.group(1))
    m["pass_marker"] = ("FUSION_TB_PASS" in txt) if top == "fused" else ("UNFUSED_TB_PASS" in txt)
    m["fault_marker"] = ("fault=1" in txt)
    return m


def main():
    BUILD.mkdir(exist_ok=True)
    LOGS.mkdir(exist_ok=True)
    t_start = time.time()
    result = {
        "task": "ds_closeout_fusion",
        "scope": "logic simulation only; no synthesis/Vivado/STA/board/VNC/push",
        "started": time.strftime("%Y-%m-%d %H:%M:%S"),
        "compile": {}, "fixtures": {}, "cases": [], "totals": {},
    }

    result["compile"] = compile_all()
    result["fixtures"] = gen_fixtures()
    if any(v["rc"] != 0 for v in result["compile"].values()) or any(v != 0 for v in result["fixtures"].values()):
        result["status"] = "FAIL_COMPILE_OR_FIXTURE"
        (ROOT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print("FAIL compile/fixture")
        return 1

    all_ok = True
    cases = []

    for (label, fx, scale, bias, fma, relu, bp, lm, lp, ll, seed, lmin, lmax) in FUSED_CASES:
        _fx = next(t for t in FIXTURES if t[0] == fx)
        m, n, k = _fx[1], _fx[2], _fx[3]
        if gold(fx, scale, bias, fma, relu) != 0:
            cases.append({"label": label, "rc": 1, "gold_rc": 1}); all_ok = False; continue
        shutil.copyfile(VEC / fx / "gold_a16.hex", LOGS / (label + ".gold.hex"))
        shutil.copyfile(VEC / fx / "gold_muladd_a16.hex", LOGS / (label + ".gold_muladd.hex"))
        args = [VVP, "build/tb_fused.vvp",
                "+init=vectors/%s/init.hex" % fx, "+out=logs/%s.hex" % label,
                "+m=%d" % m, "+n=%d" % n, "+k=%d" % k, "+positions=76543210",
                "+scale=%08x" % scale, "+bias=%08x" % bias,
                "+fma=%d" % fma, "+relu=%d" % relu,
                "+bp=%d" % bp, "+longmode=%d" % lm, "+longper=%d" % lp,
                "+longlen=%d" % ll, "+seed=%d" % seed,
                "+latmin=%d" % lmin, "+latmax=%d" % lmax]
        rc, secs = run(args, LOGS / (label + ".log"))
        cmprc = compare("logs/%s.hex" % label, "logs/%s.gold.hex" % label, label)
        met = parse_metrics(label, "fused")
        ok = (rc == 0 and cmprc == 0 and met.get("pass_marker") and not met.get("fault_marker"))
        all_ok &= bool(ok)
        cases.append({"label": label, "kind": "fused", "fixture": fx, "rc": rc,
                      "check_rc": cmprc, "seconds": secs, "ok": bool(ok),
                      "scale": "0x%08x" % scale, "bias": "0x%08x" % bias,
                      "fma_mode": fma, "relu": relu, "bp_pct": bp,
                      "long_mode": lm, "long_period": lp, "long_len": ll,
                      "seed": seed, "lat_min": lmin, "lat_max": lmax,
                      "dut_sha": sha(LOGS / (label + ".hex")),
                      "gold_sha": sha(LOGS / (label + ".gold.hex")),
                      "metrics": met})
        print("%-20s rc=%d check=%d ok=%s" % (label, rc, cmprc, ok))

    for (label, fx, scale, bias, fma, relu, bp, lm, lp, ll, seed, lmin, lmax) in UNFUSED_CASES:
        _fx = next(t for t in FIXTURES if t[0] == fx)
        m, n, k = _fx[1], _fx[2], _fx[3]
        if gold(fx, scale, bias, fma, relu) != 0:
            cases.append({"label": label, "rc": 1, "gold_rc": 1}); all_ok = False; continue
        shutil.copyfile(VEC / fx / "gold_a16.hex", LOGS / (label + ".gold.hex"))
        args = [VVP, "build/tb_unfused.vvp",
                "+init=vectors/%s/init.hex" % fx, "+out=logs/%s.hex" % label,
                "+m=%d" % m, "+n=%d" % n, "+k=%d" % k, "+positions=76543210",
                "+c48base=03010000", "+a16base=03020000",
                "+scale=%08x" % scale, "+bias=%08x" % bias,
                "+fma=%d" % fma, "+relu=%d" % relu,
                "+bp=%d" % bp, "+longmode=%d" % lm, "+longper=%d" % lp,
                "+longlen=%d" % ll, "+seed=%d" % seed,
                "+latmin=%d" % lmin, "+latmax=%d" % lmax]
        rc, secs = run(args, LOGS / (label + ".log"),
                       timeout=1200)
        cmprc = compare("logs/%s.hex" % label, "logs/%s.gold.hex" % label, label)
        met = parse_metrics(label, "unfused")
        ok = (rc == 0 and cmprc == 0 and met.get("pass_marker") and not met.get("fault_marker"))
        all_ok &= bool(ok)
        cases.append({"label": label, "kind": "unfused", "fixture": fx, "rc": rc,
                      "check_rc": cmprc, "seconds": secs, "ok": bool(ok),
                      "scale": "0x%08x" % scale, "bias": "0x%08x" % bias,
                      "fma_mode": fma, "relu": relu, "bp_pct": bp,
                      "long_mode": lm, "long_period": lp, "long_len": ll,
                      "seed": seed, "lat_min": lmin, "lat_max": lmax,
                      "dut_sha": sha(LOGS / (label + ".hex")),
                      "gold_sha": sha(LOGS / (label + ".gold.hex")),
                      "metrics": met})
        print("%-20s rc=%d check=%d ok=%s" % (label, rc, cmprc, ok))

    for label, words, last_bytes in ODDTAIL_CASES:
        args = [VVP, "build/tb_oddtail.vvp", "+words=%d" % words,
                "+last_bytes=%d" % last_bytes, "+addr=03000000"]
        rc, secs = run(args, LOGS / (label + ".log"), timeout=120)
        txt = (LOGS / (label + ".log")).read_text(errors="replace")
        ok = (rc == 0 and "ODDTAIL_PASS" in txt and "ODDTAIL_FAIL" not in txt)
        all_ok &= ok
        cases.append({"label": label, "kind": "oddtail", "rc": rc, "ok": ok,
                      "words": words, "last_bytes": last_bytes, "seconds": secs})
        print("%-20s rc=%d ok=%s" % (label, rc, ok))

    rc, secs = run([VVP, "build/tb_fifo.vvp"], LOGS / "fifo_unit.log", timeout=180)
    txt = (LOGS / "fifo_unit.log").read_text(errors="replace")
    ok = (rc == 0 and "FIFO_PASS" in txt and "FIFO_FAIL" not in txt)
    all_ok &= ok
    cases.append({"label": "fifo_capacity", "kind": "fifo", "rc": rc,
                  "ok": ok, "seconds": secs,
                  "log_excerpt": [l for l in txt.splitlines() if "FIFO " in l]})
    print("%-20s rc=%d ok=%s" % ("fifo_capacity", rc, ok))

    rc, secs = run([VVP, "build/tb_contract.vvp", "+vec=vectors/a16_contract_cases.txt"],
                   LOGS / "contract.log", timeout=120)
    txt = (LOGS / "contract.log").read_text(errors="replace")
    ok = (rc == 0 and "CONTRACT_PASS" in txt and "fma_mismatch=0" in txt)
    all_ok &= ok
    cases.append({"label": "epilogue_contract", "kind": "contract", "rc": rc,
                  "ok": ok, "seconds": secs,
                  "log_excerpt": [l for l in txt.splitlines() if "CONTRACT" in l]})
    print("%-20s rc=%d ok=%s" % ("epilogue_contract", rc, ok))

    result["cases"] = cases
    result["totals"] = {
        "cases": len(cases),
        "passed": sum(1 for c in cases if c.get("ok")),
        "failed": sum(1 for c in cases if not c.get("ok")),
        "elapsed_seconds": round(time.time() - t_start, 2),
    }
    result["status"] = "PASS" if all_ok else "FAIL"
    (ROOT / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    with open(LOGS / "regression.tsv", "w") as f:
        f.write("label\tkind\trc\tcheck_rc\tok\tcycles\tbytes_rd\tbytes_wr\tfifo_peak\n")
        for c in cases:
            met = c.get("metrics", {})
            f.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                c["label"], c["kind"], c.get("rc"), c.get("check_rc"), c.get("ok"),
                met.get("cycles", ""),
                met.get("rd_bytes", (met.get("rd_beats", 0) * 16) if met.get("rd_beats") else ""),
                met.get("wr_bytes", met.get("a16_bytes", "")), met.get("fifo_peak", "")))
    print("TOTAL cases=%d passed=%d failed=%d status=%s" % (
        result["totals"]["cases"], result["totals"]["passed"],
        result["totals"]["failed"], result["status"]))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
