"""Real RTL command-engine backend via a persistent Icarus process, NOT a board.

Uses exactly the same binary framing and SerialBackend arithmetic dispatch.
Only the UART bit timing is bypassed here; tb_asr_uart tests that separately.
"""
from pathlib import Path
from queue import Queue, Empty
from threading import Thread
import subprocess
import os
from .transport import Link, SerialBackend, ProtocolError

ROOT = Path(__file__).resolve().parents[1]

def compile_bridge(work=None, iverilog=None):
    iverilog = iverilog or os.environ.get('ASR_IVERILOG', 'iverilog')
    work = (Path(work) if work else ROOT / 'build' / 'tests' / 'stdio').resolve()
    work.mkdir(parents=True, exist_ok=True)
    executable = work / 'asr_stdio.vvp'
    subprocess.run([iverilog, '-g2012', '-s', 'tb_asr_stdio', '-o', str(executable),
                    *map(str, sorted((ROOT / 'rtl').glob('*.sv'))),
                    str(ROOT / 'sim' / 'tb_asr_stdio.sv')], check=True, cwd=work)
    return executable

class VvpStream:
    def __init__(self, executable, vvp=None, timeout=30.0):
        vvp = vvp or os.environ.get('ASR_VVP', 'vvp')
        self.timeout, self.pending = timeout, bytearray()
        self.lines, self.diagnostics = Queue(), []
        self.process = subprocess.Popen([vvp, str(executable)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, bufsize=1)
        def pump():
            for line in self.process.stdout:
                self.lines.put(line)
            self.lines.put(None)
        self.reader = Thread(target=pump, daemon=True)
        self.reader.start()

    def write(self, frame):
        if self.pending:
            raise ProtocolError('unread simulated response')
        self.process.stdin.write(str(len(frame)) + ' ' + frame.hex(' ') + '\n')
        self.process.stdin.flush()
        while True:
            try:
                line = self.lines.get(timeout=self.timeout)
            except Empty as exc:
                raise TimeoutError('RTL simulation bridge timeout') from exc
            if line is None:
                raise ProtocolError('RTL simulator stopped: ' + ''.join(self.diagnostics[-10:]))
            if not line.startswith('R '):
                self.diagnostics.append(line)
                if len(self.diagnostics) > 50:
                    self.diagnostics.pop(0)
                continue
            fields = line.split()
            data = bytes.fromhex(' '.join(fields[2:]))
            if len(data) != int(fields[1]):
                raise ProtocolError('bad RTL bridge line')
            self.pending.extend(data)
            return len(frame)

    def read(self, count):
        result = bytes(self.pending[:count])
        del self.pending[:count]
        return result

    def close(self):
        if self.process.stdin and not self.process.stdin.closed:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        self.reader.join(timeout=2)
        self.process.stdout.close()

class RtlSimulationBackend(SerialBackend):
    name = 'rtl-simulation'
    hardware_executed = False

    def __init__(self, executable=None, vvp=None, timeout=30.0):
        self.simulator = VvpStream(executable or compile_bridge(), vvp, timeout)
        super().__init__(Link(self.simulator, timeout))
        try:
            self.link.ping()
        except BaseException:
            self.close()
            raise

    def report(self):
        result = super().report()
        result.update(hardware_executed=False, rtl_simulated=True,
                      notice='Synthesizable RTL simulated in Icarus; no physical FPGA execution')
        return result
