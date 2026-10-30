#!/usr/bin/env bash
# Reproduce the small-chain cycle comparison.
# Logic simulation only: no synthesis, Vivado, STA, board, VNC or push.
# Single-job compilation: iverilog is used without any parallel job flag.
set -u
cd "$(dirname "$0")"
mkdir -p build logs reports runs
export MAKEFLAGS=-j1

echo "== 1. independent input/gold verification =="
python3 scripts/verify_inputs.py > logs/verify_inputs.log 2>&1 || { echo "FATAL input check"; cat logs/verify_inputs.log; exit 2; }

echo "== 2. compile candidate (frozen integrated snapshot RTL) =="
iverilog -g2012 -s tb_chain_integrated -o build/tb_candidate.vvp \
  -f filelist_candidate.f rtl_harness/axi128_bfm_scenario.sv tb/tb_chain_integrated.sv \
  > logs/compile_candidate.log 2>&1 || { echo "FATAL candidate compile"; cat logs/compile_candidate.log; exit 2; }

echo "== 3. compile host-sequenced sealed baseline =="
iverilog -g2012 -s tb_chain_baseline -o build/tb_baseline.vvp \
  -f filelist_baseline_full.f rtl_harness/axi128_bfm_scenario.sv tb/tb_chain_baseline.sv \
  > logs/compile_baseline.log 2>&1 || { echo "FATAL baseline compile"; cat logs/compile_baseline.log; exit 2; }

run_one() {
  local mode="$1" who="$2" d="runs/$1/$2"
  mkdir -p "$d"
  (
    cd "$d"
    rm -f run.log out.hex stage_c48.hex stage_d0.hex stage_d1.hex stage_d2.hex stage_i16.hex
    if [ "$who" = candidate ]; then
      timeout 240 vvp ../../../build/tb_candidate.vvp \
        +memfile=../../../inputs/mem_integrated.hex +outfile=out.hex \
        +watchdog=120000 +lat_mode="$mode" +seed=1 > run.log 2>&1
    else
      timeout 240 vvp ../../../build/tb_baseline.vvp \
        +memfile=../../../inputs/mem_integrated.hex +outfile=out.hex \
        +exp=../../../inputs/mat32/exp_c.txt \
        +watchdog=120000 +lat_mode="$mode" +seed=1 > run.log 2>&1
    fi
    rc=$?
    echo "$mode $who rc=$rc"
    exit $rc
  ) || { echo "FATAL $mode $who"; tail -20 "$d/run.log"; exit 3; }
}

echo "== 4. three identical scenarios (seed=1) =="
for mode in default rand_bp long_wait; do
  run_one "$mode" candidate
  run_one "$mode" baseline
done

echo "== 4b. watchdog self-test (deliberately tiny watchdog; must fire) =="
mkdir -p runs/watchdog_selftest/candidate
(
  cd runs/watchdog_selftest/candidate
  rm -f run.log out.hex stage_*.hex
  timeout 60 vvp ../../../build/tb_candidate.vvp \
    +memfile=../../../inputs/mem_integrated.hex +outfile=out.hex \
    +watchdog=100 +lat_mode=default +seed=1 > run.log 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then echo "FATAL watchdog self-test unexpectedly passed"; exit 1; fi
  grep -q "WATCHDOG_FIRED" run.log || { echo "FATAL watchdog diagnostic missing"; exit 1; }
  echo "watchdog self-test rc=$rc (expected nonzero) and diagnostic present"
) || { echo "FATAL watchdog self-test did not behave as expected"; exit 3; }

echo "== 5. output, C48 and interval checks =="
python3 scripts/check_results.py > logs/check_results.log 2>&1 || { echo "FATAL result check"; cat logs/check_results.log; exit 4; }

echo "== 6. source/input/log SHA manifest =="
python3 scripts/make_manifest.py > logs/make_manifest.log 2>&1 || { echo "FATAL manifest"; cat logs/make_manifest.log; exit 5; }

echo "== summary =="
python3 - <<'PY'
import json
r=json.load(open('result.json'))
print(json.dumps({
  'all_outputs_and_c48_match_gold': r['all_outputs_and_c48_match_gold'],
  'status': r['status'],
  'scenarios': {s: v['delta'] for s,v in r['scenarios'].items()},
}, indent=2))
PY
echo "RUN_ALL_DONE (small chain only; full system remains PENDING)"
