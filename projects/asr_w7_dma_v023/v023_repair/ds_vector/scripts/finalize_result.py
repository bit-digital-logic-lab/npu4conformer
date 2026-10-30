#!/usr/bin/env python3
"""Merge exact/approx/AXI/FMA results into the final result.json."""
import json, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
reg=json.loads((ROOT/"regression_result.json").read_text())
ap=json.loads((ROOT/"approx_result.json").read_text())
ax=json.loads((ROOT/"axi_result.json").read_text())
sha={}
for line in (ROOT/"SHA256SUMS.txt").read_text().splitlines():
    h,p=line.split(None,1); sha[p.strip()]=h
out={"task":"ds_vector",
 "status":"completed" if (reg["passed"] and ap["passed"] and ax["passed"]) else "failed",
 "passed":bool(reg["passed"] and ap["passed"] and ax["passed"]),
 "scope":reg["scope"],
 "acceptance_response":{
   "primary_report":"../primary_acceptance/REPORT.md",
   "tail_cases":"fixed: add_tail5/add_tail7/a48_tail3/f32_to_i16_tail7 route banks <=8 to exact core; all 67 exact fixtures pass",
   "fma":"not implemented/substituted in ds_vector; op17 only reaches vendor asr_fma_ip and aborts under forbidden stub; epilogue FMA blocker remains outside this task",
   "approx_tiers":"three-tier claim withdrawn; delivered core is one fixed 4-stage structure; TIER/LATENCY/II are metadata, not structural",
   "early_pass_reused":False},
 "counts":{"exact_regression_cases":reg["counts"]["regression_cases"],
   "exact_stress_cases":reg["counts"]["stress_cases"],
   "exact_passed":reg["counts"]["passed_cases"],
   "axi_cases":len(ax["tests"]),"approx_normal":len(ap["tests"]),
   "approx_special":len(ap["special"]),"approx_backpressure":len(ap["backpressure"])},
 "exact":reg,"approx":ap,"axi":ax,
 "fma":{"covered":False,"reason":"vendor asr_fma_ip simulation model absent; tests link fma_forbidden_stub.sv",
        "evidence_log":"logs/fma_not_covered.log","expected_rc":1,
        "observed_message":"FMA not covered by forbidden-stub tests"},
 "deliverables_sha256":sha,
 "uncompleted":["FMA numeric simulation not covered (vendor model absent); primary FMA rounding blocker in epilogue remains open",
   "No whole-model accuracy/latency claim; vector-level simulation only",
   "No synthesis/STA/Vivado/board/300-600MHz claim",
   "Wide-lane tag tokens carried/echoed but not used as an ordering gate",
   "Candidate AXI write/compute overlap zero on add_scalar; read/compute overlap nonzero",
   "Generated exp/log gold differs because baseline is polynomial approximation"]}
(ROOT/"result.json").write_text(json.dumps(out,indent=2)+"\n")
print("V023_FINAL_RESULT",out["status"],out["counts"])
