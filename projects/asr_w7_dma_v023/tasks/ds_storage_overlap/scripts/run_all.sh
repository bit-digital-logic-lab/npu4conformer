#!/usr/bin/env bash
# Reproduce the ds_storage_overlap logic tests.  No synthesis, no Vivado,
# no board, no network.  Every command and rc is written to logs/commands.log.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
RTL="$ROOT/candidate/rtl"
T="$ROOT/tests"
L="$ROOT/logs"
mkdir -p "$L" /tmp/opencode/dso_build
: > "$L/commands.log"
: > "$L/metrics.txt"

run() {
  local name="$1"; shift
  printf '%s\n' "### $name :: $*" >> "$L/commands.log"
  "$@" > "$L/$name.log" 2>&1
  local rc=$?
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/commands.log"
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/metrics.txt"
  grep -E "PASS|FAIL|INFO (done|bfm|AXI)|BASE done|PASS_FAULT" "$L/$name.log" >> "$L/metrics.txt" || true
  return $rc
}

V="verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT"
CAND_COMMON="$RTL/block_engine_prefetch_v1.sv $RTL/block_storage_stream_v1.sv $RTL/operand_banks_dual_v1.sv $RTL/block_address_v020.sv $RTL/array16_direct_v020.sv $RTL/pe_direct_v020.sv $RTL/c_cache_banked4.sv"
BASE_COMMON="/home/yang/Desktop/项目/work/rtl/block_engine_l1bank_v020.sv /home/yang/Desktop/项目/work/rtl/block_storage_dma_prefetch.sv /home/yang/Desktop/项目/work/rtl/block_address_v020.sv /home/yang/Desktop/项目/work/rtl/operand_banks_v020.sv /home/yang/Desktop/项目/work/rtl/array16_direct_v020.sv /home/yang/Desktop/项目/work/rtl/pe_direct_v020.sv /home/yang/Desktop/项目/work/rtl/c_cache_banked4.sv"

# ---------------- builds ----------------
run build_storage_unit $V --top-module tb_storage_unit $T/tb_storage_unit.sv $T/txn_dma_bfm.sv $RTL/block_storage_stream_v1.sv $RTL/operand_banks_dual_v1.sv -Mdir /tmp/opencode/dso_build/su -o /tmp/opencode/dso_build/tb_su
run build_engine_fast $V -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/engf -o /tmp/opencode/dso_build/tb_engf
run build_engine_bp $V -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=60 -GB_DELAY=40 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/engbp -o /tmp/opencode/dso_build/tb_engbp
run build_engine_err_rd $V -GEXPECT_FAULT=1 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/errd -o /tmp/opencode/dso_build/tb_errd
run build_engine_err_wr $V -GEXPECT_FAULT=2 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/errw -o /tmp/opencode/dso_build/tb_errw
run build_engine_badpar $V -GEXPECT_FAULT=3 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/bp -o /tmp/opencode/dso_build/tb_bp
run build_engine_k1 $V -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/engk1 -o /tmp/opencode/dso_build/tb_engk1
run build_engine_n64 $V -GM=32 -GN=64 -GK=64 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_overlap $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON -Mdir /tmp/opencode/dso_build/engn64 -o /tmp/opencode/dso_build/tb_engn64
run build_storage_axi $V --top-module tb_storage_axi $T/tb_storage_axi.sv $T/axi128_mem_bfm_v1.sv $RTL/block_storage_stream_v1.sv $RTL/operand_banks_dual_v1.sv $RTL/axi_dma_v019.sv -Mdir /tmp/opencode/dso_build/axi -o /tmp/opencode/dso_build/tb_axi

