#!/usr/bin/env bash
# V0.23 ds_layout: full logic-only regression.  No synthesis / Vivado / board.
# Compiles sequentially to avoid competing with other workers for CPU/RAM.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs fixtures/gold fixtures/random

# Non-ASCII project path breaks Icarus $readmemh; use /tmp symlinks.
ln -sfn "$PWD/fixtures/gold" /tmp/opencode/ds_layout_gold
ln -sfn /home/yang/Desktop/项目/work/tests/layout_fixtures /tmp/opencode/ds_layout_fixtures

W=/home/yang/Desktop/项目/work/rtl
COMMON="tests/ddr_layout_axi_ref.sv tests/axi128_memory_bfm.sv"

echo "[1/9] generating deterministic independent-golden fixtures"
(cd scripts && python3 gen_gold_fixtures.py)

echo "[2/9] compiling official testbenches (sequential)"
iverilog -g2012 -I tests -o build/layout_orig.vvp $COMMON \
  "$W/ddr_layout_engine.sv" "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_engine.sv > logs/compile_orig.log 2>&1
iverilog -g2012 -I tests -o build/layout_v1.vvp $COMMON \
  rtl/ddr_layout_engine_v023.sv "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_engine.sv > logs/compile_v1.log 2>&1
iverilog -g2012 -I tests -o build/layout_burst.vvp $COMMON \
  rtl/ddr_layout_engine_v023_burst.sv "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_engine.sv > logs/compile_burst.log 2>&1

echo "[3/9] compiling fuzz testbenches (sequential)"
iverilog -g2012 -I tests -o build/layout_fuzz_orig.vvp $COMMON \
  "$W/ddr_layout_engine.sv" "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_fuzz.sv > logs/fuzz_compile_orig.log 2>&1
iverilog -g2012 -I tests -o build/layout_fuzz_cand.vvp $COMMON \
  rtl/ddr_layout_engine_v023_burst.sv "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_fuzz.sv > logs/fuzz_compile_burst.log 2>&1

echo "[4/9] official 8 fixtures + 12 error modes"
python3 scripts/run_official.py > logs/run_official_stdout.log 2>&1

echo "[5/9] descriptor fuzz (57 cases, original vs candidate)"
python3 scripts/gen_layout_fuzz.py > logs/run_fuzz_stdout.log 2>&1

echo "[6/9] independent golden suite and random fuzz"
python3 scripts/run_gold.py > logs/run_gold_stdout.log 2>&1
(cd scripts && python3 random_gold.py) > logs/run_random_stdout.log 2>&1

echo "[7/9] prefetch policy variant (MAX_PREFETCH=1)"
sed 's/parameter integer MAX_PREFETCH = 16/parameter integer MAX_PREFETCH = 1/' \
  rtl/ddr_layout_engine_v023_burst.sv > /tmp/opencode/ddr_layout_engine_nopf.sv
iverilog -g2012 -I tests -o build/layout_nopf.vvp $COMMON \
  /tmp/opencode/ddr_layout_engine_nopf.sv "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_engine.sv > logs/compile_nopf.log 2>&1
python3 scripts/run_prefetch_policy.py > logs/run_prefetch_stdout.log 2>&1

echo "[8/9] C48 cross-line negative control"
python3 - <<'PYEOF'
s=open('rtl/ddr_layout_engine_v023_burst.sv').read()
old="NEXT:begin\n      state<=LOOKUP;\n      source_part<=0;value_hi<=0;"
assert old in s
open('/tmp/opencode/ddr_layout_engine_no_spreset.sv','w').write(s.replace(old,"NEXT:begin\n      state<=LOOKUP;"))
PYEOF
iverilog -g2012 -I tests -o build/layout_bad_spreset.vvp $COMMON \
  /tmp/opencode/ddr_layout_engine_no_spreset.sv "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/tb_layout_engine.sv > logs/c48_known_bad_compile.log 2>&1
./build/layout_bad_spreset.vvp +folder=/tmp/opencode/ds_layout_fixtures/unpack_c48_compact \
  +nbytes=6930 +mode=0 > logs/c48_known_bad_unpack_c48_compact.log 2>&1 || true
./build/layout_bad_spreset.vvp +folder=/tmp/opencode/ds_layout_gold/copy_tail_6b \
  +nbytes=4098 +mode=0 > logs/c48_known_bad_copy_tail_6b.log 2>&1 || true
./build/layout_burst.vvp +folder=/tmp/opencode/ds_layout_fixtures/unpack_c48_compact \
  +nbytes=6930 +mode=0 > logs/c48_fixed_unpack_c48_compact.log 2>&1
./build/layout_burst.vvp +folder=/tmp/opencode/ds_layout_gold/copy_tail_6b \
  +nbytes=4098 +mode=0 > logs/c48_fixed_copy_tail_6b.log 2>&1
grep -q FATAL logs/c48_known_bad_unpack_c48_compact.log || { echo "negative control did not fail"; exit 1; }
grep -q FATAL logs/c48_known_bad_copy_tail_6b.log || { echo "negative control did not fail"; exit 1; }
grep -q PASS logs/c48_fixed_unpack_c48_compact.log || { echo "fixed C48 failed"; exit 1; }
grep -q PASS logs/c48_fixed_copy_tail_6b.log || { echo "fixed C48 failed"; exit 1; }

echo "[9/9] lint + source hashes"
verilator --lint-only -Wall -Wno-fatal --top-module ddr_layout_engine \
  rtl/ddr_layout_engine_v023.sv "$W/u16_divmod.sv" > logs/verilator_v1_lint.log 2>&1 || true
verilator --lint-only -Wall -Wno-fatal --top-module ddr_layout_engine \
  rtl/ddr_layout_engine_v023_burst.sv "$W/u16_divmod.sv" > logs/verilator_burst_lint.log 2>&1 || true
sha256sum rtl/*.sv tests/*.sv scripts/*.py fixtures/gold/meta.json \
  REPORT.md FINDINGS.md INTERFACE.md README.md result.json progress.json \
  > SHA256SUMS.txt
sha256sum $(ls logs/*.log | grep -v "LOGS_SHA256") > logs/LOGS_SHA256.txt

{
  cat logs/official_table.log
  echo
  sed -n '/^name ok/,$p' logs/layout_fuzz.log
  echo
  cat logs/gold_table.log
  echo
  tail -4 logs/random_fuzz.log
  echo
  cat logs/prefetch_policy.log
} > logs/FINAL_SUMMARY.txt

echo "ALL DONE"
grep -h "SUMMARY" logs/official_table.log logs/layout_fuzz.log logs/gold_table.log logs/random_fuzz.log logs/prefetch_policy.log
