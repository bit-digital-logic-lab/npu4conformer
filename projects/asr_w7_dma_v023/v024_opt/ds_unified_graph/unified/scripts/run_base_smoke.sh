#!/usr/bin/env bash
# Focused V0.23-base smoke on the unified controller/top edits.
# Not the full 26-test closeout; these are the tests that prove the default
# (header FUSION_ALLOW clear) path still terminates and drains.
set -u
cd "$(dirname "$0")/.."
mkdir -p build logs
FAILS=0
run() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/base_${name}.log"
  timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  echo "$name rc=$rc"
  if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); fi
  if ! grep -q "SAFETY_RESULT PASS" "$log"; then
    echo "  missing SAFETY_RESULT PASS ($name)"; FAILS=$((FAILS+1))
  fi
}
iverilog -g2012 -s tb_safety_integrated -o build/tb_safety_base.vvp \
  -f filelist_safety.f tb/wc_safety_bfm.sv tb/tb_safety_integrated.sv \
  > logs/base_compile.log 2>&1 || { echo FATAL compile; exit 2; }

run normal 360 vvp build/tb_safety_base.vvp \
  +memfile=fixtures/mem_normal.hex +outfile=logs/base_normal_out.hex \
  +watchdog=120000 +mode=0
run multitask 360 vvp build/tb_safety_base.vvp \
  +memfile=fixtures/mem_multitask.hex +outfile=logs/base_multitask_out.hex \
  +watchdog=120000 +mode=5
run bad_queue_magic 180 vvp build/tb_safety_base.vvp \
  +memfile=fixtures/mem_bad_queue_magic.hex +outfile=logs/base_badq_out.hex \
  +watchdog=60000 +allow_fault=1 +expect_error=3
run bad_vec_op 180 vvp build/tb_safety_base.vvp \
  +memfile=fixtures/mem_bad_vec_op.hex +outfile=logs/base_badv_out.hex \
  +watchdog=60000 +allow_fault=1 +expect_error=7
run hold_b_c 300 vvp build/tb_safety_base.vvp \
  +memfile=fixtures/mem_normal.hex +outfile=logs/base_holdb_out.hex \
  +watchdog=60000 +allow_fault=1 +expect_error=14 +expect_iso=1 \
  +expect_requires_reset=1 +hold_b_lo=04002000 +hold_b_hi=04003000

if [ $FAILS -ne 0 ]; then echo "BASE_SMOKE_FAIL rc=$FAILS"; exit 1; fi
echo "BASE_SMOKE_PASS (focused; not the full 26-test closeout)"
