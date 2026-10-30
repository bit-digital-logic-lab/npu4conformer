#!/usr/bin/env bash
# ds_layout_wide — full logic-only regression (sequential, one compile at a time).
# No synthesis / Vivado / board / VNC / push.  Every simulation is bounded by an
# external timeout in the Python driver and by the in-TB cycle watchdog.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs fixtures/gold fixtures/edge fixtures/random fixtures/official

# Icarus $readmemh cannot open the non-ASCII project path directly; link into
# /tmp/opencode (points back into this directory).
ln -sfn "$PWD/fixtures/official" /tmp/opencode/dslw_official
ln -sfn "$PWD/fixtures/gold"     /tmp/opencode/dslw_gold
ln -sfn "$PWD/fixtures/edge"     /tmp/opencode/dslw_edge
ln -sfn "$PWD/fixtures/random"   /tmp/opencode/dslw_random

COMMON="tests/ddr_layout_axi_ref.sv tests/axi128_memory_bfm.sv"
BASE="rtl/ddr_layout_engine_baseline_burst.sv rtl/u16_divmod.sv rtl/axi_dma_v019.sv"
WIDE="rtl/ddr_layout_engine_wide.sv rtl/u16_divmod.sv rtl/axi_dma_v019.sv"

python3 scripts/progress.py 1 generating "independent gold / edge / official fixture set"
python3 scripts/gen_gold_fixtures.py
python3 scripts/gen_edge_fixtures.py

python3 scripts/progress.py 2 compiling "baseline + candidate + scalar variants (-j1)"
iverilog -g2012 -I tests -o build/base_official.vvp $COMMON $BASE tests/tb_layout_engine.sv      > logs/compile_base_official.log 2>&1
iverilog -g2012 -I tests -o build/base_dst.vvp      $COMMON $BASE tests/tb_layout_engine_dst.sv  > logs/compile_base_dst.log 2>&1
iverilog -g2012 -I tests -o build/base_fuzz.vvp     $COMMON $BASE tests/tb_layout_fuzz.sv       > logs/compile_base_fuzz.log 2>&1
iverilog -g2012 -I tests -o build/wide_fasttb.vvp   $COMMON $WIDE tests/tb_layout_engine_wide.sv > logs/compile_wide.log 2>&1
iverilog -g2012 -I tests -o build/wide_fuzz.vvp     $COMMON $WIDE tests/tb_layout_fuzz.sv       > logs/compile_wide_fuzz.log 2>&1

sed -e 's/parameter integer FASTPATH = 1/parameter integer FASTPATH = 0/' \
    -e 's/parameter integer MODE2_PREFETCH = 1/parameter integer MODE2_PREFETCH = 16/' \
    rtl/ddr_layout_engine_wide.sv > /tmp/opencode/dslw_scalar.sv
iverilog -g2012 -I tests -o build/wide_scalar.vvp $COMMON /tmp/opencode/dslw_scalar.sv \
  rtl/u16_divmod.sv rtl/axi_dma_v019.sv tests/tb_layout_engine_dst.sv > logs/compile_scalar.log 2>&1

sed 's/parameter integer MODE2_PREFETCH = 1/parameter integer MODE2_PREFETCH = 16/' \
    rtl/ddr_layout_engine_wide.sv > /tmp/opencode/dslw_m2p16.sv
iverilog -g2012 -I tests -o build/wide_m2p16.vvp $COMMON /tmp/opencode/dslw_m2p16.sv \
  rtl/u16_divmod.sv rtl/axi_dma_v019.sv tests/tb_layout_engine_wide.sv > logs/compile_m2p16.log 2>&1

python3 - <<'PY'
from pathlib import Path
s = Path('rtl/ddr_layout_engine_wide.sv').read_text()
old = "NEXT:begin\n      state<=LOOKUP;\n      source_part<=0;value_hi<=0;"
assert old in s, "C48 negative-control anchor missing"
Path('/tmp/opencode/dslw_bad_spreset.sv').write_text(
    s.replace(old, "NEXT:begin\n      state<=LOOKUP;"))
PY
iverilog -g2012 -I tests -o build/wide_bad_spreset.vvp $COMMON /tmp/opencode/dslw_bad_spreset.sv \
  rtl/u16_divmod.sv rtl/axi_dma_v019.sv tests/tb_layout_engine_wide.sv > logs/compile_bad_spreset.log 2>&1

python3 scripts/progress.py 3 running "official 8 normal + 12 error/ACL/lifecycle modes"
python3 scripts/run_official_suite.py > logs/run_official_stdout.log 2>&1

