"""Host transport for an already commissioned, exclusive A53/PL encoder."""
import atexit
from contextlib import ExitStack
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import threading
import time
import uuid

HERE = Path(__file__).resolve().parent
MODEL = HERE.parent / "native_model"
BIN = Path("C:/Academic_Application/Vivado/2025.2/Vivado/bin")
IMAGE = "0xA51A2493"
DIGEST = "c0ce4706835a5a462c3b5efbe283a29026db188f1e2675a0588323d0d53bca19"
NBYTES = 84994048
BASE = 0x10100000
sys.path.insert(0, str(HERE.parent / "operator_ui"))
from board_adapter import _board_lock
try:
    from .verify_receipt import verify
except ImportError:
    from verify_receipt import verify


def _json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _publish(path, text):
    pending = path.with_suffix(".part")
    pending.write_text(text, encoding="utf-8")
    pending.replace(path)


def _proof(control):
    manifest = _json(MODEL / "manifest.json")
    active = _json(MODEL / "ACTIVE_BOARD_WEIGHTS.json")
    if not (active["passed"] is True and
            active["source_sha256"] == active["board_readback_sha256"] == manifest["image_sha256"] == DIGEST and
            active["bytes"] == manifest["image_bytes"] == NBYTES and int(str(active["address"]), 0) == BASE and
            active["image"].lower() == IMAGE.lower()):
        raise ValueError("板上权重整包读回记录与编码器版本不符。")
    boot = HERE / "runs" / str(active["runtime_boot"])
    for mode in ("boot", "selftest", "pltest"):
        v = _json(boot / mode / "verified.json")
        if v.get("passed") is not True or v["mailbox"]["capabilities"] != 7:
            raise ValueError("该固件启动批次缺少 A53／PL 原始验收。")
    qualification = _json(HERE.parent / "board_test" / "active_qualification.json")
    cold = _json(Path(qualification["qualification"]))
    if (cold.get("passed") is not True or cold["serial"] != "210512180081" or
            cold["usr_access"].lower() != IMAGE.lower() or cold["dump_words"] != 8192):
        raise ValueError("缺少指定板 2493 冷启动验收记录。")
    data = []
    with (MODEL / "weights.bin").open("rb") as stream:
        if stream.seek(0, 2) != NBYTES:
            raise ValueError("本地权重长度不符。")
        for offset in (0, 4, 0x1810, 0x6080, NBYTES//2, NBYTES-64):
            stream.seek(offset)
            data.append(f"{BASE+offset:#x} {int.from_bytes(stream.read(4), 'little'):#x}")
    (control / "fingerprints").write_text("\n".join(data), encoding="ascii")
    return {"image": IMAGE, "serial": cold["serial"], "runtime_boot": active["runtime_boot"],
            "model_sha256": DIGEST, "cold_verification_utc": cold["utc"], "weight_load": str(active["run"])}


class BoardEncoder:
    """start holds the shared board lock until close. Calls are serialized across threads."""
    def __init__(self):
        self._op = threading.RLock()
        self._state = "cold", "尚未连接板端编码器。"
        self._stack = self._proc = self._control = None
        self._info = {}
        self._job = self._seq = 0
        atexit.register(self.close)

    def status(self):
        state, detail = self._state
        proc = self._proc
        if state in ("ready", "busy") and proc is not None and proc.poll() is not None:
            state, detail = "failed", "调试器连接已经关闭。"
        return dict(self._info, state=state, detail=detail, ready=state=="ready")

    def _stop(self):
        proc = self._proc
        if proc and proc.poll() is None:
            (self._control / "STOP").touch()
            try:
                proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                               capture_output=True, timeout=12, creationflags=subprocess.CREATE_NO_WINDOW)
                proc.wait(timeout=8)
        self._proc = None

    def _clean(self):
        if self._stack is not None:
            stack, self._stack = self._stack, None
            stack.close()

    def _wait(self, path, timeout, progress=None):
        deadline = time.monotonic()+timeout
        stage, last_check = "", 0
        locked_since = {}
        def read_signal(signal, optional=False):
            try:
                value = signal.read_text(encoding="utf-8").strip()
                locked_since.pop(signal, None)
                return value
            except FileNotFoundError:
                return None
            except PermissionError:
                # XSDB replaces progress files atomically. Windows may deny a
                # racing read briefly; UI progress must never abort computation.
                if optional:
                    return None
                began = locked_since.setdefault(signal, time.monotonic())
                if time.monotonic()-began >= 3:
                    raise
                return None
        while True:
            for problem in (path.parent / "FAILED", self._control / "FAILED"):
                message = read_signal(problem)
                if message is not None:
                    raise RuntimeError(message)
            value = read_signal(path)
            if value is not None:
                return value
            if self._proc.poll() is not None:
                raise RuntimeError(f"XSDB 意外退出，详见 {self._control / 'xsdb.log'}")
            if time.monotonic() >= deadline:
                raise TimeoutError(f"等待 {path.name} 超时。")
            if progress and time.monotonic() >= last_check:
                s = path.parent / "STAGE"
                current = read_signal(s, optional=True)
                if current is not None:
                    if current != stage and current.isdecimal():
                        stage = current
                        progress({"type":"progress", "message":f"开发板正在计算，固件阶段 {stage}。", "stage":int(stage)})
                last_check = time.monotonic()+0.25
            time.sleep(0.02)

    def start(self, emit_progress=None):
        with self._op:
            if self.status()["ready"]:
                return self.status()
            self._clean()
            self._state = "starting", "正在核对板上的编码器和常驻权重。"
            self._stack = ExitStack()
            self._info = {}
            try:
                self._stack.enter_context(_board_lock())
                if emit_progress:
                    emit_progress({"type":"progress", "message":self._state[1]})
                self._control = HERE / "resident_runs" / uuid.uuid4().hex
                self._control.mkdir(parents=True)
                self._info = _proof(self._control)
                self._info["session_id"] = self._control.name
                lease = self._control / "lease"
                lease.touch()
                stop = threading.Event()
                def heartbeat():
                    while not stop.wait(5):
                        lease.touch()
                thread = threading.Thread(target=heartbeat, name="A53-host-lease", daemon=True)
                thread.start()
                self._stack.callback(thread.join, 6)
                self._stack.callback(stop.set)
                log = self._stack.enter_context((self._control / "xsdb.log").open("wb"))
                self._proc = subprocess.Popen(["cmd.exe", "/d", "/c", str(BIN / "xsdb.bat"),
                        str(HERE / "resident_host.tcl"), str(self._control)], cwd=self._control,
                        stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                        creationflags=subprocess.CREATE_NO_WINDOW)
                self._stack.callback(self._stop)
                pid, self._seq = map(int, self._wait(self._control/"READY", 90).split())
                if pid<=1 or self._seq<=0:
                    raise ValueError("板端握手数据不完整。")
                self._info["xsdb_pid"] = pid
                self._job = 0
                self._state = "ready", "A53 与 PL 已连接，模型权重已驻留。"
            except BaseException as exc:
                self._state = "failed", str(exc)
                self._clean()
                raise
            return self.status()

    def encode(self, features_f32, outdir, emit_progress=None):
        with self._op:
            if not self.status()["ready"]:
                raise RuntimeError("板端编码器尚未就绪。")
            folder = Path(outdir).resolve() / "board_encoder"
            folder.mkdir(parents=True, exist_ok=False)
            target = folder / "input_f32.bin"
            if isinstance(features_f32, (str, Path)):
                shutil.copyfile(features_f32, target)
            else:
                import numpy as np
                data = np.asarray(features_f32)
                if data.ndim != 2 or data.shape[1] != 80 or data.dtype != np.dtype("<f4"):
                    raise ValueError("输入必须为 [F,80] 的小端 float32 log-Mel。")
                np.ascontiguousarray(data).tofile(target)
            size = target.stat().st_size
            f = size//320
            if size != f*320 or not 7 <= f <= 1876:
                raise ValueError("特征长度超出板端范围。")
            if not all(math.isfinite(x[0]) for x in struct.iter_unpack("<f",target.read_bytes())):
                raise ValueError("输入特征含非有限值。")
            self._state = "busy", "开发板正在运行 Conformer。"
            try:
                self._job += 1
                _publish(self._control/f"job_{self._job:08}", str(folder))
                seq = int(self._wait(folder/"DONE", 3660, emit_progress))
                if seq != ((self._seq+1) & 0xffffffff):
                    raise ValueError("实板请求序号不连续。")
                receipt = verify("encode", folder)
                box = receipt["mailbox"]
                if seq != box["response_seq"] or f != box["feature_frames"]:
                    raise ValueError("固件返回了不同的请求。")
                self._seq = seq
                checked = folder / "verified.json"
                checked.write_text(json.dumps(dict(receipt, **self._info), indent=2), encoding="utf-8")
            except BaseException as exc:
                self._state = "failed", str(exc)
                self._clean()
                raise
            self._state = "ready", "A53 与 PL 已连接，模型权重已驻留。"
            return dict(self._info, encoded_f32=folder/"encoder_output_f32.bin", verification=checked,
                        output_shape=receipt["output_shape"], pl_calls=box["pl_calls"], board_ticks=box["ticks_lo"]+
                        (box["ticks_hi"]<<32), timer_hz=box["timer_hz"], board_seconds=receipt["board_elapsed_seconds"],
                        request_seq=seq, input_bytes=size, output_bytes=receipt["output_shape"][0]*512*4)

    def close(self):
        with self._op:
            self._clean()
            self._state = "cold", "尚未连接板端编码器。"
