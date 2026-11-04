"""固定 Model A 的离线 FP32 后端；INT16 仅存权重，加载后仍用 FP32 算子。

导入本模块不会导入 Torch/ESPnet，也不会联网。原始模型文件只读；仅在
artifacts/runtime 生成绝对路径配置，避免通过 chdir 改变进程全局工作目录。
"""
from __future__ import annotations

import copy
import gc
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import sys
import tempfile
import time
from typing import Any

from asr_chip.assets import MODEL_FILES, MODEL_ID, MODEL_REVISION, MODEL_ROOT, ROOT, file_hash

CHECKPOINT_RELATIVE = "exp/asr_train_asr_conformer8_raw_en_bpe5000_sp/valid.acc.ave.pth"
CHECKPOINT_SHA256 = MODEL_FILES[CHECKPOINT_RELATIVE]
CONFIG_RELATIVE = "exp/asr_train_asr_conformer8_raw_en_bpe5000_sp/config.yaml"
STATS_RELATIVE = "exp/asr_stats_raw_en_bpe5000_sp/train/feats_stats.npz"
BPE_RELATIVE = "data/en_token_list/bpe_unigram5000/bpe.model"
_CONFIG_KEYS = {
    "schema_version", "model_id", "revision", "dtype", "int8", "training", "sample_rate",
    "language", "mode", "device", "seed", "threads", "deterministic", "decoding",
}
_DECODING_KEYS = {"method", "beam_size", "ctc_weight", "lm_weight", "nbest", "maxlenratio", "minlenratio"}


def _number(value: Any, name: str, *, minimum: float, maximum: float | None = None) -> None:
    if (type(value) not in (int, float) or not math.isfinite(value) or value < minimum
            or (maximum is not None and value > maximum)):
        raise ValueError(f"invalid finite numeric config field: {name}")


def _validate_config(config: dict) -> dict:
    """严格限制本轮已确认范围，拼错字段不能被默认值静默吞掉。"""
    if not isinstance(config, dict) or set(config) != _CONFIG_KEYS:
        raise ValueError(f"config must contain exactly these fields: {sorted(_CONFIG_KEYS)}")
    for key, expected in {
        "schema_version": 1, "model_id": MODEL_ID, "revision": MODEL_REVISION,
        "dtype": "float32", "int8": False, "training": False, "sample_rate": 16000,
        "language": "en", "mode": "offline", "deterministic": True,
    }.items():
        if type(config[key]) is not type(expected) or config[key] != expected:
            raise ValueError(f"config {key} must be {expected!r}")
    if not isinstance(config["device"], str) or re.fullmatch(r"cpu|auto|cuda(?::(?:0|[1-9][0-9]*))?", config["device"]) is None:
        raise ValueError("device must be cpu, auto, cuda or cuda:N")
    if type(config["seed"]) is not int or not 0 <= config["seed"] <= 2**32 - 1:
        raise ValueError("seed must be an integer in [0, 2**32-1]")
    if type(config["threads"]) is not int or config["threads"] < 1:
        raise ValueError("threads must be a positive integer")
    decoding = config["decoding"]
    if not isinstance(decoding, dict) or set(decoding) != _DECODING_KEYS:
        raise ValueError(f"decoding must contain exactly these fields: {sorted(_DECODING_KEYS)}")
    if decoding["method"] != "beam":
        raise ValueError("only the original ESPnet CTC/attention beam decoding is approved")
    if type(decoding["beam_size"]) is not int or decoding["beam_size"] < 1:
        raise ValueError("beam_size must be a positive integer")
    if type(decoding["nbest"]) is not int or decoding["nbest"] != 1:
        raise ValueError("nbest must be 1")
    _number(decoding["ctc_weight"], "ctc_weight", minimum=0.0, maximum=1.0)
    _number(decoding["lm_weight"], "lm_weight", minimum=0.0, maximum=0.0)
    _number(decoding["maxlenratio"], "maxlenratio", minimum=0.0)
    _number(decoding["minlenratio"], "minlenratio", minimum=0.0)
    if decoding["maxlenratio"] > 0 and decoding["minlenratio"] > decoding["maxlenratio"]:
        raise ValueError("minlenratio exceeds maxlenratio")
    return copy.deepcopy(config)


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON configuration key: {key}")
        result[key] = value
    return result


def read_config(path: Path = ROOT / "configs/asr_chip_baseline.json") -> dict:
    config = json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=_unique_pairs)
    return _validate_config(config)


