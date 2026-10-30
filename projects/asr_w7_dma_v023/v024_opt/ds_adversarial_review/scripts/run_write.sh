#!/usr/bin/env bash
# Independent storage write-merge / 4 KiB gate.
#   bash scripts/run_write.sh <tag> <rtl_file> [rtl_file ...]
# Gate: native aligned, native block crossing 4 KiB, single generic stride seg.
# Advisory: generic segment that itself crosses 4 KiB (AXI4 page rule).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?tag}"; shift
[ "$#" -ge 1 ] || { echo "need rtl files"; exit 2; }
OUT="$ROOT/logs/write/$TAG"; mkdir -p "$OUT"
RC=0
python3 - "$ROOT/reports/frozen_shas.json" "$TAG" "$@" <<'PY'
import json,sys,hashlib,os,time
path,tag,*files=sys.argv[1:]
try: db=json.load(open(path))
except Exception: db={}
db[tag]={"when":time.strftime("%Y-%m-%dT%H:%M:%S"),"files":{os.path.abspath(f):hashlib.sha256(open(f,'rb').read()).hexdigest() for f in files}}
json.dump(db,open(path,'w'),indent=1)
PY
iverilog -g2012 -o "$OUT/sim" "$ROOT/tb/tb_storage.sv" "$@" >"$OUT/compile.log" 2>&1
C=$?; echo "compile rc=$C" | tee "$OUT/rc.txt"
[ "$C" -eq 0 ] || { echo "FAIL compile"; exit 1; }

run() { # name args...
  local name=$1; shift
  local log="$OUT/$name.log"
  ( cd "$ROOT" && timeout 120 vvp "$OUT/sim" +cbase=03000c00 "$@" >"$log" 2>&1 )
  local r=$?
  echo "$name rc=$r $(grep -E '^RESULT' "$log" | tail -1)" | tee -a "$OUT/rc.txt"
  RC=1; [ "$r" -eq 0 ] && RC=$RC
  return $r
}

run_gate() { # name args...
  local name=$1; shift
  local log="$OUT/$name.log"
  ( cd "$ROOT" && timeout 120 vvp "$OUT/sim" +cbase=03000c00 "$@" >"$log" 2>&1 )
  local r=$?
  echo "$name rc=$r $(grep -E '^RESULT' "$log" | tail -1)" | tee -a "$OUT/rc.txt"
  [ "$r" -eq 0 ] || RC=1
}

run_gate native +native
run_gate pagecross +pagecross
run_gate generic_single +generic +ngen=1 +genoff=00001110

# advisory probes: expected to expose the generic-path page rule / back-to-back
( cd "$ROOT" && timeout 60 vvp "$OUT/sim" +cbase=03000c00 +generic +ngen=1 +genoff=00000fe0 >"$OUT/generic_pagecross_probe.log" 2>&1 )
echo "generic_pagecross_probe rc=$? (advisory; nonzero = 4KiB-crossing generic burst)" | tee -a "$OUT/rc.txt"
( cd "$ROOT" && timeout 30 vvp "$OUT/sim" +cbase=03000c00 +generic +ngen=2 +genoff=00001110 >"$OUT/generic_multi_probe.log" 2>&1 )
echo "generic_multi_probe rc=$? (advisory; nonzero = back-to-back generic stall)" | tee -a "$OUT/rc.txt"

[ "$RC" -eq 0 ] && echo "WRITE_GATE_PASS $TAG" || echo "WRITE_GATE_FAIL $TAG"
exit "$RC"
