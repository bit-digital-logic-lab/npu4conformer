#!/usr/bin/env bash
# V0.23 matrix P2 unified-candidate regression.
# Logic simulation only: no synthesis, no Vivado, no board, no network, no push.
# Each Verilator invocation uses -j 1 to avoid multi-task resource contention.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
RTL="$ROOT/candidate/rtl"
T="$ROOT/tests"
L="$ROOT/logs"
B=/tmp/opencode/mx_build
mkdir -p "$L" "$B" "$ROOT/traffic/raw" "$ROOT/activity" "$ROOT/traffic"
: > "$L/commands.log"; : > "$L/metrics.txt"

run() {
  local name="$1"; shift
  printf '### %s :: %s\n' "$name" "$*" >> "$L/commands.log"
  "$@" > "$L/$name.log" 2>&1
  local rc=$?
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/commands.log"
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/metrics.txt"
  case "$name" in
    run_*) grep -E "PASS|FAIL|INFO done|INFO cluster|INFO dma|MULTI_TEST_END|STROBE|TIMEOUT|PASS_FAULT|DMA_EDGE" "$L/$name.log" >> "$L/metrics.txt" || true ;;
  esac
  return $rc
}

V="verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT"
COMMON="$T/tb_engine_p2.sv $T/txn_dma_bfm.sv $RTL/block_engine_prefetch_v2.sv $RTL/block_storage_stream_v2.sv $RTL/operand_banks_dual_v2.sv $RTL/block_address_v020.sv $RTL/array16_w7_c48_cfg.sv $RTL/pe_w7_c48_cfg.sv $RTL/c_cache_banked4_pipe.sv"
BASE_COMMON="/home/yang/Desktop/项目/work/rtl/block_engine_l1bank_v020.sv /home/yang/Desktop/项目/work/rtl/block_storage_dma_prefetch.sv /home/yang/Desktop/项目/work/rtl/block_address_v020.sv /home/yang/Desktop/项目/work/rtl/operand_banks_v020.sv /home/yang/Desktop/项目/work/rtl/array16_direct_v020.sv /home/yang/Desktop/项目/work/rtl/pe_direct_v020.sv /home/yang/Desktop/项目/work/rtl/c_cache_banked4.sv"
CLUSTER="$T/tb_p2_cluster_axi.sv $T/axi128_ddr_bfm_v2.sv $RTL/matrix_p2_cluster_v2.sv $RTL/block_engine_prefetch_v2.sv $RTL/block_storage_stream_v2.sv $RTL/operand_banks_dual_v2.sv $RTL/block_address_v020.sv $RTL/array16_w7_c48_cfg.sv $RTL/pe_w7_c48_cfg.sv $RTL/c_cache_banked4_pipe.sv $RTL/axi_dma_v020_multi_v2.sv"

# ---------- skill self-tests ----------
run skill_traffic_selftest python3 /home/yang/Desktop/项目/skills/traffic-ledger/scripts/selftest.py
run skill_activity_selftest python3 /home/yang/Desktop/项目/skills/module-activity-waveform/scripts/selftest.py

# ---------- small directed blocks ----------
run build_cache_pipe iverilog -g2012 -s tb_cache_pipe -o "$B/tb_cache_pipe.vvp" "$T/tb_cache_pipe.sv" "$RTL/c_cache_banked4_pipe.sv"
run run_cache_pipe vvp "$B/tb_cache_pipe.vvp"
run build_strobe iverilog -g2012 -s tb_strobe -o "$B/tb_strobe.vvp" "$T/tb_strobe.sv" "$RTL/axi_dma_v020_multi_v2.sv"
run run_strobe vvp "$B/tb_strobe.vvp"
run build_dma_multi iverilog -g2012 -s tb_dma_multi -o "$B/tb_dma_multi.vvp" "$T/tb_dma_multi.sv" "$RTL/axi_dma_v020_multi_v2.sv"
run run_dma_multi vvp "$B/tb_dma_multi.vvp"

