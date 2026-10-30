#!/usr/bin/env bash
# Random AXI backpressure sweep: the delivered wc_graph_bfm LFSR is re-seeded
# for the same input image and independent gold.  Runs on the canonical
# 4-stage build and on the 7-stage ds_fma_deep candidate build.
set -u
cd "$(dirname "$0")"
mkdir -p logs reports
: > reports/backpressure.tsv
: > logs/rc_backpressure.txt
FAILS=0

one() {
  local vvp="$1" c="$2" seed="$3" tag="$4"
  local cdir="fixtures/cases/$c"
  local plan total out outwords
  plan=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['plan_base'])")
  total=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['total'])")
  out=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['d_addr'])")
  outwords=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['outwords'])")
  timeout 900 vvp "$vvp" +memfile="$cdir/mem.hex" +plan="$plan" \
    +total="$total" +out="$out" +outwords="$outwords" \
    +dump="logs/${c}_bp_${tag}.out.hex" +seed="$seed" +watchdog=2000000 \
    > "logs/${c}_bp_${tag}.log" 2>&1
  local src=$?
  python3 scripts/check_case.py --case "$cdir" --dump "logs/${c}_bp_${tag}.out.hex" \
    --log "logs/${c}_bp_${tag}.log" > "logs/${c}_bp_${tag}.check" 2>&1
  local crc=$?
  echo "$c seed=$seed tag=$tag sim_rc=$src check_rc=$crc" | tee -a logs/rc_backpressure.txt
  echo "$c $seed $tag $src $crc" >> reports/backpressure.tsv
  if [ "$src" -ne 0 ] || [ "$crc" -ne 0 ]; then FAILS=$((FAILS+1)); fi
}

# canonical 4-stage core
one build/tb_plan.vvp official_fixture_1001 1 s1
one build/tb_plan.vvp official_fixture_1001 2 s2
one build/tb_plan.vvp official_fixture_1001 3735928559 s3
one build/tb_plan.vvp official_fixture_1001 1515870810 s4
one build/tb_plan.vvp tail_0260 7 s5
one build/tb_plan.vvp tail_0260 305419896 s6
one build/tb_plan.vvp tail_0270 3405691582 s7
one build/tb_plan.vvp mul_0010 1959364493 s8
one build/tb_plan.vvp i16_0016 1437226410 s9
one build/tb_plan.vvp full8734 2654435769 s10

# 7-stage ds_fma_deep candidate through the same vector engine
one build/tb_plan_fma7.vvp official_fixture_1001 4276993775 x7a
one build/tb_plan_fma7.vvp tail_0270 232373521 x7b
one build/tb_plan_fma7.vvp full8734 2654435769 x7c

if [ "$FAILS" -ne 0 ]; then echo "BACKPRESSURE FAILS=$FAILS"; exit 1; fi
echo "BACKPRESSURE PASS"
