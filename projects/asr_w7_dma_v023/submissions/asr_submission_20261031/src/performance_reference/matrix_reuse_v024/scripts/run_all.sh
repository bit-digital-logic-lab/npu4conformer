#!/usr/bin/env bash
# ds_matrix_reuse v1 regression.  Logic simulation only.
# -j 1 for every Verilator build; every simulation has a timeout watchdog.
# No synthesis, Vivado, board, VNC or push.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
RTL="$ROOT/candidate/rtl"
T="$ROOT/tests"
L="$ROOT/logs"
B="${B:-/tmp/opencode/mxreuse_final}"
V23="${V23:-/home/yang/Desktop/项目/v023_repair/ds_matrix}"
mkdir -p "$L" "$B" "$ROOT/fixtures" "$ROOT/traffic"
: > "$L/commands.log"
: > "$L/metrics.txt"

run() {
  local name="$1" tmo="$2"; shift 2
  printf '### %s :: %s\n' "$name" "$*" >> "$L/commands.log"
  timeout "$tmo" "$@" > "$L/$name.log" 2>&1
  local rc=$?
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/commands.log"
  printf '%s rc=%s\n' "$name" "$rc" >> "$L/metrics.txt"
  grep -E "PASS|FAIL|INFO done|INFO reuse|INFO bfm|INFO store|INFO hazard|PASS_FAULT|INFO cluster|INFO dma|INFO axi|INFO drain|TIMEOUT" "$L/$name.log" >> "$L/metrics.txt" 2>/dev/null || true
  if [ "$rc" -ne 0 ]; then echo "RUNFAIL $name rc=$rc" | tee -a "$L/metrics.txt"; fi
  return 0
}

gold() {
  local name="$1"; shift
  python3 scripts/gold_reuse.py --out "$ROOT/fixtures/$name" --tag "$name" "$@" > "$L/gold_$name.log" 2>&1
  local rc=$?
  printf 'gold_%s rc=%s\n' "$name" "$rc" >> "$L/commands.log"
  return 0
}

V="verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-UNUSED"
ENGINE_SRC="$T/tb_reuse_engine.sv $T/txn_dma_bfm.sv $RTL/block_engine_reuse_v1.sv $RTL/block_storage_stream_reuse_v1.sv $RTL/operand_banks_dual_reuse.sv $RTL/block_address_v020.sv $RTL/array16_w7_c48_cfg.sv $RTL/pe_w7_c48_cfg.sv $RTL/c_cache_banked4_pipe.sv"
CLUSTER_SRC="$T/tb_reuse_cluster_axi.sv $T/axi128_ddr_bfm_v2.sv $RTL/matrix_reuse_cluster_v1.sv $RTL/block_engine_reuse_v1.sv $RTL/block_storage_stream_reuse_v1.sv $RTL/operand_banks_dual_reuse.sv $RTL/block_address_v020.sv $RTL/array16_w7_c48_cfg.sv $RTL/pe_w7_c48_cfg.sv $RTL/c_cache_banked4_pipe.sv $RTL/axi_dma_v020_multi_v2.sv"

# ---------------- independent integer fixtures (fresh, not old JSON) ----------------
gold m32n32k32_c0_r0 --m 32 --n 32 --k 32 --c-valid 0 --seed 11
gold m32n64k32_c0_r1 --m 32 --n 64 --k 32 --c-valid 0 --seed 301
gold m32n32k32_c1_r0 --m 32 --n 32 --k 32 --c-valid 1 --seed 302 --c-mode random
gold m64n32k96_c0_r1 --m 64 --n 32 --k 96 --c-valid 0 --seed 22
gold m64n32k96_c1_r1 --m 64 --n 32 --k 96 --c-valid 1 --seed 101 --c-mode random
gold m64n64k96_c0_r1 --m 64 --n 64 --k 96 --c-valid 0 --seed 103
gold m96n32k96_c0_r1 --m 96 --n 32 --k 96 --c-valid 0 --seed 102
gold m96n64k64_c1_r1 --m 96 --n 64 --k 64 --c-valid 1 --seed 107 --c-mode random
gold m64n32k1_c0_r1 --m 64 --n 32 --k 1 --c-valid 0 --seed 105
gold m64n32k32_c0_r1 --m 64 --n 32 --k 32 --c-valid 0 --seed 108
gold m64n32k33_c0_r1 --m 64 --n 32 --k 33 --c-valid 0 --seed 106
gold m64n32k65_c0_r1 --m 64 --n 32 --k 65 --c-valid 0 --seed 303
gold ovf_m64n32k32_c1_r1 --m 64 --n 32 --k 32 --c-valid 1 --seed 201 --c-mode max --a-mode one --w-mode one
gold badpar_m64n32k96_c0_r1 --m 64 --n 32 --k 96 --c-valid 0 --seed 202 --bad-parity

