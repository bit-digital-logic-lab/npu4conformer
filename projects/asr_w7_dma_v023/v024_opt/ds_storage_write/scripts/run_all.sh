#!/usr/bin/env bash
# V0.24 ds_storage_write regression.
# Logic simulation only: no synthesis, Vivado, STA, board, VNC or push.
# Every Verilator invocation uses -j 1.  Every simulation is wrapped in
# timeout and the testbench has an internal watchdog.  A missing PASS or a
# non-zero rc makes this script exit non-zero.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
R="$ROOT/rtl"
T="$ROOT/tests"
L="$ROOT/logs"
B=/tmp/opencode/dsw_build
V2="/home/yang/Desktop/项目/v023_repair/ds_matrix"
mkdir -p "$L" "$ROOT/reports" "$B"
: > "$L/commands.log"
: > "$L/metrics.txt"
rm -f "$L"/run_*.log "$L"/build_*.log "$L"/regen_*.log "$L"/cmp_*.log "$L"/check_reference.log
fails=0
runs=0

run_build() {
  local name="$1"; shift
  printf '### %s :: %s\n' "$name" "$*" >> "$L/commands.log"
  timeout 600 "$@" > "$L/$name.log" 2>&1
  local rc=$?
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/commands.log"
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name rc=$rc"
    fails=$((fails+1))
  else
    echo "ok   $name"
  fi
  return 0
}

run_sim() {
  local name="$1"; shift
  runs=$((runs+1))
  printf '### %s :: %s\n' "$name" "$*" >> "$L/commands.log"
  timeout 600 "$@" > "$L/$name.log" 2>&1
  local rc=$?
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/commands.log"
  if [ "$rc" -ne 0 ] || ! grep -qE 'PASS|PASS_FAULT' "$L/$name.log"; then
    echo "FAIL $name rc=$rc"
    fails=$((fails+1))
  else
    echo "ok   $name"
  fi
  return 0
}

V="verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT"
ENG="$T/tb_engine_v3.sv $T/txn_dma_bfm.sv $R/block_engine_prefetch_v3.sv $R/block_storage_stream_v3.sv $R/operand_banks_dual_v2.sv $R/block_address_v020.sv $R/array16_w7_c48_cfg.sv $R/pe_w7_c48_cfg.sv $R/c_cache_banked4_pipe.sv"
CL="$T/tb_cluster_v3.sv $T/axi128_ddr_bfm_v2.sv $R/matrix_p2_cluster_v3.sv $R/block_engine_prefetch_v3.sv $R/block_storage_stream_v3.sv $R/operand_banks_dual_v2.sv $R/block_address_v020.sv $R/array16_w7_c48_cfg.sv $R/pe_w7_c48_cfg.sv $R/c_cache_banked4_pipe.sv $R/axi_dma_v020_multi_v2.sv"
STO="$T/tb_storage_coalesce.sv $T/txn_dma_bfm.sv $R/block_storage_stream_v3.sv $R/operand_banks_dual_v2.sv"
VAL="$T/tb_validator_pipe.sv $R/block_storage_stream_v3.sv $R/operand_banks_dual_v2.sv"
REF_ENG="$V2/tests/tb_engine_p2.sv $V2/tests/txn_dma_bfm.sv $V2/candidate/rtl/block_engine_prefetch_v2.sv $V2/candidate/rtl/block_storage_stream_v2.sv $V2/candidate/rtl/operand_banks_dual_v2.sv $V2/candidate/rtl/block_address_v020.sv $V2/candidate/rtl/array16_w7_c48_cfg.sv $V2/candidate/rtl/pe_w7_c48_cfg.sv $V2/candidate/rtl/c_cache_banked4_pipe.sv"
REF_CL="$V2/tests/tb_p2_cluster_axi.sv $V2/tests/axi128_ddr_bfm_v2.sv $V2/candidate/rtl/matrix_p2_cluster_v2.sv $V2/candidate/rtl/block_engine_prefetch_v2.sv $V2/candidate/rtl/block_storage_stream_v2.sv $V2/candidate/rtl/operand_banks_dual_v2.sv $V2/candidate/rtl/block_address_v020.sv $V2/candidate/rtl/array16_w7_c48_cfg.sv $V2/candidate/rtl/pe_w7_c48_cfg.sv $V2/candidate/rtl/c_cache_banked4_pipe.sv $V2/candidate/rtl/axi_dma_v020_multi_v2.sv"

