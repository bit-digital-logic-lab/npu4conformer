#!/usr/bin/env bash
# Reproduce AR-006/007 on the original advisory harness, prove the failure is
# the harness freezing consumer ready, and produce old-vs-new strict evidence.
# The reference worker tree is never edited: the advisory tb/script are copied
# byte-identically into ref_probe/ and run there.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="/home/yang/Desktop/项目/v024_opt/ds_adversarial_review"
OLD="/home/yang/Desktop/项目/v024_opt/ds_epilogue_channels/rtl"
NEW="$ROOT/rtl"
EV="$ROOT/logs/evidence"; rm -rf "$EV"; mkdir -p "$EV"

# ---------- 1. byte-identical advisory harness copy ----------
rm -rf "$ROOT/ref_probe"; mkdir -p "$ROOT/ref_probe/scripts" "$ROOT/ref_probe/tb" "$ROOT/ref_probe/vectors" "$ROOT/ref_probe/reports"
cp "$REF/scripts/run_epilogue.sh" "$ROOT/ref_probe/scripts/"
cp "$REF/tb/tb_epilogue.sv" "$ROOT/ref_probe/tb/"
cp -r "$REF/vectors/epi" "$ROOT/ref_probe/vectors/"
sha256sum "$ROOT/ref_probe/scripts/run_epilogue.sh" "$ROOT/ref_probe/tb/tb_epilogue.sv" > "$EV/ref_copy_sha.txt"
sha256sum "$REF/scripts/run_epilogue.sh" "$REF/tb/tb_epilogue.sv" >> "$EV/ref_copy_sha.txt"
echo '{"note":"local reproduction db; reference tree is read-only"}' > "$ROOT/ref_probe/reports/frozen_shas.json"

# ---------- 2. original advisory: old and new ----------
bash "$ROOT/ref_probe/scripts/run_epilogue.sh" adv_old "$OLD"/*.sv > "$EV/advisory_old.txt" 2>&1
echo "advisory_old_script_rc=$?" >> "$EV/advisory_old.txt"
bash "$ROOT/ref_probe/scripts/run_epilogue.sh" adv_new "$NEW"/*.sv > "$EV/advisory_new.txt" 2>&1
echo "advisory_new_script_rc=$?" >> "$EV/advisory_new.txt"

# ---------- 3. corrected-ready copy: only the ready driver changed ----------
# exp/tb_exp.sv is ref_probe/tb/tb_epilogue.sv plus a clocked drive_bp in every
# wait loop (send/drain/config/param).  No RTL file was changed.
iverilog -g2012 -o "$EV/sim_old_ready" "$ROOT/exp/tb_exp.sv" "$OLD"/*.sv > "$EV/compile_old_ready.log" 2>&1
echo "compile_old_ready_rc=$?" >> "$EV/compile_old_ready.log"
iverilog -g2012 -o "$EV/sim_new_ready" "$ROOT/exp/tb_exp.sv" "$NEW"/*.sv > "$EV/compile_new_ready.log" 2>&1
echo "compile_new_ready_rc=$?" >> "$EV/compile_new_ready.log"
for who in old new; do
  for probe in "ar006:3:1" "ar007:0:2"; do
    name=${probe%%:*}; rest=${probe#*:}; m=${rest%%:*}; bp=${rest##*:}
    ( cd "$ROOT" && timeout 200 vvp "$EV/sim_${who}_ready" +dir=ref_probe/vectors/epi +mode=$m +bp=$bp ) \
      > "$EV/corrected_${who}_${name}.log" 2>&1
    echo "corrected_${who}_${name}_rc=$?" >> "$EV/corrected_${who}_${name}.log"
  done
done

# ---------- 4. strict gate: old must fail cfg_pending_beat, new must pass all ----------
bash "$ROOT/scripts/run_gate.sh" strict_old "$OLD"/*.sv > "$EV/strict_old.txt" 2>&1
echo "strict_old_rc=$?" >> "$EV/strict_old.txt"
bash "$ROOT/scripts/run_gate.sh" strict_new "$NEW"/*.sv > "$EV/strict_new.txt" 2>&1
echo "strict_new_rc=$?" >> "$EV/strict_new.txt"

python3 - "$ROOT" <<'PY'
import json, os, re, sys
root=sys.argv[1]; ev=os.path.join(root,'logs/evidence')
def txt(p):
    try: return open(p,errors='replace').read()
    except Exception: return ''
def probe_rc(who,name):
    t=txt(os.path.join(ev,f'advisory_{who}.txt'))
    m=re.search(rf'{name} rc=(\d+)',t)
    return int(m.group(1)) if m else None
def corrected(who,name):
    p=os.path.join(ev,f'corrected_{who}_{name}.log'); t=txt(p)
    m=re.search(r'corrected_'+who+'_'+name+r'_rc=(\d+)',t)
    r=re.search(r'^(RESULT .*)$',t,re.M)
    return {'rc':int(m.group(1)) if m else None,
            'result':r.group(1) if r else None,
            'pass':'PASS' in t}
def gate(tag):
    p=os.path.join(root,'logs',tag,'summary.json')
    if not os.path.exists(p): return {'gate_rc':None,'failed':[]}
    d=json.load(open(p))
    return {'gate_rc':d['gate_rc'],'case_count':d['case_count'],'failed':d['failed'],
            'fail_lines':{k:v['fail_lines'] for k,v in d['cases'].items() if not v['pass']}}
out={
 'reference_copy_sha':txt(os.path.join(ev,'ref_copy_sha.txt')).splitlines(),
 'original_advisory':{
   'old':{'AR-006_rc':probe_rc('old','probe_both_bp'),'AR-007_rc':probe_rc('old','probe_multiphase_a16bp')},
   'new':{'AR-006_rc':probe_rc('new','probe_both_bp'),'AR-007_rc':probe_rc('new','probe_multiphase_a16bp')},
   'root_cause':'the advisory TB stops driving a16_ready/fp32x4_ready after the last send_beat and during cfg/param/drain waits; a consumer that never re-asserts ready cannot drain any correct pipelined RTL'},
 'corrected_ready_old':{'AR-006':corrected('old','ar006'),'AR-007':corrected('old','ar007')},
 'corrected_ready_new':{'AR-006':corrected('new','ar006'),'AR-007':corrected('new','ar007')},
 'strict_gate_old':gate('strict_old'),
 'strict_gate_new':gate('strict_new'),
}
json.dump(out,open(os.path.join(ev,'summary.json'),'w'),indent=1)
print(json.dumps(out,indent=1))
PY
