#!/usr/bin/env bash
# Lookahead-enabled safety/negative regression.  Every run is bounded by an
# external timeout and the TB watchdog; the TB is compiled with $fatal on
# local failure, so a bad run is non-zero.
set -u
cd "$(dirname "$0")/.."
mkdir -p logs
: > logs/rc_lookahead.tsv
FAILS=0
run() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/${name}.log"
  local t0=$(date +%s)
  timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  printf '%s\t%s\t%s\n' "$name" "$rc" "$((t1-t0))" >> logs/rc_lookahead.tsv
  echo "${name} rc=${rc} seconds=$((t1-t0))"
  if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); fi
}

run lu_normal 180 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/lu_normal_out.hex +watchdog=40000 +mode=0
run lu_multitask 240 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_multitask.hex +outfile=logs/lu_multitask_out.hex +watchdog=60000 +mode=5
run lu_seq_lay 90 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_seq_lay_first.hex +watchdog=20000 +mode=1 +seq_ready_delay=4 +seq_done_delay=20
run lu_seq_seq 90 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_seq_seq_first.hex +watchdog=20000 +mode=2 +seq_ready_delay=4 +seq_done_delay=20
run lu_hang_wait 90 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_seq_hang_wait.hex +watchdog=5000 +mode=3 +expect_iso=1 +allow_fault=1
run lu_hang_run 90 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_seq_hang_run.hex +watchdog=5000 +mode=4 +expect_iso=1 +allow_fault=1
run lu_bad_queue 120 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_bad_queue_magic.hex +outfile=logs/lu_bad_queue_out.hex +watchdog=40000 +allow_fault=1 +expect_error=3
run lu_bad_vec 120 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_bad_vec_op.hex +outfile=logs/lu_bad_vec_out.hex +watchdog=40000 +allow_fault=1 +expect_error=7
run lu_bad_lay 120 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_bad_lay_mode.hex +outfile=logs/lu_bad_lay_out.hex +watchdog=40000 +allow_fault=1 +expect_error=7
run lu_hold_r_c 120 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/lu_hold_r_c_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_r_lo=04002000 +hold_r_hi=04003000
run lu_hold_b_c 120 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/lu_hold_b_c_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_b_lo=04002000 +hold_b_hi=04003000
run lu_restart 120 vvp build/tb_lu_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/lu_restart_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_r_lo=10000000 +hold_r_hi=10040000 +test_restart=1

if [ $FAILS -ne 0 ]; then
  echo "LOOKAHEAD_SAFETY_FAIL rc=$FAILS"
  exit 1
fi
echo "LOOKAHEAD_SAFETY_PASS"