echo "== reference freeze =="
run_build check_reference python3 scripts/check_reference.py
cat "$L/check_reference.log"

echo "== independent integer gold regeneration =="
rm -rf "$B/regen_k1" "$B/regen_c1"
run_build regen_k1 python3 "$T/gen_engine_vectors.py" --out "$B/regen_k1" --m 32 --n 32 --k 32 --c-valid 0 --seed 77 --positions 0x76543210 --clip 1 --a-base 0x03000000 --b-base 0x03002000 --c-base 0x03003000 --mem-words 1536
run_build regen_c1 python3 "$T/gen_engine_vectors.py" --out "$B/regen_c1" --m 64 --n 32 --k 96 --c-valid 1 --seed 222 --positions 0x76543210 --clip 1 --a-base 0x03000000 --b-base 0x03004000 --c-base 0x03005000 --mem-words 2048
run_build cmp_gold_k1 bash -c "cmp '$B/regen_k1/init.hex' fixtures/eng_k1/init.hex && cmp '$B/regen_k1/exp_c.txt' fixtures/eng_k1/exp_c.txt"
run_build cmp_gold_c1 bash -c "cmp '$B/regen_c1/init.hex' fixtures/eng_c1/init.hex && cmp '$B/regen_c1/exp_c.txt' fixtures/eng_c1/exp_c.txt"

echo "== directed storage / validator =="
run_build build_storage_coalesce $V --top-module tb_storage_coalesce $STO -Mdir "$B/coal" -o "$B/tb_coal"
for m in native generic tail bad abortm split; do
  run_sim "run_coal_$m" "$B/tb_coal" "+$m"
done
run_build build_validator $V --top-module tb_validator_pipe $VAL -Mdir "$B/val" -o "$B/tb_val"
run_sim run_validator "$B/tb_val"

echo "== candidate engine regression =="
run_build build_eng_fast $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_fast" -o "$B/tb_eng_fast"
run_sim run_eng_fast_c0 "$B/tb_eng_fast" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run_sim run_eng_fast_c1 "$B/tb_eng_fast" +cvalid=1 +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt
for s in 1 2 3; do run_sim "run_eng_fast_seed$s" "$B/tb_eng_fast" "+seed=$s" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt; done
run_build build_eng_nosame $V -GPIPE=4 -GSAME_CYCLE=0 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_nosame" -o "$B/tb_eng_nosame"
run_sim run_eng_nosame_c0 "$B/tb_eng_nosame" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt

run_build build_eng_n64 $V -GPIPE=4 -GM=32 -GN=64 -GK=64 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_n64" -o "$B/tb_eng_n64"
run_sim run_eng_n64 "$B/tb_eng_n64" +init=fixtures/eng_n64/init.hex +exp=fixtures/eng_n64/exp_c.txt
run_build build_eng_k1 $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_k1" -o "$B/tb_eng_k1"
run_sim run_eng_k1 "$B/tb_eng_k1" +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt
run_sim run_eng_p12 "$B/tb_eng_k1" +pos=CCCC +init=fixtures/eng_p12/init.hex +exp=fixtures/eng_p12/exp_c.txt
run_build build_eng_edge $V -GPIPE=4 -GM=17 -GN=19 -GK=33 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_edge" -o "$B/tb_eng_edge"
run_sim run_eng_edge "$B/tb_eng_edge" +init=fixtures/eng_edge/init.hex +exp=fixtures/eng_edge/exp_c.txt

run_build build_eng_bp $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=60 -GB_DELAY=40 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_bp" -o "$B/tb_eng_bp"
run_sim run_eng_bp "$B/tb_eng_bp" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run_build build_eng_errrd $V -GPIPE=4 -GEXPECT_FAULT=1 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_errrd" -o "$B/tb_eng_errrd"
run_sim run_eng_errrd "$B/tb_eng_errrd" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run_build build_eng_errwr $V -GPIPE=4 -GEXPECT_FAULT=2 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_errwr" -o "$B/tb_eng_errwr"
run_sim run_eng_errwr "$B/tb_eng_errwr" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run_build build_eng_badpar $V -GPIPE=4 -GEXPECT_FAULT=3 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_v3 $ENG -Mdir "$B/eng_badpar" -o "$B/tb_eng_badpar"
run_sim run_eng_badpar "$B/tb_eng_badpar" +init=fixtures/eng_badpar/init.hex +exp=fixtures/eng_badpar/exp_c.txt

