#!/usr/bin/env bash
# Independent per-channel epilogue gate.
#   bash scripts/run_epilogue.sh <tag> <rtl_file> [rtl_file ...]
# The file list must define epilogue_stream_engine_v024 + its submodules +
# fp32_fma_pipe. Returns 0 only when both modes pass.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?tag}"; shift
[ "$#" -ge 1 ] || { echo "need rtl files"; exit 2; }
OUT="$ROOT/logs/epi/$TAG"; mkdir -p "$OUT"
RC=0
python3 - "$ROOT/reports/frozen_shas.json" "$TAG" "$@" <<'PY'
import json,sys,hashlib,os,time
path,tag,*files=sys.argv[1:]
try: db=json.load(open(path))
except Exception: db={}
db[tag]={"when":time.strftime("%Y-%m-%dT%H:%M:%S"),"files":{os.path.abspath(f):hashlib.sha256(open(f,'rb').read()).hexdigest() for f in files}}
json.dump(db,open(path,'w'),indent=1)
PY
iverilog -g2012 -o "$OUT/sim" "$ROOT/tb/tb_epilogue.sv" "$@" >"$OUT/compile.log" 2>&1
C=$?; echo "compile rc=$C" | tee "$OUT/rc.txt"
[ "$C" -eq 0 ] || { echo "FAIL compile"; exit 1; }
run_gate() { # name mode bp
  local name=$1 m=$2 b=$3
  ( cd "$ROOT" && timeout 180 vvp "$OUT/sim" +dir=vectors/epi +mode=$m +bp=$b >"$OUT/$name.log" 2>&1 )
  local r=$?
  echo "$name rc=$r $(grep -E '^RESULT' "$OUT/$name.log" | tail -1)" | tee -a "$OUT/rc.txt"
  [ "$r" -eq 0 ] || RC=1
}
run_gate mode0_nobp 0 0
run_gate mode1_abort_nobp 1 0
run_gate mode2_scalar_nobp 2 0
run_gate mode3_pc_nobp 3 0
run_gate mode4_stall 4 0
run_gate mode3_a16bp 3 2
run_gate mode3_fp32bp 3 3
# advisory: simultaneous independent A16+FP32 backpressure and multi-phase A16 bp
( cd "$ROOT" && timeout 120 vvp "$OUT/sim" +dir=vectors/epi +mode=3 +bp=1 >"$OUT/probe_both_bp.log" 2>&1 )
echo "probe_both_bp rc=$? (advisory; nonzero = AR-006 channel deadlock)" | tee -a "$OUT/rc.txt"
( cd "$ROOT" && timeout 120 vvp "$OUT/sim" +dir=vectors/epi +mode=0 +bp=2 >"$OUT/probe_multiphase_a16bp.log" 2>&1 )
echo "probe_multiphase_a16bp rc=$? (advisory; nonzero = AR-007 multi-phase stall)" | tee -a "$OUT/rc.txt"
python3 - "$OUT" "$TAG" "$RC" <<'PY'
import json,sys,os
out,tag,rc=sys.argv[1],sys.argv[2],int(sys.argv[3])
res={"tag":tag,"gate_rc":rc,"modes":{}}
for f in sorted(os.listdir(out)):
    if f.startswith('mode') and f.endswith('.log'):
        t=open(os.path.join(out,f)).read()
        res["modes"][f[:-4]]={"pass":("PASS" in t),"lines":[l for l in t.splitlines() if l.startswith(("RESULT","FAIL","WATCHDOG"))][-6:]}
json.dump(res,open(os.path.join(out,"summary.json"),'w'),indent=1)
PY
[ "$RC" -eq 0 ] && echo "EPI_GATE_PASS $TAG" || echo "EPI_GATE_FAIL $TAG"
exit "$RC"
