"""Read-only model execution profile and UART wire-time lower bound.

Run from the ASR project root:
    python -B -m host.profile_model --report reports/model_a_uart_estimate.json

This executes the explicit NumPy software reference, NEVER connects a board,
and predicts the scalar/DOT expansion of protocol version 1. Time estimates
exclude FPGA execution, USB buffering, OS/host overhead, stop-and-wait latency,
and errors. Results are neither hardware measurements nor RTL acceptance.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import time
import numpy as np

from .model_a import run_case
from .model_manifest import DEFAULT_MODEL_DIR, DEFAULT_CASE_DIR, audit_model_a
from .onnx_executor import ExecutionError, OnnxExecutor, SoftwareBackend


CONTROL_OPS = frozenset({"Where", "Equal", "Less", "LessOrEqual", "Greater",
                         "GreaterOrEqual", "Not", "And", "Or", "Cast", "Range"})
COMPARISONS = frozenset({"Equal", "Less", "LessOrEqual", "Greater", "GreaterOrEqual"})
ARITHMETIC = frozenset({"Add", "Sub", "Mul", "Div", "Min", "Max",
                        "ReduceSum", "ReduceMean", "ReduceMax"})


def profile_model(model_dir=DEFAULT_MODEL_DIR, case_dir=DEFAULT_CASE_DIR):
    """Profile one actual full chain; patching is in-process and restored."""
    manifest = audit_model_a(model_dir)
    if not manifest["coverage_pass"]:
        raise ExecutionError(str(manifest["issues"]))
    backend = SoftwareBackend()
    counts = Counter()
    control_records, violations = [], []
    original_eval = OnnxExecutor._eval
    producer_maps = {}

    def audited_eval(executor, node, args, selected_backend):
        dynamic = selected_backend is backend
        present = [arg.data for arg in args if arg is not None]
        integer_arithmetic = node.op_type in ARITHMETIC and present and all(
            np.issubdtype(value.dtype, np.integer) for value in present)
        watched = node.op_type in CONTROL_OPS or integer_arithmetic
        if dynamic and watched:
            model_key = id(executor.model)
            if model_key not in producer_maps:
                producer_maps[model_key] = {name: source for source in executor.model.graph.node for name in source.output}
            producers = producer_maps[model_key]
            entries = []
            for name, tensor in zip(node.input, args):
                if tensor is None:
                    entries.append({"name": name, "missing": True})
                    continue
                source = producers.get(name)
                entries.append({"name": name, "dtype": str(tensor.data.dtype),
                                "shape": list(tensor.data.shape),
                                "producer_op": source.op_type if source else "initializer_or_graph_input",
                                "producer_name": source.name if source else name,
                                "has_int16_qdq_provenance": tensor.q is not None,
                                "prepared_static": name in executor.static})
            record = {"node": node.name, "op": node.op_type, "inputs": entries,
                      "host_integer_arithmetic": bool(integer_arithmetic)}
            if node.op_type in COMPARISONS and any(np.issubdtype(a.dtype, np.floating) for a in present):
                violations.append({"node": node.name, "reason": "dynamic floating-point comparison would execute on host"})
            if integer_arithmetic and any(a.dtype.itemsize < 4 for a in present):
                violations.append({"node": node.name, "reason": "quantized small-integer neural arithmetic would execute on host"})
            if node.op_type == "Where" and (not present or present[0].dtype != np.dtype(bool)):
                violations.append({"node": node.name, "reason": "Where selector is not a Boolean mask"})
            control_records.append(record)
        output = original_eval(executor, node, args, selected_backend)
        if dynamic and watched:
            out = output if isinstance(output, (tuple, list)) else [output]
            control_records[-1]["output_dtypes"] = [str(v.data.dtype) for v in out]
        return output

    # Keep exact SoftwareBackend type so its explicitly software-only integer
    # matrix fast path remains active. No hardware adapter is constructed.
    for name in ("binary", "unary", "quantize", "dequantize", "int48_to_float",
                 "reduce_sum", "reduce_max", "matmul_i16"):
        original = getattr(backend, name)

        def wrapped(*args, _name=name, _original=original, **kwargs):
            if _name == "matmul_i16":
                a, b = args
                batches = math.prod(np.broadcast_shapes(a.shape[:-2], b.shape[:-2]))
                outputs = batches * a.shape[-2] * b.shape[-1]
                k = a.shape[-1]
                counts["mac_pairs"] += outputs * k
                counts["dot_outputs"] += outputs
                counts["dot_packets"] += outputs * math.ceil(k / 256)
                counts["max_dot_length"] = max(counts["max_dot_length"], k)
            elif _name == "binary":
                count = math.prod(np.broadcast_shapes(np.shape(args[1]), np.shape(args[2])))
                counts["scalar_packets"] += count
                counts["scalar_from_binary"] += count
            elif _name == "unary":
                # SerialBackend Sigmoid: Abs, Neg, Exp, Add, Div, Div; Where
                # selects the positive/negative branch using stored sign bits.
                count = np.size(args[1]) * (6 if args[0] == "Sigmoid" else 1)
                counts["scalar_packets"] += count
                counts["scalar_from_unary"] += count
            elif _name in ("quantize", "dequantize"):
                # Q: divide + RNE/saturating FP32->INT16.
                # DQ: INT16->FP32 + multiply. These are RTL scalar commands.
                count = 2 * math.prod(np.broadcast_shapes(np.shape(args[0]), np.shape(args[1])))
                counts["scalar_packets"] += count
                counts["scalar_from_" + _name] += count
            elif _name == "int48_to_float":
                count = np.size(args[0])
                counts["scalar_packets"] += count
                counts["scalar_from_int48_to_float"] += count
            else:
                x, axes, _keep = args
                k = math.prod(x.shape[i] for i in axes)
                count = x.size - x.size // k
                counts["scalar_packets"] += count
                counts["scalar_from_" + _name] += count
            return _original(*args, **kwargs)

        setattr(backend, name, wrapped)

    started = time.perf_counter()
    OnnxExecutor._eval = audited_eval
    try:
        software_report, _outputs = run_case(model_dir, case_dir, backend)
    finally:
        OnnxExecutor._eval = original_eval

    # A request/reply both include 2 sync + 6 header + 2 CRC bytes.
    # DOT adds 4 bytes per pair in requests and 6 result bytes per reply.
    # SCALAR adds 8 request payload bytes and 5 response payload bytes.
    dot_bytes = 4 * counts["mac_pairs"] + 26 * counts["dot_packets"]
    scalar_bytes = 33 * counts["scalar_packets"]
    total_bytes = dot_bytes + scalar_bytes
    signatures = Counter()
    for item in control_records:
        signature = item["op"] + "(" + ",".join(v.get("dtype", "missing") for v in item["inputs"]) + ")->" + ",".join(item["output_dtypes"])
        signatures[signature] += 1
    return {
        "schema": "asr-model-a-uart-estimate-v1", "backend": "software",
        "hardware_executed": False, "rtl_acceptance": False,
        "purpose": "reproducible dynamic dtype audit and predicted protocol-v1 wire traffic",
        "model_manifest": manifest,
        "case_dir": str(Path(case_dir).resolve()),
        "feats_shape": software_report["feats_shape"], "tokens_shape": software_report["tokens_shape"],
        "profile_execution_seconds": time.perf_counter() - started,
        "decoder_uses_actual_encoder_output": True, "ctc_included": False,
        "counts": {k: int(v) for k, v in counts.items()},
        "wire_bytes": {"dot_requests_and_replies": int(dot_bytes),
                       "scalar_requests_and_replies": int(scalar_bytes),
                       "total": int(total_bytes)},
        "wire_time_lower_bounds_8n1": {
            str(baud): {"seconds": total_bytes * 10 / baud,
                        "hours": total_bytes * 10 / baud / 3600,
                        "days": total_bytes * 10 / baud / 86400}
            for baud in (115200, 921600)
        },
        "estimation_assumptions": [
            "single shared MAC, signed48 partial sum held across 256-pair DOT packets",
            "each floating-point scalar request/reply occupies 33 bytes total",
            "sum/max reductions match SerialBackend's left-to-right scalar expansion",
            "stop-and-wait prevents overlapping request/reply transmission",
            "excludes PING setup, FPGA latency, USB/OS overhead, idle gaps and retries",
            "no tile reuse or future batch-command optimization is assumed",
            "no physical serial port was opened and no FPGA was measured",
        ],
        "host_control_audit": {
            "pass": not violations, "violations": violations,
            "dynamic_dtype_signatures": dict(sorted(signatures.items())),
            "dynamic_host_control_nodes": len(control_records),
            "dynamic_float_comparison_nodes": sum(
                r["op"] in COMPARISONS and any(v.get("dtype", "").startswith("float") for v in r["inputs"])
                for r in control_records),
            "interpretation": "Boolean/integer masks, token indices and shape/address arithmetic are host control; Where moves selected values without numeric evaluation",
            "records": control_records,
        },
        "constant_preparation": {
            "encoder_static_folded_nodes": software_report["encoder_execution"]["static_folded_nodes"],
            "decoder_static_folded_nodes": software_report["decoder_execution"]["static_folded_nodes"],
            "encoder_dynamic_operator_counts": software_report["encoder_execution"]["operators"],
            "decoder_dynamic_operator_counts": software_report["decoder_execution"]["operators"],
            "explanation": "Only nodes whose entire input ancestry is constant are prepared in software, such as packed-weight DQ, weight transpose and weight QDQ. All 38 encoder Conv, 145 encoder MatMul, 84 decoder MatMul and decoder Gemm remain dynamic. Original graph/weights SHA256, layer counts, width and vocabulary stay unchanged. Constant preparation is scheduling, not model reduction.",
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    parser.add_argument("--case-dir", type=Path, default=DEFAULT_CASE_DIR)
    parser.add_argument("--report", type=Path, default=Path("reports/model_a_uart_estimate.json"))
    args = parser.parse_args(argv)
    destination = args.report.resolve()
    for protected in (args.model_dir.resolve(), args.case_dir.resolve()):
        if destination == protected or protected in destination.parents:
            raise ExecutionError("refusing to write generated report into original model/vector directories")
    report = profile_model(args.model_dir, args.case_dir)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    compact = {key: report[key] for key in ("hardware_executed", "counts", "wire_bytes", "wire_time_lower_bounds_8n1")}
    compact["dynamic_dtype_signatures"] = report["host_control_audit"]["dynamic_dtype_signatures"]
    compact["host_control_audit_pass"] = report["host_control_audit"]["pass"]
    compact["report"] = str(destination)
    print(json.dumps(compact, indent=2))
    return 0 if report["host_control_audit"]["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
