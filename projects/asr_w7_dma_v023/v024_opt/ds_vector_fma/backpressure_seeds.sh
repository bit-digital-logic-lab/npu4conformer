#!/usr/bin/env bash
# Extra random-backpressure evidence: the delivered wc_graph_bfm LFSR is
# re-seeded; the same input image and gold are used.  Not a new RTL test.
set -u
cd "$(dirname "$0")"
mkdir -p logs reports
: > reports/backpressure.tsv
: > logs/rc_backpressure.txt
FAILS=0

one() {
  local c="$1" seed="$2" tag="$3"
  local cdir="fixtures/cases/$c"
  local plan total out outwords
  plan=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['plan_base'])")
  total=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['total'])")
  out=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['d_addr'])")
  outwords=$(python3 -c "import json;m=json.load(open('$cdir/meta.json'));print(m['outwords'])")
  timeout 300 vvp build/tb_plan.vvp +memfile="$cdir/mem.hex" +plan="$plan" \
    +total="$total" +out="$out" +outwords="$outwords" \
    +dump="logs/${c}_bp_${tag}.out.hex" +seed="$seed" +watchdog=200000 \
    > "logs/${c}_bp_${tag}.log" 2>&1
  local src=$?
  python3 scripts/check_case.py --case "$cdir" --dump "logs/${c}_bp_${tag}.out.hex" \
    --log "logs/${c}_bp_${tag}.log" > "logs/${c}_bp_${tag}.check" 2>&1
  local crc=$?
  echo "$c seed=$seed tag=$tag sim_rc=$src check_rc=$crc" | tee -a logs/rc_backpressure.txt
  echo "$c $seed $tag $src $crc" >> reports/backpressure.tsv
  if [ "$src" -ne 0 ] || [ "$crc" -ne 0 ]; then FAILS=$((FAILS+1)); fi
}

one official_fixture_1001 1 s1
one official_fixture_1001 2 s2
one official_fixture_1001 3735928559 s3
one official_fixture_1001 1515870810 s4
one full8734 2654435769 s5

if [ "$FAILS" -ne 0 ]; then echo "BACKPRESSURE FAILS=$FAILS"; exit 1; fi
echo "BACKPRESSURE PASS"
