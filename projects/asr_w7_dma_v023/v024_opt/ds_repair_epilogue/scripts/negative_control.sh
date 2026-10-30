#!/usr/bin/env bash
# Negative control: force every lane to table column 0.  The strict gate must
# reject it with real value mismatches (not a compile error / timeout alone).
# Exits 0 only when the broken RTL is rejected for the intended reason.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NEG="$ROOT/negctl/rtl"; rm -rf "$NEG"; mkdir -p "$NEG"
cp "$ROOT"/rtl/*.sv "$NEG"/
python3 - "$NEG/epilogue_stream_engine_v024.sv" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
a='assign lane_scale[gg] = s_hit ? tbl_scale[idx] : eff_scale;'
b='assign lane_scale[gg] = s_hit ? tbl_scale[{active_bank, 5\'d0}] : eff_scale;'
c='assign lane_bias[gg]  = b_hit ? tbl_bias[idx]  : eff_bias;'
d='assign lane_bias[gg]  = b_hit ? tbl_bias[{active_bank, 5\'d0}] : eff_bias;'
assert a in s and c in s, 'mutation anchor not found'
open(p,'w').write(s.replace(a,b).replace(c,d))
PY
echo "=== negative control (column-0 mutation) ==="
bash "$ROOT/scripts/run_gate.sh" negctl "$NEG"/*.sv
RC=$?
if [ "$RC" -eq 0 ]; then
  echo "NEGCTL_FAIL: broken RTL was accepted"
  python3 -c "import json;json.dump({'rejected':False,'value_mismatch':False},open('$ROOT/logs/negctl/status.json','w'))"
  exit 1
fi
python3 - "$ROOT/logs/negctl/summary.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
real=any(any(('FAIL a16' in l) or ('FAIL fp' in l) or ('FAIL packed' in l)
            for l in c['fail_lines']) for c in d['cases'].values())
out={'rejected':True,'value_mismatch':bool(real),'failed_cases':d['failed'],'gate_rc':d['gate_rc']}
json.dump(out,open(p.replace('summary.json','status.json'),'w'),indent=1)
if not real:
    print('NEGCTL_FAIL: rejected but without value mismatches:', d.get('failed'))
    sys.exit(1)
print('NEGCTL_OK: broken RTL rejected with value mismatches in', len(d['failed']), 'cases')
PY
exit $?
