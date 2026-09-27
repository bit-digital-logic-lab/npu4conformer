"""Bounded V2 acceptance/benchmark. Simulation is the safe default.

The checks exercise the physical board only with --backend hardware --port.
They are NOT complete Encoder/Decoder inference or model-accuracy acceptance.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
from host.transport import open_link
from .transport import BufferedBackend
from .rtl_sim import RtlSimulationBackend, compile_bridge
from v2.tests.checks import checks


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("rtl-simulation", "hardware"), default="rtl-simulation")
    parser.add_argument("--port")
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--timeout", type=float, default=60.)
    parser.add_argument("--iverilog")
    parser.add_argument("--vvp")
    parser.add_argument("--simulation-executable", type=Path)
    parser.add_argument("--simulation-build", type=Path)
    parser.add_argument("--extended", action="store_true", help="Include full 31x256x64 tile and long reduction; still bounded, not inference")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(argv)
    if args.backend == "hardware" and not args.port:
        parser.error("hardware requires an explicit --port")
    if args.backend != "hardware" and args.port:
        parser.error("simulation never opens a serial port; remove --port")
    if min(args.baud, args.timeout) <= 0:
        parser.error("baud/timeout must be positive")
    started, backend = time.perf_counter(), None
    report = {"schema_version": 2, "timestamp_utc": datetime.now(timezone.utc).isoformat(),
              "backend": args.backend, "physical_fpga_executed": False, "rtl_simulated": False,
              "scope": "Bounded V2 operator and protocol acceptance only; NOT full model inference",
              "extended": args.extended, "tests": [], "pass": False}
    try:
        if args.backend == "hardware":
            link = open_link(args.port, args.baud, args.timeout)
            try:
                backend = BufferedBackend(link)
            except BaseException:
                link.stream.close()
                raise
            report.update(port=args.port, baud=args.baud)
        else:
            executable = args.simulation_executable or compile_bridge(args.simulation_build, args.iverilog)
            backend = RtlSimulationBackend(executable, args.vvp, args.timeout)
            report["simulation_executable"] = str(executable)
        report.update(physical_fpga_executed=bool(backend.hardware_executed), rtl_simulated=not backend.hardware_executed)
        checks(backend, report["tests"], extended=args.extended)
        report["pass"] = bool(report["tests"]) and all(item["pass"] for item in report["tests"])
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
        print(f"FAIL {report['error']}", flush=True)
    finally:
        if backend is not None:
            report["backend_report"] = backend.report()
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
        print(f"{'PASS' if report['pass'] else 'FAIL'} V2 physical_fpga_executed={report['physical_fpga_executed']}")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
