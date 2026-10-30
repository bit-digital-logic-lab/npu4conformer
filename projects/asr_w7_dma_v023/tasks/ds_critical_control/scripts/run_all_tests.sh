#!/usr/bin/env bash
# Reproduce all logic-only checks.  No synthesis, no Vivado, no board access.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build logs
TMP=/tmp/opencode/dscc_run
mkdir -p "$TMP"
cp fixtures/storage_stim.hex "$TMP/stim.hex"
ln -sfn /home/yang/Desktop/项目/work/tests/layout_fixtures /tmp/opencode/dscc_fixtures

W=../../work/rtl
C=candidate/rtl

# ---- compile pairs in parallel (-j2 style) --------------------------------
iverilog -g2012 -I tests -o build/layout_orig.vvp tests/ddr_layout_axi_ref.sv \
  "$W/ddr_layout_engine.sv" "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/axi128_memory_bfm.sv tests/tb_layout_engine.sv \
  > logs/layout_compile_orig.log 2>&1 & p1=$!
iverilog -g2012 -I tests -o build/layout_cand.vvp tests/ddr_layout_axi_ref.sv \
  "$C/ddr_layout_engine_pipe_v1.sv" "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/axi128_memory_bfm.sv tests/tb_layout_engine.sv \
  > logs/layout_compile_cand.log 2>&1 & p2=$!
wait $p1 $p2

python3 scripts/run_layout_equiv.py > logs/layout_equiv_run.log 2>&1

iverilog -g2012 -I tests -o build/layout_fuzz_orig.vvp tests/ddr_layout_axi_ref.sv \
  "$W/ddr_layout_engine.sv" "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/axi128_memory_bfm.sv tests/tb_layout_fuzz.sv \
  > logs/layout_fuzz_compile_orig.log 2>&1 & p3=$!
iverilog -g2012 -I tests -o build/layout_fuzz_cand.vvp tests/ddr_layout_axi_ref.sv \
  "$C/ddr_layout_engine_pipe_v1.sv" "$W/u16_divmod.sv" "$W/axi_dma_v019.sv" \
  tests/axi128_memory_bfm.sv tests/tb_layout_fuzz.sv \
  > logs/layout_fuzz_compile_cand.log 2>&1 & p4=$!
wait $p3 $p4
python3 scripts/gen_layout_fuzz.py > logs/layout_fuzz_run.log 2>&1

iverilog -g2012 -I tests -o build/storage_orig.vvp \
  "$W/block_storage_dma_prefetch.sv" tests/tb_storage_equiv.sv \
  > logs/storage_compile_orig.log 2>&1 & p5=$!
iverilog -g2012 -I tests -o build/storage_cand.vvp \
  "$C/block_storage_dma_wide4_pipe_v1.sv" tests/tb_storage_equiv.sv \
  > logs/storage_compile_cand.log 2>&1 & p6=$!
wait $p5 $p6
vvp build/storage_orig.vvp +stim="$TMP/stim.hex" +log="$TMP/storage_orig.log" \
  > logs/storage_stdout_orig.log 2>&1
vvp build/storage_cand.vvp +stim="$TMP/stim.hex" +log="$TMP/storage_cand.log" \
  > logs/storage_stdout_cand.log 2>&1
cp "$TMP/storage_orig.log" logs/storage_equiv_orig.log
cp "$TMP/storage_cand.log" logs/storage_equiv_cand.log
diff -u logs/storage_equiv_orig.log logs/storage_equiv_cand.log \
  > logs/storage_equiv_diff.log || { echo "storage mismatch"; exit 1; }

SRC="tests/block_engine_simfix_v020.sv $W/block_address_v020.sv $W/array16_direct_v020.sv \
  $W/pe_direct_v020.sv $W/operand_banks_v020.sv $W/c_cache_banked4.sv"
iverilog -g2012 -I tests -o build/block_orig.vvp $SRC \
  "$W/block_storage_dma_prefetch.sv" tests/tb_block_integration.sv \
  > logs/block_compile_orig.log 2>&1 & p7=$!
iverilog -g2012 -I tests -o build/block_cand.vvp $SRC \
  "$C/block_storage_dma_wide4_pipe_v1.sv" tests/tb_block_integration.sv \
  > logs/block_compile_cand.log 2>&1 & p8=$!
wait $p7 $p8
: > logs/block_integration.log
for cfg in "32 32 32" "64 32 64"; do
  set -- $cfg
  echo "CFG $1 $2 $3" >> logs/block_integration.log
  vvp build/block_orig.vvp +m=$1 +n=$2 +k=$3 +log="$TMP/block_orig_$1_$2_$3.log" \
    >> logs/block_integration.log 2>&1
  vvp build/block_cand.vvp +m=$1 +n=$2 +k=$3 +log="$TMP/block_cand_$1_$2_$3.log" \
    >> logs/block_integration.log 2>&1
  cat "$TMP/block_orig_$1_$2_$3.log" >> logs/block_integration.log
  cat "$TMP/block_cand_$1_$2_$3.log" >> logs/block_integration.log
done

verilator --lint-only -Wall -Wno-fatal --top-module block_storage_dma_wide4 \
  "$C/block_storage_dma_wide4_pipe_v1.sv" > logs/verilator_storage_lint.log 2>&1 || true
verilator --lint-only -Wall -Wno-fatal --top-module ddr_layout_engine \
  "$C/ddr_layout_engine_pipe_v1.sv" "$W/u16_divmod.sv" > logs/verilator_layout_lint.log 2>&1 || true

python3 scripts/calc_bounds.py >/dev/null
sha256sum "$C"/*.sv tests/*.sv scripts/*.py scripts/*.sh > SHA256SUMS.txt

echo "ALL LOGIC TESTS COMPLETE"
grep -E '^SUMMARY' logs/layout_equiv_run.log logs/layout_fuzz_run.log || true
echo "storage cases: $(wc -l < logs/storage_equiv_orig.log), diff bytes: $(wc -c < logs/storage_equiv_diff.log)"
grep '^BLOCK ' logs/block_integration.log || true
