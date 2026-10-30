#!/usr/bin/env bash
# Run the original worker's 10-case regression unmodified, but with THIS tree's
# RTL substituted into a local copy (the worker tree stays read-only).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="/home/yang/Desktop/项目/v024_opt/ds_epilogue_channels"
DST="$ROOT/regress"
rm -rf "$DST"; mkdir -p "$DST"
cp -r "$SRC/scripts" "$SRC/tb" "$SRC/vectors" "$SRC/ref" "$DST"/
cp "$SRC/filelist_v024.f" "$SRC/REFERENCE_LOCK.json" "$DST"/ 2>/dev/null
mkdir -p "$DST/rtl" "$DST/logs"
cp "$ROOT"/rtl/*.sv "$DST/rtl"/
( cd "$DST" && python3 scripts/run_suite.py ) > "$ROOT/logs/regress_console.txt" 2>&1
RC=$?
python3 - "$DST/RUN_RESULT.json" "$ROOT/logs/regress_console.txt" "$RC" <<'PY'
import json,sys,os
p,log,rc=sys.argv[1],sys.argv[2],int(sys.argv[3])
if not os.path.exists(p):
    print('REGRESS_FAIL: no RUN_RESULT.json; rc=%d'%rc); sys.exit(1)
d=json.load(open(p))
print('REGRESS %s cases=%d failed=%s rc=%d' %
      ('PASS' if d.get('pass') else 'FAIL', d.get('case_count',-1),
       d.get('failed'), rc))
for c in d.get('cases',[]):
    if not c.get('pass'):
        print('  FAIL', c.get('name'), c.get('errors'))
sys.exit(0 if (d.get('pass') and rc==0) else 1)
PY
