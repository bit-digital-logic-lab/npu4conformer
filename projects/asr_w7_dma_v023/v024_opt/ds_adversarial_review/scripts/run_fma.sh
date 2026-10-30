#!/usr/bin/env bash
# Independent FMA gate. Usage:
#   bash scripts/run_fma.sh <tag> <fma_source> [extra_source ...]
# Gate: modes 0(stream,8734), 1(flush,251), 2(reset,251), 3(II,8734).
# Probe: mode 4 (handshake during flush) is recorded, not gating.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?tag}"; shift
[ "$#" -ge 1 ] || { echo "need source"; exit 2; }
OUT="$ROOT/logs/fma/$TAG"
mkdir -p "$OUT"
RC=0
VEC="vectors"
SIM="$OUT/sim"

sha() { sha256sum "$1" | awk '{print $1}'; }
python3 - "$ROOT/reports/frozen_shas.json" "$TAG" "$@" <<'PY'
import json,sys,hashlib,os,time
path,tag,*files=sys.argv[1:]
try: db=json.load(open(path))
except Exception: db={}
db[tag]={"when":time.strftime("%Y-%m-%dT%H:%M:%S"),"files":{}}
for f in files:
    db[tag]["files"][os.path.abspath(f)]=hashlib.sha256(open(f,'rb').read()).hexdigest()
json.dump(db,open(path,'w'),indent=1)
PY

iverilog -g2012 -o "$SIM" "$ROOT/tb/tb_fma.sv" "$@" >"$OUT/compile.log" 2>&1
C=$?
echo "compile rc=$C" | tee "$OUT/rc.txt"
if [ "$C" -ne 0 ]; then echo "FAIL compile"; exit 1; fi

run() { # name mode vectors expect
  local name="$1" mode="$2" vec="$3"
  local log="$OUT/$name.log"
  ( cd "$ROOT" && timeout 300 vvp "$SIM" +vec="$vec" +mode="$mode" >"$log" 2>&1 )
  local r=$?
  echo "$name rc=$r" | tee -a "$OUT/rc.txt"
  if [ "$r" -ne 0 ]; then RC=1; fi
  return $r
}

run stream_8734 0 "$VEC/fma_8734_proj.txt"
run flush_251 1 "$VEC/fma_251_proj.txt"
run reset_251 2 "$VEC/fma_251_proj.txt"
run ii_8734 3 "$VEC/fma_8734_proj.txt"
  probe_log="$OUT/flush_handshake_probe.log"
  ( cd "$ROOT" && timeout 300 vvp "$SIM" +vec="$VEC/fma_251_proj.txt" +mode=4 >"$probe_log" 2>&1 )
  echo "flush_handshake_probe rc=$? (advisory; nonzero = AR-001 hazard)" | tee -a "$OUT/rc.txt"

python3 - "$OUT" "$TAG" "$RC" <<'PY'
import json,sys,os
out,tag,rc=sys.argv[1],sys.argv[2],int(sys.argv[3])
res={"tag":tag,"gate_rc":rc,"modes":{}}
for f in sorted(os.listdir(out)):
    if f.endswith('.log') and f!='compile.log':
        t=open(os.path.join(out,f)).read()
        res["modes"][f[:-4]]={"pass":("PASS" in t),"rc_lines":[l for l in t.splitlines() if l.startswith(("RESULT","II_","FLUSH_","FAIL","WATCHDOG"))][-4:]}
json.dump(res,open(os.path.join(out,"summary.json"),'w'),indent=1)
PY
if [ "$RC" -eq 0 ]; then echo "FMA_GATE_PASS $TAG"; else echo "FMA_GATE_FAIL $TAG"; fi
exit "$RC"
