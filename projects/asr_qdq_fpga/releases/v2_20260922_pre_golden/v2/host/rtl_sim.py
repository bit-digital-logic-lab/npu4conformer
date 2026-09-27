"""Real V2 RTL simulator transport, never physical FPGA evidence."""
from pathlib import Path
import os
import subprocess
from host.rtl_sim import VvpStream
from host.transport import Link
from .transport import BufferedBackend

ROOT = Path(__file__).resolve().parents[2]
FROZEN = ROOT / "releases" / "v1_20260922_board_verified"


def compile_bridge(work=None, iverilog=None):
    iverilog = iverilog or os.environ.get("ASR_IVERILOG", "iverilog")
    work = (Path(work) if work else ROOT / "v2" / "build" / "stdio").resolve()
    work.mkdir(parents=True, exist_ok=True)
    executable = work / "asr_stdio_v2.vvp"
    sources = sorted((FROZEN / "rtl").glob("*.sv")) + sorted((ROOT / "v2" / "rtl").glob("*.sv"))
    subprocess.run([iverilog, "-g2012", "-s", "tb_asr_stdio_v2", "-o", str(executable),
                    *map(str, sources), str(ROOT / "v2" / "sim" / "tb_asr_stdio_v2.sv")],
                   check=True, cwd=work)
    return executable


class RtlSimulationBackend(BufferedBackend):
    name = "rtl-simulation-v2"
    hardware_executed = False

    def __init__(self, executable=None, vvp=None, timeout=60.0):
        self.simulator = VvpStream(executable or compile_bridge(), vvp, timeout)
        try:
            super().__init__(Link(self.simulator, timeout))
            self.link.ping()
        except BaseException:
            self.simulator.close()
            raise

    def report(self):
        result = super().report()
        result.update(hardware_executed=False, physical_fpga_executed=False, rtl_simulated=True,
                      notice="Synthesizable V2 RTL executed in Icarus; no physical FPGA connection")
        return result
