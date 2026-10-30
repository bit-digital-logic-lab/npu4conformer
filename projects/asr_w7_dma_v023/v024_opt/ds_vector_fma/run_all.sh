#!/usr/bin/env bash
# ds_vector_fma reproduction: local logic simulation only.
# No synthesis, no Vivado/STA, no board, no VNC, no git push.
# Compiles are sequential (one iverilog at a time).  Every simulation has a
# shell `timeout` and an in-TB cycle watchdog.  Any failure exits non-zero.
set -u
cd "$(dirname "$0")"
mkdir -p build logs reports fixtures
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

echo "== 0. deterministic fixtures (independent gold) =="
if ! run gen_fixtures 600 logs/gen_cases.log python3 scripts/gen_cases.py; then
  echo "FATAL fixture generation"; exit 2
fi

echo "== 1. unique filelist =="
run check_unique_modules 120 logs/unique_modules.log python3 scripts/check_unique_modules.py

echo "== 2. sequential compile (iverilog, one at a time) =="
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

echo "== 3. per-case graph runs =="
for cdir in fixtures/cases/*; do
  c=$(basename "$cdir")
  python3 - "$c" > /tmp/ds_vector_fma_casevars <<'PY'
import json, sys
m = json.load(open(f'fixtures/cases/{sys.argv[1]}/meta.json'))
print(m['plan_base'], m['total'], m['d_addr'], m['outwords'],
      m.get('scenario', '-'), m.get('plan1', 0), m.get('plan2', 0),
      m.get('plan1_total', 0), m.get('plan1_d', 0))
PY
  read -r plan total out outwords scen p1 p2 t1 d1 < /tmp/ds_vector_fma_casevars
  if [ "$scen" = "-" ]; then
    run "sim_$c" 300 "logs/$c.log" \
      vvp build/tb_plan.vvp +memfile="$cdir/mem.hex" +plan="$plan" \
        +total="$total" +out="$out" +outwords="$outwords" \
        +dump="logs/$c.out.hex" +watchdog=200000
    simrc=$?
    python3 scripts/check_case.py --case "$cdir" --dump "logs/$c.out.hex" \
      --log "logs/$c.log" >> reports/check.log 2>&1
    chkrc=$?
    echo "$c $simrc $chkrc" >> reports/regression.tsv
    if [ "$chkrc" -ne 0 ]; then
      echo "CHECK_FAIL $c" >&2
      tail -5 reports/check.log >&2
      FAILS=$((FAILS+1))
    fi
  else
    run "sim_$c" 300 "logs/$c.log" \
      vvp build/tb_abort.vvp +memfile="$cdir/mem.hex" +scenario="$scen" \
        +plan1="$p1" +plan2="$p2" +total1="$t1" +total2="$total" \
        +d1="$d1" +d2="$out" +abort_after_busy=3000 \
        +dump="logs/$c.out.hex" +watchdog=300000
    simrc=$?
    python3 scripts/check_case.py --case "$cdir" --dump "logs/$c.out.hex" \
      --log "logs/$c.log" >> reports/check.log 2>&1
    chkrc=$?
    echo "$c $simrc $chkrc" >> reports/regression.tsv
    if [ "$chkrc" -ne 0 ]; then
      echo "CHECK_FAIL $c" >&2
      tail -5 reports/check.log >&2
      FAILS=$((FAILS+1))
    fi
  fi
done

echo "== 4. latency-variable FMA check (EXTRA_STAGES=3) =="
for c in full8734 official_fixture_1001 tail_0260 tail_0513 mul_0005 i16_0007; do
  cdir="fixtures/cases/$c"
  python3 - "$c" > /tmp/ds_vector_fma_casevars <<'PY'
import json, sys
m = json.load(open(f'fixtures/cases/{sys.argv[1]}/meta.json'))
print(m['plan_base'], m['total'], m['d_addr'], m['outwords'])
PY
  read -r plan total out outwords < /tmp/ds_vector_fma_casevars
  run "sim_x3_$c" 300 "logs/${c}_x3.log" \
    vvp build/tb_plan_x3.vvp +memfile="$cdir/mem.hex" +plan="$plan" \
      +total="$total" +out="$out" +outwords="$outwords" \
      +dump="logs/${c}_x3.out.hex" +watchdog=200000
  simrc=$?
  python3 scripts/check_case.py --case "$cdir" --dump "logs/${c}_x3.out.hex" \
    --log "logs/${c}_x3.log" >> reports/check.log 2>&1
  chkrc=$?
  echo "x3:$c $simrc $chkrc" >> reports/regression.tsv
  if [ "$chkrc" -ne 0 ]; then
    echo "CHECK_FAIL x3:$c" >&2
    tail -5 reports/check.log >&2
    FAILS=$((FAILS+1))
  fi
done

echo "== 5. negative control (a corrupted gold word must fail) =="
python3 scripts/check_case.py --case fixtures/cases/tail_0256 \
  --dump logs/tail_0256.out.hex --log logs/tail_0256.log --negative \
  > logs/negative_control.log 2>&1
nrc=$?
echo "negative_control rc=$nrc expected_failure log=logs/negative_control.log" | tee -a logs/rc.txt
if [ "$nrc" -eq 1 ] && grep -q 'CHECK_NEGATIVE_OK' logs/negative_control.log; then
  { echo "rc=1"; echo "observed=expected_failure"; } > reports/negative_control.txt
else
  { echo "rc=$nrc"; echo "observed=unexpected"; } > reports/negative_control.txt
  echo "NEGATIVE_CONTROL_FAIL rc=$nrc" >&2
  FAILS=$((FAILS+1))
fi

echo "== 6. result.json / SHA evidence =="
run make_result 120 logs/make_result.log python3 scripts/make_result.py

echo "== summary =="
if [ "$FAILS" -ne 0 ]; then
  echo "RUN_ALL FAILS=$FAILS"
  exit 1
fi
echo "RUN_ALL_PASS vector op17 + 4-lane fixed-op regression only; not full-model/board acceptance"
exit 0