echo "== candidate AXI cluster (same strict BFM) =="
run_build build_cl_fast $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GLAT_MIN=0 -GLAT_MAX=0 -GBP_PCT=0 -GSEED=7 -GDUPLEX=0 --top-module tb_cluster_v3 $CL -Mdir "$B/cl_fast" -o "$B/tb_cl_fast"
run_sim run_cl_fast "$B/tb_cl_fast" +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt +trace="$B/cl_fast.csv"
run_build build_cl_lw $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GLAT_MIN=48 -GLAT_MAX=48 -GBP_PCT=0 -GSEED=7 -GDUPLEX=0 --top-module tb_cluster_v3 $CL -Mdir "$B/cl_lw" -o "$B/tb_cl_lw"
run_sim run_cl_lw "$B/tb_cl_lw" +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt +trace="$B/cl_lw.csv"

echo "== v023 read-only baseline, same BFM =="
run_build build_ref_eng_fast $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_p2 $REF_ENG -Mdir "$B/ref_eng_fast" -o "$B/tb_ref_eng_fast"
run_sim run_ref_eng_fast "$B/tb_ref_eng_fast" +init="$V2/fixtures/eng_c0/init.hex" +exp="$V2/fixtures/eng_c0/exp_c.txt"
run_build build_ref_eng_bp $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=60 -GB_DELAY=40 --top-module tb_engine_p2 $REF_ENG -Mdir "$B/ref_eng_bp" -o "$B/tb_ref_eng_bp"
run_sim run_ref_eng_bp "$B/tb_ref_eng_bp" +init="$V2/fixtures/eng_c0/init.hex" +exp="$V2/fixtures/eng_c0/exp_c.txt"
run_build build_ref_cl_fast $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GLAT_MIN=0 -GLAT_MAX=0 -GBP_PCT=0 -GSEED=7 -GDUPLEX=0 --top-module tb_p2_cluster_axi $REF_CL -Mdir "$B/ref_cl_fast" -o "$B/tb_ref_cl_fast"
run_sim run_ref_cl_fast "$B/tb_ref_cl_fast" +init="$V2/fixtures/eng_k1/init.hex" +exp="$V2/fixtures/eng_k1/exp_c.txt" +trace="$B/ref_cl_fast.csv"
run_build build_ref_cl_lw $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GLAT_MIN=48 -GLAT_MAX=48 -GBP_PCT=0 -GSEED=7 -GDUPLEX=0 --top-module tb_p2_cluster_axi $REF_CL -Mdir "$B/ref_cl_lw" -o "$B/tb_ref_cl_lw"
run_sim run_ref_cl_lw "$B/tb_ref_cl_lw" +init="$V2/fixtures/eng_k1/init.hex" +exp="$V2/fixtures/eng_k1/exp_c.txt" +trace="$B/ref_cl_lw.csv"
run_build build_ref_cl_wr64 $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GLAT_MIN=48 -GLAT_MAX=48 -GBP_PCT=0 -GSEED=7 -GDUPLEX=0 --top-module tb_cluster_ref_wr64 "$T/tb_cluster_ref_wr64.sv" $V2/tests/axi128_ddr_bfm_v2.sv $V2/candidate/rtl/matrix_p2_cluster_v2.sv $V2/candidate/rtl/block_engine_prefetch_v2.sv $V2/candidate/rtl/block_storage_stream_v2.sv $V2/candidate/rtl/operand_banks_dual_v2.sv $V2/candidate/rtl/block_address_v020.sv $V2/candidate/rtl/array16_w7_c48_cfg.sv $V2/candidate/rtl/pe_w7_c48_cfg.sv $V2/candidate/rtl/c_cache_banked4_pipe.sv $V2/candidate/rtl/axi_dma_v020_multi_v2.sv -Mdir "$B/ref_cl_wr64" -o "$B/tb_ref_cl_wr64"
run_sim run_ref_cl_wr64 "$B/tb_ref_cl_wr64" +init="$V2/fixtures/eng_k1/init.hex" +exp="$V2/fixtures/eng_k1/exp_c.txt" +trace="$B/ref_cl_wr64.csv"

echo "== metrics =="
python3 scripts/collect_metrics.py
python3 scripts/make_result.py "$fails"
echo "RUNS=$runs FAILS=$fails"
if [ "$fails" -ne 0 ]; then
  echo "REGRESSION FAIL"
  exit 1
fi
echo "ALL PASS"
exit 0
