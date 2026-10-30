"""Audit the actual project ASR model parameters (read-only) and check the
KWT-1 claims used by gemini_approx / gemini_epilogue.

Reads:
  tasks/ds_pl_autonomy/assets/manifest_v022.json   (metadata)
  work/assets/parameters002/parameters.bin         (read-only image)
  v023_repair/ds_graph/analysis/nonmatrix_ops.json

Writes:
  ref/real_model_scales.json
  model_audit.json
"""

import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROJ = "/home/yang/Desktop/项目"
MANIFEST = os.path.join(PROJ, "tasks/ds_pl_autonomy/assets/manifest_v022.json")
IMAGE = os.path.join(PROJ, "work/assets/parameters002/parameters.bin")
NONMATRIX = os.path.join(PROJ, "v023_repair/ds_graph/analysis/nonmatrix_ops.json")


def read_scalar(f, e):
    f.seek(e["offset"])
    raw = f.read(e["bytes"])
    if e["dtype"] == "<f4":
        return struct.unpack("<f", raw)[0]
    if e["dtype"] == "<i2":
        return struct.unpack("<h", raw)[0]
    return None


def read_array(f, e):
    f.seek(e["offset"])
    raw = f.read(e["bytes"])
    if e["dtype"] == "<f4":
        return list(struct.unpack("<" + "f" * (len(raw) // 4), raw))
    if e["dtype"] == "<i2":
        return list(struct.unpack("<" + "h" * (len(raw) // 2), raw))
    return []


def stats(xs):
    xs = sorted(x for x in xs if x == x)  # drop NaN
    if not xs:
        return None
    n = len(xs)
    return {
        "n": n,
        "min": xs[0],
        "max": xs[-1],
        "median": xs[n // 2],
        "mean": sum(xs) / n,
    }


def main():
    m = json.load(open(MANIFEST))
    ents = m["directory"]
    f = open(IMAGE, "rb")

    # LayerNorm output quantisation parameters
    ln_scale_ents = [e for e in ents if "LayerNormalization_output_0_scale" in e["name"]]
    ln_zp_ents = [e for e in ents if "LayerNormalization_output_0_zero_point" in e["name"]]
    ln_scales = [read_scalar(f, e) for e in ln_scale_ents]
    ln_zps = [read_scalar(f, e) for e in ln_zp_ents]

    # Actual FP32 LayerNorm gamma/beta arrays
    gamma = []
    beta = []
    seen_beta = set()
    for e in ents:
        nm = e["name"]
        if ("weight_DequantizeLinear_Output/data" in nm and "norm" in nm
                and "conv_module" not in nm):
            gamma.extend(read_array(f, e))
        if (".norm" in nm and nm.endswith(".bias/data")
                and "conv_module" not in nm and nm not in seen_beta):
            seen_beta.add(nm)
            beta.extend(read_array(f, e))

    # Softmax output scales
    sm_scale_ents = [e for e in ents if "Softmax_output_0_scale" in e["name"]]
    sm_scales = [read_scalar(f, e) for e in sm_scale_ents]

    ops = json.load(open(NONMATRIX))
    enc_ops = ops["encoder"]["operators"]
    dec_ops = ops["decoder"]["operators"]

    # Which tensor shapes does LayerNormalization carry?  All LN output scales
    # are per-tensor; the 512-wide gamma/beta arrays show d_model=512.
    ln_shapes = sorted({tuple(e["shape"]) for e in ents
                        if "LayerNormalization_output_0_scale" in e["name"]})

    # Claims in gemini_approx/FINDINGS.md and gemini_epilogue
    claims = {
        "model_family": "KWT-1 keyword transformer (64 features, 99 keywords)",
        "layernorm_features": 64,
        "layernorm_var_range": [1e-6, 1e2],
        "epsilon": 1e-6,
        "softmax_row_length": 99,
    }
    observed = {
        "model_family": "Conformer/Transformer ASR encoder-decoder (ONNX names: "
                        "encoder.encoders.N, decoder.decoders.N, conv_module, "
                        "norm_mha/norm_conv/norm_ff/norm_ff_macaron)",
        "encoder_layers": 12,
        "decoder_layers": 6,
        "d_model": 512,
        "layernorm_instances": len(ln_scale_ents),
        "layernorm_output_scale_stats": stats(ln_scales),
        "layernorm_output_zero_point_stats": stats(ln_zps),
        "layernorm_gamma_stats": stats(gamma),
        "layernorm_beta_stats": stats(beta),
        "layernorm_gamma_nonunit_fraction": (
            sum(1 for x in gamma if abs(x - 1.0) > 1e-6) / len(gamma) if gamma else None),
        "layernorm_beta_nonzero_fraction": (
            sum(1 for x in beta if abs(x) > 1e-9) / len(beta) if beta else None),
        "softmax_count_encoder": enc_ops.get("Softmax"),
        "softmax_count_decoder": dec_ops.get("Softmax"),
        "logsoftmax_count_decoder": dec_ops.get("LogSoftmax"),
        "div_count_encoder": enc_ops.get("Div"),
        "div_count_decoder": dec_ops.get("Div"),
        "layernorm_count_encoder": enc_ops.get("LayerNormalization"),
        "layernorm_count_decoder": dec_ops.get("LayerNormalization"),
        "softmax_output_scale_stats": stats(sm_scales),
        "case0000_frames": 128,
        "case0000_supplied_tokens": 16,
    }
    verdict = {
        "model_family": "REFUTED: the project image is a Conformer/Transformer ASR, not KWT-1",
        "layernorm_features": "REFUTED: 512, not 64",
        "layernorm_var_range": "UNVERIFIED for this model: no ONNX/calibration data in the read-only tree; the [1e-6,1e2] range is a KWT/old-competition assumption",
        "epsilon": "UNVERIFIED for this model: epsilon is not present in the parameter image",
        "softmax_row_length": "REFUTED as a model-wide claim: 24 Softmax ops over time-frame axes; case0000 has 128 frames/16 supplied tokens, not 99 keywords",
    }

    out = {
        "manifest": MANIFEST,
        "image": IMAGE,
        "image_sha256": m.get("image_sha256"),
        "model_hashes": m.get("model_hashes"),
        "claims": claims,
        "observed": observed,
        "verdict": verdict,
        "real_ln_output_scales": ln_scales,
    }
    with open(os.path.join(ROOT, "model_audit.json"), "w") as fh:
        json.dump(out, fh, indent=2)
    with open(os.path.join(ROOT, "ref/real_model_scales.json"), "w") as fh:
        json.dump({"ln_output_scales": ln_scales,
                   "ln_output_zero_points": ln_zps}, fh, indent=2)
    print(json.dumps({"observed": observed, "verdict": verdict}, indent=2))


if __name__ == "__main__":
    main()
