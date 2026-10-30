#!/usr/bin/env bash
# Same-input, same-BFM, same-plan comparison against the read-only v023
# single-outstanding op17 engine.  This is evidence only; it is not the
# canonical filelist.  Runs the canonical 4-stage new engine and the 7-stage
# ds_fma_deep candidate on the same images after the baseline.
set -u
cd "$(dirname "$0")"
mkdir -p build logs reports
: > logs/rc_baseline.txt
rc=0

iverilog -g2012 -s tb_vector_fma_plan -o build/tb_plan_base.vvp \
  -f filelist_baseline.f tb/wc_graph_bfm.sv tb/tb_vector_fma_plan.sv \
  > logs/compile_baseline.log 2>&1
crc=$?
echo "compile_baseline rc=$crc" | tee -a logs/rc_baseline.txt
[ "$crc" -eq 0 ] || exit 1

one() {
  local c="$1"
  local cdir="fixtures/cases/$c"
  local plan total out outwords
  plan=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['plan_base'])")
  total=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['total'])")
  out=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['d_addr'])")
  outwords=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['outwords'])")

  timeout 1800 vvp build/tb_plan_base.vvp \
    +memfile="$cdir/mem.hex" +plan="$plan" +total="$total" \
    +out="$out" +outwords="$outwords" \
    +dump="logs/${c}_baseline.out.hex" +seed=1 +watchdog=4000000 \
    > "logs/${c}_baseline.log" 2>&1
  local src=$?
  python3 scripts/check_case.py --case "$cdir" \
    --dump "logs/${c}_baseline.out.hex" --log "logs/${c}_baseline.log" \
    > "logs/check_${c}_baseline.log" 2>&1
  local qrc=$?
  local same=0
  if cmp -s "logs/${c}.out.hex" "logs/${c}_baseline.out.hex"; then same=1; fi
  local bc nc xc
  bc=$(grep -o 'vcyc=[0-9]*' "logs/${c}_baseline.log" | head -1 | cut -d= -f2)
  nc=$(grep -o 'vcyc=[0-9]*' "logs/${c}.log" | head -1 | cut -d= -f2)
  xc=$(grep -o 'vcyc=[0-9]*' "logs/${c}_fma7.log" 2>/dev/null | head -1 | cut -d= -f2)
  echo "${c}_sim_baseline rc=$src" | tee -a logs/rc_baseline.txt
  echo "${c}_check_baseline rc=$qrc" | tee -a logs/rc_baseline.txt
  echo "${c}_baseline_vs_new byte_identical=$same" | tee -a logs/rc_baseline.txt
  echo "${c}_cycles baseline=${bc:-NA} new4=${nc:-NA} new7=${xc:-NA}" | tee -a logs/rc_baseline.txt
  if [ "$src" -ne 0 ] || [ "$qrc" -ne 0 ] || [ "$same" -ne 1 ]; then rc=1; fi
}

# full 8,734-element plan, the 270-element tail bank, the official fixture
one full8734
one tail_0270
one official_fixture_1001

if [ "$rc" -eq 0 ]; then
  echo "BASELINE PASS byte_identical=3/3" | tee -a logs/rc_baseline.txt
else
  echo "BASELINE FAIL" | tee -a logs/rc_baseline.txt
fi
exit "$rc"
