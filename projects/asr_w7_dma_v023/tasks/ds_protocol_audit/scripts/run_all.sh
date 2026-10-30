#!/bin/bash
# Reproduce every audit run. Read-only sources: /home/yang/Desktop/项目/work.
# New code/logs live only under this task directory. No synthesis/Vivado/board.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="/home/yang/Desktop/项目/work"
TB="$ROOT/tb"
SNAP="$ROOT/snapshots/axi_dma_v020_multi_snapshot_20261029.sv"
VV=/home/yang/yosys-sta/oss-cad-suite/bin/vvp
IV=/home/yang/yosys-sta/oss-cad-suite/bin/iverilog
VF=/tmp/opencode/vf
LF=/tmp/opencode/lf
mkdir -p "$VF" "$LF"
for d in add_scalar mul_vector i16_to_float round_i16 i48_to_float; do ln -sfn "$WORK/tests/vector_fixtures/$d" "$VF/$d"; done
for d in "$WORK"/tests/layout_fixtures/*/; do ln -sfn "$d" "$LF/$(basename "$d")"; done
mkdir -p "$ROOT/reports"

run_one () { # tag cmd...
  tag="$1"; shift
  d="$ROOT/reports/$tag"; mkdir -p "$d"
  printf '%s\n' "$*" > "$d/cmd.txt"
  "$@" > "$d/run.log" 2>&1
  echo $? > "$d/rc.txt"
}

# ---------------- compile ----------------
mkdir -p "$ROOT/reports/compile"
"$IV" -g2012 -s tb_dma_edge -o "$ROOT/reports/compile/dma_edge.vvp" \
 "$TB/tb_dma_edge.sv" "$WORK/rtl/axi_dma_v019.sv" > "$ROOT/reports/compile/dma_edge.log" 2>&1
echo $? > "$ROOT/reports/compile/dma_edge.rc"

"$IV" -g2012 -s tb_vector_stress -o "$ROOT/reports/compile/vector_stress.vvp" \
 "$TB/tb_vector_stress.sv" "$TB/axi128_stress_bfm.sv" \
 "$WORK/rtl/ddr_vector_axi.sv" "$WORK/rtl/ddr_vector_engine.sv" "$WORK/rtl/asr_fp32_alu.sv" \
 "$WORK/rtl/axi_dma_v019.sv" "$WORK/tests/fma_forbidden_stub.sv" > "$ROOT/reports/compile/vector_stress.log" 2>&1
echo $? > "$ROOT/reports/compile/vector_stress.rc"

"$IV" -g2012 -s tb_layout_stress -o "$ROOT/reports/compile/layout_stress.vvp" \
 "$TB/tb_layout_stress.sv" "$TB/axi128_stress_bfm.sv" \
 "$WORK/rtl/ddr_layout_axi.sv" "$WORK/rtl/ddr_layout_engine.sv" "$WORK/rtl/u16_divmod.sv" \
 "$WORK/rtl/axi_dma_v019.sv" > "$ROOT/reports/compile/layout_stress.log" 2>&1
echo $? > "$ROOT/reports/compile/layout_stress.rc"

"$IV" -g2012 -s tb_csr_snapshot -o "$ROOT/reports/compile/csr.vvp" \
 "$TB/tb_csr_snapshot.sv" "$WORK/rtl/plan_submit_csr.sv" > "$ROOT/reports/compile/csr.log" 2>&1
echo $? > "$ROOT/reports/compile/csr.rc"

"$IV" -g2012 -s tb_plan_stall -o "$ROOT/reports/compile/plan_stall.vvp" \
 "$TB/tb_plan_stall.sv" "$TB/axi128_stress_bfm.sv" \
 "$WORK/rtl/pl_execution_plan_v022.sv" "$WORK/rtl/axi_dma_v019.sv" > "$ROOT/reports/compile/plan_stall.log" 2>&1
echo $? > "$ROOT/reports/compile/plan_stall.rc"

"$IV" -g2012 -s tb_dma_multi -o "$ROOT/reports/compile/multi.vvp" \
 "$TB/tb_dma_multi.sv" "$SNAP" > "$ROOT/reports/compile/multi.log" 2>&1
echo $? > "$ROOT/reports/compile/multi.rc"

"$IV" -g2012 -s tb_strobe -o "$ROOT/reports/compile/strobe.vvp" \
 "$ROOT/tb/tb_strobe.sv" "$SNAP" > "$ROOT/reports/compile/strobe.log" 2>&1
echo $? > "$ROOT/reports/compile/strobe.rc"

# ---------------- directed ----------------
run_one dma_edge001 timeout 120 "$VV" "$ROOT/reports/compile/dma_edge.vvp"
run_one csr001 timeout 60 "$VV" "$ROOT/reports/compile/csr.vvp"
run_one plan_stall001 timeout 60 "$VV" "$ROOT/reports/compile/plan_stall.vvp"
run_one multi001 timeout 90 "$VV" "$ROOT/reports/compile/multi.vvp"
run_one strobe001 timeout 20 "$VV" "$ROOT/reports/compile/strobe.vvp"

# ---------------- vector fixture reruns ----------------
V="$ROOT/reports/vector_stress001"; mkdir -p "$V"; : > "$V/summary.tsv"
for fx in add_scalar mul_vector i16_to_float round_i16 i48_to_float; do
  case "$fx" in round_i16) nb=2002;; *) nb=4004;; esac
  for seed in 5 17 29; do
    timeout 120 "$VV" "$ROOT/reports/compile/vector_stress.vvp" \
      +folder="$VF/$fx" +nbytes="$nb" +seed="$seed" > "$V/${fx}_${seed}.log" 2>&1
    rc=$?
    line=$(grep -E "VECTOR_STRESS_PASS|FATAL|watchdog" "$V/${fx}_${seed}.log" | head -1)
    printf '%s\t%s\t%s\t%s\n' "$fx" "$seed" "$rc" "$line" >> "$V/summary.tsv"
  done
done

# ---------------- layout fixture reruns ----------------
L="$ROOT/reports/layout_stress001"; mkdir -p "$L"; : > "$L/summary.tsv"
for spec in "copy_i16 2002" "pack_matrix_edges 8192" "unpack_row_fp32 4620" "unpack_nchw_fp32 4620" "unpack_c48_compact 6930" "conv_padding 4096" "depthwise_31 2048"; do
  set -- $spec; fx=$1; nb=$2
  for seed in 5 17; do
    timeout 200 "$VV" "$ROOT/reports/compile/layout_stress.vvp" \
      +folder="$LF/$fx" +nbytes="$nb" +seed="$seed" > "$L/${fx}_${seed}.log" 2>&1
    rc=$?
    line=$(grep -E "LAYOUT_STRESS_PASS|FATAL|watchdog" "$L/${fx}_${seed}.log" | head -1)
    printf '%s\t%s\t%s\t%s\n' "$fx" "$seed" "$rc" "$line" >> "$L/summary.tsv"
  done
done
for seed in 17 29; do
  timeout 300 "$VV" "$ROOT/reports/compile/layout_stress.vvp" \
    +folder="$LF/case0000_embed_conv0" +nbytes=157696 +seed="$seed" > "$L/case0000_${seed}.log" 2>&1
  rc=$?
  line=$(grep -E "LAYOUT_STRESS_PASS|FATAL|watchdog" "$L/case0000_${seed}.log" | head -1)
  printf 'case0000_embed_conv0\t%s\t%s\t%s\n' "$seed" "$rc" "$line" >> "$L/summary.tsv"
done

# ---------------- ACL overflow probes ----------------
A="$ROOT/reports/acl001"; mkdir -p "$A"
timeout 60 "$VV" "$ROOT/reports/compile/vector_stress.vvp" +folder="$VF/add_scalar" +nbytes=4004 +seed=5 +acl=1 > "$A/vector_acl.log" 2>&1
echo $? > "$A/vector_acl.rc"
timeout 60 "$VV" "$ROOT/reports/compile/layout_stress.vvp" +folder="$LF/copy_i16" +nbytes=2002 +seed=5 +acl=1 > "$A/layout_acl.log" 2>&1
echo $? > "$A/layout_acl.rc"
echo "32-bit add would wrap at 0xFFFFFFF0; the 64-bit ACL must reject with no AXI." > "$A/cmd.txt"

echo "RUN_ALL_DONE $(date -u +%FT%TZ)"
