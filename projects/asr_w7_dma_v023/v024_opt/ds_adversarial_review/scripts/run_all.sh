#!/usr/bin/env bash
# Rerun every independent gate against the frozen V0.24 candidates.
# Read-only to all worker trees. Non-zero if any gate fails.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V24="/home/yang/Desktop/项目/v024_opt"
RC=0
mkdir -p "$ROOT/vectors"
ln -sfn "$V24/ds_fusion_buffers/vectors" "$ROOT/vectors/fusion_link"
step() { echo; echo "==== $* ===="; }

step "FMA 7-stage deep (numeric, II, flush, reset)"
bash "$ROOT/scripts/run_fma.sh" fma_deep_final \
  "$V24/ds_fma_deep/candidate/fp32_fma_pipe.sv" || RC=1

step "FMA repair (flush contract, AR-001)"
bash "$ROOT/scripts/run_fma.sh" fma_repair \
  "$V24/ds_repair_fmaflush/rtl/fp32_fma_pipe.sv" || RC=1

step "per-channel epilogue (functional + output-backpressure probes)"
R="$V24/ds_epilogue_channels/rtl"
bash "$ROOT/scripts/run_epilogue.sh" epi_pc_final2 \
  "$R/epilogue_stream_engine_v024.sv" "$R/epilogue_lane.sv" \
  "$R/epilogue_fma_stage.sv" "$R/epilogue_i48_to_f32.sv" \
  "$R/epilogue_f32_to_i16.sv" "$R/epilogue_relu.sv" "$R/fp32_fma_pipe.sv" || RC=1

step "per-channel epilogue repair (AR-006/007)"
ER="$V24/ds_repair_epilogue/rtl"
if [ -f "$ER/epilogue_stream_engine_v024.sv" ]; then
  bash "$ROOT/scripts/run_epilogue.sh" epi_repair \
    "$ER/epilogue_stream_engine_v024.sv" "$ER/epilogue_lane.sv" \
    "$ER/epilogue_fma_stage.sv" "$ER/epilogue_i48_to_f32.sv" \
    "$ER/epilogue_f32_to_i16.sv" "$ER/epilogue_relu.sv" "$ER/fp32_fma_pipe.sv" || RC=1
fi

step "vector op17 II=1 and 4-lane tail"
V="$V24/ds_vector_fma/rtl"
bash "$ROOT/scripts/run_vector_tail.sh" vec_final \
  "$V/ddr_vector_engine_pipe.sv" "$V/vector_fma_lane.sv" \
  "$V/asr_fp32_lane_fixed.sv" "$V/asr_fp32_alu.sv" \
  "$V/vector_desc_check_pipe.sv" "$V/fp32_fma_pipe.sv" "$V/asr_fma_ip.sv" || RC=1

step "storage write coalescer / 4 KiB"
S="$V24/ds_storage_write"
bash "$ROOT/scripts/run_write.sh" write_final \
  "$S/rtl/block_storage_stream_v3.sv" "$S/rtl/operand_banks_dual_v2.sv" \
  "$S/tests/txn_dma_bfm.sv" || RC=1

step "matrix 2x1 W reuse (same fixture, reuse 0 vs 1)"
M="$V24/ds_matrix_reuse"
if iverilog -g2012 -s tb_reuse_cluster_axi -o /tmp/opencode/tb_clu_ar \
  "$M/tests/tb_reuse_cluster_axi.sv" "$M/tests/axi128_ddr_bfm_v2.sv" \
  "$M/candidate/rtl/matrix_reuse_cluster_v1.sv" "$M/candidate/rtl/block_engine_reuse_v1.sv" \
  "$M/candidate/rtl/block_storage_stream_reuse_v1.sv" "$M/candidate/rtl/operand_banks_dual_reuse.sv" \
  "$M/candidate/rtl/block_address_v020.sv" "$M/candidate/rtl/array16_w7_c48_cfg.sv" \
  "$M/candidate/rtl/pe_w7_c48_cfg.sv" "$M/candidate/rtl/c_cache_banked4_pipe.sv" \
  "$M/candidate/rtl/axi_dma_v020_multi_v2.sv"; then
  FX="$M/fixtures/m64n32k96_c0_r1"
  for r in 0 1; do
    ( cd "$M" && timeout 120 vvp /tmp/opencode/tb_clu_ar +m=64 +n=32 +k=96 +cvalid=0 +reuse=$r \
        +init="$FX/init.hex" +exp="$FX/exp_c.txt" > /tmp/opencode/reuse_$r.log 2>&1 )
    rcr=$?
    echo "reuse=$r rc=$rcr $(grep -E '^PASS' /tmp/opencode/reuse_$r.log | tail -1)"
    [ "$rcr" -eq 0 ] || RC=1
  done
else
  echo "matrix reuse compile failed"; RC=1
fi

step "fusion dual done-after-last-B"
F="$V24/ds_fusion_buffers"
iverilog -g2012 -o /tmp/opencode/tb_doneb_ar "$ROOT/tb/tb_doneb.sv" "$F/rtl/fusion_a16_writer.sv" || RC=1
for b in 0 5 30; do
  timeout 30 vvp /tmp/opencode/tb_doneb_ar +bdelay=$b > /tmp/opencode/doneb_$b.log 2>&1 || RC=1
  echo "writer bdelay=$b $(grep -E '^RESULT' /tmp/opencode/doneb_$b.log | tail -1)"
done
if [ -x "$F/build/tb_fusion_dual.vvp" ]; then
  ( cd "$ROOT" && timeout 300 vvp "$F/build/tb_fusion_dual.vvp" \
      +init=vectors/fusion_link/n64/init.hex +out=/tmp/opencode/fusion_n64.hex \
      +m=32 +n=64 +k=64 +positions=76543210 +scale=3f000000 +bias=3f800000 \
      +fma=1 +relu=0 +bp=0 +longmode=0 +longper=240 +longlen=96 +seed=7 \
      +latmin=8 +latmax=32 +bextra=3000 +watchdog=400000 > /tmp/opencode/fusion_n64.log 2>&1 )
  rcf=$?
  echo "dual n64 bextra=3000 rc=$rcf"
  grep -E "FUSION_DRAIN|FUSION_TB" /tmp/opencode/fusion_n64.log
  [ "$rcf" -eq 0 ] || RC=1
fi

echo
if [ "$RC" -eq 0 ]; then echo "ALL_MODULE_GATES_PASS"; else echo "MODULE_GATES_FAIL"; fi
exit "$RC"
