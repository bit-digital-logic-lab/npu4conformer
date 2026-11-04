"""可复现的 LibriSpeech 清单与完整音频输入。

JSONL 中 audio_path 相对于清单所在目录；加载后统一返回绝对 Path。
清单操作仅依赖标准库，读取 FLAC/WAV 元数据或波形时才导入 soundfile。
本模块不截断音频、不重采样、不混合声道，避免静默改变参考实验。
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
from typing import Mapping, Sequence


SCHEMA_FIELDS = {
    "utt_id", "audio_path", "text", "split", "speaker_id", "duration_seconds", "sha256"
}
REQUIRED_FIELDS = SCHEMA_FIELDS - {"sha256"}
SAMPLE_RATE = 16000


@dataclass(frozen=True)
class AudioRecord:
    """一条音频及其完整转录；audio_path 在加载后为绝对路径。"""

    utt_id: str
    audio_path: Path
    text: str
    split: str
    speaker_id: str
    duration_seconds: float
    sha256: str | None = None


def file_sha256(path: str | Path) -> str:
    """流式读取文件，避免把整套音频载入内存。"""
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _soundfile():
    try:
        import soundfile
    except ImportError as exc:
        raise RuntimeError(
            "读取音频需要 soundfile；请先在 ASR 环境安装工程依赖。"
        ) from exc
    return soundfile


def _validate_record(record: AudioRecord) -> None:
    for name in ("utt_id", "split", "speaker_id"):
        value = getattr(record, name)
        if not isinstance(value, str) or not value.strip() or any(c.isspace() for c in value):
            raise ValueError(f"{name} 必须是不含空白的非空字符串")
    if not isinstance(record.text, str) or "\n" in record.text or "\r" in record.text:
        raise ValueError("text 必须是单行字符串；静音样本可使用空字符串")
    duration = record.duration_seconds
    if isinstance(duration, bool) or not isinstance(duration, (int, float)):
        raise ValueError("duration_seconds 必须是数值")
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("duration_seconds 必须是有限正数")
    if record.sha256 is not None:
        if not isinstance(record.sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", record.sha256):
            raise ValueError("sha256 必须是 64 位小写十六进制字符串")


def _check_unique(records: Sequence[AudioRecord]) -> None:
    ids: dict[str, AudioRecord] = {}
    paths: dict[str, AudioRecord] = {}
    hashes: dict[str, AudioRecord] = {}
    for record in records:
        _validate_record(record)
        key = os.path.normcase(str(Path(record.audio_path).resolve()))
        if record.utt_id in ids:
            raise ValueError(f"重复 utt_id: {record.utt_id}")
        if key in paths:
            raise ValueError(f"重复音频路径: {record.audio_path}")
        if record.sha256 is not None and record.sha256 in hashes:
            raise ValueError(f"重复音频内容 SHA-256: {record.utt_id}")
        ids[record.utt_id] = record
        paths[key] = record
        if record.sha256 is not None:
            hashes[record.sha256] = record


def load_manifest(
    path: str | Path,
    *,
    expected_split: str | None = None,
    check_files: bool = True,
    verify_hashes: bool = False,
) -> list[AudioRecord]:
    """加载 JSONL 并拒绝重复 ID、路径和已声明的重复文件内容。

    verify_hashes=True 会重新计算所有文件的哈希，校验声明并检测未声明的
    重复内容。跨清单隔离另用 validate_split_isolation()，其默认复核内容。
    """
    manifest_path = Path(path).resolve()
    records: list[AudioRecord] = []
    with manifest_path.open("r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                raw = json.loads(line)
                if not isinstance(raw, dict):
                    raise ValueError("每行必须是 JSON 对象")
                missing, unknown = REQUIRED_FIELDS - raw.keys(), raw.keys() - SCHEMA_FIELDS
                if missing or unknown:
                    raise ValueError(f"清单字段不匹配：missing={sorted(missing)}, unknown={sorted(unknown)}")
                if not isinstance(raw["audio_path"], str) or not raw["audio_path"].strip():
                    raise ValueError("audio_path 必须是非空字符串")
                audio_path = Path(raw["audio_path"])
                audio_path = (manifest_path.parent / audio_path).resolve()
                checksum = raw.get("sha256")
                record = AudioRecord(
                    utt_id=raw["utt_id"], audio_path=audio_path, text=raw["text"],
                    split=raw["split"], speaker_id=raw["speaker_id"],
                    duration_seconds=raw["duration_seconds"], sha256=checksum,
                )
                _validate_record(record)
                if expected_split is not None and record.split != expected_split:
                    raise ValueError(f"split={record.split!r}，预期 {expected_split!r}")
                if check_files or verify_hashes:
                    if not audio_path.is_file():
                        raise FileNotFoundError(f"音频不存在: {audio_path}")
                if verify_hashes:
                    actual = file_sha256(audio_path)
                    if checksum is not None and checksum != actual:
                        raise ValueError(f"音频 SHA-256 不匹配: {audio_path}")
                    record = AudioRecord(**{**record.__dict__, "sha256": actual})
                records.append(record)
            except (ValueError, TypeError, KeyError, OSError) as exc:
                raise ValueError(f"{manifest_path}:{number}: {exc}") from exc
    if not records:
        raise ValueError(f"清单为空: {manifest_path}")
    _check_unique(records)
    return records


def validate_split_isolation(
    manifests: Mapping[str, Sequence[AudioRecord]],
    *,
    verify_content: bool = True,
) -> None:
    """检查所有清单的 ID、实际文件和文件内容均不重叠。

    键为 split，值为该 split 的记录。默认读取文件验证 SHA-256，即使复制
    到其他路径、修改 ID，也能检测同一文件内容。verify_content=False 只
    用声明的哈希做快速检查，不代表完成内容隔离审计。不同编码但波形等价
    的音频不由文件哈希识别，需要数据集来源审计或另行做波形去重。
    """
    if not manifests:
        raise ValueError("至少提供一个 split")
    all_records: list[AudioRecord] = []
    for split, records in manifests.items():
        if not records:
            raise ValueError(f"split 为空: {split}")
        for record in records:
            _validate_record(record)
            if record.split != split:
                raise ValueError(f"{record.utt_id}: split={record.split!r} 与分组 {split!r} 不符")
            checksum = record.sha256
            if verify_content:
                actual = file_sha256(record.audio_path)
                if checksum is not None and checksum != actual:
                    raise ValueError(f"音频 SHA-256 不匹配: {record.audio_path}")
                checksum = actual
            all_records.append(AudioRecord(**{**record.__dict__, "sha256": checksum}))
    _check_unique(all_records)


def build_librispeech_manifest(
    data_root: str | Path,
    output_path: str | Path,
    *,
    split: str,
    include_sha256: bool = True,
    overwrite: bool = False,
) -> list[AudioRecord]:
    """从 LibriSpeech/<split>/<speaker>/<chapter> 构建稳定排序的 JSONL。

    data_root 可以是 LibriSpeech 根目录或名字等于 split 的子目录。
    保留完整标签及完整音频，严格检查 16 kHz 单声道和缺失的 FLAC。
    只有全部检查成功后才写清单；默认拒绝覆盖已有文件。
    """
    root = Path(data_root).resolve()
    destination = Path(output_path).resolve()
    if destination.exists() and not overwrite:
        raise FileExistsError(f"清单已存在，拒绝覆盖: {destination}")
    if (root / split).is_dir():
        split_root = root / split
    elif root.is_dir() and root.name == split:
        split_root = root
    else:
        raise FileNotFoundError(f"找不到 LibriSpeech split {split!r}: {root}")
    transcripts = sorted(split_root.glob("*/*/*.trans.txt"))
    if not transcripts:
        raise FileNotFoundError(f"找不到 *.trans.txt: {split_root}")
    sf = _soundfile()
    records: list[AudioRecord] = []
    for transcript in transcripts:
        for number, line in enumerate(transcript.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            fields = line.split(maxsplit=1)
            if len(fields) != 2 or not fields[1].strip():
                raise ValueError(f"{transcript}:{number}: 转录行必须包含 ID 和文本")
            utt_id, text = fields
            # 禁止 ID 带路径，使转录只能引用本章内的音频。
            if not re.fullmatch(r"\d+-\d+-\d+", utt_id):
                raise ValueError(f"非法 LibriSpeech utterance ID: {utt_id}")
            speaker_id, chapter_id, _ = utt_id.split("-")
            if speaker_id != transcript.parent.parent.name or chapter_id != transcript.parent.name:
                raise ValueError(f"{utt_id}: 转录 ID 与 speaker/chapter 目录不匹配")
            audio_path = transcript.parent / f"{utt_id}.flac"
            if not audio_path.is_file():
                raise FileNotFoundError(f"缺少转录对应音频: {audio_path}")
            info = sf.info(str(audio_path))
            if info.samplerate != SAMPLE_RATE or info.channels != 1 or info.frames <= 0:
                raise ValueError(f"音频必须是非空 16 kHz 单声道: {audio_path}")
            records.append(AudioRecord(
                utt_id=utt_id, audio_path=audio_path, text=text.strip(), split=split,
                speaker_id=speaker_id, duration_seconds=info.frames / info.samplerate,
                sha256=file_sha256(audio_path) if include_sha256 else None,
            ))
    records.sort(key=lambda record: record.utt_id)
    _check_unique(records)
    if not records:
        raise ValueError("没有可导出的音频记录")
    lines = []
    for record in records:
        try:
            relative_path = Path(os.path.relpath(record.audio_path, destination.parent)).as_posix()
        except ValueError:
            # Windows 不同盘符无法相对定位，显式保存绝对路径。
            relative_path = record.audio_path.as_posix()
        row = {**record.__dict__, "audio_path": relative_path}
        if row["sha256"] is None:
            row.pop("sha256")
        lines.append(json.dumps(row, ensure_ascii=False, sort_keys=True))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w" if overwrite else "x", encoding="utf-8", newline="\n") as stream:
        stream.write("\n".join(lines) + "\n")
    return records


def load_audio(
    record_or_path: AudioRecord | str | Path,
    *,
    sample_rate: int = SAMPLE_RATE,
    max_duration_seconds: float | None = None,
):
    """读取完整 float32 单声道波形；超长直接拒绝，绝不截断标签对应的音频。"""
    if sample_rate != SAMPLE_RATE:
        raise ValueError("Model A 输入固定为 16000 Hz；改变采样率需要独立模型验证")
    if max_duration_seconds is not None:
        if isinstance(max_duration_seconds, bool) or not isinstance(max_duration_seconds, (int, float)):
            raise ValueError("max_duration_seconds 必须为有限正数或 None")
        if not math.isfinite(max_duration_seconds) or max_duration_seconds <= 0:
            raise ValueError("max_duration_seconds 必须为有限正数或 None")
    record = record_or_path if isinstance(record_or_path, AudioRecord) else None
    path = Path(record.audio_path if record is not None else record_or_path).resolve()
    sf = _soundfile()
    info = sf.info(str(path))
    if info.samplerate != sample_rate or info.channels != 1 or info.frames <= 0:
        raise ValueError(f"音频必须是非空 {sample_rate} Hz 单声道: {path}")
    duration = info.frames / info.samplerate
    if max_duration_seconds is not None and duration > max_duration_seconds:
        raise ValueError(f"音频时长 {duration:.6f}s 超过上限 {max_duration_seconds}s；拒绝截断: {path}")
    if record is not None:
        _validate_record(record)
        if abs(duration - record.duration_seconds) > 1.0 / sample_rate:
            raise ValueError(f"清单时长与音频不匹配: {path}")
    samples, actual_rate = sf.read(str(path), dtype="float32", always_2d=False)
    if actual_rate != sample_rate or samples.ndim != 1 or len(samples) != info.frames:
        raise ValueError(f"音频读取期间格式或长度发生变化: {path}")
    import numpy as np
    if not np.isfinite(samples).all():
        raise ValueError(f"音频包含 NaN 或 Inf: {path}")
    return samples
