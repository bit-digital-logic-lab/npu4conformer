#!/usr/bin/env bash
# v024 ds_graph_prefetch reproducible entry.
#
# Logic simulation only.  No synthesis/Vivado/STA/board/VNC/push.
# Compilation is single-threaded (iverilog).  Every simulation has an external
# timeout and an in-TB cycle watchdog.  Expected-fault tests use allow_fault=1;
# any unexpected failure makes the TB $fatal (non-zero) and/or the checker fail.
set -uo pipefail
export MAKEFLAGS=-j1
cd "$(dirname "$0")/.."
mkdir -p build logs reports traces
FAILS=0

step() { echo "== $* =="; }
run() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/${name}.log"
  local t0=$(date +%s)
  timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  printf '%s\t%s\t%s\n' "$name" "$rc" "$((t1-t0))" >> logs/rc.tsv
  echo "${name} rc=${rc} seconds=$((t1-t0))"
  if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); fi
  return $rc
}

: > logs/rc.tsv
python3 scripts/progress.py freeze running "verify frozen reference hashes and independent gold"
python3 scripts/verify_reference.py || { echo "FATAL reference"; exit 2; }
python3 scripts/progress.py freeze done "reference frozen; independent gold recompute matches"

step "compile (single-threaded iverilog)"
iverilog -g2012 -s v023_integrated_top -o build/int_top.vvp -f filelist_graph_prefetch.f > logs/compile_top.log 2>&1 || { echo FATAL compile top; exit 2; }
iverilog -g2012 -s tb_graph_prefetch -o build/tb_gp_off.vvp -f filelist_graph_prefetch.f tb/wc_safety_bfm.sv tb/tb_graph_prefetch.sv > logs/compile_gp_off.log 2>&1 || { echo FATAL compile off; exit 2; }
iverilog -g2012 -DLOOKAHEAD_ON -s tb_graph_prefetch -o build/tb_gp_on.vvp -f filelist_graph_prefetch.f tb/wc_safety_bfm.sv tb/tb_graph_prefetch.sv > logs/compile_gp_on.log 2>&1 || { echo FATAL compile on; exit 2; }
iverilog -g2012 -DBASELINE_RTL -s tb_graph_prefetch -o build/tb_gp_base.vvp -f filelist_baseline_graph.f tb/wc_safety_bfm.sv tb/tb_graph_prefetch.sv > logs/compile_gp_base.log 2>&1 || { echo FATAL compile baseline; exit 2; }
iverilog -g2012 -s tb_axi_multi -o build/tb_axi_multi.vvp rtl/v023_axi_shared.sv tb/axi_multi_bfm.sv tb/tb_axi_multi.sv > logs/compile_axi_multi.log 2>&1 || { echo FATAL compile axi; exit 2; }
iverilog -g2012 -s tb_lookahead_safety -o build/tb_lu_safety.vvp -f filelist_graph_prefetch.f tb/wc_safety_bfm.sv tb/tb_lookahead_safety.sv > logs/compile_lu_safety.log 2>&1 || { echo FATAL compile lu safety; exit 2; }
python3 scripts/progress.py compile done "candidate/baseline/axi/lookahead-safety compiled"

step "same-input / same-BFM baseline and candidate"
python3 scripts/progress.py graph running "baseline v023, candidate lookahead off/on"
run gp_base 240 vvp build/tb_gp_base.vvp +memfile=fixtures/mem_normal.hex +watchdog=40000 +trace=traces/gp_base.csv +finalfile=logs/gp_base_final.hex +c48file=logs/gp_base_c48.hex
run gp_off 240 vvp build/tb_gp_off.vvp +memfile=fixtures/mem_normal.hex +watchdog=40000 +trace=traces/gp_off.csv +finalfile=logs/gp_off_final.hex +c48file=logs/gp_off_c48.hex
run gp_on 240 vvp build/tb_gp_on.vvp +memfile=fixtures/mem_normal.hex +watchdog=40000 +trace=traces/gp_on.csv +finalfile=logs/gp_on_final.hex +c48file=logs/gp_on_c48.hex
python3 scripts/progress.py graph done "baseline/off/on ran; outputs and C48 compared below"

step "exclusive-union / per-node ledger"
python3 scripts/ledger.py --off-log logs/gp_off.log --off-trace traces/gp_off.csv \
  --on-log logs/gp_on.log --on-trace traces/gp_on.csv \
  --json reports/ledger.json --csv reports/node_ledger.csv
[ $? -eq 0 ] || FAILS=$((FAILS+1))
python3 scripts/progress.py ledger done "legacy 59.8% artifact reproduced; exclusive union checked"

step "shared-AXI real multi-outstanding stress"
run axi_multi 120 vvp build/tb_axi_multi.vvp +watchdog=20000
python3 scripts/progress.py axi done "multi-outstanding owner/tag/B and isolation gate"

step "lookahead-enabled safety / negative suite"
bash scripts/run_lookahead_safety.sh
[ $? -eq 0 ] || FAILS=$((FAILS+1))
python3 scripts/progress.py safety done "SEQ mutex, hung child, bad queue/op, R/B hold, restart"

step "strict acceptance"
python3 scripts/check_results.py
CHECK_RC=$?
[ $CHECK_RC -eq 0 ] || FAILS=$((FAILS+1))

step "write result and hashes"
python3 scripts/write_result.py || { echo "FATAL write_result"; exit 2; }
python3 scripts/source_sha.py || { echo "FATAL source_sha"; exit 2; }
sha256sum REPORT.md INTERFACE.md USER_UPDATES.md result.json progress.json filelist_graph_prefetch.f filelist_baseline_graph.f \
  reference/REFERENCE_FREEZE.json SOURCE_SHA256.json scripts/*.py scripts/*.sh rtl/*.sv tb/*.sv \
  reports/ledger.json reports/node_ledger.csv reports/check_summary.json > SHA256SUMS.txt 2>/dev/null || true

if [ $FAILS -ne 0 ] || [ $CHECK_RC -ne 0 ]; then
  python3 scripts/progress.py final failed "one or more checks failed"
  echo "RUN_ALL_FAIL fails=$FAILS check_rc=$CHECK_RC"
  exit 1
fi
python3 scripts/progress.py final done "all required checks passed; full model still not claimed"
echo "RUN_ALL_PASS (local logic candidate only; full model/board/STA not claimed)"