# ---------- storage unit / AXI boundary ----------
run build_storage_unit $V --top-module tb_storage_unit "$T/tb_storage_unit.sv" "$T/txn_dma_bfm.sv" "$RTL/block_storage_stream_v2.sv" "$RTL/operand_banks_dual_v2.sv" -Mdir "$B/su" -o "$B/tb_su"
run run_storage_unit "$B/tb_su"
run build_storage_axi $V --top-module tb_storage_axi "$T/tb_storage_axi.sv" "$T/axi128_mem_bfm_v1.sv" "$RTL/block_storage_stream_v2.sv" "$RTL/operand_banks_dual_v2.sv" "$RTL/axi_dma_v019.sv" -Mdir "$B/axi" -o "$B/tb_axi"
run run_storage_axi "$B/tb_axi"

# ---------- PIPE_STAGES = 3/4/5/6, same K96 C0 fixture ----------
for P in 3 4 5 6; do
  run build_pipe$P $V -GPIPE=$P -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_p2 $COMMON -Mdir "$B/p$P" -o "$B/tb_p$P"
  run run_pipe${P}_c0 "$B/tb_p$P" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
done
run run_pipe4_c1 "$B/tb_p4" +cvalid=1 +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt
for s in 1 2 3; do run run_pipe4_seed$s "$B/tb_p4" +seed=$s +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt; done

# ---------- other old storage/engine cases ----------
run build_k1 $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_p2 $COMMON -Mdir "$B/k1" -o "$B/tb_k1"
run run_k1 "$B/tb_k1" +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt
run build_n64 $V -GPIPE=4 -GM=32 -GN=64 -GK=64 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_p2 $COMMON -Mdir "$B/n64" -o "$B/tb_n64"
run run_n64 "$B/tb_n64" +init=fixtures/eng_n64/init.hex +exp=fixtures/eng_n64/exp_c.txt
run build_edge $V -GPIPE=4 -GM=17 -GN=19 -GK=33 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_p2 $COMMON -Mdir "$B/edge" -o "$B/tb_edge"
run run_edge "$B/tb_edge" +init=fixtures/eng_edge/init.hex +exp=fixtures/eng_edge/exp_c.txt
run build_p12 $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 -GRD_LAT=5 -GRD_GAP=12 -GWR_GAP=12 -GB_DELAY=8 --top-module tb_engine_p2 $COMMON -Mdir "$B/p12" -o "$B/tb_p12"
run run_p12 "$B/tb_p12" +pos=CCCC +init=fixtures/eng_p12/init.hex +exp=fixtures/eng_p12/exp_c.txt
run build_bp $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=60 -GB_DELAY=40 --top-module tb_engine_p2 $COMMON -Mdir "$B/bp" -o "$B/tb_bp"
run run_bp "$B/tb_bp" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run build_errrd $V -GPIPE=4 -GEXPECT_FAULT=1 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_p2 $COMMON -Mdir "$B/errrd" -o "$B/tb_errrd"
run run_errrd "$B/tb_errrd" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run build_errwr $V -GPIPE=4 -GEXPECT_FAULT=2 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_p2 $COMMON -Mdir "$B/errwr" -o "$B/tb_errwr"
run run_errwr "$B/tb_errwr" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run build_badpar $V -GPIPE=4 -GEXPECT_FAULT=3 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_p2 $COMMON -Mdir "$B/badpar" -o "$B/tb_badpar"
run run_badpar "$B/tb_badpar" +init=fixtures/eng_badpar/init.hex +exp=fixtures/eng_badpar/exp_c.txt

# ---------- read-only V020 baseline, same fixtures/BFM ----------
run build_base_fast $V -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_baseline "$T/tb_engine_baseline.sv" "$T/txn_dma_bfm.sv" $BASE_COMMON -Mdir "$B/basefast" -o "$B/tb_basefast"
run run_base_fast "$B/tb_basefast" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt
run build_base_c1 $V -GCVALID=1 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_baseline "$T/tb_engine_baseline.sv" "$T/txn_dma_bfm.sv" $BASE_COMMON -Mdir "$B/basec1" -o "$B/tb_basec1"
run run_base_c1 "$B/tb_basec1" +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt
run build_base_bp $V -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=60 -GB_DELAY=40 --top-module tb_engine_baseline "$T/tb_engine_baseline.sv" "$T/txn_dma_bfm.sv" $BASE_COMMON -Mdir "$B/basebp" -o "$B/tb_basebp"
run run_base_bp "$B/tb_basebp" +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt

