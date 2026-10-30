#!/usr/bin/env bash
# V0.23 abnormal-closeout reproduction (logic simulation only).
# No synthesis, Vivado, STA, board, VNC or push.  Every simulation is bounded
# by both `timeout` and the testbench's own cycle watchdog; the rc of every run
# is recorded in logs/rc.tsv.  Compilation is single-threaded (iverilog).
set -u
cd "$(dirname "$0")/.."
mkdir -p build logs reports fixtures
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

echo "== 0. fixtures (independent generator; no RTL output used) =="
python3 scripts/gen_mutex_fixtures.py > logs/gen_mutex.log 2>&1 || { echo FATAL mutex fixtures; exit 2; }
python3 scripts/gen_safety_fixtures.py > logs/gen_safety.log 2>&1 || { echo FATAL safety fixtures; exit 2; }

echo "== 1. unique safety build (single-threaded) =="
iverilog -g2012 -s v023_integrated_top -o build/int_top.vvp -f filelist_safety.f > logs/compile_top.log 2>&1 || { echo FATAL compile top; exit 2; }
iverilog -g2012 -s tb_safety_integrated -o build/tb_safety.vvp -f filelist_safety.f tb/wc_safety_bfm.sv tb/tb_safety_integrated.sv > logs/compile_safety_tb.log 2>&1 || { echo FATAL compile safety tb; exit 2; }
iverilog -g2012 -DPATCHED -s tb_graph_mutex -o build/tb_mutex_p.vvp rtl/wc_graph_ctrl.sv rtl/axi_dma_v019.sv tb/wc_safety_bfm.sv tb/tb_graph_mutex.sv > logs/compile_mutex_p.log 2>&1 || { echo FATAL compile mutex patched; exit 2; }
iverilog -g2012 -s tb_graph_mutex -o build/tb_mutex_b.vvp integrated_copy/rtl/wc_graph_ctrl.sv rtl/axi_dma_v019.sv tb/wc_safety_bfm.sv tb/tb_graph_mutex.sv > logs/compile_mutex_b.log 2>&1 || { echo FATAL compile mutex baseline; exit 2; }
iverilog -g2012 -s tb_axi_reset_hazard -o build/tb_hazard.vvp rtl/v023_axi_shared.sv tb/tb_axi_reset_hazard.sv > logs/compile_hazard.log 2>&1 || { echo FATAL compile hazard; exit 2; }

echo "== 2. normal exact path + per-op counters =="
run safety_normal 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/safety_normal_out.hex +watchdog=40000 +mode=0
run safety_multitask 120 vvp build/tb_safety.vvp +memfile=fixtures/mem_multitask.hex +outfile=logs/safety_multitask_out.hex +watchdog=60000 +mode=5

echo "== 3. SEQ-exclusive ownership: patched vs delivered negative control =="
run mutex_lay_patched 60 vvp build/tb_mutex_p.vvp +memfile=fixtures/mutex_lay_first.hex +watchdog=20000 +lay_delay=300 +seq_done_delay=300 +expect_no_overlap=1
run mutex_lay_baseline 60 vvp build/tb_mutex_b.vvp +memfile=fixtures/mutex_lay_first.hex +watchdog=20000 +lay_delay=300 +seq_done_delay=300 +expect_no_overlap=1
run mutex_seq_patched 60 vvp build/tb_mutex_p.vvp +memfile=fixtures/mutex_seq_first.hex +watchdog=20000 +lay_delay=300 +seq_done_delay=300 +expect_no_overlap=1
run mutex_seq_baseline 60 vvp build/tb_mutex_b.vvp +memfile=fixtures/mutex_seq_first.hex +watchdog=20000 +lay_delay=300 +seq_done_delay=300 +expect_no_overlap=1
run mutex_healthy_patched 60 vvp build/tb_mutex_p.vvp +memfile=fixtures/mutex_healthy.hex +watchdog=20000 +lay_delay=40 +seq_done_delay=20 +expect_no_overlap=1

