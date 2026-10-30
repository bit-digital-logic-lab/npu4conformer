#!/usr/bin/env bash
# Optional extra evidence: same memfile/BFM/plan, old single-outstanding op17
# vs the new single-lane II=1 op17.  Not part of the acceptance filelist.
set -u
cd "$(dirname "$0")"
mkdir -p build logs reports
rc=0
iverilog -g2012 -s tb_vector_fma_plan -o build/tb_plan_base.vvp \
  -f filelist_baseline.f tb/wc_graph_bfm.sv tb/tb_vector_fma_plan.sv \
  > logs/compile_baseline.log 2>&1
crc=$?
echo "compile_baseline rc=$crc" | tee -a logs/rc_baseline.txt
[ "$crc" -eq 0 ] || exit 1
timeout 1200 vvp build/tb_plan_base.vvp \
  +memfile=fixtures/cases/full8734/mem.hex +plan=268468224 +total=8734 \
  +out=67219456 +outwords=8734 +dump=logs/full8734_baseline.out.hex \
  +watchdog=2000000 > logs/full8734_baseline.log 2>&1
src=$?
echo "sim_baseline rc=$src" | tee -a logs/rc_baseline.txt
python3 scripts/check_case.py --case fixtures/cases/full8734 \
  --dump logs/full8734_baseline.out.hex --log logs/full8734_baseline.log \
  > logs/check_baseline.log 2>&1
qrc=$?
echo "check_baseline rc=$qrc" | tee -a logs/rc_baseline.txt
if [ "$src" -ne 0 ] || [ "$qrc" -ne 0 ]; then rc=1; fi
# compare baseline vs new byte-for-byte
if cmp -s logs/full8734.out.hex logs/full8734_baseline.out.hex; then
  echo "baseline_vs_new byte_identical=1" | tee -a logs/rc_baseline.txt
else
  echo "baseline_vs_new byte_identical=0" | tee -a logs/rc_baseline.txt
  rc=1
fi
{
  echo "baseline_cycles=$(grep -o 'vcyc=[0-9]*' logs/full8734_baseline.log | head -1)"
  echo "new_cycles=$(grep -o 'vcyc=[0-9]*' logs/full8734.log | head -1)"
} >> logs/rc_baseline.txt
exit "$rc"
