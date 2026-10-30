#!/usr/bin/env bash
# ds_repair_fmaflush — full local-logic gate. Serial compile+sim, one
# watchdog per simulation (shell timeout + in-TB watchdog), no synthesis.
# Every case records its real exit code AND a log marker; the summary fails
# if the two disagree or if an expected PASS/FAIL is not observed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-gate}"
LOG="$ROOT/logs/$TAG"
SIM="$ROOT/sim/$TAG"
RUNS="$LOG/runs.tsv"
rm -rf "$LOG" "$SIM"
mkdir -p "$LOG" "$SIM"
: > "$RUNS"
START="$(date -Iseconds)"

# ---------------- tool / environment record ----------------
{
  echo "date=$START"
  echo "host=$(hostname)"
  echo "uname=$(uname -srm)"
  echo "python=$(python3 -V 2>&1)"
  echo "iverilog=$(iverilog -V 2>&1 | head -1)"
  echo "root=$ROOT"
} > "$LOG/env.txt"

# ---------------- helpers ----------------
compile_case() { # top out args...
  local top="$1" out="$2"; shift 2
  local name; name="compile_$(basename "$out" .vvp)"
  rm -f "$out"
  iverilog -g2012 -s "$top" -o "$out" "$@" > "$LOG/$name.log" 2>&1
  local rc=$?
  printf '%s\t%s\tpass\t%s\t%s\n' "$name" "$rc" "$LOG/$name.log" "" >> "$RUNS"
  return $rc
}

run_case() { # name vvp expect markers args...
  local name="$1" vvpfile="$2" expect="$3" markers="$4"; shift 4
  ( cd "$ROOT" && timeout 300 vvp "$vvpfile" "$@" > "$LOG/$name.log" 2>&1 )
  local rc=$?
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$rc" "$expect" "$LOG/$name.log" "$markers" >> "$RUNS"
  return 0
}

py_case() { # name expect markers script args...
  local name="$1" expect="$2" markers="$3"; shift 3
  ( cd "$ROOT" && timeout 300 python3 "$@" > "$LOG/$name.log" 2>&1 )
  local rc=$?
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$rc" "$expect" "$LOG/$name.log" "$markers" >> "$RUNS"
  return 0
}

# ---------------- stage 1: mutants + independent gold + vectors ----------------
py_case make_mutants pass "mutants written" scripts/make_mutants.py
py_case gold_check pass "GOLD_CHECK=PASS" gold/check_and_gen.py
py_case prepare_asr_vectors pass "wrote 8734 asr rows" scripts/prepare_vectors.py

