#!/usr/bin/env bash
# Numeric closeout reproduction: local logic simulation only.
# No synthesis, no Vivado/STA, no board, no VNC, no git push.
# All compiles are sequential (iverilog is invoked one at a time); every
# simulation has a shell timeout and an in-TB cycle watchdog.
set -u
cd "$(dirname "$0")"
mkdir -p build logs reports fixtures
FAILS=0
run() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/${name}.log"
  local t0=$(date +%s)
  timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local t1=$(date +%s)
  echo "${name} rc=${rc} seconds=$((t1-t0)) log=${log}" | tee -a logs/rc.txt
  if [ $rc -ne 0 ]; then
    echo "FAIL ${name} rc=${rc}" >&2
    tail -20 "$log" >&2
    FAILS=$((FAILS+1))
  fi
  return $rc
}

: > logs/rc.txt
echo "== 0. deterministic fixture / plan / independent golden =="
python3 scripts/gen_closeout_fixtures.py > logs/gen_fixtures.log 2>&1 || { echo "FATAL fixture"; exit 2; }
python3 scripts/check_unique_modules.py > logs/unique_modules.log 2>&1 || FAILS=$((FAILS+1))

echo "== 1. sequential compile (iverilog, one at a time) =="
iverilog -g2012 -s v023_integrated_top -o build/top_closeout.vvp \
  -f filelist_closeout_numeric.f > logs/compile_top.log 2>&1
rc=$?; echo "compile_top rc=$rc" | tee -a logs/rc.txt
[ $rc -eq 0 ] || FAILS=$((FAILS+1))
iverilog -g2012 -Wall -s v023_integrated_top -o build/top_closeout_lint.vvp \
  -f filelist_closeout_numeric.f > logs/lint_compile.log 2>&1
echo "compile_lint rc=$?" | tee -a logs/rc.txt
iverilog -g2012 -DUSE_APPROX=0 -s tb_closeout_numeric -o build/tb_closeout_exact.vvp \
  -f filelist_closeout_numeric.f tb/wc_graph_bfm.sv tb/tb_closeout_numeric.sv > logs/compile_exact.log 2>&1 \
  || { echo "FATAL compile exact"; exit 2; }
iverilog -g2012 -DUSE_APPROX=1 -s tb_closeout_numeric -o build/tb_closeout_approx.vvp \
  -f filelist_closeout_numeric.f tb/wc_graph_bfm.sv tb/tb_closeout_numeric.sv > logs/compile_approx.log 2>&1 \
  || { echo "FATAL compile approx"; exit 2; }

echo "== 2. exact baseline (FMA op17 + DIV op3 + SQRT op4) =="
run exact 360 vvp build/tb_closeout_exact.vvp \
  +memfile=fixtures/mem_closeout.hex +watchdog=300000
cp -f logs/fma_out.hex logs/exact_fma.hex
cp -f logs/div_out.hex logs/exact_div.hex
cp -f logs/sqrt_out.hex logs/exact_sqrt.hex

echo "== 3. candidate approx (same plan/load) =="
run approx 240 vvp build/tb_closeout_approx.vvp \
  +memfile=fixtures/mem_closeout.hex +watchdog=60000
cp -f logs/fma_out.hex logs/approx_fma.hex
cp -f logs/div_out.hex logs/approx_div.hex
cp -f logs/sqrt_out.hex logs/approx_sqrt.hex

echo "== 4. abort drain + new-epoch isolation =="
run abort 180 vvp build/tb_closeout_approx.vvp \
  +memfile=fixtures/mem_closeout.hex +scenario=1 +abort_at=2500 +watchdog=60000
cp -f logs/fma2_out.hex logs/abort_fma2.hex

echo "== 5. reset + new-epoch isolation =="
run reset 180 vvp build/tb_closeout_approx.vvp \
  +memfile=fixtures/mem_closeout.hex +scenario=2 +reset_at=3000 +watchdog=60000
cp -f logs/fma2_out.hex logs/reset_fma2.hex

echo "== 6. independent check =="
python3 scripts/check_closeout.py > logs/check.log 2>&1
rc=$?; cat logs/check.log
echo "check rc=$rc" | tee -a logs/rc.txt
[ $rc -eq 0 ] || FAILS=$((FAILS+1))

echo "== 6b. integration patch + result.json =="
python3 scripts/make_evidence.py > logs/make_evidence.log 2>&1
rc=$?; echo "make_evidence rc=$rc" | tee -a logs/rc.txt
[ $rc -eq 0 ] || FAILS=$((FAILS+1))
./scripts/make_patch.sh > logs/make_patch.log 2>&1
rc=$?; echo "make_patch rc=$rc" | tee -a logs/rc.txt
[ $rc -eq 0 ] || FAILS=$((FAILS+1))
python3 scripts/make_result.py > logs/make_result.log 2>&1
rc=$?; echo "make_result rc=$rc" | tee -a logs/rc.txt
[ $rc -eq 0 ] || FAILS=$((FAILS+1))

echo "== 7. source SHA / evidence =="
sha256sum $(sed 's#//.*##' filelist_closeout_numeric.f | tr -d ' ' | grep -v '^$') \
  tb/tb_closeout_numeric.sv tb/wc_graph_bfm.sv scripts/*.py scripts/*.sh run_all.sh \
  filelist_closeout_numeric.f > SHA256SUMS.txt
sha256sum REPORT.md INTERFACE.md result.json progress.json USER_UPDATES.md README.md \
  patch/closeout_numeric.patch >> SHA256SUMS.txt
sha256sum rtl/asr_fma_ip.sv rtl/fp32_fma_pipe.sv rtl/approx_div_sqrt.sv \
  rtl/approx_recip_lut.sv rtl/approx_rsqrt_lut.sv > reports/NUMERIC_SOURCE_SHA256.txt
sha256sum ../gemini_fma_round2/candidate/fp32_fma_pipe.sv \
  ../gemini_fma_round2/candidate/asr_fma_ip.sv \
  ../gemini_approx_round2/candidate/rtl/approx_div_sqrt.sv \
  ../gemini_approx_round2/candidate/rtl/approx_recip_lut.sv \
  ../gemini_approx_round2/candidate/rtl/approx_rsqrt_lut.sv > reports/UPSTREAM_SHA256.txt
sha256sum reports/PRIMARY_ACCEPTANCE_CITED.json reports/SNAPSHOT_INTEGRITY.txt \
  reports/NUMERIC_SOURCE_SHA256.txt reports/UPSTREAM_SHA256.txt >> SHA256SUMS.txt

echo "== summary =="
if [ $FAILS -ne 0 ]; then echo "RUN_ALL FAILS=$FAILS"; exit 1; fi
echo "RUN_ALL_PASS numeric vector path only; not full-model/board acceptance"
