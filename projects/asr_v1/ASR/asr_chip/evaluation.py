"""整句 ASR 评估、协议冻结与 FP32/INT16 权重存储对比。

test 清单只能由冻结协议的 compare_protocol 入口完整运行；开发集允许
显式 limit。第一版明确拒绝 resume，避免把不同协议的旧输出混入结果。
所有时间均是软件运行时间，不代表 FPGA/ASIC 功耗、面积或频率。
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
from typing import Any

from asr_chip.assets import MODEL_ID, MODEL_FILES, MODEL_ROOT
from asr_chip.backend import (
    CHECKPOINT_SHA256, Recognizer, _validate_config, environment_info, read_config,
)
from asr_chip.data import AudioRecord, file_sha256, load_audio, load_manifest, validate_split_isolation
from asr_chip.metrics import compute_wer


NORMALIZATION = {"lowercase": True, "remove_punctuation": False}
PROTOCOL_FORMAT = "software4npu.asr_fp32_int16_comparison"
TIMING_DEFINITION = {
    "per_utterance_seconds": "GPU synchronize before clock; audio file read + preprocessing + model + complete beam decode + GPU synchronize before stop",
    "rtf": "sum(per_utterance_seconds) / sum(audio_duration_seconds); ratio, not utterance-average",
    "steady_state_rtf": "same ratio excluding the first measured utterance; null when fewer than two utterances",
    "excluded": ["model construction and weight loading", "manifest/audio hash preflight", "warmup", "WER computation", "JSON output"],
    "first_utterance": "first measured utterance; separate warmup is recorded when used",
    "cache_note": "audio hash preflight may warm the operating-system file cache; this is recorded software throughput, not cold-disk performance",
    "hardware_claim": "none; no FPGA/ASIC measurement",
}


class EvaluationError(RuntimeError):
    """评估中断；已完成项与失败原因保留在新输出目录。"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _json_hash(value: Any) -> str:
    return hashlib.sha256(_json_bytes(value)).hexdigest()