# ---------------- freeze all inputs before any simulation ----------------
{
  echo "== RTL ==";      sha256sum "$ROOT"/rtl/*.sv
  echo "== TB ==";       sha256sum "$ROOT"/tb/*.sv
  echo "== GOLD ==";     sha256sum "$ROOT"/gold/*.py
  echo "== VECTORS ==";  sha256sum "$ROOT"/vectors/*.txt
  echo "== MUTANTS ==";  sha256sum "$ROOT"/mutants/*.sv
} > "$ROOT/SHA256SUMS"
python3 - "$ROOT" <<'PY'
import hashlib,json,os,sys,time
root=sys.argv[1]
out={}
for d in ("rtl","tb","gold","vectors","mutants"):
    out[d]={}
    for f in sorted(os.listdir(os.path.join(root,d))):
        p=os.path.join(root,d,f)
        if os.path.isfile(p):
            out[d][f]=hashlib.sha256(open(p,'rb').read()).hexdigest()
json.dump({"when":time.strftime("%Y-%m-%dT%H:%M:%S%z"),"sha256":out},
          open(os.path.join(root,"reports","frozen_shas.json"),"w"),indent=1)
PY

# ---------------- stage 2: compile (serial, -j1) ----------------
compile_case tb_fma "$SIM/tb_fma.vvp" tb/tb_fma_mode4.sv rtl/fp32_fma_pipe.sv
compile_case tb_fma_latency "$SIM/tb_fma_latency.vvp" tb/tb_fma_latency.sv rtl/epilogue_fma_stage.sv rtl/fp32_fma_pipe.sv
compile_case tb_flush "$SIM/tb_flush.vvp" tb/tb_flush_lat.sv rtl/epilogue_i48_to_f32.sv rtl/epilogue_fma_stage.sv rtl/epilogue_f32_to_i16.sv rtl/epilogue_lane.sv rtl/epilogue_relu.sv rtl/fp32_fma_pipe.sv
compile_case tb_flush_contract "$SIM/tb_flush_contract.vvp" tb/tb_flush_contract.sv rtl/fp32_fma_pipe.sv
compile_case tb_wrap_lane_lat "$SIM/tb_wrap_lane_lat.vvp" tb/tb_wrap_lane_lat.sv rtl/epilogue_lane.sv rtl/epilogue_fma_stage.sv rtl/epilogue_i48_to_f32.sv rtl/epilogue_relu.sv rtl/epilogue_f32_to_i16.sv rtl/fp32_fma_pipe.sv rtl/asr_fma_ip.sv
compile_case tb_asr_fma_ip "$SIM/tb_asr_fma_ip.vvp" tb/tb_asr_fma_ip.sv rtl/asr_fma_ip.sv rtl/fp32_fma_pipe.sv

# negative-control compiles
compile_case tb_fma "$SIM/tb_fma_m0.vvp" tb/tb_fma_mode4.sv mutants/m0_original_unfixed.sv
compile_case tb_flush_contract "$SIM/tb_contract_m1.vvp" tb/tb_flush_contract.sv mutants/m1_inready_only.sv
compile_case tb_flush_contract "$SIM/tb_contract_m2.vvp" tb/tb_flush_contract.sv mutants/m2_no_reset_gate.sv

# ---------------- stage 3: functional gate (fixed RTL) ----------------
run_case mode0_8734 "$SIM/tb_fma.vvp" pass "RESULT mode=0 n=8734 out=8734 errors=0;PASS" +vec=vectors/fma_8734_proj.txt +mode=0
run_case mode1_flush_8734 "$SIM/tb_fma.vvp" pass "RESULT mode=1 n=8734 out=0 errors=0;PASS" +vec=vectors/fma_8734_proj.txt +mode=1
run_case mode2_reset_8734 "$SIM/tb_fma.vvp" pass "RESULT mode=2 n=8734 out=8734 errors=0;PASS" +vec=vectors/fma_8734_proj.txt +mode=2
run_case mode3_ii_8734 "$SIM/tb_fma.vvp" pass "II_ACCEPT span=8734 n=8734 max_gap=1 accepted=8734;PASS" +vec=vectors/fma_8734_proj.txt +mode=3
run_case mode4_flush_handshake "$SIM/tb_fma.vvp" pass "FLUSH_HANDSHAKES=0;PASS" +vec=vectors/fma_8734_proj.txt +mode=4
run_case mode0_fresh2000 "$SIM/tb_fma.vvp" pass "RESULT mode=0 n=2000 out=2000 errors=0;PASS" +vec=vectors/fma_fresh_2000.txt +mode=0
run_case mode1_flush_fresh2000 "$SIM/tb_fma.vvp" pass "RESULT mode=1 n=2000 out=0 errors=0;PASS" +vec=vectors/fma_fresh_2000.txt +mode=1
run_case mode2_reset_fresh2000 "$SIM/tb_fma.vvp" pass "RESULT mode=2 n=2000 out=2000 errors=0;PASS" +vec=vectors/fma_fresh_2000.txt +mode=2
run_case mode3_ii_fresh2000 "$SIM/tb_fma.vvp" pass "max_gap=1;PASS" +vec=vectors/fma_fresh_2000.txt +mode=3
run_case mode4_flush_handshake_fresh "$SIM/tb_fma.vvp" pass "FLUSH_HANDSHAKES=0;PASS" +vec=vectors/fma_fresh_2000.txt +mode=4
run_case latency_7_ii1_bypass "$SIM/tb_fma_latency.vvp" pass "latency=7, II=1;LATENCY_TEST_ERRORS=0" 
run_case flush_contract "$SIM/tb_flush_contract.vvp" pass "CONTRACT_ERRORS=0"
run_case flush_leaves "$SIM/tb_flush.vvp" pass "FLUSH_ERRORS=0"
run_case wrap_lane_latency "$SIM/tb_wrap_lane_lat.vvp" pass "wrapper latency=7;lane mode0 bypass latency=12;WRAP_LANE_ERRORS=0"
run_case asr_wrapper_8734 "$SIM/tb_asr_fma_ip.vvp" pass "DONE asr_fma_ip in=8734 out=8734" +VEC_FILE=vectors/asr_8734.txt +OUT_FILE=logs/$TAG/asr_out.txt +MAX_CYCLES=200000
py_case asr_numeric_compare pass "asr_numeric_mismatch=0" - "$ROOT" "$LOG/asr_out.txt" <<'PY'
import sys
root,out=sys.argv[1],sys.argv[2]
exp=[l.split()[3].lower() for l in open(root+'/vectors/fma_8734_proj.txt') if len(l.split())>=4]
got=[l.split()[1].lower() for l in open(out) if len(l.split())>=2]
bad=[i for i,(e,g) in enumerate(zip(exp,got)) if e!=g]
print('asr_expected=%d asr_got=%d asr_numeric_mismatch=%d'%(len(exp),len(got),len(bad)))
for i in bad[:5]: print('MISMATCH idx=%d exp=%s got=%s'%(i,exp[i],got[i]))
raise SystemExit(0 if len(exp)==len(got) and not bad else 1)
PY

# ---------------- stage 4: negative controls ----------------
run_case neg_m0_original_mode4 "$SIM/tb_fma_m0.vvp" fail "FLUSH_HANDSHAKES=4;FAIL" +vec=vectors/fma_251_proj.txt +mode=4
run_case neg_m0_original_mode1 "$SIM/tb_fma_m0.vvp" pass "RESULT mode=1 n=8734 out=0 errors=0;PASS" +vec=vectors/fma_8734_proj.txt +mode=1
run_case neg_m1_inready_only "$SIM/tb_contract_m1.vvp" fail "out_valid not cancelled combinationally;CONTRACT_ERRORS=2" 
run_case neg_m2_no_reset_gate "$SIM/tb_contract_m2.vvp" fail "in_ready=1 while rst_n=0;CONTRACT_ERRORS=3" 

# ---------------- stage 5: result ----------------
python3 - "$ROOT" "$LOG" "$RUNS" "$TAG" "$START" <<'PY'
import json,os,sys
root,log,runs_file,tag,start=sys.argv[1:]
rows=[]
with open(runs_file) as f:
    for line in f:
        p=line.rstrip('\n').split('\t')
        if len(p)<5: continue
        rows.append({"name":p[0],"rc":int(p[1]),"expect":p[2],"log":p[3],
                     "markers":[m for m in p[4].split(';') if m]})
def read(path):
    try: return open(path,errors='replace').read()
    except Exception: return ''
all_ok=True
for r in rows:
    txt=read(r["log"])
    if r["expect"]=="pass":
        rc_ok=(r["rc"]==0)
        marker_ok=all(m in txt for m in r["markers"])
    else:
        rc_ok=(r["rc"]!=0)
        marker_ok=all(m in txt for m in r["markers"]) and ("FAIL" in txt or "FATAL" in txt)
    r["rc_consistent"]=rc_ok
    r["marker_ok"]=marker_ok
    r["ok"]=rc_ok and marker_ok
    if not r["ok"]: all_ok=False
res={"task":"ds_repair_fmaflush","tag":tag,"started":start,
     "finished":__import__('time').strftime("%Y-%m-%dT%H:%M:%S%z"),
     "top_rc":0 if all_ok else 1,
     "compiles":[r for r in rows if r["name"].startswith("compile_")],
     "runs":[r for r in rows if not r["name"].startswith("compile_")],
     "note":"Local Icarus logic simulation only; no synthesis/STA/board."}
json.dump(res,open(os.path.join(root,"result.json"),"w"),indent=1)
print("%-34s %-6s %-6s %-5s %-5s %s"%("case","rc","expect","rcOK","mkr","verdict"))
bad=0
for r in rows:
    print("%-34s %-6d %-6s %-5s %-5s %s"%(r["name"],r["rc"],r["expect"],
          "yes" if r["rc_consistent"] else "NO",
          "yes" if r["marker_ok"] else "NO",
          "PASS" if r["ok"] else "FAIL"))
    if not r["ok"]: bad+=1
print("GATE_%s cases=%d failures=%d top_rc=%d"%("PASS" if all_ok else "FAIL",len(rows),bad,0 if all_ok else 1))
raise SystemExit(0 if all_ok else 1)
PY

RC=$?
echo "RUN_ALL_RC=$RC"
exit $RC
