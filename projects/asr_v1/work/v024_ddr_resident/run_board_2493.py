"""Program the signed volatile image, then capture and independently check DDR output."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PHYSICAL = HERE / "physical_native/physical"
BIN = Path("C:/Academic_Application/Vivado/2025.2/Vivado/bin")
sys.path[:0] = [str(HERE / "operator_ui"),
               str(ROOT / "work/v024_deploy_20261101/recovery_20261102")]
from board_adapter import _board_lock
from run_partitioned_board_once import ensure_server


def sha(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def command(tool, script, args, out, name, timeout):
    with (out / (name + ".log")).open("xb") as log:
        process = subprocess.Popen(
            ["cmd.exe", "/d", "/c", str(BIN / tool), *script, *map(str, args)],
            cwd=out, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            code = process.wait(timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           capture_output=True, check=False, timeout=20)
            process.wait(timeout=20)
            raise
    raw = (out / (name + ".log")).read_text(errors="replace")
    if code:
        raise RuntimeError(f"{name} returned {code}. See {out / (name + '.log')}")
    return raw


def main():
    receipt = json.loads((PHYSICAL / "reports/state.json").read_text())
    bit = PHYSICAL / "build/candidate_A51A2493.bit"
    if receipt.get("stage") != "PASS" or receipt["bit_sha256"] != sha(bit):
        raise RuntimeError("Physical implementation has not passed for this exact bitstream.")
    if receipt["input_sha256"] != sha(HERE / "physical_native/build/ps_ddr_synth.dcp"):
        raise RuntimeError("Synthesis input changed.")
    if receipt["script_sha256"] != sha(PHYSICAL / "implement.tcl"):
        raise RuntimeError("Implementation script changed after signing.")
    if "All user specified timing constraints are met." not in (PHYSICAL / "reports/timing.rpt").read_text():
        raise RuntimeError("Post-route timing did not pass.")
    out = HERE / "board_test/runs" / datetime.now().strftime("%Y%m%d_%H%M%S")
    out.mkdir(parents=True, exist_ok=False)
    result = dict(stage="STARTING", bit_sha256=sha(bit), out=str(out))

    def stage(value):
        result["stage"] = value
        result["updated"] = datetime.now().astimezone().isoformat()
        (out / "deployment.json").write_text(json.dumps(result, indent=2))
        print(value, out, flush=True)

    try:
        with _board_lock():
            ensure_server("hw_server", 3121)
            ensure_server("cs_server", 3042)
            stage("PROGRAMMING")
            raw = command("vivado.bat", ["-mode", "batch", "-nojournal", "-log",
                          str(out / "program_vivado.log"), "-source", str(HERE / "program_resident.tcl"), "-tclargs"],
                          [bit, out], out, "program", 150)
            if "PROGRAM_2493_PASS" not in raw:
                raise RuntimeError("Vivado did not confirm the live new image.")
            stage("MEASURING_FIRST_GRAPH")
            wrapper = out / "capture.tcl"
            library = (HERE / "board_test/capture_ddr.tcl").as_posix()
            run = (out / "functional").as_posix()
            identity = (out / "identity.txt").as_posix()
            wrapper.write_text(
                'connect -url tcp:127.0.0.1:3121\n'
                'if {[catch {\n'
                f'    source {{{library}}}\n'
                f'    resident_board::run {{{run}}} {{{identity}}} {{{Path(sys.executable).as_posix()}}} 1\n'
                '} message options]} {\n'
                '    puts stderr [dict get $options -errorinfo]\n'
                '    catch {disconnect}\n'
                '    exit 1\n'
                '}\ndisconnect\nexit\n', encoding="utf-8")
            raw = command("xsdb.bat", [str(wrapper)], [], out, "capture", 240)
            checked = json.loads((out / "functional/verification.json").read_text())
            if not checked.get("passed") or "DDR_COLD_GRAPH_PASS" not in raw:
                raise RuntimeError("Cold first graph did not pass the independent verifier.")
            result["verification"] = checked
            stage("PASS")
    except BaseException as exc:
        result["error"] = str(exc)
        stage("FAILED")
        raise


if __name__ == "__main__":
    main()