run build_base_fast $V -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_baseline $T/tb_engine_baseline.sv $T/txn_dma_bfm.sv $BASE_COMMON -Mdir /tmp/opencode/dso_build/basef -o /tmp/opencode/dso_build/tb_basef
run build_base_bp $V -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=60 -GB_DELAY=40 --top-module tb_engine_baseline $T/tb_engine_baseline.sv $T/txn_dma_bfm.sv $BASE_COMMON -Mdir /tmp/opencode/dso_build/basebp -o /tmp/opencode/dso_build/tb_basebp
run build_base_c1 $V -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GCVALID=1 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_baseline $T/tb_engine_baseline.sv $T/txn_dma_bfm.sv $BASE_COMMON -Mdir /tmp/opencode/dso_build/basec1 -o /tmp/opencode/dso_build/tb_basec1
run build_base_k1 $V -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_baseline $T/tb_engine_baseline.sv $T/txn_dma_bfm.sv $BASE_COMMON -Mdir /tmp/opencode/dso_build/basek1 -o /tmp/opencode/dso_build/tb_basek1

# Icarus real-simulator cross-check (no Verilator in this step)
run build_icarus_k3 iverilog -g2012 -s tb_engine_overlap -Ptb_engine_overlap.M=32 -Ptb_engine_overlap.N=32 -Ptb_engine_overlap.K=96 -Ptb_engine_overlap.MEM_WORDS=1152 -Ptb_engine_overlap.A_BASE=32\'h03000000 -Ptb_engine_overlap.B_BASE=32\'h03002000 -Ptb_engine_overlap.C_BASE=32\'h03003000 -Ptb_engine_overlap.RD_LAT=2 -Ptb_engine_overlap.RD_GAP=1 -Ptb_engine_overlap.WR_GAP=1 -Ptb_engine_overlap.B_DELAY=4 -o /tmp/opencode/dso_build/tb_ic3.vvp $T/tb_engine_overlap.sv $T/txn_dma_bfm.sv $CAND_COMMON

# ---------------- runs ----------------
run run_storage_unit /tmp/opencode/dso_build/tb_su
run run_engine_fast_c0 /tmp/opencode/dso_build/tb_engf +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_seed1 /tmp/opencode/dso_build/tb_engf +seed=1 +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_seed2 /tmp/opencode/dso_build/tb_engf +seed=2 +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_seed3 /tmp/opencode/dso_build/tb_engf +seed=3 +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_c1 /tmp/opencode/dso_build/tb_engf +cvalid=1 +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt
run run_engine_bp /tmp/opencode/dso_build/tb_engbp +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_err_rd /tmp/opencode/dso_build/tb_errd +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_err_wr /tmp/opencode/dso_build/tb_errw +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_engine_badpar /tmp/opencode/dso_build/tb_bp +init=fixtures/eng_badpar/init.hex +exp=fixtures/eng_badpar/exp_c.txt
run run_engine_k1 /tmp/opencode/dso_build/tb_engk1 +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt
run run_engine_n64 /tmp/opencode/dso_build/tb_engn64 +init=fixtures/eng_n64/init.hex +exp=fixtures/eng_n64/exp_c.txt
run run_storage_axi /tmp/opencode/dso_build/tb_axi
run run_icarus_k3 vvp /tmp/opencode/dso_build/tb_ic3.vvp +init=fixtures/eng_k3_ic/init.hex +exp=fixtures/eng_k3_ic/exp_c.txt

run run_base_fast /tmp/opencode/dso_build/tb_basef +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_base_bp /tmp/opencode/dso_build/tb_basebp +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run run_base_c1 /tmp/opencode/dso_build/tb_basec1 +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt
run run_base_k1 /tmp/opencode/dso_build/tb_basek1 +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt

cp "$T/../fixtures/eng_c0/manifest.json" "$L/manifest_eng_c0.json" 2>/dev/null || true
cp "$T/../fixtures/eng_c1/manifest.json" "$L/manifest_eng_c1.json" 2>/dev/null || true
cp "$T/../fixtures/eng_k1/manifest.json" "$L/manifest_eng_k1.json" 2>/dev/null || true

echo "ALL DONE" >> "$L/commands.log"
cat "$L/metrics.txt"
