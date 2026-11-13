"""Commission the fixed AXU15EGB once; publish pointers only after real readback.

Explicit invocation is required. Import and --check never access hardware.
Requires a power-reset board with APU in reset; no automatic reset of active CPUs.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(HERE), str(HERE / "native_ps"), str(ROOT / "tools")]
import run_board_2493 as deploy
from verify_receipt import verify
from restore_assets import audit, sha


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix(".part")
    pending.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    pending.replace(path)


def preflight():
    checked = audit(ROOT)
    if not checked["passed"]:
        raise ValueError("先恢复 Release 附件：" + json.dumps(checked, ensure_ascii=False))
    deploy.validate_image()
    for tool in ("vivado.bat", "xsdb.bat", "hw_server.bat", "cs_server.bat"):
        if not (deploy.BIN / tool).is_file():
            raise ValueError(f"找不到 {tool}；请将 ASR_VIVADO_BIN 配置为 Vivado 2025.2 的 bin 目录。")
    return dict(assets=checked, vivado_bin=str(deploy.BIN), hardware_access=False)


def activate(qualification, boot, weights):
    """Recompute checks from this run's raw files, never trust a copied passed flag."""
    sys.path.insert(0, str(HERE / "board_test"))
    from verify_ddr import verify as verify_graph
    cold = verify_graph(qualification.parent)
    if cold["dump_words"] != 8192 or cold["usr_access"] != "0xA51A2493":
        raise ValueError("Cold graph identity or output length differs")
    for mode in ("boot", "selftest", "pltest"):
        result = verify(mode, boot / mode)
        if result["mailbox"]["capabilities"] != 7:
            raise ValueError("Expected complete encoder firmware")
        write_json(boot / mode / "verified.json", result)
    model = json.loads((HERE / "native_model/manifest.json").read_text(encoding="utf-8"))
    source = HERE / "native_model/weights.bin"
    readback = weights / "weights_readback.bin"
    if (source.stat().st_size != model["image_bytes"] or readback.stat().st_size != model["image_bytes"] or
            sha(source) != model["image_sha256"] or sha(readback) != model["image_sha256"]):
        raise ValueError("DDR weight full readback mismatch")
    write_json(qualification, cold)
    receipt = dict(passed=True, source_sha256=model["image_sha256"], board_readback_sha256=sha(readback),
                   bytes=model["image_bytes"], address="0x10100000", runtime_boot=boot.name,
                   image="0xA51A2493", run=str(weights.resolve()), utc=datetime.now(timezone.utc).isoformat())
    # Only the hardware runner below calls this after all tools return successfully.
    write_json(HERE / "board_test/active_qualification.json", {"qualification": str(qualification.resolve())})
    write_json(HERE / "native_model/ACTIVE_BOARD_WEIGHTS.json", receipt)
    return dict(cold_graph=cold, weights=receipt)


def run():
    preflight()
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:8]
    output = HERE / "cold_start_runs" / run_id
    output.mkdir(parents=True, exist_ok=False)
    boot = HERE / "native_ps/runs" / run_id
    boot.mkdir(parents=True, exist_ok=False)
    weights = HERE / "native_model/board_loads" / run_id
    pointers = [HERE / "board_test/active_qualification.json", HERE / "native_model/ACTIVE_BOARD_WEIGHTS.json"]
    try:
        with deploy._board_lock():
            # Preserve old files but invalidate their active names BEFORE touching the board.
            for pointer in pointers:
                if pointer.exists():
                    pointer.rename(pointer.with_name(pointer.name + ".stale." + run_id))
            deploy.ensure_server("hw_server", 3121)
            deploy.ensure_server("cs_server", 3042)
            raw = deploy.command("xsdb.bat", [str(HERE / "prepare_ddr.tcl")], [output], output, "prepare_ddr", 180)
            if "PS_DDR_INITIALIZATION_PASS" not in raw:
                raise RuntimeError("PS DDR initialization not confirmed")
            qualification = deploy.run(output / "board", locked=True, cold_boot=True)
            for mode in ("boot", "selftest", "pltest"):
                args = [mode, boot / mode]
                if mode == "boot":
                    args.append(HERE / "native_ps/build/encoder.elf")
                deploy.command("xsdb.bat", [str(HERE / "native_ps/run_xsdb.tcl")], args,
                               output, mode, 180)
                result = verify(mode, boot / mode)
                if result["mailbox"]["capabilities"] != 7:
                    raise ValueError("ELF is not the complete encoder")
                write_json(boot / mode / "verified.json", result)
            deploy.command("xsdb.bat", [str(HERE / "native_model/load_weights.tcl")],
                           [HERE / "native_model/weights.bin", weights], output, "weights", 1800)
            result = activate(qualification, boot, weights)
            write_json(output / "result.json", dict(passed=True, **result))
    except BaseException as exc:
        write_json(output / "result.json", dict(passed=False, error=str(exc)))
        raise
    print("COLD_START_PASS", output, flush=True)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="offline files/tools check only")
    args = parser.parse_args()
    if args.check:
        print(json.dumps(preflight(), indent=2))
    else:
        run()