python3 scripts/progress.py 4 running "32 independent gold + 53 new edge fixtures"
python3 scripts/run_gold_suite.py > logs/run_gold_stdout.log 2>&1

python3 scripts/progress.py 5 running "100 preserved random + 52 new random/short-tail, independent gold"
python3 scripts/run_random.py > logs/run_random_stdout.log 2>&1

python3 scripts/progress.py 6 running "57 descriptor fuzz + scalar fallback equivalence"
python3 scripts/run_fuzz.py > logs/run_fuzz_stdout.log 2>&1
python3 scripts/check_scalar.py > logs/run_scalar_stdout.log 2>&1

python3 scripts/progress.py 7 running "mode-2 prefetch gate A/B measurement"
python3 scripts/measure_mode2.py > logs/run_mode2_stdout.log 2>&1

python3 scripts/progress.py 8 running "C48 6B cross-line negative control"
set +e
./build/wide_bad_spreset.vvp +folder=/tmp/opencode/dslw_gold/copy_tail_6b \
  +nbytes=4098 +mode=0 > logs/c48_bad_copy_tail_6b.log 2>&1
bad1=$?
./build/wide_bad_spreset.vvp +folder=/tmp/opencode/dslw_official/unpack_c48_compact \
  +nbytes=6930 +mode=0 > logs/c48_bad_unpack_c48.log 2>&1
bad2=$?
./build/wide_fasttb.vvp +folder=/tmp/opencode/dslw_gold/copy_tail_6b \
  +nbytes=4098 +mode=0 > logs/c48_fixed_copy_tail_6b.log 2>&1
good1=$?
./build/wide_fasttb.vvp +folder=/tmp/opencode/dslw_official/unpack_c48_compact \
  +nbytes=6930 +mode=0 > logs/c48_fixed_unpack_c48.log 2>&1
good2=$?
set -e
ok=1
grep -q FATAL logs/c48_bad_copy_tail_6b.log || ok=0
grep -q FATAL logs/c48_bad_unpack_c48.log || ok=0
grep -q V022_LAYOUT_AXI_PASS logs/c48_fixed_copy_tail_6b.log || ok=0
grep -q V022_LAYOUT_AXI_PASS logs/c48_fixed_unpack_c48.log || ok=0
[ "$bad1" -ne 0 ] && [ "$bad2" -ne 0 ] && [ "$good1" -eq 0 ] && [ "$good2" -eq 0 ] || ok=0
{
  echo "c48_negative_control: bad rc=$bad1,$bad2 good rc=$good1,$good2 ok=$ok"
  if [ "$ok" -eq 1 ]; then echo KNOWN_BAD_FAILED; echo FIXED_PASSED; else echo C48_NEGATIVE_CONTROL_FAILED; fi
} | tee logs/c48_negative_control.log
[ "$ok" -eq 1 ] || { echo "C48 negative control failed"; exit 1; }

python3 scripts/progress.py 9 lint "verilator lint + merge summary + hashes"
verilator --lint-only -Wall -Wno-fatal --top-module ddr_layout_engine \
  rtl/ddr_layout_engine_wide.sv rtl/u16_divmod.sv > logs/verilator_wide_lint.log 2>&1 || true
verilator --lint-only -Wall -Wno-fatal --top-module ddr_layout_engine \
  rtl/ddr_layout_engine_baseline_burst.sv rtl/u16_divmod.sv > logs/verilator_base_lint.log 2>&1 || true

python3 scripts/audit_metrics.py > logs/metric_audit.log 2>&1 || true
bash scripts/selftest_failure_rc.sh > logs/selftest_stdout.log 2>&1
python3 scripts/summarize.py > logs/summary_stdout.log 2>&1
rc=$?
python3 scripts/freeze_refs.py > logs/freeze_stdout.log 2>&1
python3 scripts/make_result.py "$rc" > logs/result_stdout.log 2>&1 || true
python3 scripts/progress.py 10 complete "all suites finished; see logs/summary.json and REPORT.md"
sha256sum rtl/*.sv tests/*.sv scripts/*.py scripts/*.sh fixtures/official/meta.json \
  fixtures/gold/meta.json fixtures/edge/meta.json INTERFACE.md REPORT.md README.md \
  result.json REFERENCE_FREEZE.json progress.json > SHA256SUMS.txt
sha256sum $(ls logs/*.log | grep -v LOGS_SHA256) > logs/LOGS_SHA256.txt
echo "ALL DONE rc=$rc"
exit $rc
