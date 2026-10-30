#!/usr/bin/env bash
# Unique V0.23 integrated reproduction entry.
# Logic simulation only: no synthesis, Vivado, STA, board, VNC or push.
set -u
cd "$(dirname "$0")/.."
mkdir -p build logs traces reports fixtures
FAILS=0
run() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/${name}.log"
  local t0=$(date +%s)
  timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  echo "${name} rc=${rc} seconds=$((t1-t0)) log=${log}"
  if [ $rc -ne 0 ]; then
    echo "FAIL ${name} rc=${rc}" >&2
    tail -20 "$log" >&2
    FAILS=$((FAILS+1))
  fi
  return $rc
}

echo "== 1. deterministic fixture/plan/golden =="
python3 scripts/gen_integrated_fixture.py > logs/gen_fixture.log 2>&1 || { echo "FATAL fixture"; exit 2; }

echo "== 2. integrated exact build/run =="
iverilog -g2012 -s v023_integrated_top -o build/int_top.vvp -f filelist_integrated.f > logs/compile_int_top.log 2>&1 || { echo "FATAL compile top"; exit 2; }
iverilog -g2012 -s tb_v023_integrated -o build/tb_integrated.vvp -f filelist_integrated.f tb/wc_graph_bfm.sv tb/tb_v023_integrated.sv > logs/compile_tb_int.log 2>&1 || { echo "FATAL compile tb"; exit 2; }
run integrated_run 180 vvp build/tb_integrated.vvp \
  +memfile=fixtures/mem_integrated.hex +outfile=logs/integrated_out.hex +watchdog=50000
cp logs/integrated_run.log logs/integrated_run.keep.log

echo "== 3. negative/error inputs =="
run bad_queue 90 vvp build/tb_integrated.vvp \
  +memfile=fixtures/mem_bad_queue.hex +outfile=logs/bad_queue_out.hex +watchdog=50000 +allow_fault=1
run bad_vec 90 vvp build/tb_integrated.vvp \
  +memfile=fixtures/mem_bad_vec.hex +outfile=logs/bad_vec_out.hex +watchdog=50000 +allow_fault=1

echo "== 4. exact sealed-RTL baseline chain =="
iverilog -g2012 -s tb_v023_baseline_chain -o build/tb_baseline.vvp \
  -f filelist_baseline.f tb/wc_graph_bfm.sv tb/tb_v023_baseline_chain.sv > logs/compile_baseline.log 2>&1 || { echo "FATAL compile baseline"; exit 2; }
run baseline_chain 180 vvp build/tb_baseline.vvp \
  +memfile=fixtures/mem_baseline.hex +outfile=logs/baseline_out.hex

echo "== 5. matrix V020 baseline (same M32/N32/K32 fixture) =="
if [ ! -x build/base_mx/tb_base_m32 ]; then
  mkdir -p build/base_mx
  timeout 400 verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    -GM=32 -GN=32 -GK=32 -GMEM_WORDS=2048 \
    -GA_BASE=50331648 -GB_BASE=50335744 -GC_BASE=50339840 \
    -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 \
    --top-module tb_engine_baseline \
    ../ds_matrix/tests/tb_engine_baseline.sv ../ds_matrix/tests/txn_dma_bfm.sv \
    ../../work/rtl/block_engine_l1bank_v020.sv ../../work/rtl/block_storage_dma_prefetch.sv \
    ../../work/rtl/block_address_v020.sv ../../work/rtl/operand_banks_v020.sv \
    ../../work/rtl/array16_direct_v020.sv ../../work/rtl/pe_direct_v020.sv \
    ../../work/rtl/c_cache_banked4.sv \
    -Mdir build/base_mx -o "$PWD/build/base_mx/tb_base_m32" > logs/base_mx_build.log 2>&1
  if [ $? -ne 0 ]; then echo "WARN: matrix baseline build failed (see logs/base_mx_build.log)"; FAILS=$((FAILS+1)); fi
fi
if [ -x build/base_mx/tb_base_m32 ]; then
  run base_mx_m32 120 build/base_mx/tb_base_m32 +init=fixtures/mat32/init.hex +exp=fixtures/mat32/exp_c.txt
fi

echo "== 6. output/golden checks =="
python3 scripts/check_integrated.py | tee logs/check_integrated.log || FAILS=$((FAILS+1))
python3 scripts/check_stages.py | tee logs/check_stages.log || FAILS=$((FAILS+1))

echo "== 7. trace + project skills =="
run integrated_trace_run 240 vvp build/tb_integrated.vvp \
  +memfile=fixtures/mem_integrated.hex +outfile=logs/integrated_trace_out.hex \
  +trace=traces/integrated_trace.csv +trace_enable=1 +watchdog=50000
python3 scripts/make_integrated_trace.py > logs/make_trace.log 2>&1 || FAILS=$((FAILS+1))
rm -rf reports/traffic
python3 ../../skills/traffic-ledger/scripts/analyze.py traces/integrated_trace.jsonl --out reports/traffic > logs/traffic_analyze.log 2>&1 || FAILS=$((FAILS+1))
python3 ../../skills/module-activity-waveform/scripts/render.py traces/integrated_trace.jsonl \
  --out reports/integrated_activity.html --title "V0.23 integrated superplan activity" > logs/activity_render.log 2>&1 || FAILS=$((FAILS+1))

echo "== summary =="
python3 - <<'PY'
import json,re
from pathlib import Path
def grab(p,pat,last=True):
    try:
        xs=re.findall(pat,Path(p).read_text())
        return xs[-1] if last else xs
    except Exception: return None
print(json.dumps({
 'integrated_end': grab('logs/integrated_run.log', r'INTEGRATED_END[^\n]*'),
 'integrated_result': grab('logs/integrated_run.log', r'INTEGRATED_RESULT (PASS|FAIL)'),
 'baseline_result': grab('logs/baseline_chain.log', r'BASE_CHAIN_RESULT (PASS|FAIL)'),
 'baseline_matrix': grab('logs/base_mx_m32.log', r'PASS tb_engine_baseline[^\n]*'),
 'bad_queue': grab('logs/bad_queue.log', r'INTEGRATED_END[^\n]*'),
 'bad_vec': grab('logs/bad_vec.log', r'INTEGRATED_END[^\n]*'),
 'check': json.loads(Path('reports/check_summary.json').read_text()) if Path('reports/check_summary.json').exists() else None,
}, indent=2))
PY
if [ $FAILS -ne 0 ]; then echo "RUN_ALL FAILS=$FAILS"; exit 1; fi
echo "RUN_ALL_PASS (integrated candidate only; final acceptance is gated separately)"
