#!/usr/bin/env bash
# V0.24 final export reproduction (logic simulation only).
# Serial compile (one iverilog at a time), shell timeout + in-TB watchdog per run,
# non-zero exit on any mismatch, missing PASS marker or non-drained normal run.
# No synthesis / Vivado / STA / board / VNC / push.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p build logs
: > logs/rc.tsv
FAILS=0

run() {
  local name="$1" tmo="$2"; shift 2
  local t0 t1 rc
  t0=$(date +%s)
  timeout "$tmo" "$@" > "logs/${name}.log" 2>&1
  rc=$?
  t1=$(date +%s)
  printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$((t1-t0))" "logs/${name}.log" >> logs/rc.tsv
  echo "${name} rc=${rc} seconds=$((t1-t0))"
  if [ "$rc" -ne 0 ]; then FAILS=$((FAILS+1)); return 1; fi
  return 0
}

require_drained() {
  local name="$1" log="logs/$1.log"
  if ! grep -q 'b_pending=0' "$log" || ! grep -q 'quiesced=1' "$log"; then
    echo "  ${name}: normal completion did not prove b_pending=0 quiesced=1"
    FAILS=$((FAILS+1))
  fi
}

echo "== 0. independent fixtures + gold =="
timeout 180 python3 scripts/sim/gen_v024_graph.py > logs/gen_v024.log 2>&1 \
  || { echo "FATAL fixture/gold generation"; exit 2; }

echo "== 1. serial compile =="
iverilog -g2012 -s v024_unified_top -o build/v024_top.vvp \
  -f filelist.f > logs/compile_top.log 2>&1 \
  || { echo "FATAL compile v024 top"; exit 2; }
iverilog -g2012 -s tb_v024_unified -o build/tb_v024.vvp \
  -f filelist.f sim/tb/wc_safety_bfm.sv sim/tb/tb_v024_unified.sv \
  > logs/compile_tb_v024.log 2>&1 \
  || { echo "FATAL compile v024 TB"; exit 2; }
iverilog -g2012 -s tb_v024_epilogue -o build/tb_epi.vvp \
  -f filelist.f sim/tb/tb_v024_epilogue.sv > logs/compile_epi.log 2>&1 \
  || { echo "FATAL compile epilogue TB"; exit 2; }
iverilog -g2012 -s tb_safety_integrated -o build/tb_safety_base.vvp \
  -f filelist.f sim/tb/wc_safety_bfm.sv sim/tb/tb_safety_integrated.sv \
  > logs/compile_base.log 2>&1 \
  || { echo "FATAL compile baseline-smoke TB"; exit 2; }

echo "== 2. fused small graph (A16 + per-channel + DIV + SQRT) =="
run v024_fused 300 vvp build/tb_v024.vvp \
  +memfile=sim/fixtures/mem_v024_fused.hex +outfile=logs/v024_fused_out.hex \
  +watchdog=100000 +mode=0 && require_drained v024_fused

echo "== 3. explicit fallback to legacy C48 path =="
run v024_fallback 300 vvp build/tb_v024.vvp \
  +memfile=sim/fixtures/mem_v024_fallback.hex +outfile=logs/v024_fallback_out.hex \
  +watchdog=100000 +mode=1 && require_drained v024_fallback

echo "== 4. multi-consumer plan -> legacy fallback =="
run v024_multicons 300 vvp build/tb_v024.vvp \
  +memfile=sim/fixtures/mem_v024_multicons.hex +outfile=logs/v024_multicons_out.hex \
  +watchdog=100000 +mode=4 && require_drained v024_multicons

echo "== 5. MATF without FUSION_ALLOW -> error 0x04 =="
run v024_badflag 120 vvp build/tb_v024.vvp \
  +memfile=sim/fixtures/mem_v024_badflag.hex +outfile=logs/v024_badflag_out.hex \
  +watchdog=40000 +mode=3 +expect_error=4

echo "== 6. fused A16 write B held -> isolation, no false drain =="
run v024_hold 300 vvp build/tb_v024.vvp \
  +memfile=sim/fixtures/mem_v024_fused.hex +outfile=logs/v024_hold_out.hex \
  +watchdog=80000 +mode=2 +hold_b_lo=04004000 +hold_b_hi=04005000

echo "== 7. directed single-rounding FMA vs mul+add =="
run v024_lane 60 vvp build/tb_epi.vvp \
  +vecfile=sim/fixtures/lane_vectors.hex \
  +goldfile=sim/fixtures/lane_gold.hex \
  +twofile=sim/fixtures/lane_muladd.hex

echo "== 8. independent judge =="
python3 scripts/analysis/check_export.py > logs/check_export.log 2>&1
CHECK_RC=$?
cat logs/check_export.log

echo "== 9. focused baseline smoke (default header, no fusion) =="
run base_normal 360 vvp build/tb_safety_base.vvp \
  +memfile=sim/fixtures/mem_normal.hex +outfile=logs/base_normal_out.hex \
  +watchdog=120000 +mode=0 && require_drained base_normal
run base_multitask 360 vvp build/tb_safety_base.vvp \
  +memfile=sim/fixtures/mem_multitask.hex +outfile=logs/base_multitask_out.hex \
  +watchdog=120000 +mode=5 && require_drained base_multitask
run base_bad_queue_magic 180 vvp build/tb_safety_base.vvp \
  +memfile=sim/fixtures/mem_bad_queue_magic.hex +outfile=logs/base_badq_out.hex \
  +watchdog=60000 +allow_fault=1 +expect_error=3
run base_bad_vec_op 180 vvp build/tb_safety_base.vvp \
  +memfile=sim/fixtures/mem_bad_vec_op.hex +outfile=logs/base_badv_out.hex \
  +watchdog=60000 +allow_fault=1 +expect_error=7
run base_hold_b_c 300 vvp build/tb_safety_base.vvp \
  +memfile=sim/fixtures/mem_normal.hex +outfile=logs/base_holdb_out.hex \
  +watchdog=60000 +allow_fault=1 +expect_error=14 +expect_iso=1 \
  +expect_requires_reset=1 +hold_b_lo=04002000 +hold_b_hi=04003000

if [ "$FAILS" -ne 0 ] || [ "$CHECK_RC" -ne 0 ]; then
  echo "RUN_EXPORT_FAIL sim_fails=$FAILS check_rc=$CHECK_RC"
  exit 1
fi
echo "RUN_EXPORT_PASS (small-graph integrated candidate + focused baseline smoke;"
echo "                 no full-model, synthesis, STA, board or frequency claim)"
