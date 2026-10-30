#!/usr/bin/env bash
# ds_resume_vector reproduction: local logic simulation only.
# No synthesis, no Vivado/STA, no board, no VNC, no git push.
# Compiles are sequential (one iverilog at a time).  Every simulation has a
# shell `timeout` and an in-TB cycle watchdog.  Any failure exits non-zero and
# result.json/reports/run_all_status.json report the same rc.
set -u
cd "$(dirname "$0")"
mkdir -p build logs reports fixtures imported
FAILS=0
: > logs/rc.txt
: > reports/regression.tsv
: > reports/check.log

record() {
  echo "$1 rc=$2 seconds=$3 log=$4" | tee -a logs/rc.txt
}

run() {
  local name="$1" tmo="$2" log="$3"; shift 3
  local t0 t1 rc
  t0=$(date +%s)
  timeout "$tmo" "$@" > "$log" 2>&1
  rc=$?
  t1=$(date +%s)
  record "$name" "$rc" "$((t1-t0))" "$log"
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name rc=$rc" >&2
    tail -20 "$log" >&2
    FAILS=$((FAILS+1))
  fi
  return "$rc"
}

case_vars() {
  python3 - "$1" <<'PY'
import json, sys
m = json.load(open(f'fixtures/cases/{sys.argv[1]}/meta.json'))
print(m['plan_base'], m['total'], m['d_addr'], m['outwords'],
      m.get('scenario', '-'), m.get('plan1', 0), m.get('plan2', 0),
      m.get('plan1_total', 0), m.get('plan1_d', 0))
PY
}

run_case() {
  local c="$1" plan_build="$2" abort_build="$3" suffix="$4" regprefix="$5"
  local plan total out outwords scen p1 p2 t1 d1
  read -r plan total out outwords scen p1 p2 t1 d1 < <(case_vars "$c")
  local dump="logs/${c}${suffix}.out.hex"
  local log="logs/${c}${suffix}.log"
  local simrc chkrc
  if [ "$scen" = "-" ]; then
    run "sim${suffix}_${c}" 300 "$log" \
      vvp "build/${plan_build}.vvp" +memfile="fixtures/cases/$c/mem.hex" \
        +plan="$plan" +total="$total" +out="$out" +outwords="$outwords" \
        +dump="$dump" +watchdog=2000000
    simrc=$?
  else
    run "sim${suffix}_${c}" 300 "$log" \
      vvp "build/${abort_build}.vvp" +memfile="fixtures/cases/$c/mem.hex" \
        +scenario="$scen" +plan1="$p1" +plan2="$p2" +total1="$t1" \
        +total2="$total" +d1="$d1" +d2="$out" +abort_after_busy=3000 \
        +dump="$dump" +watchdog=3000000
    simrc=$?
  fi
  python3 scripts/check_case.py --case "fixtures/cases/$c" --dump "$dump" \
    --log "$log" >> reports/check.log 2>&1
  chkrc=$?
  echo "${regprefix}${c} $simrc $chkrc" >> reports/regression.tsv
  if [ "$chkrc" -ne 0 ]; then
    echo "CHECK_FAIL ${regprefix}${c}" >&2
    tail -5 reports/check.log >&2
    FAILS=$((FAILS+1))
  fi
}

echo "== 0. deterministic fixtures (independent refmodel gold) =="
if ! run gen_fixtures 900 logs/gen_cases.log python3 scripts/gen_cases.py; then
  echo "FATAL fixture generation"; exit 2
fi

echo "== 0b. audit imported old logs (informational; not acceptance) =="
run audit_imported 300 logs/audit_imported.log python3 scripts/audit_imported.py

echo "== 2. frozen-source / unique-filelist checks =="
run check_frozen 120 logs/check_frozen.log python3 scripts/check_frozen.py
run check_unique_modules 120 logs/unique_modules.log python3 scripts/check_unique_modules.py

echo "== 3. sequential compile (iverilog, one at a time) =="
run compile_top 300 logs/compile_top.log \
  iverilog -g2012 -s v023_integrated_top -o build/top.vvp -f filelist_vector_fma.f
run compile_plan 300 logs/compile_plan.log \
  iverilog -g2012 -s tb_vector_fma_plan -o build/tb_plan.vvp \
    -f filelist_vector_fma.f tb/wc_graph_bfm.sv tb/tb_vector_fma_plan.sv
run compile_plan_x3 300 logs/compile_plan_x3.log \
  iverilog -g2012 -DFMA_EXTRA_STAGES=3 -s tb_vector_fma_plan -o build/tb_plan_x3.vvp \
    -f filelist_vector_fma.f tb/wc_graph_bfm.sv tb/tb_vector_fma_plan.sv
