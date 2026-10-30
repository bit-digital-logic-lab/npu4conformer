#!/usr/bin/env bash
# Self-contained regression for ds_control_fixes.
# Read-only sources are referenced by absolute path; every artifact is written
# under this task directory.  No synthesis/Vivado/board/push.
set -u
cd "$(dirname "$0")/.."
ROOT="/home/yang/Desktop/项目"
IV="iverilog -g2012"
mkdir -p build logs reports
SUMMARY="reports/RUN_SUMMARY.txt"
: > "$SUMMARY"
FAILS=0

note() { echo "$*" | tee -a "$SUMMARY"; }
compile() {
  local name="$1"; shift
  $IV -o "build/$name.vvp" "$@" > "logs/${name}_compile.log" 2>&1
  local rc=$?
  note "COMPILE $name rc=$rc"
  if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); fi
  return $rc
}
run_expect() {
  local name="$1" pattern="$2"
  vvp -n "build/$name.vvp" > "logs/$name.log" 2>&1
  local rc=$?
  local hit=0
  grep -q "$pattern" "logs/$name.log" && hit=1
  note "RUN $name rc=$rc expect='$pattern' hit=$hit"
  if [ $rc -ne 0 ] || [ $hit -ne 1 ]; then FAILS=$((FAILS+1)); fi
}

# PA-001: original must show the interleaved bug; v023 must pass.
compile csr_orig tb/tb_csr_pa001.sv "$ROOT/work/rtl/plan_submit_csr.sv"
run_expect csr_orig "PA001_INTERLEAVED_BUG"
compile csr_v023 -DDUT_V023 tb/tb_csr_pa001.sv candidate/rtl/plan_submit_csr_v023.sv
run_expect csr_v023 "PA001_PASS"

# PA-002: original must hang (no DONE) in FETCH/ERROR_DRAIN; v023 must bound it.
compile plan_before tb/tb_plan_pa002_before.sv "$ROOT/work/rtl/pl_execution_plan_v022.sv" "$ROOT/work/rtl/axi_dma_v019.sv" tb/axi128_multi_bfm.sv
run_expect plan_before "PA002_FETCH_UNBOUNDED_CONFIRMED"
run_expect plan_before "PA002_ERROR_DRAIN_UNBOUNDED_CONFIRMED"
compile plan_v023 tb/tb_plan_pa002.sv candidate/rtl/pl_execution_plan_v023.sv candidate/rtl/axi_dma_v023_bounded.sv
run_expect plan_v023 "PA002_PASS"

# PA-003/PA-004: v020_multi wrap/count bug vs v023 fixes (multi and bounded).
compile dma_before tb/tb_dma_pa003_pa004_before.sv "$ROOT/tasks/ds_ddr/candidate/axi_dma_v020_multi.sv" tb/axi128_multi_bfm.sv
run_expect dma_before "PA003_WRAP_BUG_CONFIRMED"
run_expect dma_before "PA004_STRB_COUNT_BUG_CONFIRMED"
compile dma_v023 tb/tb_dma_pa003_pa004.sv candidate/rtl/axi_dma_v023_multi.sv tb/axi128_multi_bfm.sv
run_expect dma_v023 "PA003_PA004_PASS"
compile dma_bounded tb/tb_dma_bounded_pa003.sv candidate/rtl/axi_dma_v023_bounded.sv tb/axi128_multi_bfm.sv
run_expect dma_bounded "BOUNDED_PASS"

# Ready-mask banked scanner.
compile ready_scan tb/tb_ready_scan.sv candidate/rtl/ready_scan_banked_v1.sv
run_expect ready_scan "READY_SCAN_PASS"

# block_address pipeline vs the read-only v020 combinational reference.
compile block_address tb/tb_block_address.sv candidate/rtl/block_address_v023.sv "$ROOT/work/rtl/block_address_v020.sv"
run_expect block_address "BLOCK_ADDRESS_PASS"

# Storage descriptor handshake with the pipelined block address.
compile storage_handshake tb/tb_storage_handshake.sv candidate/rtl/block_address_v023.sv candidate/rtl/block_storage_dma_wide4_v023.sv
run_expect storage_handshake "STORAGE_HANDSHAKE_PASS"

# Lint (structural; no timing claim).
for f in candidate/rtl/*.sv; do
  b=$(basename "$f")
  verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM "$f" > "logs/lint_${b}.log" 2>&1
  note "LINT $b rc=$?"
done

# SHA manifest of everything needed to re-run.
{
  sha256sum candidate/rtl/*.sv tb/*.sv scripts/*.sh 2>/dev/null
  sha256sum "$ROOT/work/rtl/plan_submit_csr.sv" "$ROOT/work/rtl/pl_execution_plan_v022.sv" \
    "$ROOT/work/rtl/block_address_v020.sv" "$ROOT/work/rtl/axi_dma_v019.sv" \
    "$ROOT/tasks/ds_ddr/candidate/axi_dma_v020_multi.sv" \
    "$ROOT/tasks/ds_critical_control/candidate/rtl/block_storage_dma_wide4_pipe_v1.sv"
} > reports/TEST_SHA256.txt

note "SUMMARY fails=$FAILS"
if [ $FAILS -eq 0 ]; then note "RUN_ALL_PASS"; else note "RUN_ALL_FAIL"; fi
exit $FAILS
