"""INT16 权重存储参考：加载后反量化为 FP32，不声称整数推理。

格式 v1 使用输出通道（axis=0）对称量化，码值范围 [-32767, 32767]。
量化计算使用 FP64 除法与 ties-to-even 舍入，实际保存的 scale 是 FP32。
只有二维至五维的浮点 ``*.weight``/``weight`` 是候选；norm 路径除外。
该名称规则适用于当前 Model A 的 Linear/Conv/Embedding，实际覆盖逐项记录。
bias、norm 和其他 buffer 保持原值。构建时要求候选权重来自 FP32 基线。
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import tempfile
from collections import OrderedDict
from collections.abc import Mapping
from pathlib import Path
from typing import Any

import torch


FORMAT = "software4npu.int16_weight_storage"
FORMAT_VERSION = 1
QMIN, QMAX = -32767, 32767
SELECTION_RULE = "floating_weight_rank_2_to_5_excluding_norm_v1"
QUANTIZATION = {
    "storage_dtype": "int16",
    "scale_dtype": "float32",
    "scale_axis": 0,
    "zero_point": 0,
    "qmin": QMIN,
    "qmax": QMAX,
    "rounding": "nearest_ties_to_even",
    "quantization_division_dtype": "float64",
    "clipping": "saturate_to_symmetric_range",
    "zero_channel_scale": 1.0,
    "subnormal_scale_rule": "floor_at_smallest_positive_float32",
    "dequantization_dtype": "float32",
    "selection_rule": SELECTION_RULE,
}
_DTYPES = {
    str(value).removeprefix("torch."): value
    for value in (
        torch.float16, torch.bfloat16, torch.float32, torch.float64,
        torch.int8, torch.uint8, torch.int16, torch.int32, torch.int64, torch.bool,
    )
}
_ARTIFACT_KEYS = {
    "format", "format_version", "inference", "base_sha256", "model_id",
    "quantization", "state_order", "quantized_tensor_names", "preserved_tensor_names",
    "tensors", "report", "manifest_sha256",
}
_ENTRY_COMMON = {"kind", "shape", "source_dtype", "source_sha256", "reason"}
_QUANTIZED_KEYS = _ENTRY_COMMON | {
    "codes", "scales", "codes_sha256", "scales_sha256", "error", "scale_floor_channels",
}
_PRESERVED_KEYS = _ENTRY_COMMON | {"value", "value_sha256"}


class QuantizationError(ValueError):
    """数值、来源绑定或序列化格式不满足软件参考合同。"""


def _sha256_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise QuantizationError(f"{label} 必须是 64 位小写 SHA-256 十六进制字符串")
    return value


def _dtype_name(tensor: torch.Tensor) -> str:
    return str(tensor.dtype).removeprefix("torch.")


def _check_tensor(tensor: Any, name: str) -> None:
    if not isinstance(tensor, torch.Tensor):
        raise QuantizationError(f"{name}: state_dict 仅支持 Tensor")
    if tensor.layout != torch.strided or tensor.is_quantized or tensor.device.type == "meta":
        raise QuantizationError(f"{name}: 仅支持真实的 dense strided Tensor")
    if _dtype_name(tensor) not in _DTYPES:
        raise QuantizationError(f"{name}: 不支持 dtype {tensor.dtype}")
    if tensor.is_floating_point() and not bool(torch.isfinite(tensor).all()):
        raise QuantizationError(f"{name}: 拒绝 NaN/Inf")


def _cpu_copy(tensor: torch.Tensor) -> torch.Tensor:
    return tensor.detach().to(device="cpu").contiguous().clone()


def _tensor_hash(tensor: torch.Tensor) -> str:
    # 先展平，再转原始字节，兼容标量与 bfloat16，避免 numpy dtype 限制。
    value = tensor.detach().cpu().contiguous().reshape(-1).view(torch.uint8)
    return hashlib.sha256(value.numpy().tobytes()).hexdigest()


def _selection_reason(name: str, tensor: torch.Tensor) -> tuple[bool, str]:
    parts = name.lower().split(".")
    if any("norm" in part or re.fullmatch(r"bn\d*", part) for part in parts[:-1]):
        return False, "normalization_preserved"
    if parts[-1] == "bias":
        return False, "bias_preserved"
    if parts[-1] != "weight":
        return False, "buffer_or_non_weight_preserved"
    if not tensor.is_floating_point():
        return False, "non_floating_weight_preserved"
    if tensor.ndim not in (2, 3, 4, 5):
        return False, "weight_rank_not_2_to_5_preserved"
    return True, "matrix_or_convolution_weight_output_channel_axis_0"


def _quantize_weight(value: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, int]:
    if value.dtype != torch.float32:
        raise QuantizationError("量化候选权重必须是 FP32；请先建立 FP32 基线")
    if value.numel() == 0 or any(size == 0 for size in value.shape):
        raise QuantizationError("量化权重不能含零长度维度")
    rows = value.reshape(value.shape[0], -1).double()
    maxima = rows.abs().amax(dim=1)
    scales = (maxima / QMAX).float()
    zero = maxima == 0
    tiny = torch.nextafter(torch.tensor(0.0), torch.tensor(1.0))
    underflow = (~zero) & (scales == 0)
    scales[underflow] = tiny
    scales[zero] = 1.0
    # FP32 最大值附近 scale 向上舍入时，32767*scale 可能溢出；向下取邻值。
    largest_safe = torch.finfo(torch.float32).max / QMAX
    unsafe = scales.double() > largest_safe
    scales[unsafe] = torch.nextafter(scales[unsafe], torch.zeros_like(scales[unsafe]))
    codes = torch.round(rows / scales.double().unsqueeze(1)).clamp(QMIN, QMAX)
    return codes.to(torch.int16).reshape(value.shape), scales, int(underflow.sum())


def _dequantize_weight(codes: torch.Tensor, scales: torch.Tensor) -> torch.Tensor:
    shape = (codes.shape[0],) + (1,) * (codes.ndim - 1)
    # 中间乘法用 FP64，使导出重载的结果不依赖隐式整数/浮点类型提升。
    value = (codes.double() * scales.double().reshape(shape)).float()
    if not bool(torch.isfinite(value).all()):
        raise QuantizationError("反量化产生 NaN/Inf")
    return value.contiguous()


def _errors(reference: torch.Tensor, actual: torch.Tensor) -> dict[str, float]:
    difference = actual.double() - reference.double()
    squared_error = float(difference.square().sum())
    squared_reference = float(reference.double().square().sum())
    return {
        "max_abs_error": float(difference.abs().max()),
        "sum_squared_error": squared_error,
        "sum_squared_reference": squared_reference,
        "relative_l2_error": math.sqrt(squared_error / squared_reference) if squared_reference else 0.0,
    }


def _metadata(value: Any) -> Any:
    if isinstance(value, torch.Tensor):
        return {"tensor_payload": True, "dtype": _dtype_name(value), "shape": list(value.shape)}
    if isinstance(value, dict):
        return {key: _metadata(item) for key, item in value.items() if key != "manifest_sha256"}
    if isinstance(value, (list, tuple)):
        return [_metadata(item) for item in value]
    return value


def _manifest_hash(artifact: Mapping[str, Any]) -> str:
    try:
        encoded = json.dumps(_metadata(dict(artifact)), sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise QuantizationError("manifest 包含不能序列化或非有限的元数据") from error
    return hashlib.sha256(encoded).hexdigest()


def _report(tensors: Mapping[str, dict[str, Any]]) -> dict[str, Any]:
    quantized = [entry for entry in tensors.values() if entry["kind"] == "quantized_int16"]
    preserved = [entry for entry in tensors.values() if entry["kind"] == "preserved"]
    code_bytes = sum(entry["codes"].numel() * 2 for entry in quantized)
    scale_bytes = sum(entry["scales"].numel() * 4 for entry in quantized)
    preserved_bytes = sum(entry["value"].numel() * entry["value"].element_size() for entry in preserved)
    source_bytes = sum(math.prod(entry["shape"]) * torch.empty((), dtype=_DTYPES[entry["source_dtype"]]).element_size()
                       for entry in tensors.values())
    sum_error = sum(entry["error"]["sum_squared_error"] for entry in quantized)
    sum_reference = sum(entry["error"]["sum_squared_reference"] for entry in quantized)
    return {
        "evidence_level": "SOFTWARE_WEIGHT_STORAGE_AND_FP32_DEQUANTIZATION",
        "inference_arithmetic": "fp32_existing_operators",
        "integer_inference": False,
        "activation_quantization": False,
        "state_tensor_count": len(tensors),
        "quantized_tensor_count": len(quantized),
        "preserved_tensor_count": len(preserved),
        "quantized_weight_elements": sum(entry["codes"].numel() for entry in quantized),
        "source_state_logical_bytes": source_bytes,
        "logical_int16_code_bytes": code_bytes,
        "scale_bytes": scale_bytes,
        "preserved_tensor_bytes": preserved_bytes,
        "logical_payload_bytes": code_bytes + scale_bytes + preserved_bytes,
        "quantized_weights_max_abs_error": max((entry["error"]["max_abs_error"] for entry in quantized), default=0.0),
        "quantized_weights_relative_l2_error": math.sqrt(sum_error / sum_reference) if sum_reference else 0.0,
        "error_reference": "original_fp32_weights; no ASR/WER claim",
        "scale_floor_channels": sum(entry["scale_floor_channels"] for entry in quantized),
        "serialized_size_note": "使用 save_int16_artifact 或 artifact_report(path=...) 读取实际文件大小",
    }


def build_int16_artifact(
    state_dict: Mapping[str, torch.Tensor], *, base_sha256: str, model_id: str | None = None,
) -> dict[str, Any]:
    """从完整 FP32 模型 state_dict 创建版本化 INT16 权重存储包。

    base_sha256 应是原始 checkpoint 文件的 SHA-256，由调用方从文件计算。
    保留全部 state 键；不修改调用方张量。逐项覆盖表可直接用于审计。
    """
    _sha256_string(base_sha256, "base_sha256")
    if not isinstance(state_dict, Mapping) or not state_dict:
        raise QuantizationError("state_dict 必须是非空 Mapping")
    if any(not isinstance(name, str) or not name for name in state_dict):
        raise QuantizationError("state_dict 键必须是非空字符串")
    if model_id is not None and not isinstance(model_id, str):
        raise QuantizationError("model_id 必须为字符串或 None")
    tensors: dict[str, dict[str, Any]] = {}
    for name in sorted(state_dict):
        original = state_dict[name]
        _check_tensor(original, name)
        value = _cpu_copy(original)
        selected, reason = _selection_reason(name, value)
        entry: dict[str, Any] = {
            "kind": "quantized_int16" if selected else "preserved",
            "shape": list(value.shape), "source_dtype": _dtype_name(value),
            "source_sha256": _tensor_hash(value), "reason": reason,
        }
        if selected:
            codes, scales, floors = _quantize_weight(value)
            entry.update(codes=codes, scales=scales, codes_sha256=_tensor_hash(codes),
                         scales_sha256=_tensor_hash(scales), scale_floor_channels=floors,
                         error=_errors(value, _dequantize_weight(codes, scales)))
        else:
            entry.update(value=value, value_sha256=_tensor_hash(value))
        tensors[name] = entry
    artifact: dict[str, Any] = {
        "format": FORMAT, "format_version": FORMAT_VERSION,
        "inference": "fp32_dequantized", "base_sha256": base_sha256, "model_id": model_id,
        "quantization": dict(QUANTIZATION), "state_order": list(tensors), "tensors": tensors,
        "quantized_tensor_names": [name for name, item in tensors.items() if item["kind"] == "quantized_int16"],
        "preserved_tensor_names": [name for name, item in tensors.items() if item["kind"] == "preserved"],
        "report": _report(tensors),
    }
    artifact["manifest_sha256"] = _manifest_hash(artifact)
    return artifact


def validate_int16_artifact(
    artifact: Mapping[str, Any], *, expected_base_sha256: str,
    reference_state_dict: Mapping[str, torch.Tensor] | None = None,
    verify_source_values: bool = False,
) -> None:
    """完整检查后才允许解码；可对 fresh canonical 基线逐项核对源值。

    verify_source_values=True 只能用于尚未应用量化的基线 state；它同时
    检查被量化权重、bias、norm 与 buffer，避免把同结构的别的权重错绑。
    """
    if type(verify_source_values) is not bool:
        raise QuantizationError("verify_source_values 必须是 bool")
    if verify_source_values and reference_state_dict is None:
        raise QuantizationError("校验 source_sha256 必须提供 fresh canonical reference_state_dict")
    _sha256_string(expected_base_sha256, "expected_base_sha256")
    if not isinstance(artifact, dict) or set(artifact) != _ARTIFACT_KEYS:
        raise QuantizationError("artifact 顶层字段缺失或含未知字段")
    if artifact["format"] != FORMAT or type(artifact["format_version"]) is not int or artifact["format_version"] != FORMAT_VERSION:
        raise QuantizationError("不支持的 artifact 格式或版本")
    if artifact["inference"] != "fp32_dequantized" or artifact["quantization"] != QUANTIZATION:
        raise QuantizationError("不是本合同约定的 INT16 存储/FP32 推理格式")
    if _sha256_string(artifact["base_sha256"], "base_sha256") != expected_base_sha256:
        raise QuantizationError("base checkpoint SHA-256 不匹配")
    if artifact["model_id"] is not None and not isinstance(artifact["model_id"], str):
        raise QuantizationError("model_id 非法")
    _sha256_string(artifact["manifest_sha256"], "manifest_sha256")
    if _manifest_hash(artifact) != artifact["manifest_sha256"]:
        raise QuantizationError("manifest SHA-256 不匹配")
    entries, order = artifact["tensors"], artifact["state_order"]
    if not isinstance(entries, dict) or not entries or not isinstance(order, list):
        raise QuantizationError("tensors/state_order 非法")
    if any(not isinstance(name, str) or not name for name in entries):
        raise QuantizationError("tensors 键必须是非空字符串")
    if any(not isinstance(name, str) or not name for name in order):
        raise QuantizationError("state_order 必须包含非空字符串")
    if len(order) != len(set(order)) or order != sorted(entries):
        raise QuantizationError("state_order 不完整、重复或顺序非法")
    quantized, preserved = [], []
    for name in order:
        entry = entries[name]
        if not isinstance(entry, dict):
            raise QuantizationError(f"{name}: entry 必须为 dict")
        kind = entry.get("kind")
        expected_keys = _QUANTIZED_KEYS if kind == "quantized_int16" else _PRESERVED_KEYS if kind == "preserved" else None
        if expected_keys is None or set(entry) != expected_keys:
            raise QuantizationError(f"{name}: entry 字段或 kind 非法")
        shape = entry["shape"]
        if not isinstance(shape, list) or any(type(size) is not int or size < 0 for size in shape):
            raise QuantizationError(f"{name}: shape 非法")
        if entry["source_dtype"] not in _DTYPES:
            raise QuantizationError(f"{name}: source_dtype 非法")
        _sha256_string(entry["source_sha256"], f"{name}.source_sha256")
        if kind == "quantized_int16":
            codes, scales = entry["codes"], entry["scales"]
            _check_tensor(codes, f"{name}.codes")
            _check_tensor(scales, f"{name}.scales")
            if codes.device.type != "cpu" or scales.device.type != "cpu":
                raise QuantizationError(f"{name}: 保存/加载参考格式必须位于 CPU")
            if codes.dtype != torch.int16 or scales.dtype != torch.float32 or entry["source_dtype"] != "float32":
                raise QuantizationError(f"{name}: 必须为 INT16 codes、FP32 scales/源权重")
            if list(codes.shape) != shape or len(shape) not in (2, 3, 4, 5) or not all(shape):
                raise QuantizationError(f"{name}: codes shape 非法")
            if list(scales.shape) != [shape[0]] or not bool((scales > 0).all()):
                raise QuantizationError(f"{name}: scale 维度或正值约束不满足")
            if bool((codes < QMIN).any()) or bool((codes > QMAX).any()):
                raise QuantizationError(f"{name}: 码值超出对称 INT16 范围")
            for label, tensor in (("codes", codes), ("scales", scales)):
                if _tensor_hash(tensor) != _sha256_string(entry[label + "_sha256"], name + "." + label):
                    raise QuantizationError(f"{name}: {label} SHA-256 不匹配")
            selected, reason = _selection_reason(name, torch.empty(shape, device="meta", dtype=torch.float32))
            if not selected or entry["reason"] != reason:
                raise QuantizationError(f"{name}: 不满足权重选择规则")
            error = entry["error"]
            if not isinstance(error, dict) or set(error) != {"max_abs_error", "sum_squared_error", "sum_squared_reference", "relative_l2_error"}:
                raise QuantizationError(f"{name}: error 元数据非法")
            if any(type(value) not in (float, int) or not math.isfinite(value) or value < 0 for value in error.values()):
                raise QuantizationError(f"{name}: error 元数据必须有限且非负")
            floors = entry["scale_floor_channels"]
            if type(floors) is not int or floors < 0 or floors > shape[0]:
                raise QuantizationError(f"{name}: scale_floor_channels 非法")
            _dequantize_weight(codes, scales)
            quantized.append(name)
        else:
            value = entry["value"]
            _check_tensor(value, name)
            if value.device.type != "cpu" or list(value.shape) != shape or _dtype_name(value) != entry["source_dtype"]:
                raise QuantizationError(f"{name}: preserved shape/dtype/device 不匹配")
            value_hash = _tensor_hash(value)
            if value_hash != entry["value_sha256"] or value_hash != entry["source_sha256"]:
                raise QuantizationError(f"{name}: preserved SHA-256 不匹配")
            selected, reason = _selection_reason(name, value)
            if selected or entry["reason"] != reason:
                raise QuantizationError(f"{name}: preserved 条目违反选择规则")
            preserved.append(name)
    if quantized != artifact["quantized_tensor_names"] or preserved != artifact["preserved_tensor_names"]:
        raise QuantizationError("量化/保留 tensor 覆盖清单不一致")
    if _report(entries) != artifact["report"]:
        raise QuantizationError("report 容量/误差汇总与条目不一致")
    if reference_state_dict is not None:
        if not isinstance(reference_state_dict, Mapping) or set(reference_state_dict) != set(order):
            raise QuantizationError("目标模型 state_dict keys 不完整或含多余项")
        for name in order:
            reference = reference_state_dict[name]
            _check_tensor(reference, f"reference.{name}")
            if list(reference.shape) != entries[name]["shape"] or _dtype_name(reference) != entries[name]["source_dtype"]:
                raise QuantizationError(f"{name}: 目标模型 shape/dtype 不匹配")
            if verify_source_values and _tensor_hash(reference) != entries[name]["source_sha256"]:
                raise QuantizationError(f"{name}: source_sha256 与 fresh canonical 基线值不匹配")


def dequantize_state_dict(
    artifact: Mapping[str, Any], *, expected_base_sha256: str,
    reference_state_dict: Mapping[str, torch.Tensor] | None = None,
) -> OrderedDict[str, torch.Tensor]:
    """返回独立完整 state_dict；被量化的权重恢复为 FP32。"""
    validate_int16_artifact(artifact, expected_base_sha256=expected_base_sha256,
                           reference_state_dict=reference_state_dict)
    output: OrderedDict[str, torch.Tensor] = OrderedDict()
    for name in artifact["state_order"]:
        entry = artifact["tensors"][name]
        output[name] = (_dequantize_weight(entry["codes"], entry["scales"])
                        if entry["kind"] == "quantized_int16" else entry["value"].clone())
    return output


def artifact_report(artifact: Mapping[str, Any], *, path: str | Path | None = None) -> dict[str, Any]:
    """容量是软件字节统计；文件大小与逻辑 tensor payload 分开报告。"""
    validate_int16_artifact(artifact, expected_base_sha256=artifact.get("base_sha256", ""))
    report = dict(artifact["report"])
    report["base_sha256"] = artifact["base_sha256"]
    report["manifest_sha256"] = artifact["manifest_sha256"]
    if path is not None:
        report["artifact_file_bytes"] = Path(path).stat().st_size
        report["artifact_path"] = str(Path(path).resolve())
    return report


def save_int16_artifact(
    artifact: Mapping[str, Any], path: str | Path, *, overwrite: bool = False,
) -> dict[str, Any]:
    """同目录临时文件写入＋fsync＋原子替换；异常不留下半个最终文件。"""
    validate_int16_artifact(artifact, expected_base_sha256=artifact.get("base_sha256", ""))
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and not overwrite:
        raise FileExistsError(f"输出文件已存在：{destination}")
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", prefix=f".{destination.name}.", suffix=".tmp",
                                         dir=destination.parent, delete=False) as handle:
            temporary = Path(handle.name)
            torch.save(dict(artifact), handle)
            handle.flush()
            os.fsync(handle.fileno())
        if overwrite:
            os.replace(temporary, destination)
        else:
            # 同目录硬链接原子创建最终名称，另一个进程抢先创建时不会覆盖。
            os.link(temporary, destination)
            temporary.unlink()
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return artifact_report(artifact, path=destination)


def load_int16_artifact(
    path: str | Path, *, expected_base_sha256: str,
    reference_state_dict: Mapping[str, torch.Tensor] | None = None,
    verify_source_values: bool = False,
) -> dict[str, Any]:
    """安全 tensor-only 加载；fresh 基线首次加载应开启 source 值校验。"""
    _sha256_string(expected_base_sha256, "expected_base_sha256")
    artifact = torch.load(Path(path), map_location="cpu", weights_only=True)
    validate_int16_artifact(artifact, expected_base_sha256=expected_base_sha256,
                           reference_state_dict=reference_state_dict,
                           verify_source_values=verify_source_values)
    return artifact


def apply_int16_artifact(
    model: torch.nn.Module, artifact: Mapping[str, Any], *, expected_base_sha256: str,
) -> dict[str, Any]:
    """先验证全部键/shape/dtype，再加载；失败的格式检查不会部分更新模型。

    模型应是普通 FP32 PyTorch/ESPnet 模型；保留现有算子与解码流程。
    该接口不会设置 eval()、移动设备或改变解码器，交由调用方显式控制。
    """
    reference = model.state_dict()
    values = dequantize_state_dict(artifact, expected_base_sha256=expected_base_sha256,
                                  reference_state_dict=reference)
    model.load_state_dict(values, strict=True)
    return dict(artifact["report"])
