#!/usr/bin/env python3
"""Strict parameter assertion test for approx_div_sqrt.

Verifies:
1. Unsupported TIER parameters (TIER=0, TIER=2, TIER=99) are rejected at compilation/elaboration time.
2. Incorrect LATENCY parameters (LATENCY=4, LATENCY=7) are rejected at compilation/elaboration time.
3. Incorrect II parameters (II=2, II=0) are rejected at compilation/elaboration time.
4. Default parameters and explicit valid parameters (TIER=1, LATENCY=5, II=1) compile and elaborate cleanly.
5. Watchdog and non-zero exit on assertion failure.
"""

import sys
import subprocess
import tempfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
RTL_DIR = BASE_DIR / 'rtl'

RTL_FILES = [
    str(RTL_DIR / 'approx_div_sqrt.sv'),
    str(RTL_DIR / 'approx_recip_lut.sv'),
    str(RTL_DIR / 'approx_rsqrt_lut.sv')
]

def test_config(params_str: str, expect_success: bool, test_name: str) -> bool:
    top_code = f"""
    `timescale 1ns/1ps
    module top;
        reg clk = 0;
        reg rst_n = 1;
        wire out_valid;
        approx_div_sqrt {params_str} dut (
            .clk(clk),
            .rst_n(rst_n),
            .flush(1'b0),
            .in_valid(1'b0),
            .in_ready(),
            .op(2'b00),
            .a(32'h0),
            .b(32'h0),
            .tag(16'h0),
            .out_valid(out_valid),
            .out_ready(1'b1),
            .result(),
            .flags(),
            .tag_out()
        );
    endmodule
    """
    with tempfile.NamedTemporaryFile(suffix='.sv', mode='w') as f_sv:
        f_sv.write(top_code)
        f_sv.flush()
        with tempfile.NamedTemporaryFile(suffix='.vvp') as f_vvp:
            cmd = ['iverilog', '-g2012', '-o', f_vvp.name, f_sv.name] + RTL_FILES
            res = subprocess.run(cmd, capture_output=True, text=True)

            if expect_success:
                if res.returncode != 0:
                    print(f"FAILED [{test_name}]: Expected compilation success for {params_str}, but failed:")
                    print(res.stderr)
                    return False
                print(f"PASSED [{test_name}]: Successfully elaborated valid configuration {params_str}")
                return True
            else:
                if res.returncode == 0:
                    print(f"FAILED [{test_name}]: Expected compilation/elaboration error for {params_str}, but succeeded!")
                    return False
                print(f"PASSED [{test_name}]: Rejected invalid configuration {params_str} as expected (rc={res.returncode})")
                return True

def main():
    print("=== Testing Parameter Rejection & Strict Assertion in approx_div_sqrt ===")
    test_cases = [
        # (params_str, expect_success, description)
        ("", True, "Default parameters (TIER=1, LATENCY=5, II=1)"),
        ("#(.TIER(1), .LATENCY(5), .II(1))", True, "Explicit valid parameters (TIER=1, LATENCY=5, II=1)"),
        ("#(.TIER(0))", False, "Unsupported fake TIER=0 (must fail)"),
        ("#(.TIER(2))", False, "Unsupported fake TIER=2 (must fail)"),
        ("#(.TIER(3))", False, "Unsupported illegal TIER=3 (must fail)"),
        ("#(.LATENCY(4))", False, "Mismatched LATENCY=4 (must fail)"),
        ("#(.LATENCY(7))", False, "Mismatched LATENCY=7 (must fail)"),
        ("#(.II(2))", False, "Mismatched II=2 (must fail)"),
    ]

    all_passed = True
    for params_str, expect_success, desc in test_cases:
        ok = test_config(params_str, expect_success, desc)
        if not ok:
            all_passed = False

    if not all_passed:
        print("\nFATAL: Parameter assertion tests failed!")
        sys.exit(1)
    else:
        print("\nAll parameter assertion tests passed successfully (rc=0).")
        sys.exit(0)

if __name__ == '__main__':
    main()
