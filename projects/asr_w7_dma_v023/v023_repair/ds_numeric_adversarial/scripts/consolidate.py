"""Consolidate all audit runs into the final result.json."""

import hashlib
import json
import os
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
P = "/home/yang/Desktop/项目/v023_repair"


def load(name):
    with open(os.path.join(ROOT, name)) as f:
        return json.load(f)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


OLD_SRC = {
    "epilogue_i48_to_f32.sv": f"{P}/gemini_epilogue/epilogue_i48_to_f32.sv",
    "epilogue_fma_stage.sv": f"{P}/gemini_epilogue/epilogue_fma_stage.sv",
    "epilogue_f32_to_i16.sv": f"{P}/gemini_epilogue/epilogue_f32_to_i16.sv",
    "epilogue_relu.sv": f"{P}/gemini_epilogue/epilogue_relu.sv",
    "epilogue_lane.sv": f"{P}/gemini_epilogue/epilogue_lane.sv",
    "epilogue_stream_engine_v023.sv": f"{P}/gemini_epilogue/epilogue_stream_engine_v023.sv",
    "approx_div_sqrt.sv": f"{P}/gemini_approx/rtl/approx_div_sqrt.sv",
    "approx_recip_lut.sv": f"{P}/gemini_approx/rtl/approx_recip_lut.sv",
    "approx_rsqrt_lut.sv": f"{P}/gemini_approx/rtl/approx_rsqrt_lut.sv",
}
FMA_SRC = {
    "epilogue_i48_to_f32.sv": f"{P}/gemini_fma_repair/candidate/epilogue_i48_to_f32.sv",
    "epilogue_fma_stage.sv": f"{P}/gemini_fma_repair/candidate/epilogue_fma_stage.sv",
    "fp32_fma_pipe.sv": f"{P}/gemini_fma_repair/candidate/fp32_fma_pipe.sv",
    "asr_fma_ip.sv": f"{P}/gemini_fma_repair/candidate/asr_fma_ip.sv",
    "epilogue_f32_to_i16.sv": f"{P}/gemini_fma_repair/candidate/epilogue_f32_to_i16.sv",
    "epilogue_relu.sv": f"{P}/gemini_fma_repair/candidate/epilogue_relu.sv",
    "epilogue_lane.sv": f"{P}/gemini_fma_repair/candidate/epilogue_lane.sv",
    "epilogue_stream_engine_v023.sv": f"{P}/gemini_fma_repair/candidate/epilogue_stream_engine_v023.sv",
}
APPROX_SRC = {
    "approx_div_sqrt.sv": f"{P}/gemini_approx_repair/candidate/rtl/approx_div_sqrt.sv",
    "approx_recip_lut.sv": f"{P}/gemini_approx_repair/candidate/rtl/approx_recip_lut.sv",
    "approx_rsqrt_lut.sv": f"{P}/gemini_approx_repair/candidate/rtl/approx_rsqrt_lut.sv",
}
TEST_SRC = {}
for d in ["ref", "tb", "scripts"]:
    for f in sorted(os.listdir(os.path.join(ROOT, d))):
        p = os.path.join(ROOT, d, f)
        if os.path.isfile(p):
            TEST_SRC[f"{d}/{f}"] = p


def summarize_tests(tests, keys=None):
    out = {}
    for k, v in tests.items():
        if keys and k not in keys:
            continue
        out[k] = {kk: v.get(kk) for kk in [
            "pass", "rc", "vectors", "mismatches", "special_mismatch", "last_errors",
            "flags_errors", "flag_semantic_errors", "stability_errors",
            "tag_errors", "order_errors", "latency", "ii", "max_rel_err",
            "mean_rel_err", "a16_mismatch", "packed_mismatch",
            "spill_mismatch", "tag_mismatch", "a16_count_mismatch",
            "packed_count_mismatch", "post_abort_outputs",
            "in_flight_corrupted", "flush_errors", "by_mode", "by_class",
            "underflow_results", "overflow_results", "a16", "cases",
        ] if kk in v}
    return out


