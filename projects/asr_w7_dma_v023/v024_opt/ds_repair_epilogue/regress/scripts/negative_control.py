#!/usr/bin/env python3
"""Negative control: prove the regression is not a self-fulfilling PASS.

Builds a deliberately broken copy of the engine in build/neg_rtl (all four
lanes forced to column 0's scale/bias), runs the per-column scenario, and
requires the comparison to FAIL.  The real rtl/ tree is untouched.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUILD = os.path.join(ROOT, "build", "neg_rtl")
LOGS = os.path.join(ROOT, "logs", "negctl")
EXE = os.path.join(ROOT, "build", "neg_tb")
sys.path.insert(0, HERE)
import run_suite as RS  # noqa: E402

SRC = [
    "epilogue_i48_to_f32.sv",
    "epilogue_fma_stage.sv",
    "epilogue_f32_to_i16.sv",
    "epilogue_relu.sv",
    "epilogue_lane.sv",
    "fp32_fma_pipe.sv",
    "epilogue_stream_engine_v024.sv",
]


def main():
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(LOGS, exist_ok=True)
    for f in SRC:
        shutil.copyfile(os.path.join(ROOT, "rtl", f), os.path.join(BUILD, f))
    eng = os.path.join(BUILD, "epilogue_stream_engine_v024.sv")
    with open(eng) as f:
        s = f.read()
    s2 = s.replace(".cfg_scale      (lane_scale[g])", ".cfg_scale      (lane_scale[0])")
    s2 = s2.replace(".cfg_bias       (lane_bias[g])", ".cfg_bias       (lane_bias[0])")
    if s2 == s:
        print("NEGATIVE CONTROL SETUP FAILED: patch point not found")
        return 1
    with open(eng, "w") as f:
        f.write(s2)
    cmd = ["iverilog", "-g2012", "-o", EXE] + [
        os.path.join(BUILD, f) for f in SRC
    ] + [os.path.join(ROOT, "tb/tb_epilogue_channels.sv"), "-s", "tb_epilogue_channels"]
    r = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        print("NEGATIVE CONTROL COMPILE FAILED (also a harness failure):")
        print(r.stdout[-2000:])
        return 1
    with open(os.path.join(ROOT, "vectors", "per_column_bp1.json")) as f:
        desc = json.load(f)
    RS.EXE = EXE
    RS.LOGS = LOGS
    res = RS.run_case(desc)
    out = {
        "name": "negative_control_per_column",
        "broken_rtl": "all lanes forced to lane_scale[0]/lane_bias[0]",
        "rc": res["rc"],
        "unexpectedly_passed": bool(res["pass"]),
        "errors": res["errors"][:20],
        "expected": "comparison must fail",
        "pass": (res["rc"] == 0 and not res["pass"]),
    }
    with open(os.path.join(ROOT, "NEGATIVE_CONTROL.json"), "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(f"NEGATIVE CONTROL: rc={res['rc']} pass={res['pass']} errors={len(res['errors'])}")
    if res["pass"]:
        print("ERROR: broken RTL passed the regression")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