# ---------- AXI cluster + activity traffic ----------
run build_cluster_k1 $V -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 --top-module tb_p2_cluster_axi $CLUSTER -Mdir "$B/cluster" -o "$B/tb_cluster"
run run_cluster_k1 "$B/tb_cluster" +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt +trace=traffic/raw/cluster_k1.csv
run build_cluster_c1_k96 $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=2048 -GA_BASE=50331648 -GB_BASE=50348032 -GC_BASE=50352128 --top-module tb_p2_cluster_axi $CLUSTER -Mdir "$B/cluster96" -o "$B/tb_cluster96"
run run_cluster_c1_k96 "$B/tb_cluster96" +cvalid=1 +init=fixtures/eng_c1/init.hex +exp=fixtures/eng_c1/exp_c.txt +trace=traffic/raw/cluster_c1_k96.csv

# ---------- independent golden regeneration ----------
rm -rf "$B/regen_k1" "$B/regen_c1"
run regen_k1 python3 "$T/gen_engine_vectors.py" --out "$B/regen_k1" --m 32 --n 32 --k 32 --c-valid 0 --seed 77 --positions 0x76543210 --clip 1 --a-base 0x03000000 --b-base 0x03002000 --c-base 0x03003000 --mem-words 1536
run regen_c1 python3 "$T/gen_engine_vectors.py" --out "$B/regen_c1" --m 64 --n 32 --k 96 --c-valid 1 --seed 222 --positions 0x76543210 --clip 1 --a-base 0x03000000 --b-base 0x03004000 --c-base 0x03005000 --mem-words 2048
run compare_golden_k1 bash -c "cmp '$B/regen_k1/init.hex' fixtures/eng_k1/init.hex && cmp '$B/regen_k1/exp_c.txt' fixtures/eng_k1/exp_c.txt"
run compare_golden_c1 bash -c "cmp '$B/regen_c1/init.hex' fixtures/eng_c1/init.hex && cmp '$B/regen_c1/exp_c.txt' fixtures/eng_c1/exp_c.txt"


# ---------- Icarus cross-simulator check of the engine ----------
run build_icarus_k1 iverilog -g2012 -s tb_engine_p2 -Ptb_engine_p2.PIPE=4 -Ptb_engine_p2.M=32 -Ptb_engine_p2.N=32 -Ptb_engine_p2.K=32 -Ptb_engine_p2.MEM_WORDS=1536 -Ptb_engine_p2.A_BASE=50331648 -Ptb_engine_p2.B_BASE=50339840 -Ptb_engine_p2.C_BASE=50343936 -Ptb_engine_p2.RD_LAT=5 -Ptb_engine_p2.RD_GAP=12 -Ptb_engine_p2.WR_GAP=12 -Ptb_engine_p2.B_DELAY=8 -o "$B/tb_ic_k1.vvp" $COMMON
run run_icarus_k1 vvp "$B/tb_ic_k1.vvp" +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt

# ---------- traffic ledger + module activity waveform ----------
run trace_k1 python3 scripts/make_trace.py traffic/raw/cluster_k1.csv --out traffic/cluster_k1.jsonl --scope 'RTL logic simulation: matrix P2 cluster K32, AXI128 BFM; not board DDR'
run ledger_k1 python3 /home/yang/Desktop/项目/skills/traffic-ledger/scripts/analyze.py traffic/cluster_k1.jsonl --out traffic/report_k1
run activity_k1 python3 /home/yang/Desktop/项目/skills/module-activity-waveform/scripts/render.py traffic/cluster_k1.jsonl --out activity/cluster_k1.html --title 'matrix P2 cluster K32: AXI + module activity'
run trace_c1_k96 python3 scripts/make_trace.py traffic/raw/cluster_c1_k96.csv --out traffic/cluster_c1_k96.jsonl --scope 'RTL logic simulation: matrix P2 cluster K96 C=1, AXI128 BFM; not board DDR'
run ledger_c1_k96 python3 /home/yang/Desktop/项目/skills/traffic-ledger/scripts/analyze.py traffic/cluster_c1_k96.jsonl --out traffic/report_c1_k96
run activity_c1_k96 python3 /home/yang/Desktop/项目/skills/module-activity-waveform/scripts/render.py traffic/cluster_c1_k96.jsonl --out activity/cluster_c1_k96.html --title 'matrix P2 cluster K96 C1: AXI + module activity'

echo "ALL DONE" >> "$L/commands.log"
cat "$L/metrics.txt"