def _write_new_json(path: Path, value: Any) -> None:
    """原子创建新 JSON；既有记录永不静默覆盖。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False).encode("utf-8") + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _config(config: Mapping[str, Any] | str | Path) -> tuple[dict, str | None]:
    if isinstance(config, (str, Path)):
        path = Path(config).resolve()
        return read_config(path), file_sha256(path)
    return _validate_config(dict(config)), None


def _split(records: list[AudioRecord]) -> str:
    splits = {record.split for record in records}
    if len(splits) != 1:
        raise ValueError("一次评估必须只有一个 split")
    return next(iter(splits))


def _snapshot(records: list[AudioRecord]) -> list[dict]:
    return [{
        "utt_id": item.utt_id, "audio_path": str(item.audio_path), "text": item.text,
        "split": item.split, "speaker_id": item.speaker_id,
        "duration_seconds": item.duration_seconds,
        "sha256": item.sha256 if item.sha256 is not None else file_sha256(item.audio_path),
    } for item in records]


def _implementation_hashes() -> dict[str, str]:
    root = Path(__file__).resolve().parent
    hashes = {name: file_sha256(root / name) for name in ("evaluation.py", "backend.py", "data.py", "metrics.py", "quantization.py")}
    # 网络源码现在可在工程内编辑，冻结协议必须同时记录它，避免改网络后复用旧协议。
    source = root.parent / "third_party/espnet"
    digest = hashlib.sha256()
    for package in ("espnet2", "espnet3"):
        paths = sorted((source / package).rglob("*.py"))
        if not paths:
            raise FileNotFoundError(f"Missing editable ESPnet package: {source / package}")
        for path in paths:
            digest.update(path.relative_to(source).as_posix().encode("utf-8") + b"\0")
            digest.update(file_sha256(path).encode("ascii") + b"\n")
    hashes["editable_espnet_source_tree"] = digest.hexdigest()
    return hashes


def _reject_resume(resume: bool) -> None:
    if resume:
        raise NotImplementedError("本版本不支持 resume；请保留原输出并使用新的目录完整重跑")


def _artifact_identity(path: str | Path) -> dict:
    from asr_chip.quantization import load_int16_artifact
    location = Path(path).resolve()
    checksum = file_sha256(location)
    artifact = load_int16_artifact(location, expected_base_sha256=CHECKPOINT_SHA256)
    if artifact["model_id"] != MODEL_ID:
        raise ValueError("INT16 artifact model_id 与固定 Model A 不一致")
    return {
        "path": str(location), "sha256": checksum, "file_bytes": location.stat().st_size,
        "base_sha256": artifact["base_sha256"], "manifest_sha256": artifact["manifest_sha256"],
        "format": artifact["format"], "format_version": artifact["format_version"],
        "inference": artifact["inference"],
    }


def _timing(rows: list[dict]) -> dict:
    elapsed = sum(item["elapsed_seconds"] for item in rows)
    duration = sum(item["duration_seconds"] for item in rows)
    tail_elapsed = sum(item["elapsed_seconds"] for item in rows[1:])
    tail_duration = sum(item["duration_seconds"] for item in rows[1:])
    return {
        "total_audio_seconds": duration, "total_inference_seconds": elapsed,
        "rtf": elapsed / duration if duration else None,
        "first_utterance_seconds": rows[0]["elapsed_seconds"] if rows else None,
        "steady_state_rtf": tail_elapsed / tail_duration if tail_duration else None,
        "steady_state_utterances": max(0, len(rows) - 1),
    }


def evaluate_manifest(
    config: Mapping[str, Any] | str | Path, manifest_path: str | Path, output_dir: str | Path,
    *, precision: str = "fp32", artifact: str | Path | None = None,
    model_root: str | Path = MODEL_ROOT, limit: int | None = None,
    warmup_audio: str | Path | None = None, resume: bool = False,
) -> dict:
    """开发集整句评估；正式 test 请先 freeze_protocol，再 compare_protocol。"""
    return _evaluate(config, manifest_path, output_dir, precision=precision, artifact=artifact,
                     model_root=model_root, limit=limit, warmup_audio=warmup_audio,
                     resume=resume, frozen_protocol=None)


def _evaluate(
    config, manifest_path, output_dir, *, precision, artifact, model_root, limit,
    warmup_audio, resume, frozen_protocol,
) -> dict:
    _reject_resume(resume)
    if precision not in ("fp32", "int16") or ((precision == "int16") != (artifact is not None)):
        raise ValueError("precision 仅支持 fp32/int16，且只有 int16 必须提供 artifact")
    settings, config_file_hash = _config(config)
    manifest = Path(manifest_path).resolve()
    records = load_manifest(manifest, verify_hashes=True)
    split = _split(records)
    is_dev, is_test = split == "dev-clean", split == "test-clean"
    if not (is_dev or is_test):
        raise ValueError("本轮只接受 dev-clean 或 test-clean 清单")
    if is_test and frozen_protocol is None:
        raise ValueError("test 评估必须先冻结协议，并通过 compare_protocol 完整执行")
    if limit is not None:
        if not is_dev:
            raise ValueError("test 禁止 limit/抽样")
        if type(limit) is not int or limit <= 0:
            raise ValueError("limit 必须为正整数")
    all_count = len(records)
    if limit is not None:
        records = records[:limit]
    artifact_path = Path(artifact).resolve() if artifact is not None else None
    artifact_hash = file_sha256(artifact_path) if artifact_path is not None else None
    if frozen_protocol is not None:
        if _json_hash(settings) != frozen_protocol["config_canonical_sha256"]:
            raise ValueError("配置与冻结协议不一致")
        if file_sha256(manifest) != frozen_protocol["test"]["manifest_sha256"]:
            raise ValueError("test manifest 与冻结协议不一致")
        if _snapshot(records) != frozen_protocol["test"]["records"]:
            raise ValueError("test 音频/顺序/参考文本与冻结协议不一致")
        if precision == "int16" and artifact_hash != frozen_protocol["artifact"]["sha256"]:
            raise ValueError("INT16 artifact 与冻结协议不一致")
    warmup = Path(warmup_audio).resolve() if warmup_audio is not None else None
    warmup_hash = file_sha256(warmup) if warmup is not None else None
    destination = Path(output_dir).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    identity = {
        "schema_version": 1, "created_utc": _now(), "precision": precision,
        "inference_arithmetic": "fp32", "integer_inference": False,
        "config": settings, "config_canonical_sha256": _json_hash(settings),
        "config_file_sha256": config_file_hash,
        "manifest_path": str(manifest), "manifest_sha256": file_sha256(manifest),
        "split": split, "manifest_utterance_count": all_count, "requested_utterance_count": len(records),
        "limit": limit, "dataset_coverage": "complete frozen/requested manifest, not proof of the complete official split",
        "artifact_path": str(artifact_path) if artifact_path else None,
        "artifact_sha256": artifact_hash, "base_sha256": CHECKPOINT_SHA256,
        "model_root": str(Path(model_root).resolve()), "expected_model_hashes": dict(MODEL_FILES),
        "normalization": dict(NORMALIZATION), "timing_definition": dict(TIMING_DEFINITION),
        "warmup_audio": str(warmup) if warmup else None, "warmup_sha256": warmup_hash,
        "protocol_sha256": frozen_protocol["protocol_sha256"] if frozen_protocol else None,
        "implementation_sha256": _implementation_hashes(), "environment": environment_info(),
        "records": _snapshot(records),
    }
    _write_new_json(destination / "request.json", identity)
    recognizer = None
    rows: list[dict] = []
    model_load_seconds = None
    warmup_seconds = None
    current = None
    started = None
    try:
        constructor_started = time.perf_counter()
        recognizer = Recognizer(settings, model_root=Path(model_root), precision=precision, artifact=artifact_path)
        recognizer.synchronize()
        model_load_seconds = time.perf_counter() - constructor_started
        if warmup is not None:
            recognizer.synchronize()
            warmup_started = time.perf_counter()
            waveform = load_audio(warmup, sample_rate=settings["sample_rate"])
            recognizer.transcribe(waveform)
            recognizer.synchronize()
            warmup_seconds = time.perf_counter() - warmup_started
        with (destination / "utterances.jsonl").open("x", encoding="utf-8", newline="\n") as stream:
            for index, current in enumerate(records):
                recognizer.synchronize()
                started = time.perf_counter()
                waveform = load_audio(current, sample_rate=settings["sample_rate"])
                hypothesis = recognizer.transcribe(waveform)
                recognizer.synchronize()
                elapsed = time.perf_counter() - started
                counts = compute_wer([current.text], [hypothesis], **NORMALIZATION)["per_utterance"][0]
                row = {
                    "index": index, "utt_id": current.utt_id, "audio_path": str(current.audio_path),
                    "audio_sha256": current.sha256, "split": current.split, "speaker_id": current.speaker_id,
                    "reference_raw": current.text, "hypothesis_raw": hypothesis,
                    **{key: value for key, value in counts.items() if key != "index"},
                    "duration_seconds": current.duration_seconds, "elapsed_seconds": elapsed,
                    "rtf": elapsed / current.duration_seconds, "status": "complete",
                    "precision": precision,
                }
                stream.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")
                stream.flush()
                rows.append(row)
                print(f"EVAL {precision} {index + 1}/{len(records)} {current.utt_id} {elapsed:.3f}s", flush=True)
        totals = compute_wer([item["reference_raw"] for item in rows], [item["hypothesis_raw"] for item in rows], **NORMALIZATION)
        totals.pop("per_utterance")
        summary = {
            **identity, "status": "complete", "completed_utc": _now(), "completed_utterance_count": len(rows),
            "resolved_device": recognizer.device, "verified_model_hashes": recognizer.model_hashes,
            "model_load_seconds": model_load_seconds, "backend_load_seconds": recognizer.load_seconds,
            "warmup_seconds": warmup_seconds, "timing": _timing(rows), "metrics": totals,
            "quantization_report": recognizer.quantization_report,
            "output_dir": str(destination), "recognition_threshold": None,
            "decision": "report_only; no accuracy threshold; no test-based model selection",
        }
        _write_new_json(destination / "summary.json", summary)
        return summary
    except Exception as error:
        # 当前句失败时保留明确失败行；没有假设文本就不伪造 S/D/I/N 或 WER。
        if current is not None and len(rows) < len(records):
            failed_row = {
                "index": len(rows), "utt_id": current.utt_id, "audio_path": str(current.audio_path),
                "audio_sha256": current.sha256, "reference_raw": current.text,
                "hypothesis_raw": None, "status": "failed", "precision": precision,
                "error_type": type(error).__name__, "error": str(error), "metrics": None,
                "elapsed_seconds_until_failure": time.perf_counter() - started if started is not None else None,
            }
            with (destination / "utterances.jsonl").open("a", encoding="utf-8", newline="\n") as stream:
                stream.write(json.dumps(failed_row, ensure_ascii=False, allow_nan=False) + "\n")
        failure = {
            **identity, "status": "failed", "failed_utc": _now(), "completed_utterance_count": len(rows),
            "failed_utt_id": current.utt_id if current is not None else None,
            "failed_reference": current.text if current is not None else None,
            "error_type": type(error).__name__, "error": str(error),
            "model_load_seconds": model_load_seconds, "warmup_seconds": warmup_seconds,
            "partial_timing": _timing(rows), "metrics": None,
            "output_dir": str(destination), "message": "评估失败，没有跳过样本，也没有最终 WER",
        }
        _write_new_json(destination / "summary.json", failure)
        raise EvaluationError(f"评估中断，失败记录保存在 {destination / 'summary.json'}: {error}") from error
    finally:
        if recognizer is not None:
            recognizer.close()


def freeze_protocol(
    config_path: str | Path, dev_manifest: str | Path, test_manifest: str | Path,
    artifact: str | Path, output_path: str | Path,
) -> dict:
    """测试前冻结固定方案；校验 dev/test 内容隔离，不使用 test 选择配置。"""
    config_location = Path(config_path).resolve()
    settings = read_config(config_location)
    dev_path, test_path = Path(dev_manifest).resolve(), Path(test_manifest).resolve()
    dev = load_manifest(dev_path, verify_hashes=True)
    test = load_manifest(test_path, verify_hashes=True)
    dev_split, test_split = _split(dev), _split(test)
    if dev_split != "dev-clean" or test_split != "test-clean":
        raise ValueError("freeze_protocol 必须分别提供 dev 和 test 清单")
    validate_split_isolation({dev_split: dev, test_split: test}, verify_content=True)
    protocol = {
        "format": PROTOCOL_FORMAT, "schema_version": 1, "created_utc": _now(),
        "config_path": str(config_location), "config": settings,
        "config_file_sha256": file_sha256(config_location), "config_canonical_sha256": _json_hash(settings),
        "dev": {"manifest_path": str(dev_path), "manifest_sha256": file_sha256(dev_path), "records": _snapshot(dev)},
        "test": {"manifest_path": str(test_path), "manifest_sha256": file_sha256(test_path), "records": _snapshot(test)},
        "artifact": _artifact_identity(artifact), "base_sha256": CHECKPOINT_SHA256,
        "expected_model_hashes": dict(MODEL_FILES), "model_root": str(MODEL_ROOT.resolve()),
        "normalization": dict(NORMALIZATION), "timing_definition": dict(TIMING_DEFINITION),
        "implementation_sha256": _implementation_hashes(),
        "warmup": {"audio_path": str(dev[0].audio_path), "sha256": dev[0].sha256, "source": "first frozen dev utterance, not included in test WER"},
        "precision_order": ["fp32", "int16"], "test_limit": None,
        "training": False, "int8": False, "recognition_threshold": None,
        "selection_rule": "configuration fixed before test; test is final reporting only; no checkpoint/configuration selection",
    }
    protocol["protocol_sha256"] = _json_hash(protocol)
    _write_new_json(Path(output_path).resolve(), protocol)
    return protocol


def _read_protocol(path: str | Path) -> dict:
    protocol = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(protocol, dict) or protocol.get("format") != PROTOCOL_FORMAT or protocol.get("schema_version") != 1:
        raise ValueError("不支持的评估协议格式")
    payload = {key: value for key, value in protocol.items() if key != "protocol_sha256"}
    if _json_hash(payload) != protocol.get("protocol_sha256"):
        raise ValueError("评估协议 SHA-256 不匹配")
    if protocol["precision_order"] != ["fp32", "int16"] or protocol["test_limit"] is not None:
        raise ValueError("冻结协议必须完整比较 FP32 与 INT16，禁止 test 抽样")
    if protocol["training"] is not False or protocol["int8"] is not False or protocol["recognition_threshold"] is not None:
        raise ValueError("协议超出本轮无训练、无 INT8、无精度阈值的范围")
    if protocol["normalization"] != NORMALIZATION or protocol["timing_definition"] != TIMING_DEFINITION:
        raise ValueError("归一化或计时规则与冻结协议不同")
    if protocol["implementation_sha256"] != _implementation_hashes():
        raise ValueError("评估代码在冻结后改变，请先在 dev 上复核再冻结新协议")
    if protocol["base_sha256"] != CHECKPOINT_SHA256 or protocol["expected_model_hashes"] != MODEL_FILES:
        raise ValueError("固定模型身份与协议不一致")
    if file_sha256(protocol["config_path"]) != protocol["config_file_sha256"]:
        raise ValueError("冻结后的配置文件发生变化")
    if read_config(Path(protocol["config_path"])) != protocol["config"] or _json_hash(protocol["config"]) != protocol["config_canonical_sha256"]:
        raise ValueError("冻结后的配置内容发生变化")
    split_records = {}
    for role in ("dev", "test"):
        section = protocol[role]
        if file_sha256(section["manifest_path"]) != section["manifest_sha256"]:
            raise ValueError(f"冻结后的 {role} manifest 发生变化")
        records = load_manifest(section["manifest_path"], verify_hashes=True)
        if _split(records) != role + "-clean" or _snapshot(records) != section["records"]:
            raise ValueError(f"冻结后的 {role} 音频/参考文本/顺序发生变化")
        split_records[_split(records)] = records
    validate_split_isolation(split_records, verify_content=True)
    if _artifact_identity(protocol["artifact"]["path"]) != protocol["artifact"]:
        raise ValueError("冻结后的 INT16 artifact 发生变化")
    if file_sha256(protocol["warmup"]["audio_path"]) != protocol["warmup"]["sha256"]:
        raise ValueError("冻结后的 warmup 音频发生变化")
    return protocol


def compare_protocol(protocol_path: str | Path, output_dir: str | Path, *, resume: bool = False) -> dict:
    """同一冻结 test 清单完整比较；只报告差异，不依据测试结果挑选方案。"""
    _reject_resume(resume)
    protocol = _read_protocol(protocol_path)
    destination = Path(output_dir).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    _write_new_json(destination / "protocol.json", protocol)
    results = {}
    try:
        for precision in protocol["precision_order"]:
            # 每个版本开始前再次复核配置、清单与模型包，避免中途修改。
            _read_protocol(protocol_path)
            results[precision] = _evaluate(
                protocol["config"], protocol["test"]["manifest_path"], destination / precision,
                precision=precision, artifact=protocol["artifact"]["path"] if precision == "int16" else None,
                model_root=protocol["model_root"], limit=None, warmup_audio=protocol["warmup"]["audio_path"],
                resume=False, frozen_protocol=protocol,
            )
        _read_protocol(protocol_path)
        if results["fp32"]["environment"] != results["int16"]["environment"]:
            raise EvaluationError("两版本运行环境不同，不能作为同条件对比")
        if results["fp32"]["resolved_device"] != results["int16"]["resolved_device"]:
            raise EvaluationError("两版本实际运行设备不同，不能作为同条件对比")
        baseline, quantized = results["fp32"]["metrics"]["wer"], results["int16"]["metrics"]["wer"]
        report = {
            "schema_version": 1, "status": "complete", "completed_utc": _now(),
            "protocol_path": str(Path(protocol_path).resolve()), "protocol_sha256": protocol["protocol_sha256"],
            "test_manifest_sha256": protocol["test"]["manifest_sha256"],
            "test_utterance_count": len(protocol["test"]["records"]),
            "dataset_coverage": "complete frozen manifest; official split completeness is a separate dataset-preparation check",
            "environment_matched": True,
            "normalization": dict(NORMALIZATION), "decoding": protocol["config"]["decoding"],
            "resolved_device": results["fp32"]["resolved_device"],
            "fp32": {"metrics": results["fp32"]["metrics"], "timing": results["fp32"]["timing"], "model_load_seconds": results["fp32"]["model_load_seconds"]},
            "int16": {"metrics": results["int16"]["metrics"], "timing": results["int16"]["timing"], "model_load_seconds": results["int16"]["model_load_seconds"], "quantization_report": results["int16"]["quantization_report"]},
            "wer_difference_percentage_points": 100.0 * (quantized - baseline),
            "wer_relative_change": (quantized - baseline) / baseline if baseline else None,
            "relative_change_zero_baseline_rule": "null when FP32 WER is zero; absolute pp difference remains defined",
            "recognition_threshold": None, "decision": "report_only; no test-based selection",
            "integer_inference": False, "hardware_measurement": False,
            "note": "both versions execute FP32 operators; INT16 changes weight storage and dequantized values only; measured RTF is software timing",
        }
        _write_new_json(destination / "comparison.json", report)
        return report
    except Exception as error:
        _write_new_json(destination / "comparison_failed.json", {
            "status": "failed", "protocol_sha256": protocol["protocol_sha256"],
            "completed_precisions": list(results), "error_type": type(error).__name__, "error": str(error),
            "decision": "no final comparison; existing partial outputs retained",
        })
        raise