# ---------------- builds (-j 1) ----------------
run build_engine 1800 $V --top-module tb_reuse_engine $ENGINE_SRC -Mdir "$B/eng" -o "$B/tb_reuse"
run build_engine_bp 1800 $V -GWR_GAP=60 -GB_DELAY=40 -GRD_GAP=2 --top-module tb_reuse_engine $ENGINE_SRC -Mdir "$B/bp" -o "$B/tb_reuse_bp"
run build_cluster 1800 $V --top-module tb_reuse_cluster_axi $CLUSTER_SRC -Mdir "$B/clu" -o "$B/tb_cluster"
run build_cache_slots 300 iverilog -g2012 -s tb_cache_slots -o "$B/tb_cache_slots.vvp" "$T/tb_cache_slots.sv" "$RTL/c_cache_banked4_pipe.sv"
# read-only v023 reference engine on the same fixtures/gold
run build_ref_v023 1800 $V -GPIPE=4 -GM=64 -GN=32 -GK=96 -GMEM_WORDS=20480 -GA_BASE=50331648 -GB_BASE=50364416 -GC_BASE=50462720 -GRD_LAT=2 -GRD_GAP=1 -GWR_GAP=1 -GB_DELAY=4 \
  --top-module tb_engine_p2 "$V23/tests/tb_engine_p2.sv" "$V23/tests/txn_dma_bfm.sv" \
  "$V23/candidate/rtl/block_engine_prefetch_v2.sv" "$V23/candidate/rtl/block_storage_stream_v2.sv" "$V23/candidate/rtl/operand_banks_dual_v2.sv" "$V23/candidate/rtl/block_address_v020.sv" "$V23/candidate/rtl/array16_w7_c48_cfg.sv" "$V23/candidate/rtl/pe_w7_c48_cfg.sv" "$V23/candidate/rtl/c_cache_banked4_pipe.sv" \
  -Mdir "$B/ref" -o "$B/tb_ref"

TB="$B/tb_reuse"
TB_BP="$B/tb_reuse_bp"
TB_CLU="$B/tb_cluster"
TB_REF="$B/tb_ref"

eng() {
  local name="$1" fx="$2" m="$3" n="$4" k="$5" cv="$6" ru="$7"; shift 7
  run "run_$name" 600 "$TB" +m="$m" +n="$n" +k="$k" +cvalid="$cv" +reuse="$ru" \
    +init="$ROOT/fixtures/$fx/init.hex" +exp="$ROOT/fixtures/$fx/exp_c.txt" "$@"
}
clu() {
  local name="$1" fx="$2" m="$3" n="$4" k="$5" cv="$6" ru="$7"
  run "run_cluster_$name" 900 "$TB_CLU" +m="$m" +n="$n" +k="$k" +cvalid="$cv" +reuse="$ru" \
    +init="$ROOT/fixtures/$fx/init.hex" +exp="$ROOT/fixtures/$fx/exp_c.txt"
}

# ---------------- directed cache slot/RAW test ----------------
run run_cache_slots 300 vvp "$B/tb_cache_slots.vvp"

