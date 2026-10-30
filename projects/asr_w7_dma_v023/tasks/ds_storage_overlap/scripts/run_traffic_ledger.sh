#!/usr/bin/env bash
# Reproduce the C=0 fast-case cycle trace and traffic-ledger report.
set -u
cd "$(dirname "$0")/.."
RTL="$PWD/candidate/rtl"; T="$PWD/tests"; L="$PWD/logs"
V="verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT"
$V -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 --top-module tb_engine_overlap \
  "$T/tb_engine_overlap.sv" "$T/txn_dma_bfm.sv" \
  "$RTL/block_engine_prefetch_v1.sv" "$RTL/block_storage_stream_v1.sv" \
  "$RTL/operand_banks_dual_v1.sv" "$RTL/block_address_v020.sv" \
  "$RTL/array16_direct_v020.sv" "$RTL/pe_direct_v020.sv" "$RTL/c_cache_banked4.sv" \
  -Mdir /tmp/opencode/dso_build/engtr -o /tmp/opencode/dso_build/tb_engtr \
  > "$L/build_engine_trace.log" 2>&1
echo "build_engine_trace rc=$?" >> "$L/commands.log"
/tmp/opencode/dso_build/tb_engtr +init=fixtures/eng_c0/init.hex +exp=fixtures/eng_c0/exp_c.txt \
  +trace=traffic/cycles_c0.csv > "$L/run_engine_trace.log" 2>&1
echo "run_engine_trace rc=$?" >> "$L/commands.log"
python3 traffic/make_trace.py traffic/cycles_c0.csv traffic/engine_c0.jsonl
python3 /home/yang/.codex/skills/traffic-ledger/scripts/analyze.py traffic/engine_c0.jsonl --out traffic/report_c0
