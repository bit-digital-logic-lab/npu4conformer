#!/usr/bin/env bash
# Strict epilogue formal gate.
#   bash scripts/run_gate.sh <tag> [rtl_file ...]
# Default RTL list: rtl/*.sv in this tree.  Compilation is a single serial
# iverilog invocation (no parallel make, -j1 by construction).  Every case has
# an in-TB cycle watchdog and a shell `timeout`.
# Exit 0 only when every case returns rc=0 and prints PASS.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?tag}"; shift
if [ "$#" -gt 0 ]; then FILES=("$@"); else FILES=("$ROOT"/rtl/*.sv); fi
OUT="$ROOT/logs/$TAG"; rm -rf "$OUT"; mkdir -p "$OUT"
VEC="${VEC:-vectors}"

echo "== compile ==" | tee "$OUT/rc.txt"
iverilog -g2012 -Wall -o "$OUT/sim" "$ROOT/tb/tb_epilogue_strict.sv" "${FILES[@]}" \
  >"$OUT/compile.log" 2>&1
C=$?
echo "compile rc=$C" | tee -a "$OUT/rc.txt"
[ "$C" -eq 0 ] || { echo "GATE_COMPILE_FAIL $TAG"; exit 1; }

RC=0
run_case() { # name mode bp seed n0 n1 ns
  local name=$1 m=$2 bp=$3 seed=$4 n0=$5 n1=$6 ns=$7
  ( cd "$ROOT" && timeout 300 vvp "$OUT/sim" +dir="$VEC" +mode=$m +bp=$bp +seed=$seed \
      +n0=$n0 +n1=$n1 +ns=$ns ) >"$OUT/$name.log" 2>&1
  local r=$?
  local res; res="$(grep -E '^RESULT' "$OUT/$name.log" | tail -1)"
  local pass=FAIL; grep -q '^PASS' "$OUT/$name.log" && pass=PASS
  if [ "$r" -ne 0 ] || [ "$pass" != PASS ]; then RC=1; fi
  printf '%-26s rc=%d %-4s %s\n' "$name" "$r" "$pass" "$res" | tee -a "$OUT/rc.txt"
}

# multi-phase big: 512 + 512 + 64 = 1088 real beats
run_case multi_bp1_random        0 1 101 512 512 64
run_case multi_bp2_long_stall    0 2 102 512 512 64
run_case multi_bp3_a16_fp32      0 3 103 512 512 64
run_case multi_bp4_packed        0 4 104 512 512 64
run_case multi_odd_bp2           0 2 105 511 257 63
run_case multi_odd_bp4           0 4 106 127 129 63
# spill channel with independent backpressure
run_case spill_bp1_random        2 1 107 512 0 0
run_case spill_bp2_long_stall    2 2 108 512 0 0
# abort / new epoch
run_case abort_bp1_random        1 1 109 32 32 64
run_case abort_bp2_long_stall    1 2 110 32 32 64
# config request while an input beat is presented (old-SHA failing item)
run_case cfg_pending_beat        4 1 111 32 32 64
# boundary lengths, including odd tails and 4-lane/row boundaries
for n in 1 2 3 5 17 31 32 127 255 256 257 511 512; do
  run_case "boundary_n${n}" 3 1 $((200+n)) "$n" 32 8
done
# one more boundary family with independent A16/FP32 random backpressure
for n in 9 33 129 259; do
  run_case "boundary_bp3_n${n}" 3 3 $((400+n)) "$n" 32 8
done

python3 - "$OUT" "$TAG" "$RC" <<'PY'
import json, sys, os, re
out, tag, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
cases = {}
for f in sorted(os.listdir(out)):
    if not f.endswith('.log') or f in ('compile.log',): continue
    t = open(os.path.join(out, f), errors='replace').read()
    m = re.search(r'^(RESULT .*)$', t, re.M)
    cases[f[:-4]] = {
        'pass': ('\nPASS\n' in ('\n'+t)) or t.rstrip().endswith('PASS'),
        'result': m.group(1) if m else None,
        'watchdog': 'WATCHDOG' in t,
        'fail_lines': [l for l in t.splitlines() if l.startswith(('FAIL','WATCHDOG'))][:12],
    }
json.dump({'tag': tag, 'gate_rc': rc, 'cases': cases,
           'case_count': len(cases),
           'failed': [k for k,v in cases.items() if not v['pass']]},
          open(os.path.join(out, 'summary.json'), 'w'), indent=1)
PY

if [ "$RC" -eq 0 ]; then echo "EPI_STRICT_GATE_PASS $TAG"; else echo "EPI_STRICT_GATE_FAIL $TAG"; fi
exit "$RC"
