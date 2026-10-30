#!/usr/bin/env bash
# Independent integration smoke regression for the V0.23 candidate set.
#
# Logic simulation only.  No synthesis, Vivado, STA, board, VNC, network or push.
# All writes stay under ds_integration_audit/.  Every simulator call has a
# wall-clock timeout; the DMA/graph TBs also have internal cycle watchdogs.
#
# The script deliberately does NOT read worker PASS strings.  It runs:
#   * the independent interface/filelist audit
#   * the independent graph allocation/relocation audit
#   * the bounded dependency search
#   * independent DMA tag/abort/drain/tail tests for the three DMA variants
#   * a real LAY->VEC->VEC graph chain, checked against a locally computed golden
#   * a real matrix cluster K32 AXI run (worker fixture; arithmetic golden is
#     NOT independently re-derived here, see REPORT.md)
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p build logs analysis

SHA_LOG=logs/source_sha256.txt
if ! bash scripts/pin_sources.sh "$SHA_LOG" >/dev/null 2>&1; then
  echo "FATAL: could not hash sources" >&2
  exit 2
fi
if [ -f PINNED_SHA256.txt ] && [ "${ALLOW_SHA_DRIFT:-0}" != "1" ]; then
  if ! diff -u PINNED_SHA256.txt "$SHA_LOG" > logs/sha_diff.log 2>&1; then
    echo "FATAL: source SHA drift; see logs/sha_diff.log (set ALLOW_SHA_DRIFT=1 to override)" >&2
    cat logs/sha_diff.log >&2
    exit 2
  fi
fi

: > logs/smoke_results.csv
echo "stage,rc,seconds,log" >> logs/smoke_results.csv
FAILS=0
run_stage() {
  local name="$1" tmo="$2"; shift 2
  local log="logs/${name}.log" t0 t1 rc
  t0=$(date +%s)
  # shellcheck disable=SC2086
  timeout "$tmo" "$@" > "$log" 2>&1
  rc=$?
  t1=$(date +%s)
  if [ $rc -eq 124 ]; then
    echo "TIMEOUT ${name} after ${tmo}s" | tee -a "$log" >&2
  fi
  echo "${name},${rc},$((t1-t0)),${log}" >> logs/smoke_results.csv
  if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); echo "FAIL ${name} rc=${rc}" >&2; tail -5 "$log" >&2; fi
  return $rc
}

# ---- static audits ---------------------------------------------------------
run_stage audit_interfaces   120 python3 scripts/audit_interfaces.py
run_stage audit_graph_reloc  300 python3 scripts/audit_graph_relocation.py
run_stage audit_dependencies 120 python3 scripts/audit_dependencies.py

# ---- independent DMA audit: tail / 4GiB / WSTRB / abort / drain -----------
CC=../ds_control_fixes/candidate/rtl
MX=../ds_matrix/candidate/rtl
VEC=../ds_vector/candidate/rtl
LAY=../ds_layout/rtl
WORK=../../work/rtl

run_stage compile_dma_v023_multi 120 iverilog -g2012 -s tb_dma_audit -o build/dma_v023_multi.vvp -DHAS_ABORT \
  scripts/tb_dma_audit.sv scripts/axi128_audit_bfm.sv scripts/audit_dma_dut_v023_multi.sv "$CC/axi_dma_v023_multi.sv"
run_stage run_dma_v023_multi 60 vvp build/dma_v023_multi.vvp
run_stage compile_dma_v023_bounded 120 iverilog -g2012 -s tb_dma_audit -o build/dma_v023_bounded.vvp -DHAS_ABORT \
  scripts/tb_dma_audit.sv scripts/axi128_audit_bfm.sv scripts/audit_dma_dut_v023_bounded.sv "$CC/axi_dma_v023_bounded.sv"
run_stage run_dma_v023_bounded 60 vvp build/dma_v023_bounded.vvp
run_stage compile_dma_matrix_v2 120 iverilog -g2012 -s tb_dma_audit -o build/dma_matrix_v2.vvp \
  scripts/tb_dma_audit.sv scripts/axi128_audit_bfm.sv scripts/audit_dma_dut_matrix_v2.sv "$MX/axi_dma_v020_multi_v2.sv"