# ---------------- engine regression: M32/64/96, N32/64, K1/32/96/tail, old C ----------------
eng m32n32k32_c0_r0 m32n32k32_c0_r0 32 32 32 0 0
eng m32n32k32_c0_r1 m32n32k32_c0_r0 32 32 32 0 1
eng m32n64k32_c0_r1 m32n64k32_c0_r1 32 64 32 0 1
eng m32n32k32_c1_r0 m32n32k32_c1_r0 32 32 32 1 0
eng m64n32k96_c0_r1 m64n32k96_c0_r1 64 32 96 0 1
eng m64n32k96_c0_r0 m64n32k96_c0_r1 64 32 96 0 0
eng m64n32k96_c1_r1 m64n32k96_c1_r1 64 32 96 1 1
eng m64n64k96_c0_r1 m64n64k96_c0_r1 64 64 96 0 1
eng m96n32k96_c0_r1 m96n32k96_c0_r1 96 32 96 0 1
eng m96n64k64_c1_r1 m96n64k64_c1_r1 96 64 64 1 1
eng m64n32k1_c0_r1 m64n32k1_c0_r1 64 32 1 0 1
eng m64n32k32_c0_r1 m64n32k32_c0_r1 64 32 32 0 1
eng m64n32k33_c0_r1 m64n32k33_c0_r1 64 32 33 0 1
eng m64n32k65_c0_r1 m64n32k65_c0_r1 64 32 65 0 1
# old-C / overflow / parity / injected read/write faults (drained exit)
eng ovf_m64n32k32_c1_r1 ovf_m64n32k32_c1_r1 64 32 32 1 1 +expect_code=8
eng badpar_m64n32k96_c0_r1 badpar_m64n32k96_c0_r1 64 32 96 0 1 +expect_code=9
eng fault_rd_m64n32k96_c0_r1 m64n32k96_c0_r1 64 32 96 0 1 +inject_rd=1 +expect_code=9
eng fault_wr_m64n32k96_c0_r1 m64n32k96_c0_r1 64 32 96 0 1 +inject_wr=1 +expect_code=10

# ---------------- backpressure build, same C1 workload ----------------
run run_bp_m64n32k96_c1_r1 600 "$TB_BP" +m=64 +n=32 +k=96 +cvalid=1 +reuse=1 \
  +init="$ROOT/fixtures/m64n32k96_c1_r1/init.hex" +exp="$ROOT/fixtures/m64n32k96_c1_r1/exp_c.txt"

# ---------------- read-only v023 reference on the same fixtures/gold ----------------
run run_ref_c0 600 "$TB_REF" +cvalid=0 +init="$ROOT/fixtures/m64n32k96_c0_r1/init.hex" +exp="$ROOT/fixtures/m64n32k96_c0_r1/exp_c.txt"
run run_ref_c1 600 "$TB_REF" +cvalid=1 +init="$ROOT/fixtures/m64n32k96_c1_r1/init.hex" +exp="$ROOT/fixtures/m64n32k96_c1_r1/exp_c.txt"

# ---------------- actual AXI read/W bytes and B drain ----------------
clu m64n32k96_c0_r1 m64n32k96_c0_r1 64 32 96 0 1
clu m64n32k96_c0_r0 m64n32k96_c0_r1 64 32 96 0 0
clu m64n32k96_c1_r1 m64n32k96_c1_r1 64 32 96 1 1
clu m64n64k96_c0_r1 m64n64k96_c0_r1 64 64 96 0 1
clu m96n32k96_c0_r1 m96n32k96_c0_r1 96 32 96 0 1
clu m96n64k64_c1_r1 m96n64k64_c1_r1 96 64 64 1 1

python3 scripts/collect_metrics.py > "$L/collect_metrics.log" 2>&1
python3 scripts/check_capacity.py > "$L/capacity.log" 2>&1
printf 'ALL DONE\n' >> "$L/commands.log"
rc=0
if grep -qE ' rc=[1-9]' "$L/commands.log"; then rc=1; fi
if grep -q 'RUNFAIL' "$L/metrics.txt"; then rc=1; fi
echo "regression rc=$rc"
cat "$L/metrics.txt"
exit "$rc"
