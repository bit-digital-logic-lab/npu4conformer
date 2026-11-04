"""Prepare a fresh measurement and verify its saved XSDB/DDR bytes offline."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import secrets
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEPLOY = HERE.parent.parent / "v024_deploy_20261101"
sys.path.insert(0, str(DEPLOY / "host"))
import verify_v024 as frozen

PROBES = ("arena", "param", "extended")
IDENTITY = {"serial": "210512180081", "part": "xczu15", "usr_access": "0xA51A2493"}
PERIOD_NS = 20.625


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def identity(path):
    data = dict(line.split("=", 1) for line in path.read_text(encoding="utf-8-sig").splitlines() if "=" in line)
    for key, value in IDENTITY.items():
        require(data.get(key, "").lower() == value.lower(), f"programming identity mismatch: {key}")


def prepare(run, source):
    identity(source)
    require(-5 <= time.time() - source.stat().st_mtime <= 3600, "live programming identity must be recent")
    _, blobs, _ = frozen.validate_inputs(frozen.CORE)
    run.mkdir(exist_ok=False, parents=True)
    (run / "program_identity.txt").write_bytes(source.read_bytes())
    for name, content in blobs.items():
        (run / (name + ".bin")).write_bytes(content)
    for name in PROBES:
        (run / ("probe_" + name + ".bin")).write_bytes(secrets.token_bytes(64))
    print("DDR_ACQUISITION_PREPARED", run)


def verify(run):
    identity(run / "program_identity.txt")
    ref, blobs, _ = frozen.validate_inputs(frozen.CORE)
    receipt = {}
    for row in (run / "csr.tsv").read_text(encoding="ascii").splitlines():
        key, value = row.split("\t")
        require(key not in receipt, f"duplicate hardware observation: {key}")
        receipt[key] = int(value, 0)
    expected = {k: v for k, v in frozen.EXPECTED_TERMINAL.items() if k != "calibration_pass"}
    expected.update(cold_release=0, cold_completed=0, cold_cycles_low=0, cold_cycles_high=0,
                    cold_rd=0, cold_wr=0, cold_b=0, prestart_status=0, start_count=1,
                    xsdb_cable_serial=int(IDENTITY["serial"]))
    for key, val in expected.items():
        require(receipt.get(key) == val, f"{key}: expected {val}, got {receipt.get(key)}")
    require(receipt["ddrc_stat"] & 0xF == 1, "DDR controller not in normal operation")
    require(receipt["pl0_ref"] & 0x013F3F07 == 0x01011602, "unexpected PL0 clock register")
    require(receipt["cold_status"] & 0x0F == 0, "busy or faulted before first START")
    require((receipt["board_status"] & ~2) == 0x30 and 0 <= receipt["last_node"] < 7,
            "invalid terminal board status or node")
    cycles = receipt["cycles_low"] | (receipt["cycles_high"] << 32)
    require(cycles > 0 and cycles == (receipt["csr_cycles_low"] | (receipt["csr_cycles_high"] << 32)),
            "cycle counters disagree or are zero")
    for name in PROBES:
        written = (run / f"probe_{name}.bin").read_bytes()
        require(len(written) == 64 and written == (run / f"probe_{name}_raw.bin").read_bytes(),
                f"DDR address separation failed: {name}")
        require(receipt.get(f"probe_{name}_scalar") == int.from_bytes(written[:4], "little"),
                f"single word PS/DAP readback mismatch: {name}")
    for name, source in blobs.items():
        require((run / f"{name}.bin").read_bytes() == source, f"altered frozen {name} input")
        require((run / f"{name}_raw.bin").read_bytes() == source, f"input readback differs: {name}")
    raw = (run / "output_raw.bin").read_bytes()
    results = frozen.compare_output(raw, ref, blobs["arena"])
    initial = blobs["arena"][0x4000:0xc000]
    changed = {}
    for name, begin, end in (("a16", 0, 512), ("div", 1536, 2560), ("sqrt", 2560, 3584), ("copy", 3584, 4096)):
        changed[name] = sum(raw[i:i + 4] != initial[i:i + 4] for i in range(begin * 4, end * 4, 4))
        require(changed[name] > 0, f"{name} produced no new output")
    results.update(passed=True, scope="AXU15EGB XSDB PSU/DAP, first graph through HP0 DDR",
                   utc=datetime.now(timezone.utc).isoformat(), **IDENTITY, cycles=cycles,
                   nominal_clock_period_ns=PERIOD_NS, nominal_ms=cycles * PERIOD_NS / 1e6,
                   nominal_clock_source="implemented clk_pl_0 constraint; PL0_REF_CTRL checked on target",
                   graph_starts=1, ddr_probe_addresses=["0x0400f000", "0x1000f000", "0x1004f000"],
                   ddr_probe_bytes_per_address=64, output_sha256=hashlib.sha256(raw).hexdigest(),
                   changed_words_from_prestart=changed, hardware_registers=receipt)
    print(f"DDR_COLD_GRAPH_PASS cycles={cycles} nominal_ms={results['nominal_ms']:.9f}")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "verify"])
    parser.add_argument("run", type=Path)
    parser.add_argument("identity", nargs="?", type=Path)
    args = parser.parse_args()
    if args.action == "prepare":
        if not args.identity:
            parser.error("prepare needs the live programming identity file")
        prepare(args.run, args.identity)
    else:
        try:
            result = verify(args.run)
        except (OSError, ValueError, KeyError) as exc:
            (args.run / "verification.json").write_text(json.dumps({"passed": False, "error": str(exc)}, indent=2))
            raise
        (args.run / "verification.json").write_text(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
