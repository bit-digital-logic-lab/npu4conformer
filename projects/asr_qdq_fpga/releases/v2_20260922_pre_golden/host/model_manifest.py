"""Read-only audit of the original encoder/decoder models."""
from collections import Counter
from pathlib import Path
import hashlib
import re
import numpy as np
import onnx
from onnx import numpy_helper
from .onnx_executor import SUPPORTED_OPS

DEFAULT_MODEL_DIR = Path(r"D:\program\python\ASR-ONNX\software4npu\temp\model_a_int16_runs\run01\int16_qdq_fix01")
DEFAULT_CASE_DIR = Path(r"D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\random200_v1\cases\case_0000")
ORIGINAL_SHA256 = {
    "encoder": "58e3a6bb6a95cdb7c5cc5397793d8daac2cfd1f4e9500ad1a742295396fc0ed2",
    "decoder": "c59a0001e54cad634304c1b527771ebc22ecac7d165ef444666d0708db99ad3c",
}


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): digest.update(block)
    return digest.hexdigest()


def audit_model(path):
    path = Path(path)
    model = onnx.load(str(path))
    nodes = model.graph.node
    init = {v.name: numpy_helper.to_array(v) for v in model.graph.initializer}
    producers = {out: n for n in nodes for out in n.output}
    issues = []
    scales, qdtypes, weighted = Counter(), Counter(), Counter()
    for node in nodes:
        if node.domain not in ("", "ai.onnx"): issues.append(f"unsupported domain: {node.domain}")
        if node.op_type not in SUPPORTED_OPS: issues.append(f"unsupported op: {node.op_type}")
        if node.op_type in ("QuantizeLinear", "DequantizeLinear"):
            if len(node.input) < 3 or node.input[1] not in init or node.input[2] not in init:
                issues.append(f"QDQ scale/zero must be static: {node.name}")
                continue
            scale, zero = init[node.input[1]], init[node.input[2]]
            scales[str(tuple(scale.shape))] += 1
            qdtypes[str(zero.dtype)] += 1
            if zero.dtype != np.int16 or np.any(zero): issues.append(f"not symmetric INT16: {node.name}")
            if np.any(scale <= 0) or not np.all(np.isfinite(scale)): issues.append(f"invalid scale: {node.name}")
        if node.op_type in ("MatMul", "Conv", "Gemm"):
            weighted[node.op_type] += 1
            for name in node.input[:2]:
                source = producers.get(name)
                if source is None or source.op_type != "DequantizeLinear":
                    issues.append(f"weighted input lacks immediate DQ: {node.name}/{name}")
    layers = sorted({int(m.group(1)) for n in nodes for m in [re.search(r"(?:encoders|decoders)\.(\d+)", n.name)] if m})
    def port(v):
        return {"name": v.name, "dtype": onnx.TensorProto.DataType.Name(v.type.tensor_type.elem_type),
                "shape": [d.dim_value if d.HasField("dim_value") else d.dim_param for d in v.type.tensor_type.shape.dim]}
    return {"path": str(path.resolve()), "sha256": sha256_file(path), "file_bytes": path.stat().st_size,
            "graph_name": model.graph.name, "ir_version": model.ir_version,
            "opsets": {o.domain or "ai.onnx": o.version for o in model.opset_import},
            "nodes": len(nodes), "operators": dict(sorted(Counter(n.op_type for n in nodes).items())),
            "weighted_operators": dict(weighted), "layer_indices": layers,
            "initializer_elements": sum(a.size for a in init.values()),
            "initializer_bytes": sum(a.nbytes for a in init.values()),
            "qdq_scale_shapes": dict(scales), "qdq_zero_dtypes": dict(qdtypes),
            "inputs": [port(v) for v in model.graph.input], "outputs": [port(v) for v in model.graph.output],
            "unsupported_or_invalid": sorted(set(issues))}


def audit_model_a(model_dir=DEFAULT_MODEL_DIR):
    models = {name: audit_model(Path(model_dir) / (name + ".onnx")) for name in ("encoder", "decoder")}
    issues = [f"{name}: {issue}" for name, item in models.items() for issue in item["unsupported_or_invalid"]]
    if models["encoder"]["layer_indices"] != list(range(12)): issues.append("encoder must retain all 12 original layers")
    if models["decoder"]["layer_indices"] != list(range(6)): issues.append("decoder must retain all 6 original layers")
    for name, item in models.items():
        item["matches_original_sha256"] = item["sha256"] == ORIGINAL_SHA256[name]
        if not item["matches_original_sha256"]:
            issues.append(f"{name}: model fingerprint differs from audited original; review before execution")
    return {"schema": "asr-model-a-manifest-v1", "model_modified": False, "ctc_included": False,
            "target": "original 12-layer encoder + 6-layer decoder, D=512, vocab=5000",
            "models": models, "issues": issues, "coverage_pass": not issues,
            "hardware_executed": False}
