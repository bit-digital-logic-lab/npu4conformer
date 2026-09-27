"""Bounded physical-board baseline, never an end-to-end inference claim."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
import numpy as np
from host.transport import SerialBackend, open_link


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', required=True)
    p.add_argument('--baud', type=int, default=115200)
    p.add_argument('--report', type=Path, required=True)
    args = p.parse_args()
    report = dict(timestamp_utc=datetime.now(timezone.utc).isoformat(),
                  physical_fpga_executed=False, port=args.port, baud=args.baud,
                  scope='Bounded UART/FP32/INT16 measurements; not full inference',
                  tests=[], passed=False)
    backend = None
    try:
        backend = SerialBackend(open_link(args.port, args.baud, 5.0))
        report['physical_fpga_executed'] = True
        def measure(name, count, action, useful_bytes=0):
            sent, received = backend.link.bytes_sent, backend.link.bytes_received
            start = time.perf_counter()
            for _ in range(count):
                action()
            elapsed = time.perf_counter()-start
            item = dict(name=name, repetitions=count, elapsed_seconds=elapsed,
                        seconds_per_repetition=elapsed/count,
                        sent_bytes=backend.link.bytes_sent-sent,
                        received_bytes=backend.link.bytes_received-received,
                        useful_bytes_per_second=useful_bytes*count/elapsed,
                        passed=True)
            report['tests'].append(item)
            print(json.dumps(item), flush=True)
        measure('ping_rtt', 32, backend.link.ping)
        def scalar():
            if backend._bits(0, 0x3f800000, 0x40000000) != 0x40400000:
                raise AssertionError('FP32 1+2 != 3')
        measure('scalar_add_rtt', 64, scalar)
        rng = np.random.default_rng(20260922)
        a = rng.integers(-32768, 32768, 8192, dtype=np.int16)
        b = rng.integers(-32768, 32768, 8192, dtype=np.int16)
        expected = int(np.dot(a.astype(np.int64), b.astype(np.int64)))
        def dot():
            if backend.dot_i16(a, b) != expected:
                raise AssertionError('Random full-range signed INT16 dot mismatch')
        measure('dot8192', 3, dot, useful_bytes=a.nbytes+b.nbytes)
        report['passed'] = True
    except Exception as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
    finally:
        if backend is not None:
            report['backend'] = backend.report()
            backend.close()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(f"pass={report['passed']} report={args.report}", flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