run_stage run_dma_matrix_v2 60 vvp build/dma_matrix_v2.vvp

# ---- real graph chain: LAY copy -> VEC ADD -> VEC MUL ---------------------
run_stage compile_graph_real_candidate 180 iverilog -g2012 -s tb_wc_graph_real -o build/graph_real_candidate.vvp \
  rtl/wc_graph_top_audit.sv ../ds_graph/rtl/wc_graph_ctrl.sv ../ds_graph/tb/wc_graph_bfm.sv tb/tb_graph_real_audit.sv \
  "$WORK/axi_dma_v019.sv" \
  "$VEC/ddr_vector_axi_pipe.sv" "$VEC/ddr_vector_engine_pipe.sv" "$VEC/asr_fp32_lane_fixed.sv" "$VEC/vector_desc_check_pipe.sv" \
  "$WORK/asr_fp32_alu.sv" "$WORK/ddr_layout_axi.sv" "$LAY/ddr_layout_engine_v023_burst.sv" "$WORK/u16_divmod.sv" \
  "$WORK/../tests/fma_forbidden_stub.sv"
# vvp must run from ds_graph because the TB reads tests/fixtures relative.
( cd ../ds_graph && timeout 180 vvp "$ROOT/build/graph_real_candidate.vvp" \
    +memfile=tests/fixtures/mem_graph.hex > "$ROOT/logs/run_graph_real_candidate.log" 2>&1 )
rc=$?
echo "run_graph_real_candidate,${rc},0,logs/run_graph_real_candidate.log" >> logs/smoke_results.csv
if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); echo "FAIL run_graph_real_candidate rc=${rc}" >&2; tail -5 logs/run_graph_real_candidate.log >&2; fi
run_stage verify_graph_chain 60 python3 scripts/verify_graph_chain.py

# ---- real matrix cluster K32 (AXI BFM) ------------------------------------
MXB="$ROOT/build/mx_cluster_k1"
run_stage compile_mx_cluster_k1 600 verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
  -GPIPE=4 -GM=32 -GN=32 -GK=32 -GMEM_WORDS=1536 -GA_BASE=50331648 -GB_BASE=50339840 -GC_BASE=50343936 \
  --top-module tb_p2_cluster_axi ../ds_matrix/tests/tb_p2_cluster_axi.sv ../ds_matrix/tests/axi128_ddr_bfm_v2.sv \
  "$MX/matrix_p2_cluster_v2.sv" "$MX/block_engine_prefetch_v2.sv" "$MX/block_storage_stream_v2.sv" \
  "$MX/operand_banks_dual_v2.sv" "$MX/block_address_v020.sv" "$MX/array16_w7_c48_cfg.sv" \
  "$MX/pe_w7_c48_cfg.sv" "$MX/c_cache_banked4_pipe.sv" "$MX/axi_dma_v020_multi_v2.sv" \
  -Mdir "$MXB" -o "$ROOT/build/tb_mx_cluster_k1"
( cd ../ds_matrix && timeout 300 "$ROOT/build/tb_mx_cluster_k1" \
    +init=fixtures/eng_k1/init.hex +exp=fixtures/eng_k1/exp_c.txt > "$ROOT/logs/run_mx_cluster_k1.log" 2>&1 )
rc=$?
echo "run_mx_cluster_k1,${rc},0,logs/run_mx_cluster_k1.log" >> logs/smoke_results.csv
if [ $rc -ne 0 ]; then FAILS=$((FAILS+1)); echo "FAIL run_mx_cluster_k1 rc=${rc}" >&2; tail -5 logs/run_mx_cluster_k1.log >&2; fi

# ---- summary --------------------------------------------------------------
echo "SMOKE_FAILS=${FAILS}"
if [ $FAILS -ne 0 ]; then
  echo "SMOKE_RESULT=FAIL"
  exit 1
fi
echo "SMOKE_RESULT=PASS"
exit 0
