"""Bounded smoke checks against the real RTL simulator or an explicit FPGA port.

This checks arithmetic and the command path, not full Encoder/Decoder inference.
Default mode starts Icarus only; it never opens a physical serial connection.
Examples from the ASR directory:
  python -m host.smoke --report reports/smoke_rtl.json
  python -m host.smoke --backend hardware --port COM5 --report reports/smoke_board.json
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import time

import numpy as np
import onnx

from host.integer_reference import requantize
from host.onnx_executor import OnnxExecutor, SoftwareBackend, Tensor
from host.rtl_sim import RtlSimulationBackend, compile_bridge
from host.transport import SerialBackend, open_link


def compare(name, actual, reference, *, atol=0.0, rtol=0.0, note=""):
    actual, reference = np.asarray(actual), np.asarray(reference)
    same_shape = actual.shape == reference.shape
    if same_shape:
        aa, rr = actual.astype(np.float64), reference.astype(np.float64)
        finite = bool(np.all(np.isfinite(aa)) and np.all(np.isfinite(rr)))
        if finite:
            delta = np.abs(aa - rr)
            error = float(np.max(delta)) if delta.size else 0.0
            relative = float(np.max(delta / np.maximum(np.abs(rr), 1e-30))) if delta.size else 0.0
            passed = bool(np.all(delta <= atol + rtol * np.abs(rr)))
        else:
            passed, error, relative = False, None, None
    else:
        finite, passed, error, relative = False, False, None, None
    return {
        "name": name, "pass": passed, "shape": list(actual.shape),
        "reference_shape": list(reference.shape), "all_finite": finite,
        "max_absolute_error": error, "max_relative_error": relative,
        "absolute_tolerance": atol, "relative_tolerance": rtol,
        "acceptance": "abs(actual-reference) <= atol + rtol*abs(reference), every element",
        "note": note,
    }


def executor(backend):
    # Only _eval is called. An empty opset-21 graph makes the executor contract
    # explicit and avoids loading, modifying, or writing the original model.
    graph = onnx.helper.make_graph([], "bounded_arithmetic_smoke", [], [])
    model = onnx.helper.make_model(graph, opset_imports=[onnx.helper.make_opsetid("", 21)])
    return OnnxExecutor(model, backend, fold_constants=False)


def evaluate(engine, backend, op, values, **attributes):
    node = onnx.helper.make_node(op, [f"x{i}" for i in range(len(values))], ["y"], **attributes)
    args = [value if isinstance(value, Tensor) else Tensor(np.asarray(value)) for value in values]
    result = engine._eval(node, args, backend)
    return result[0] if isinstance(result, (tuple, list)) else result


def checks(backend, results):
    reference = SoftwareBackend()
    target_executor, reference_executor = executor(backend), executor(reference)

    def run(name, action):
        started = time.perf_counter()
        try:
            item = action()
        except Exception as exc:
            results.append({"name": name, "pass": False, "error": f"{type(exc).__name__}: {exc}",
                            "elapsed_seconds": time.perf_counter() - started})
            raise
        item["elapsed_seconds"] = time.perf_counter() - started
        results.append(item)
        print(f"{'PASS' if item['pass'] else 'FAIL'} {name}: max_abs={item['max_absolute_error']} atol={item['absolute_tolerance']} rtol={item['relative_tolerance']}", flush=True)

    def node_check(name, op, values, atol=0.0, rtol=0.0, **attributes):
        actual = evaluate(target_executor, backend, op, values, **attributes).data
        expected = evaluate(reference_executor, reference, op, values, **attributes).data
        return compare(name, actual, expected, atol=atol, rtol=rtol, note="Same scheduler operation; independent NumPy SoftwareBackend arithmetic reference")

    run("ping", lambda: compare("ping", np.frombuffer(backend.link.ping(), np.uint8), np.frombuffer(b"ASR1\x01\x00\x00\x00", np.uint8), note="Binary protocol magic and version; no model inference"))
    a = np.full(9728, -32768, np.int16)
    b = np.full(9728, -32768, np.int16)
    run("dot_i16_k9728", lambda: compare("dot_i16_k9728", backend.dot_i16(a, b), reference.dot_i16(a, b), note="38 packets, 48-bit accumulation; expected 10445360463872 exactly"))

    def integer_requant_check():
        # Byte layout: signed48 acc, signed32 multiplier, u8 shift, signed48 bias.
        cases = [(value, 1, 1, 0) for value in (-7, -5, -3, -1, 1, 3, 5, 7)]
        cases += [(32768, 1, 0, 0), (-32769, 1, 0, 0), (1, 3, 1, 2),
                  (-(1 << 47), -(1 << 31), 79, -(1 << 47)), ((1 << 47)-1, -(1 << 31), 127, (1 << 47)-1)]
        actual, expected = [], []
        for acc, multiplier, shift, bias in cases:
            payload = acc.to_bytes(6, "little", signed=True) + struct.pack("<iB", multiplier, shift) + bias.to_bytes(6, "little", signed=True)
            response = backend.link.request(4, payload)
            if len(response) != 2:
                raise RuntimeError("requant reply must have two bytes")
            actual.append(int.from_bytes(response, "little", signed=True))
            expected.append(requantize(acc, multiplier, shift, bias))
        return compare("requant_ties_saturation", actual, expected, note="Independent arbitrary-precision integer reference; includes negative ties, saturation, wide pre-add, shift127")

    run("requant_ties_saturation", integer_requant_check)
    quant_input = np.array([-40000, -32768.5, -32767.5, -3.5, -2.5, -1.5, -.5, .5, 1.5, 2.5, 3.5, 32766.5, 32767.5, 40000], np.float32)
    zero = np.array(0, np.int16)
    run("quantize_ties_saturation", lambda: node_check("quantize_ties_saturation", "QuantizeLinear", [quant_input, np.array(1, np.float32), zero]))

    def qdq_check():
        values = np.array([[-4.1875, -1.3125, -.0625, .0625, .3125, 4.1875]], np.float32)
        scale = np.array(.125, np.float32)
        actual_q = evaluate(target_executor, backend, "QuantizeLinear", [values, scale, zero])
        actual = evaluate(target_executor, backend, "DequantizeLinear", [actual_q, scale, zero]).data
        expected_q = evaluate(reference_executor, reference, "QuantizeLinear", [values, scale, zero])
        expected = evaluate(reference_executor, reference, "DequantizeLinear", [expected_q, scale, zero]).data
        return compare("qdq", actual, expected, note="QuantizeLinear then DequantizeLinear both execute through selected backend")

    run("qdq", qdq_check)

    def matmul_check():
        qa = np.array([[-32768, -3, 7, 1024, 32767], [125, 25, -35, -500, 13]], np.int16)
        qb = np.array([[32767, -1, 4], [-3, 9, -17], [65, -11, 1023], [13, 17, -19], [-123, 333, 555]], np.int16)
        scales = [np.array(.125, np.float32), np.array(.0625, np.float32)]
        selected = [evaluate(target_executor, backend, "DequantizeLinear", [q, s, zero]) for q, s in zip((qa, qb), scales)]
        software = [evaluate(reference_executor, reference, "DequantizeLinear", [q, s, zero]) for q, s in zip((qa, qb), scales)]
        actual = evaluate(target_executor, backend, "MatMul", selected).data
        expected = evaluate(reference_executor, reference, "MatMul", software).data
        return compare("matmul_int16_qdq", actual, expected, note="2x5 by 5x3, signed INT16 DQ provenance and 48-bit dot products")

    run("matmul_int16_qdq", matmul_check)
    softmax_input = np.array([[-8, -2.5, -.25, 0, 1.75, 3.5, 7], [0, 0, 0, 0, 0, 0, 0]], np.float32)
    run("softmax", lambda: node_check("softmax", "Softmax", [softmax_input], atol=3e-6, rtol=2e-5, axis=-1))
    rng = np.random.default_rng(20260922)
    ln_input = (rng.standard_normal((1, 512)) * 1.5 + 2).astype(np.float32)
    gamma = np.linspace(.5, 1.5, 512, dtype=np.float32)
    beta = np.linspace(-.2, .3, 512, dtype=np.float32)
    run("layernorm512", lambda: node_check("layernorm512", "LayerNormalization", [ln_input, gamma, beta], atol=1e-5, rtol=1e-5, axis=-1, epsilon=1e-12))
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--backend", choices=("rtl-simulation", "hardware"), default="rtl-simulation")
    parser.add_argument("--port", help="Explicit physical serial port; requires --backend hardware")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--iverilog", help="Icarus executable; default ASR_IVERILOG or PATH")
    parser.add_argument("--vvp", help="vvp executable; default ASR_VVP or PATH")
    parser.add_argument("--simulation-executable", type=Path, help="Already compiled tb_asr_stdio.vvp")
    parser.add_argument("--simulation-build", type=Path, help="Directory for compiled simulation bridge")
    parser.add_argument("--report", type=Path, help="Optional JSON report path")
    args = parser.parse_args(argv)
    if args.backend == "hardware" and not args.port:
        parser.error("--backend hardware requires an explicit --port COMx")
    if args.backend != "hardware" and args.port:
        parser.error("--port requires explicit --backend hardware; simulation never connects to serial ports")
    if args.baud <= 0 or args.timeout <= 0:
        parser.error("baud and timeout must be positive")

    started = time.perf_counter()
    backend = None
    report = {
        "schema_version": 1, "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "backend": args.backend, "physical_fpga_executed": False, "rtl_simulated": False,
        "scope": "Bounded arithmetic/transport smoke only; not complete Encoder/Decoder inference or WER validation",
        "reference": "Independent NumPy SoftwareBackend plus arbitrary-precision integer requant reference",
        "tests": [], "pass": False,
    }
    try:
        if args.backend == "hardware":
            backend = SerialBackend(open_link(args.port, args.baud, args.timeout))
            report["port"], report["baud"] = args.port, args.baud
        else:
            executable = args.simulation_executable or compile_bridge(args.simulation_build, args.iverilog)
            backend = RtlSimulationBackend(executable=executable, vvp=args.vvp, timeout=args.timeout)
            report["simulation_executable"] = str(executable)
        report["physical_fpga_executed"] = bool(backend.hardware_executed)
        report["rtl_simulated"] = args.backend == "rtl-simulation"
        report["notice"] = "Physical FPGA commands executed; only this smoke scope was checked" if backend.hardware_executed else "Synthesizable RTL executed in Icarus; no physical FPGA was connected or executed"
        checks(backend, report["tests"])
        report["pass"] = all(item["pass"] for item in report["tests"])
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
        print(f"FAIL {report['error']}", flush=True)
    finally:
        if backend is not None:
            try:
                report["backend_report"] = backend.report()
            finally:
                try:
                    backend.close()
                except Exception as exc:
                    report["cleanup_error"] = f"{type(exc).__name__}: {exc}"
                    report["pass"] = False
        report["elapsed_seconds"] = time.perf_counter() - started
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
            print(f"Report: {args.report}")
        print(f"{'PASS' if report['pass'] else 'FAIL'} backend={args.backend} physical_fpga_executed={report['physical_fpga_executed']} rtl_simulated={report['rtl_simulated']}")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
