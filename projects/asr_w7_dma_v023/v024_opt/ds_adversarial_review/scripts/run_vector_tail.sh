#!/usr/bin/env bash
# Independent vector tail / op17 II gate.
#   bash scripts/run_vector_tail.sh <tag> <rtl_file> [rtl_file ...]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?tag}"; shift
[ "$#" -ge 1 ] || { echo "need rtl files"; exit 2; }
OUT="$ROOT/logs/vec/$TAG"; mkdir -p "$OUT"
RC=0
python3 - "$ROOT/reports/frozen_shas.json" "$TAG" "$@" <<'PY'
import json,sys,hashlib,os,time
path,tag,*files=sys.argv[1:]
try: db=json.load(open(path))
except Exception: db={}
db[tag]={"when":time.strftime("%Y-%m-%dT%H:%M:%S"),"files":{os.path.abspath(f):hashlib.sha256(open(f,'rb').read()).hexdigest() for f in files}}
json.dump(db,open(path,'w'),indent=1)
PY
iverilog -g2012 -o "$OUT/sim" "$ROOT/tb/tb_vector.sv" "$@" >"$OUT/compile.log" 2>&1
C=$?; echo "compile rc=$C" | tee "$OUT/rc.txt"
[ "$C" -eq 0 ] || { echo "FAIL compile"; exit 1; }

run_case() { # op n out16 bdelay
  local op=$1 n=$2 o16=$3 bd=$4
  local name="op${op}_n${n}_o${o16}_b${bd}"
  local dir="$OUT/$name"; mkdir -p "$dir"
  ( cd "$ROOT" && python3 gold/gen_vector_vectors.py "$op" "$n" "$o16" "$dir" $((0xACE + n*3 + op)) ) >/dev/null 2>&1
  ( cd "$ROOT" && timeout 120 vvp "$OUT/sim" +dir="$dir" +op="$op" +n="$n" +out16="$o16" +bdelay="$bd" >"$dir/run.log" 2>&1 )
  local r=$?
  local line=$(grep -E "^RESULT" "$dir/run.log" | tail -1)
  echo "$name rc=$r $line" | tee -a "$OUT/rc.txt"
  [ "$r" -eq 0 ] || RC=1
}

for n in 1 2 3 4 5 7 8 9 16 17 127 255 256 257 1001; do run_case 17 "$n" 0 0; done
run_case 17 1001 0 25
for n in 1 2 3 4 5 7 8 9 10 15 16 17 127 255 257 1001; do run_case 0 "$n" 0 0; done
for n in 1 2 3 4 5 7 8 9 16 17 127 255 257 1001; do run_case 15 "$n" 1 0; done

[ "$RC" -eq 0 ] && echo "VECTOR_GATE_PASS $TAG" || echo "VECTOR_GATE_FAIL $TAG"
exit "$RC"
