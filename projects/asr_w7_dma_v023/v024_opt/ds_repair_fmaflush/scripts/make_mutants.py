#!/usr/bin/env python3
"""Build negative-control mutants from the frozen sources.

Mutants are verification artefacts only; they are never part of rtl/ payload.
"""
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUT = os.path.join(ROOT, "mutants")
os.makedirs(MUT, exist_ok=True)

fixed = open(os.path.join(ROOT, "rtl", "fp32_fma_pipe.sv")).read()

# M0: trusted unfixed core (AR-001 present) -- copied from the read-only source.
src0 = "/home/yang/Desktop/项目/v024_opt/ds_fma_deep/candidate/fp32_fma_pipe.sv"
shutil.copyfile(src0, os.path.join(MUT, "m0_original_unfixed.sv"))

# M1: only in_ready is gated (out_valid left ungated) -> must fail the
# out_valid-on-flush-cycle contract check.
old = "assign out_valid = rst_n && !flush && s7_valid;"
new = "assign out_valid = s7_valid; // MUTANT: out_valid not cancelled on flush"
assert fixed.count(old) == 1
open(os.path.join(MUT, "m1_inready_only.sv"), "w").write(fixed.replace(old, new))

# M2: flush gated but reset not -> must fail the reset-barrier check.
old2 = """    assign in_ready  = rst_n && !flush && s1_ready;
    assign out_valid = rst_n && !flush && s7_valid;"""
new2 = """    assign in_ready  = !flush && s1_ready;      // MUTANT: no reset barrier
    assign out_valid = !flush && s7_valid;      // MUTANT: no reset barrier"""
assert fixed.count(old2) == 1
open(os.path.join(MUT, "m2_no_reset_gate.sv"), "w").write(fixed.replace(old2, new2))

print("mutants written to", MUT)