echo "== 4. real hung SEQ child =="
run mutex_hang_wait_patched 60 vvp build/tb_mutex_p.vvp +memfile=fixtures/mutex_hang_wait.hex +watchdog=5000 +mode=1 +expect_iso=1 +expect_fault=1
run mutex_hang_wait_baseline 60 vvp build/tb_mutex_b.vvp +memfile=fixtures/mutex_hang_wait.hex +watchdog=5000 +mode=1
run mutex_hang_run_patched 60 vvp build/tb_mutex_p.vvp +memfile=fixtures/mutex_hang_run.hex +watchdog=5000 +mode=2 +expect_iso=1 +expect_fault=1
run mutex_hang_run_baseline 60 vvp build/tb_mutex_b.vvp +memfile=fixtures/mutex_hang_run.hex +watchdog=5000 +mode=2

echo "== 5. bad queue / illegal operator =="
run bad_queue_magic 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_queue_magic.hex +outfile=logs/bad_queue_magic_out.hex +watchdog=40000 +allow_fault=1 +expect_error=3
run bad_queue_backend 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_queue_backend.hex +outfile=logs/bad_queue_backend_out.hex +watchdog=40000 +allow_fault=1 +expect_error=3
run bad_queue_pred 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_queue_pred.hex +outfile=logs/bad_queue_pred_out.hex +watchdog=40000 +allow_fault=1 +expect_error=4
run bad_queue_overlap 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_queue_overlap.hex +outfile=logs/bad_queue_overlap_out.hex +watchdog=40000 +allow_fault=1 +expect_error=129
run bad_mat_op 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_mat_op.hex +outfile=logs/bad_mat_op_out.hex +watchdog=40000 +allow_fault=1 +expect_error=129
run bad_vec_op 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_vec_op.hex +outfile=logs/bad_vec_op_out.hex +watchdog=40000 +allow_fault=1 +expect_error=7
run bad_lay_mode 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_bad_lay_mode.hex +outfile=logs/bad_lay_mode_out.hex +watchdog=40000 +allow_fault=1 +expect_error=7

echo "== 6. AXI permanent-response wait and drain boundary =="
run safety_hold_r_plan 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/hold_r_plan_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_r_lo=10000000 +hold_r_hi=10040000
run safety_hold_r_c 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/hold_r_c_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_r_lo=04002000 +hold_r_hi=04003000
run safety_hold_b_c 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/hold_b_c_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_b_lo=04002000 +hold_b_hi=04003000
run safety_hold_b_d0 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/hold_b_d0_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_b_lo=04004000 +hold_b_hi=04005000
run safety_hold_r_c_delayed 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/hold_r_c_delayed_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +expect_quiesced=1 +hold_r_lo=04002000 +hold_r_hi=04003000 +release_after=15450
run safety_restart 90 vvp build/tb_safety.vvp +memfile=fixtures/mem_normal.hex +outfile=logs/restart_out.hex +watchdog=40000 +allow_fault=1 +expect_error=14 +expect_iso=1 +expect_requires_reset=1 +hold_r_lo=10000000 +hold_r_hi=10040000 +test_restart=1

echo "== 7. AXI reset-reuse hazard proof =="
run axi_reset_hazard 60 vvp build/tb_hazard.vvp

echo "== 8. sealed same-load baseline (read-only RTL) =="
sed 's#\.\./\.\./work/rtl#/home/yang/Desktop/项目/work/rtl#g' integrated_copy/filelist_baseline.f > filelist_baseline_local.f
( cd integrated_copy && iverilog -g2012 -s tb_v023_baseline_chain -o build/tb_baseline.vvp -f ../filelist_baseline_local.f tb/wc_graph_bfm.sv tb/tb_v023_baseline_chain.sv > ../logs/compile_baseline_local.log 2>&1 )
run baseline_chain_local 180 vvp integrated_copy/build/tb_baseline.vvp +memfile=integrated_copy/fixtures/mem_baseline.hex +outfile=logs/baseline_out.hex

echo "== 9. evaluate =="
python3 scripts/check_safety.py > logs/check_safety.log 2>&1
CHECK_RC=$?
cat logs/check_safety.log

echo "== 10. SHA =="
sha256sum REPORT.md result.json INTERFACE.md filelist_safety.f progress.json \
  USER_UPDATES.md PATCH.diff SOURCE_SHA256.json scripts/*.py scripts/*.sh \
  rtl/*.sv tb/*.sv > SHA256SUMS.txt 2>/dev/null || true

if [ $FAILS -ne 0 ] || [ $CHECK_RC -ne 0 ]; then
  echo "RUN_SAFETY_FAIL rc=$FAILS check_rc=$CHECK_RC"
  exit 1
fi
echo "RUN_SAFETY_PASS (safety closeout only; full model is not accepted)"
