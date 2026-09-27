"""Model A CLI: inspect or execute the full encoder -> decoder chain.

python -B -m host.model_a inspect
python -B -m host.model_a run --backend software --report reports/software.json
Software execution is never labelled RTL verification. The hardware backend
has no arithmetic fallback; communication/operation errors abort execution.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import time
import numpy as np
from .model_manifest import DEFAULT_MODEL_DIR, DEFAULT_CASE_DIR, audit_model_a
from .onnx_executor import OnnxExecutor, SoftwareBackend, ExecutionError


def compare(actual, expected):
    if actual.shape != expected.shape:
        return {"shape_match": False, "actual_shape": list(actual.shape), "expected_shape": list(expected.shape)}
    delta = actual.astype(np.float64) - expected.astype(np.float64)
    rms = float(np.sqrt(np.mean(delta * delta)))
    denom = float(np.sqrt(np.mean(expected.astype(np.float64) ** 2)))
    return {"shape_match": True, "shape": list(actual.shape), "all_finite": bool(np.all(np.isfinite(actual))),
            "bit_exact": bool(np.array_equal(actual.view(np.uint8), expected.view(np.uint8))),
            "max_abs_error": float(np.max(np.abs(delta))), "rms_error": rms,
            "relative_rms_error": rms / denom if denom else None,
            "atol_1e_3_rtol_1e_3_pass": bool(np.allclose(actual, expected, atol=1e-3, rtol=1e-3))}


def run_case(model_dir, case_dir, backend, progress=None, isolated_decoder=False):
    """Execute all layers, feed this run's encoder memory into the decoder."""
    case_dir, model_dir = Path(case_dir), Path(model_dir)
    with np.load(case_dir / "inputs.npz") as inputs:
        feats, tokens = inputs["feats"], inputs["tokens"]
    with np.load(case_dir / "expected.npz") as source:
        expected = {k: source[k] for k in ("encoder_memory", "encoder_memory_lengths", "decoder_log_probs")}
    started = time.perf_counter()
    encoder = OnnxExecutor(model_dir / "encoder.onnx", backend)
    memory = encoder.run({"feats": feats}, progress=progress)
    encoder_stats = encoder.last_stats
    del encoder
    encoder_seconds = time.perf_counter() - started
    decoder = OnnxExecutor(model_dir / "decoder.onnx", backend)
    decoded = decoder.run({"memory": memory["memory"], "tokens": tokens}, progress=progress)
    decoder_stats = decoder.last_stats
    comparisons = {"encoder_memory": compare(memory["memory"], expected["encoder_memory"]),
                   "encoder_memory_lengths": compare(memory["memory_lengths"], expected["encoder_memory_lengths"]),
                   "decoder_log_probs_full_chain": compare(decoded["log_probs"], expected["decoder_log_probs"])}
    if isolated_decoder:
        isolated = decoder.run({"memory": expected["encoder_memory"], "tokens": tokens}, progress=progress)
        comparisons["decoder_log_probs_isolated_reference_memory"] = compare(isolated["log_probs"], expected["decoder_log_probs"])
    hardware = bool(backend.hardware_executed)
    report = {"schema": "asr-model-a-run-v1", "backend": backend.name, "hardware_executed": hardware,
              "rtl_acceptance": "not established by this numerical report",
              "notice": "SOFTWARE REFERENCE ONLY; NOT RTL VALIDATION" if not hardware else "Hardware backend requested; review transport and operator test evidence separately",
              "encoder_layers": 12, "decoder_layers": 6, "model_width": 512, "vocabulary": 5000,
              "ctc_included": False, "model_dir": str(model_dir.resolve()), "case_dir": str(case_dir.resolve()),
              "decoder_uses_actual_encoder_output": True, "feats_shape": list(feats.shape), "tokens_shape": list(tokens.shape),
              "encoder_seconds": encoder_seconds, "total_seconds": time.perf_counter() - started,
              "encoder_execution": encoder_stats, "decoder_execution": decoder_stats,
              "comparison_to_onnx_qdq_vectors": comparisons,
              "numerical_contract": "signed INT16 exact dot -> signed48 -> FP32 -> multiplied input/weight scales; QDQ float-kernel order may differ",
              "pass_claim": False}
    return report, {"encoder_memory": memory["memory"], "encoder_memory_lengths": memory["memory_lengths"], "decoder_log_probs": decoded["log_probs"]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("inspect", "run"))
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    parser.add_argument("--case-dir", type=Path, default=DEFAULT_CASE_DIR)
    parser.add_argument("--backend", choices=("software", "hardware"), default="software")
    parser.add_argument("--port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--output-npz", type=Path)
    parser.add_argument("--isolated-decoder", action="store_true")
    args = parser.parse_args(argv)
    for destination in (args.report, args.output_npz):
        if destination is not None:
            for protected in (args.model_dir.resolve(), args.case_dir.resolve()):
                resolved = destination.resolve()
                if protected == resolved or protected in resolved.parents:
                    raise ExecutionError("refusing to write generated artifacts into original model/vector directories")
    if args.command == "inspect":
        report = audit_model_a(args.model_dir)
    else:
        audit = audit_model_a(args.model_dir)
        if not audit["coverage_pass"]: raise ExecutionError(str(audit["issues"]))
        if args.backend == "software":
            backend = SoftwareBackend()
            print("SOFTWARE REFERENCE ONLY: hardware_executed=false; no RTL acceptance claim", flush=True)
        else:
            if not args.port: parser.error("hardware backend requires --port")
            from .transport import SerialBackend, open_link
            backend = SerialBackend(open_link(args.port, baud=args.baud))
        last = [0.0]
        def progress(current, total, name, op):
            now = time.perf_counter()
            if now - last[0] >= 15 or current == total:
                print(f"[{backend.name}] {current}/{total} {op} {name}", flush=True)
                last[0] = now
        try:
            report, outputs = run_case(args.model_dir, args.case_dir, backend, progress, args.isolated_decoder)
            report["model_manifest"] = audit
            if hasattr(backend, "report"): report["backend_evidence"] = backend.report()
            if args.output_npz:
                args.output_npz.parent.mkdir(parents=True, exist_ok=True)
                np.savez(args.output_npz, **outputs)
        finally:
            if hasattr(backend, "close"): backend.close()
    encoded = json.dumps(report, indent=2, ensure_ascii=False)
    if args.report:
        # Deliberate user-selected generated report, never a source-model write.
        source = args.model_dir.resolve()
        destination = args.report.resolve()
        if source == destination or source in destination.parents:
            raise ExecutionError("refusing to write report into source-model directory")
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
