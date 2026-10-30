#!/usr/bin/env bash
# V0.24 unified candidate reproduction (logic simulation only).
# Single-threaded compile, bounded runs, non-zero exit on any failure.
# No synthesis / Vivado / STA / board / VNC / push.
set -u
cd "$(dirname "$0")/.."
mkdir -p build logs fixtures
: > logs/rc.tsv
FAILS=0
run() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/${name}.log"
  local t0=$(date +%s)
  timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$((t1-t0))" "$log" >> logs/rc.tsv
  echo "${name} rc=${rc} seconds=$((t1-t0))"
  if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); fi
}

echo "== 0. independent fixtures + gold =="
python3 scripts/gen_v024_graph.py > logs/gen_v024.log 2>&1 || { echo FATAL gen; exit 2; }

echo "== 1. single-threaded compile =="
iverilog -g2012 -s v024_unified_top -o build/v024_top.vvp \
  -f filelist_v024_unified.f > logs/compile_top_v024.log 2>&1 \
  || { echo FATAL compile top; exit 2; }
iverilog -g2012 -s tb_v024_unified -o build/tb_v024.vvp \
  -f filelist_v024_unified.f tb/wc_safety_bfm.sv tb/tb_v024_unified.sv \
  > logs/compile_tb_v024.log 2>&1 || { echo FATAL compile tb; exit 2; }
iverilog -g2012 -s tb_v024_epilogue -o build/tb_epi.vvp \
  -f filelist_v024_unified.f tb/tb_v024_epilogue.sv \
  > logs/compile_epi.log 2>&1 || { echo FATAL compile epi; exit 2; }

echo "== 2. fused small graph (A16 + per-channel + DIV + SQRT) =="
run v024_fused 300 vvp build/tb_v024.vvp \
  +memfile=fixtures/mem_v024_fused.hex +outfile=logs/v024_fused_out.hex \
  +watchdog=100000 +mode=0

echo "== 3. explicit-request fallback to legacy C48 path =="
run v024_fallback 300 vvp build/tb_v024.vvp \
  +memfile=fixtures/mem_v024_fallback.hex +outfile=logs/v024_fallback_out.hex \
  +watchdog=100000 +mode=1

echo "== 4. plan rejection: MATF without header FUSION_ALLOW =="
run v024_badflag 120 vvp build/tb_v024.vvp \
  +memfile=fixtures/mem_v024_badflag.hex +outfile=logs/v024_badflag_out.hex \
  +watchdog=40000 +mode=3 +expect_error=4

echo "== 5. fused A16 write B held: watchdog isolation, no false drain =="
run v024_hold 300 vvp build/tb_v024.vvp \
  +memfile=fixtures/mem_v024_fused.hex +outfile=logs/v024_hold_out.hex \
  +watchdog=80000 +mode=2 +hold_b_lo=04004000 +hold_b_hi=04005000

echo "== 6. directed single-rounding FMA vs mul+add =="
run v024_lane 60 vvp build/tb_epi.vvp

echo "== 7. independent judge =="
python3 scripts/check_v024.py > logs/check_v024.log 2>&1
CHECK_RC=$?
cat logs/check_v024.log

echo "== 8. SHA =="
sha256sum REPORT.md result.json INTERFACE.md filelist_v024_unified.f progress.json \
  USER_UPDATES.md scripts/*.py scripts/*.sh rtl/*.sv tb/*.sv \
  fixtures/v024_ref.json fixtures/gold_a16.hex fixtures/gold_fallback_i16.hex \
  fixtures/lane_vectors.hex fixtures/lane_gold.hex fixtures/lane_muladd.hex \
  > SHA256SUMS.txt 2>/dev/null || true

if [ $FAILS -ne 0 ] || [ $CHECK_RC -ne 0 ]; then
  echo "RUN_V024_FAIL rc=$FAILS check_rc=$CHECK_RC"
  exit 1
fi
echo "RUN_V024_PASS (unified candidate; whole-model/synthesis not claimed)"