run compile_abort 300 logs/compile_abort.log \
  iverilog -g2012 -s tb_vector_fma_abort_reset -o build/tb_abort.vvp \
    -f filelist_vector_fma.f tb/wc_graph_bfm.sv tb/tb_vector_fma_abort_reset.sv

# ds_fma_deep 7-stage candidate, same vector engine and same port set
run compile_top_fma7 300 logs/compile_top_fma7.log \
  iverilog -g2012 -s v023_integrated_top -o build/top_fma7.vvp -f filelist_vector_fma7.f
run compile_plan_fma7 300 logs/compile_plan_fma7.log \
  iverilog -g2012 -s tb_vector_fma_plan -o build/tb_plan_fma7.vvp \
    -f filelist_vector_fma7.f tb/wc_graph_bfm.sv tb/tb_vector_fma_plan.sv
run compile_abort_fma7 300 logs/compile_abort_fma7.log \
  iverilog -g2012 -s tb_vector_fma_abort_reset -o build/tb_abort_fma7.vvp \
    -f filelist_vector_fma7.f tb/wc_graph_bfm.sv tb/tb_vector_fma_abort_reset.sv
run compile_fma7_latency 300 logs/compile_fma7_latency.log \
  iverilog -g2012 -s tb_fma7_latency -o build/tb_fma7_latency.vvp \
    fma7/fp32_fma_pipe.sv rtl/vector_fma_lane.sv tb/tb_fma7_latency.sv

echo "== 4. every generated case on the canonical 4-stage build =="
for cdir in fixtures/cases/*; do
  run_case "$(basename "$cdir")" tb_plan tb_abort "" ""
done

echo "== 5. latency-variable build: vector_fma_lane EXTRA_STAGES=3 =="
for c in full8734 official_fixture_1001 tail_0260 tail_0270 tail_0513 mul_0010 i16_0016; do
  run_case "$c" tb_plan_x3 tb_abort "_x3" "x3:"
done

echo "== 6. ds_fma_deep 7-stage core through the same vector engine =="
for c in full8734 official_fixture_1001 tail_0260 tail_0270 tail_0513 mul_0010 i16_0016 abort_newepoch reset_newepoch; do
  run_case "$c" tb_plan_fma7 tb_abort_fma7 "_fma7" "fma7:"
done
run sim_fma7_latency 120 logs/fma7_latency.log vvp build/tb_fma7_latency.vvp

echo "== 7. negative control (corrupted gold must be rejected) =="
run negative_control 300 logs/negative_control.log python3 scripts/negative_control.py
if ! grep -q 'overall=pass' reports/negative_control.txt 2>/dev/null; then
  echo "NEGATIVE_CONTROL_FAIL" >&2
  FAILS=$((FAILS+1))
fi

echo "== 8. random AXI backpressure seed sweep =="
run backpressure_seeds 2400 logs/backpressure_console.log bash backpressure_seeds.sh

echo "== 9. same-input baseline cycle comparison =="
run baseline_compare 2400 logs/baseline_console.log bash baseline_compare.sh

echo "== 10. summary / REPORT / result =="
run summarize 120 logs/summarize.log python3 scripts/summarize.py
run make_result 120 logs/make_result.log python3 scripts/make_result.py

echo "== run status =="
FINAL_RC=$(python3 - <<'PY'
import json
try:
    d = json.load(open('reports/run_all_status.json'))
    print(int(d.get('rc', 1)))
except Exception:
    print(1)
PY
)
if [ "$FAILS" -ne 0 ] && [ "$FINAL_RC" -eq 0 ]; then
  # Safety net: a run-stage failure that make_result somehow did not classify
  # must not leave result.json claiming PASS.
  python3 - <<'PYEOF'
import json
r = json.load(open('result.json'))
r['pass'] = False
r['run_all_exit_rc'] = 1
r['forced_fail_by_run_all'] = True
json.dump(r, open('result.json', 'w'), indent=2)
s = json.load(open('reports/run_all_status.json'))
s['rc'] = 1
s['pass'] = False
s['forced_fail_by_run_all'] = True
json.dump(s, open('reports/run_all_status.json', 'w'), indent=2)
open('REPORT.md', 'a').write('\n**RUN_ALL safety net: a stage rc was nonzero; result forced to FAIL.**\n')
PYEOF
  FINAL_RC=1
fi
echo "RUN_ALL final_rc=$FINAL_RC FAILS=$FAILS"
if [ "$FINAL_RC" -eq 0 ]; then
  echo "RUN_ALL_PASS vector op17 + 4-lane fixed-op + 7-stage-latency regression; not full-model/board acceptance"
else
  echo "RUN_ALL_FAIL"
fi
exit "$FINAL_RC"
