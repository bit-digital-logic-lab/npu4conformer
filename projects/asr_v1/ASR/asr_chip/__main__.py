"""面向预训练 Model A 的软件命令行，不含训练或 INT8 路径。"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time

from .assets import MODEL_ROOT, ROOT, file_hash, write_json


def _print(value):
    print(json.dumps(value, ensure_ascii=False, indent=2), flush=True)


def doctor(output):
    from .backend import environment_info, verify_model
    result = {"environment": environment_info(), "checks": {}}
    try:
        from espnet2.bin.asr_inference import Speech2Text
        import torch
        result["checks"]["espnet_import"] = "passed"
        if torch.cuda.is_available():
            test = torch.ones((8, 8), device="cuda")
            actual = (test @ test).cpu()
            torch.cuda.synchronize()
            if not bool(torch.all(actual == 8)):
                raise RuntimeError("CUDA 计算自检结果不正确")
            result["checks"]["cuda_matmul"] = "passed"
        else:
            result["checks"]["cuda_matmul"] = "unavailable"
    except Exception as exc:
        result["checks"]["runtime_error"] = f"{type(exc).__name__}: {exc}"
    try:
        result["model_files"] = verify_model()
        result["checks"]["model"] = "passed"
    except Exception as exc:
        result["checks"]["model_error"] = f"{type(exc).__name__}: {exc}"
    result["status"] = "passed" if not any(key.endswith("_error") for key in result["checks"]) else "failed"
    write_json(Path(output), result)
    _print(result)
    return 0 if result["status"] == "passed" else 1


def prepare_manifests(args):
    from .data import build_librispeech_manifest, load_manifest, validate_split_isolation
    prepared = {}
    manifests = {}
    for split in ("dev-clean", "test-clean"):
        target = Path(args.output_dir) / f"{split}.jsonl"
        if target.exists():
            records = load_manifest(target, expected_split=split, verify_hashes=True)
        else:
            records = build_librispeech_manifest(Path(args.data_root), target, split=split)
        manifests[split] = records
        prepared[split] = {"manifest": str(target.resolve()), "utterances": len(records),
                           "audio_seconds": sum(r.duration_seconds for r in records),
                           "sha256": file_hash(target)}
    validate_split_isolation(manifests)
    write_json(Path(args.output_dir) / "manifest_summary.json", prepared)
    _print(prepared)


def quantize(args):
    from .backend import Recognizer, read_config, CHECKPOINT_SHA256
    from .quantization import build_int16_artifact, save_int16_artifact
    recognizer = Recognizer(read_config(args.config), model_root=Path(args.model_root))
    try:
        # 以真实加载并转换为 FP32 的推理 state 为准，避免原文件 MVN buffer dtype 差异。
        artifact = build_int16_artifact(recognizer.decoder.asr_model.float().state_dict(),
                                       base_sha256=CHECKPOINT_SHA256,
                                       model_id="pyf98/librispeech_conformer")
        report = save_int16_artifact(artifact, Path(args.output))
    finally:
        recognizer.close()
    sidecar = Path(args.output).with_suffix(".report.json")
    write_json(sidecar, report)
    _print({"artifact": str(Path(args.output).resolve()), "report": str(sidecar.resolve()),
            "execution": "INT16 weight storage; dequantized FP32 computation; activations not quantized",
            "artifact_sha256": file_hash(Path(args.output))})


def transcribe(args):
    from .backend import Recognizer, read_config
    from .data import load_audio
    config = read_config(args.config)
    recognizer = Recognizer(config, model_root=Path(args.model_root), precision=args.precision,
                            artifact=Path(args.artifact) if args.artifact else None)
    try:
        recognizer.synchronize()
        start = time.perf_counter()
        audio = load_audio(Path(args.audio), sample_rate=config["sample_rate"])
        text = recognizer.transcribe(audio)
        recognizer.synchronize()
        elapsed = time.perf_counter() - start
        result = {"audio": str(Path(args.audio).resolve()), "text": text, "precision": args.precision,
                  "compute_dtype": "float32", "device": recognizer.device,
                  "audio_seconds": len(audio) / config["sample_rate"],
                  "processing_seconds": elapsed,
                  "rtf": elapsed / (len(audio) / config["sample_rate"]),
                  "model_load_seconds": recognizer.load_seconds,
                  "timing_note": "This is a single cold/first utterance, not a corpus real-time certification."}
        if args.output:
            write_json(Path(args.output), result)
        _print(result)
    finally:
        recognizer.close()


def validate_reload(args):
    import torch
    from .backend import Recognizer, read_config
    from .data import load_audio
    config = read_config(args.config)
    audio = load_audio(Path(args.audio), sample_rate=config["sample_rate"])
    results = []
    for _ in range(2):
        recognizer = Recognizer(config, model_root=Path(args.model_root), precision=args.precision,
                                artifact=Path(args.artifact) if args.artifact else None)
        try:
            results.append((recognizer.transcribe(audio), recognizer.ctc_logits(audio)))
        finally:
            recognizer.close()
    left, right = results
    same_shape = left[1].shape == right[1].shape
    finite = bool(torch.isfinite(left[1]).all() and torch.isfinite(right[1]).all())
    close = same_shape and finite and torch.allclose(left[1], right[1], atol=1e-6, rtol=1e-5)
    report = {"precision": args.precision, "source_audio": str(Path(args.audio).resolve()),
              "text_first": left[0], "text_reloaded": right[0], "text_equal": left[0] == right[0],
              "logit_shape": list(left[1].shape), "logits_finite": finite,
              "logits_exact": bool(same_shape and torch.equal(left[1], right[1])),
              "max_abs_logit_error": float((left[1] - right[1]).abs().max()) if same_shape and finite else None,
              "atol": 1e-6, "rtol": 1e-5,
              "status": "passed" if left[0] == right[0] and close else "failed"}
    write_json(Path(args.output), report)
    _print(report)
    return 0 if report["status"] == "passed" else 1


def main():
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("doctor", help="检查当前环境、GPU 与模型完整性")
    check.add_argument("--output", default=str(ROOT / "results/asr_chip/environment.json"))
    prepare = commands.add_parser("prepare-data", help="从已下载的标准数据创建固定清单")
    prepare.add_argument("--data-root", default=str(ROOT / "data/LibriSpeech"))
    prepare.add_argument("--output-dir", default=str(ROOT / "data/manifests"))
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--config", type=Path, default=ROOT / "configs/asr_chip_baseline.json")
    common.add_argument("--model-root", default=str(MODEL_ROOT))
    quant = commands.add_parser("quantize", parents=[common], help="导出 INT16 权重及保留的浮点状态")
    quant.add_argument("--output", default=str(ROOT / "artifacts/model_a_int16.pth"))
    infer = commands.add_parser("transcribe", parents=[common], help="识别一条完整16kHz单声道音频")
    infer.add_argument("--audio", required=True)
    infer.add_argument("--precision", choices=["fp32", "int16"], default="fp32")
    infer.add_argument("--artifact")
    infer.add_argument("--output")
    evaluate = commands.add_parser("evaluate", parents=[common], help="开发集批量评估；正式测试使用freeze/compare")
    evaluate.add_argument("--manifest", required=True, type=Path)
    evaluate.add_argument("--output-dir", required=True, type=Path)
    evaluate.add_argument("--precision", choices=["fp32", "int16"], default="fp32")
    evaluate.add_argument("--artifact", type=Path)
    evaluate.add_argument("--limit", type=int)
    evaluate.add_argument("--warmup-audio", type=Path)
    reload = commands.add_parser("validate-reload", parents=[common], help="比较两次独立加载后的转录与CTC logits")
    reload.add_argument("--audio", required=True)
    reload.add_argument("--precision", choices=["fp32", "int16"], default="fp32")
    reload.add_argument("--artifact")
    reload.add_argument("--output", required=True)
    freeze = commands.add_parser("freeze-comparison", help="冻结最终测试数据和FP32/INT16对比配置")
    freeze.add_argument("--config", type=Path, default=ROOT / "configs/asr_chip_baseline.json")
    freeze.add_argument("--dev-manifest", type=Path, default=ROOT / "data/manifests/dev-clean.jsonl")
    freeze.add_argument("--test-manifest", type=Path, default=ROOT / "data/manifests/test-clean.jsonl")
    freeze.add_argument("--artifact", required=True, type=Path)
    freeze.add_argument("--output", required=True, type=Path)
    compare = commands.add_parser("compare", help="按冻结协议进行完整test-clean对照")
    compare.add_argument("--protocol", required=True, type=Path)
    compare.add_argument("--output-dir", required=True, type=Path)
    vectors = commands.add_parser("check-vectors", parents=[common], help="验证random200随机特征；不计算WER")
    vectors.add_argument("--dataset", required=True, type=Path)
    vectors.add_argument("--artifact", required=True, type=Path)
    vectors.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "doctor":
        return doctor(args.output)
    if args.command == "prepare-data":
        prepare_manifests(args)
    elif args.command == "quantize":
        quantize(args)
    elif args.command == "transcribe":
        transcribe(args)
    elif args.command == "validate-reload":
        return validate_reload(args)
    elif args.command == "evaluate":
        from .backend import read_config
        from .evaluation import evaluate_manifest
        _print(evaluate_manifest(read_config(args.config), args.manifest, args.output_dir,
                                 precision=args.precision, artifact=args.artifact,
                                 model_root=Path(args.model_root), limit=args.limit,
                                 warmup_audio=args.warmup_audio))
    elif args.command == "freeze-comparison":
        from .evaluation import freeze_protocol
        _print(freeze_protocol(args.config, args.dev_manifest, args.test_manifest, args.artifact, args.output))
    elif args.command == "check-vectors":
        from .vector_evaluation import run_vectors
        _print(run_vectors(args.dataset, args.output_dir, config_path=args.config,
                           artifact_path=args.artifact, model_root=args.model_root))
    elif args.command == "compare":
        from .evaluation import compare_protocol
        _print(compare_protocol(args.protocol, args.output_dir))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, FileNotFoundError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