def main():
    old = load("result_old_final.json")["tests"]
    fma0 = load("result_fma_repair.json")["tests"]["fma"]
    asr = load("result_fma_repair.json")["tests"]["asr_fma_ip"]
    fma1 = load("result_fma_repair_bp1.json")["tests"]["fma"]
    flush = load("result_fma_repair_flush2.json")["tests"]["flush"]
    stream0 = load("result_fma_repair_stream2.json")["tests"]
    stream1 = load("result_fma_repair_stream_bp1.json")["tests"]
    stream2 = load("result_fma_repair_stream_bp2b.json")["tests"]
    ap0 = load("result_approx_repair2.json")["tests"]
    ap1 = load("result_approx_repair_bp1.json")["tests"]
    audit = load("model_audit.json")
    ccheck = load("ref_c_crosscheck.json")
    worst = load("approx_worst_cases.json")

    res = {
        "task": "ds_numeric_adversarial",
        "date": "2026-10-29",
        "scope": ("Independent numeric acceptance audit. Logic simulation only "
                  "(Icarus Verilog 14 + Python exact arithmetic + C libc cross-check). "
                  "No synthesis, no Vivado, no board, no VNC, no push. "
                  "No module under test was modified."),
        "overall_pass": False,
        "verdict": (
            "NOT ACCEPTED. i48->f32 and f32->i16 pass the independent vectors; "
            "the repaired FMA still fails RNE tie-to-even and extreme exponent "
            "alignment; the repaired approx core still has factor-2 boundary "
            "errors and an RSQRT(-0) sign error; the epilogue stream engine "
            "corrupts A16 tags, duplicates A16 handshakes under 128-bit "
            "backpressure, ignores the parameter preload port, and allows a "
            "configuration change to hit an in-flight beat."
        ),
        "source_sha256": {
            "old": {k: sha(v) for k, v in OLD_SRC.items()},
            "fma_repair": {k: sha(v) for k, v in FMA_SRC.items()},
            "approx_repair": {k: sha(v) for k, v in APPROX_SRC.items()},
            "tests": {k: sha(v) for k, v in TEST_SRC.items()},
        },
        "reference_independence": {
            "method": ("Python Fractions/integers implement RNE from first "
                       "principles; no gemini golden model is imported."),
            "c_crosscheck": ccheck,
            "note": ("C fmaf/lrintf/cast are an independent implementation. "
                     "The FMA crosscheck is restricted to normal-input finite "
                     "non-zero results because the DUT and the contract differ "
                     "on FTZ/special signed-zero conventions."),
        },
        "model_audit": {
            "claims": audit["claims"],
            "observed": audit["observed"],
            "verdict": audit["verdict"],
        },
        "tests": {
            "old_baseline": {
                "i48": summarize_tests(old, ["i48"])["i48"],
                "fma": summarize_tests(old, ["fma"])["fma"],
                "f32i16": summarize_tests(old, ["f32i16"])["f32i16"],
                "approx": summarize_tests(old, ["approx_t0", "approx_t1", "approx_t2"]),
                "flush": summarize_tests(old, ["flush"])["flush"],
                "stream": summarize_tests(old, ["stream_conv", "stream_fma",
                                                "stream_fma_real", "stream_spill",
                                                "stream_abort", "stream_param_port",
                                                "stream_reconfig"]),
            },
            "fma_repair": {
                "fma_bp0": summarize_tests({"fma": fma0})["fma"],
                "asr_fma_ip_wrapper": asr,
                "fma_bp1": summarize_tests({"fma": fma1})["fma"],
                "flush": flush,
                "stream_bp0": summarize_tests(stream0),
                "stream_bp1": summarize_tests(stream1),
                "stream_bp2_packed_backpressure": summarize_tests(stream2),
            },
            "approx_repair": {
                "approx_t1_bp0": ap0["approx_t1"],
                "approx_t1_bp1": ap1["approx_t1"],
                "flush": ap0["approx_flush"],
                "param_rejection": ap0["approx_param_rejection"],
            },
        },
        "approx_worst_cases": worst,
        "blocking_findings": [
            {
                "id": "FMA-1",
                "module": "gemini_fma_repair candidate epilogue_fma_stage/fp32_fma_pipe/asr_fma_ip",
                "summary": ("RNE tie-to-even is still wrong for exact halfway "
                            "products. Example 0x3f800003 * 0x3fc00000: correct "
                            "0x3fc00004, DUT 0x3fc00005. 90/8311 normal-input "
                            "vectors mismatch (66 normal/normal/normal + 24 "
                            "normal/normal/zero)."),
                "evidence": "result_fma_repair.json, tb/tb_fma.sv, refmodel.py",
            },
            {
                "id": "FMA-2",
                "module": "gemini_fma_repair candidate fp32_fma_pipe/asr_fma_ip",
                "summary": ("Extreme exponent alignment is broken. Example "
                            "0x00800000 * 0x3f800001 + 0x3f800000 should be "
                            "0x3f800000 (1.0) but returns 0x0e800000 (2^-97)."),
                "evidence": "result_fma_repair.json by_class normal; C fmaf crosscheck",
            },
            {
                "id": "FMA-3",
                "module": "gemini_fma_repair candidate fp32_fma_pipe/asr_fma_ip",
                "summary": ("Special values: inf*0 returns inf instead of NaN; "
                            "inf + (-inf) returns inf instead of NaN; signed-zero "
                            "cases are inverted. 34 inf-class and 2 zero-class "
                            "mismatches."),
                "evidence": "result_fma_repair.json by_class inf/zero",
            },
            {
                "id": "APPROX-1",
                "module": "gemini_approx_repair candidate approx_div_sqrt",
                "summary": ("DIV factor-2 boundary error: 1.0 / 31.9998 "
                            "(0x3f800000/0x41fffad2) returns 0x3d7fde3c "
                            "(0.06247) instead of 0.03125 (99.88% relative error). "
                            "This is outside the claimed 0.108% bound."),
                "evidence": "approx_worst_cases.json, result_approx_repair2.json",
            },
            {
                "id": "APPROX-2",
                "module": "gemini_approx_repair candidate approx_div_sqrt",
                "summary": ("RSQRT factor-2 boundary error at max finite: "
                            "RSQRT(0x7f7fffff) returns 0x1ffffff4 (1.084e-19) "
                            "instead of 5.421e-20 (99.99985% relative error)."),
                "evidence": "approx_worst_cases.json",
            },
            {
                "id": "APPROX-3",
                "module": "gemini_approx_repair candidate approx_div_sqrt",
                "summary": ("RSQRT(-0) and RSQRT(negative subnormal) return +inf; "
                            "IEEE-754 sign is -inf. flags[1] is set, but the sign "
                            "is wrong. Low model impact (LayerNorm var+eps > 0)."),
                "evidence": "result_approx_repair2.json special_mismatch=3",
            },
            {
                "id": "STREAM-1",
                "module": "epilogue_stream_engine_v023 (unchanged by FMA repair)",
                "summary": ("A16 tag is corrupted whenever the 128-bit packer "
                            "holds a pending beat: a16_tag is muxed from p128_tag. "
                            "255/256 A16 tags wrong at BP0; example beat 2 gets "
                            "tag 1 instead of 2."),
                "evidence": "result_fma_repair_stream2.json stream_conv tag_mismatch=255",
            },
            {
                "id": "STREAM-2",
                "module": "epilogue_stream_engine_v023",
                "summary": ("A16 ready/valid violation under 128-bit packed "
                            "backpressure: a16_valid stays high while the packer "
                            "is full, so a consumer counting valid&&ready sees "
                            "duplicates. 402 A16 handshakes for 256 beats (146 "
                            "duplicates) at BP2."),
                "evidence": "result_fma_repair_stream_bp2b.json a16_count_mismatch=146",
            },
            {
                "id": "STREAM-3",
                "module": "epilogue_stream_engine_v023",
                "summary": ("param_wr_* is completely inert: writing scale 0.5 "
                            "through the parameter port while cfg_scale=1.0 "
                            "produces the cfg_scale result (113/256 A16 beats "
                            "differ from the parameter-port expectation)."),
                "evidence": "result_fma_repair_stream2.json stream_param_port",
            },
            {
                "id": "STREAM-4",
                "module": "epilogue_stream_engine_v023",
                "summary": ("cfg_ready=!in_burst allows a new descriptor to be "
                            "loaded while the last accepted beat is still in the "
                            "9-stage lane. Beat accepted under scale 1.0 is output "
                            "as 6 (new scale 3.0) instead of 2."),
                "evidence": "result_fma_repair_stream2.json stream_reconfig",
            },
        ],
        "nonblocking_findings": [
            {
                "id": "TIER-OLD",
                "summary": ("Old gemini_approx TIER=0 is broken by a factor of 2 "
                            "(seed shifted by 8 instead of 7); mean DIV relative "
                            "error 73.3%. TIER=2 is bit-identical to TIER=1 and "
                            "all tiers have 4-cycle latency, confirming the old "
                            "three-tier claim was fictitious."),
                "evidence": "result_old_final.json approx_t0/t1/t2",
            },
            {
                "id": "TIER-NEW",
                "summary": ("New approx core correctly prunes TIER 0/2 and rejects "
                            "TIER!=1, LATENCY!=5, II!=1 at elaboration. Latency=5, "
                            "II=1, flush works. This structural repair is accepted."),
                "evidence": "result_approx_repair2.json approx_param_rejection/approx_flush",
            },
            {
                "id": "APPROX-FLUSH-PORT",
                "summary": ("The new approx source declares `input wire flush` with "
                            "no default, while INTERFACE.md claims a default of 0. "
                            "The existing ds_vector candidate instantiates it "
                            "without .flush(); the port is unconnected, so the "
                            "engine's synchronous core_flush does not drain the "
                            "approx pipeline."),
                "evidence": "gemini_approx_repair/candidate/rtl/approx_div_sqrt.sv:27; "
                            "ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv:160",
            },
            {
                "id": "FMA-FIXTURE",
                "summary": ("The repaired FMA's 1001-vector official fixture does "
                            "not cover exact tie-to-even or extreme exponent "
                            "alignment; it passes while our 90 normal-input "
                            "adversarial vectors fail."),
                "evidence": "result_fma_repair.json vs gemini_fma_repair/result.json",
            },
        ],
        "passed_items": [
            "i48->f32: 37,166 vectors, 0 mismatches, tags/last/stability OK; C cast cross-check 0 mismatches.",
            "f32->i16: 464,154 vectors, 0 mismatches (RNE, ties, clamp, NaN/Inf), C lrintf cross-check 0 mismatches.",
            "Epilogue leaf flush: i48/fma/f32i16/lane 0 errors; new FMA/lane latency-adjusted flush 0 errors.",
            "Old/new epilogue mode 0 bypass, ReLU, spill data, 128-bit packing/zero padding: 0 data mismatches at BP0.",
            "Stream abort: 0 post-abort outputs, statistics retained.",
            "New approx: TIER/LATENCY/II rejection, flush, tag/order/stability, latency=5, II=1.",
        ],
        "unverified": [
            "No exhaustive proof of i48->f32 or f32->i16; only 37k/464k adversarial vectors plus C cross-check.",
            "No synthesis/Vivado/STA; no 300/600 MHz claim is made or accepted.",
            "No full ASR model accuracy/WER/CER; the actual model's LayerNorm variance/epsilon range cannot be verified because no ONNX/calibration data is present in the read-only tree.",
            "FMA/special signed-zero and subnormal-input semantics may differ from the vendor IP contract; our reference uses FTZ, so subnormal-input mismatches are reported separately and are not used as the primary FMA blocking evidence.",
            "The epilogue stream engine's packed A16 path was tested with a BFM, not with the real ds_vector/ds_layout consumer.",
            "The new approx core was not re-tested inside the ds_vector wrapper with its unconnected flush port.",
        ],
        "commands": {
            "generate_vectors": "python3 scripts/gen_vectors.py",
            "model_audit": "python3 scripts/audit_model.py",
            "c_crosscheck": "python3 scripts/crosscheck_c.py",
            "old_full": "python3 scripts/run_suite.py --label old_final",
            "fma_repair": ("python3 scripts/run_suite.py --label fma_repair "
                           "--i48 .../candidate/epilogue_i48_to_f32.sv --fma .../candidate/epilogue_fma_stage.sv "
                           "--fma-pipe .../candidate/fp32_fma_pipe.sv --f32i16 .../candidate/epilogue_f32_to_i16.sv "
                           "--relu .../candidate/epilogue_relu.sv --lane .../candidate/epilogue_lane.sv "
                           "--stream .../candidate/epilogue_stream_engine_v023.sv --only fma"),
            "approx_repair": ("python3 scripts/run_suite.py --label approx_repair2 "
                              "--approx .../candidate/rtl/approx_div_sqrt.sv "
                              "--recip .../candidate/rtl/approx_recip_lut.sv "
                              "--rsqrt .../candidate/rtl/approx_rsqrt_lut.sv "
                              "--approx-has-flush --only approx"),
        },
        "exit_codes": {
            "old_full": 1,
            "old_i48": 0,
            "old_f32i16": 0,
            "fma_repair_fma_bp0": 1,
            "fma_repair_fma_bp1": 1,
            "fma_repair_flush": 0,
            "fma_repair_stream_bp0": 1,
            "fma_repair_stream_bp1": 1,
            "fma_repair_stream_bp2": 1,
            "approx_repair_approx_bp0": 1,
            "approx_repair_approx_bp1": 1,
            "approx_repair_flush": 0,
            "approx_repair_param_rejection": 0,
            "run_all": 1
        },
        "logs": sorted(os.path.join(ROOT, "logs", f) for f in os.listdir(os.path.join(ROOT, "logs"))
                       if f.endswith(".log") or f.endswith(".out")),
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    with open(os.path.join(ROOT, "result.json"), "w") as f:
        json.dump(res, f, indent=2)
    print(json.dumps({
        "overall_pass": res["overall_pass"],
        "fma_repair_mismatches": fma0["mismatches"],
        "approx_special_mismatch": ap0["approx_t1"]["special_mismatch"],
        "stream_tag_mismatch": stream0["stream_conv"]["tag_mismatch"],
        "stream_bp2_duplicates": stream2["stream_conv"]["a16_count_mismatch"],
    }, indent=2))


if __name__ == "__main__":
    main()