def verify_model(model_root: Path = MODEL_ROOT) -> dict[str, str]:
    """严格校验固定 revision 的五个原始文件，不自动发现或替换 checkpoint。"""
    model_root = Path(model_root).resolve()
    hashes = {}
    for relative, expected in MODEL_FILES.items():
        path = model_root / relative
        if not path.is_file():
            raise FileNotFoundError(f"required pinned model file is missing: {path}")
        actual = file_hash(path)
        if actual != expected:
            raise ValueError(f"model SHA-256 mismatch: {relative}; expected {expected}, got {actual}")
        hashes[relative] = actual
    return hashes


def environment_info() -> dict:
    """返回可序列化环境信息；环境缺项明确记录，不伪造可用 CUDA。"""
    packages = {}
    for package in ("torch", "torchaudio", "espnet", "numpy", "PyYAML", "soundfile", "sentencepiece", "jiwer"):
        try:
            packages[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            packages[package] = None
    result = {
        "python": sys.version, "python_executable": sys.executable, "platform": platform.platform(),
        "project_root": str(ROOT.resolve()), "model_root": str(MODEL_ROOT.resolve()),
        "packages": packages, "cuda_available": False, "cuda_version": None, "gpus": [],
        "torch_error": None,
    }
    # 在报告中记录真实导入位置，避免阅读副本与运行源码混淆。
    from importlib.util import find_spec
    spec = find_spec("espnet2")
    result["espnet_source_file"] = str(Path(spec.origin).resolve()) if spec and spec.origin else None
    # 在任意 CUDA 探测之前设置，后续构造识别器会强制同一确定性设置。
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    try:
        import torch
        result["torch_path"] = str(Path(torch.__file__).resolve())
        result["cuda_version"] = torch.version.cuda
        result["cuda_available"] = bool(torch.cuda.is_available())
        if result["cuda_available"]:
            for index in range(torch.cuda.device_count()):
                properties = torch.cuda.get_device_properties(index)
                result["gpus"].append({"index": index, "name": properties.name,
                                       "total_memory_bytes": int(properties.total_memory)})
    except Exception as error:
        result["torch_error"] = f"{type(error).__name__}: {error}"
    return result


def _runtime_config(model_root: Path) -> Path:
    """仅改写推理使用的资源路径，保持网络配置和原始文件不变。"""
    import yaml
    source = model_root / CONFIG_RELATIVE
    config = yaml.safe_load(source.read_text(encoding="utf-8"))
    if not isinstance(config, dict) or config.get("normalize") != "global_mvn":
        raise ValueError("pinned Model A requires global_mvn normalization")
    if not isinstance(config.get("normalize_conf"), dict) or not isinstance(config.get("token_list"), list):
        raise ValueError("pinned Model A normalization/token list config is incomplete")
    config["normalize_conf"]["stats_file"] = str((model_root / STATS_RELATIVE).resolve())
    config["bpemodel"] = str((model_root / BPE_RELATIVE).resolve())
    text = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    directory = ROOT / "artifacts/runtime"
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"model_a_{digest}.yaml"
    if destination.exists():
        if destination.read_text(encoding="utf-8") != text:
            raise ValueError(f"runtime configuration content mismatch: {destination}")
        return destination
    # 唯一临时文件 + 原子替换；不会修改下载的配置或影响另一个推理进程的 cwd。
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n", dir=directory,
                                         prefix="model_a_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text)
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return destination


def _speech2text_type():
    """延迟导入固定环境中的 ESPnet；不导入历史实验脚本。"""
    from espnet2.bin.asr_inference import Speech2Text
    return Speech2Text


class Recognizer:
    def __init__(self, config: dict, *, model_root: Path = MODEL_ROOT,
                 precision: str = "fp32", artifact: Path | None = None):
        self.config = _validate_config(config)
        if precision not in {"fp32", "int16"}:
            raise ValueError("precision must be fp32 or int16 (weight storage only)")
        if (precision == "int16") != (artifact is not None):
            raise ValueError("provide an artifact exactly when precision is int16")
        self.precision = precision
        self.decoder = None
        self.quantization_report = None
        self.model_root = Path(model_root).resolve()
        started = time.perf_counter()
        self.model_hashes = verify_model(self.model_root)
        # 必须在导入/初始化 CUDA 前设置；无需通过子进程或 chdir 改变加载行为。
        os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"
        import numpy as np
        import torch
        torch.set_num_threads(self.config["threads"])
        torch.use_deterministic_algorithms(True)
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.allow_tf32 = False
        torch.backends.cuda.matmul.allow_tf32 = False
        requested = self.config["device"]
        if requested == "auto":
            requested = "cuda" if torch.cuda.is_available() else "cpu"
        if requested.startswith("cuda"):
            if not torch.cuda.is_available():
                raise RuntimeError("CUDA was requested but this environment has no available CUDA device")
            index = int(requested.split(":", 1)[1]) if ":" in requested else 0
            if index >= torch.cuda.device_count():
                raise ValueError(f"CUDA device index unavailable: {requested}")
            requested = f"cuda:{index}"
        self.device = requested
        random.seed(self.config["seed"])
        np.random.seed(self.config["seed"])
        torch.manual_seed(self.config["seed"])
        if self.device.startswith("cuda"):
            torch.cuda.manual_seed_all(self.config["seed"])
        runtime_path = _runtime_config(self.model_root)
        decoding = self.config["decoding"]
        decoder_type = _speech2text_type()
        self.decoder = decoder_type(
            asr_train_config=str(runtime_path), asr_model_file=str(self.model_root / CHECKPOINT_RELATIVE),
            token_type="bpe", bpemodel=str(self.model_root / BPE_RELATIVE), device=self.device,
            dtype="float32", beam_size=decoding["beam_size"], ctc_weight=float(decoding["ctc_weight"]),
            lm_weight=0.0, nbest=1, maxlenratio=float(decoding["maxlenratio"]),
            minlenratio=float(decoding["minlenratio"]),
        )
        # 此状态是导出/应用量化包共同使用的 canonical FP32 状态。
        # 原 checkpoint 的 MVN buffer 可能为 FP64，不能直接拿原始 state 与此混用。
        model = self.decoder.asr_model.float().eval()
        model.requires_grad_(False)
        if precision == "int16":
            from asr_chip.quantization import apply_int16_artifact, load_int16_artifact
            contents = load_int16_artifact(
                artifact, expected_base_sha256=CHECKPOINT_SHA256, reference_state_dict=model.state_dict(),
                verify_source_values=True,
            )
            if contents["model_id"] != MODEL_ID:
                raise ValueError("INT16 artifact model_id does not match pinned Model A")
            # 在原模型上严格加载参数，不替换 module，beam scorer 仍引用同一对象。
            self.quantization_report = apply_int16_artifact(model, contents, expected_base_sha256=CHECKPOINT_SHA256)
        self.runtime_config = runtime_path
        self.synchronize()
        self.load_seconds = time.perf_counter() - started

    def _audio(self, audio):
        import numpy as np
        if self.decoder is None:
            raise RuntimeError("recognizer is closed")
        if not isinstance(audio, np.ndarray) or audio.ndim != 1 or audio.dtype != np.float32:
            raise ValueError("audio must be a mono float32 NumPy array sampled at 16000 Hz")
        if audio.size == 0 or not np.isfinite(audio).all():
            raise ValueError("audio must be non-empty and finite")
        return np.ascontiguousarray(audio)

    def transcribe(self, audio) -> str:
        import torch
        waveform = self._audio(audio)
        with torch.inference_mode():
            results = self.decoder(waveform)
        if not results or results[0][0] is None:
            return ""
        # 文本规范化由统一 WER 模块负责，保留解码器的原始文本供审计。
        return str(results[0][0])

    def ctc_logits(self, audio):
        """返回有效帧的 CPU FP32 原始 CTC logits，形状 [1, T, V]。"""
        import torch
        waveform = self._audio(audio)
        speech = torch.from_numpy(waveform).unsqueeze(0).to(device=self.device, dtype=torch.float32)
        lengths = torch.tensor([waveform.size], dtype=torch.long, device=self.device)
        with torch.inference_mode():
            encoded, encoded_lengths = self.decoder.asr_model.encode(speech, lengths)
            if isinstance(encoded, tuple):
                encoded = encoded[0]
            logits = self.decoder.asr_model.ctc.ctc_lo(encoded)
            valid = int(encoded_lengths[0].item())
            return logits[:, :valid].detach().to(device="cpu", dtype=torch.float32).contiguous()

    def synchronize(self) -> None:
        if self.device.startswith("cuda"):
            import torch
            torch.cuda.synchronize(self.device)

    def close(self) -> None:
        if self.decoder is not None:
            self.synchronize()
            self.decoder = None
            gc.collect()
