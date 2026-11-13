"""Optional external adapter and legacy transport helpers, not the v1 encoder.

The v1 UI uses mode=hybrid -> native_host.backend.NativeHybrid ->
native_ps.resident_host.BoardEncoder. That implemented path does NOT require
ASR_RESIDENT_ADAPTER. Only the optional mode=board extension below requires it.

ASR_RESIDENT_ADAPTER is a trusted absolute .py or .exe path on the operator PC.
Its --status returns one JSON object: ready, board="AXU15EGB", mode="resident",
verified (current hardware/firmware handshake) and optional detail. Its --wav PATH
writes UTF-8 NDJSON progress/message, token/text, result/text, error/message or
done events, flushes increments, and exits zero on success. Token text is an
appendable decoder delta including any real spaces. This is a local plugin API.
"""
from contextlib import contextmanager
import json
import logging
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from uuid import uuid4

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ASR = ROOT / "ASR"
PYTHON = ASR / "environment/envs/ASR/python.exe"
RECOVERY = ROOT / "work/v024_deploy_20261101/recovery_20261102"
LEGACY = RECOVERY / "utterance_2492_1089_0001"
VIVADO = Path("C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat")
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)
RUNTIME = HERE / ".runtime"
DDR_QUALIFICATION = HERE.parent / "board_test/active_qualification.json"


def _native_command():
    value = os.environ.get("ASR_RESIDENT_ADAPTER")
    if not value:
        raise ValueError("未配置可选的外部适配器；ASR v1 请使用板内 Conformer 页面（?mode=hybrid），无需 ASR_RESIDENT_ADAPTER。")
    path = Path(value)
    if not path.is_absolute() or not path.is_file() or path.suffix.lower() not in {".py", ".exe"}:
        raise ValueError("ASR_RESIDENT_ADAPTER 必须指向本机实际存在的 .py 或 .exe 的绝对路径。")
    return [sys.executable, str(path)] if path.suffix.lower() == ".py" else [str(path)]


def get_status():
    status = dict(ready=False, verified=False, label="板端常驻识别")
    try:
        probe = subprocess.run([*_native_command(), "--status"], capture_output=True,
                               timeout=3, stdin=subprocess.DEVNULL, creationflags=HIDDEN)
        if probe.returncode:
            raise ValueError("板端适配器探测失败。")
        data = json.loads(probe.stdout)
        if not isinstance(data, dict) or data.get("board") != "AXU15EGB" or data.get("mode") != "resident":
            raise ValueError("未确认 AXU15EGB 常驻识别服务。")
        if data.get("ready") is not True or data.get("verified") is not True:
            raise ValueError(str(data.get("detail") or "常驻识别服务尚未通过板端握手。"))
        status.update(ready=True, verified=True, detail=str(data.get("detail") or "板端识别服务已就绪。"))
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        status["detail"] = str(exc)
    return status


def get_hybrid_status():
    if DDR_QUALIFICATION.is_file():
        try:
            qualification = Path(json.loads(DDR_QUALIFICATION.read_text(encoding="utf-8"))["qualification"])
            proof = json.loads(qualification.read_text(encoding="utf-8"))
            ready = proof.get("passed") is True and proof.get("usr_access") == "0xA51A2493"
            return dict(ready=ready, verified=False, label="混合实板 · DDR",
                        detail="FPGA 经 PS 的 DDR 通路计算平方根，电脑完成英文解码。提交时读取实板镜像号。")
        except (OSError, ValueError, KeyError):
            return dict(ready=False, verified=False, label="混合实板 · DDR", detail="本次 DDR 上板验收凭据不可用。")
    required = (PYTHON, VIVADO, LEGACY / "run_utterance.py", LEGACY / "serve.tcl",
                RECOVERY / "retained_coeff_physical/physical/build/candidate_A51A2492.bit",
                RECOVERY / "retained_coeff_physical/physical/build/candidate_A51A2492.ltx")
    ready = all(path.is_file() for path in required)
    return dict(ready=ready, verified=False, label="混合实板 · JTAG",
                detail=("驱动已就绪，提交时核对板卡和镜像。FPGA 计算归一化平方根，"
                        "电脑完成其余计算及英文解码。限 30 秒，需多次往返。")
                if ready else "本机未找到完整的 ASR 环境、Vivado 或 A51A2492 运行文件。")


@contextmanager
def _board_lock():
    # Keep the file as a stable mutex; the OS releases its lock on process exit.
    RUNTIME.mkdir(exist_ok=True)
    with (RUNTIME / "axu15egb_210512180081.lock").open("a+b") as handle:
        if not handle.tell():
            handle.write(b"0")
            handle.flush()
        handle.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            raise RuntimeError("板卡正在处理另一段语音，请稍后再试。") from exc
        yield


@contextmanager
def temporary_session():
    RUNTIME.mkdir(exist_ok=True)
    folder = RUNTIME / uuid4().hex
    folder.mkdir()
    try:
        yield folder
    finally:
        if folder.resolve().parent == RUNTIME.resolve():
            try:
                shutil.rmtree(folder)
            except OSError as exc:
                if getattr(exc, "winerror", None) not in (32, 33):
                    raise
                # Vivado's log writer can outlive its successful batch process.
                # Only retry removal of this request's unique, completed folder.
                threading.Thread(target=_remove_released, args=(folder,), daemon=True).start()


def _remove_released(folder):
    for delay in (1, 3, 10, 30, 60, 120):
        time.sleep(delay)
        try:
            shutil.rmtree(folder)
            return
        except FileNotFoundError:
            return
        except OSError as exc:
            if getattr(exc, "winerror", None) not in (32, 33):
                break
    logging.warning("Vivado log directory pending cleanup: %s", folder)


def _events(command, folder, *, hybrid=False, stop_folder=None):
    # A regular file lets us enforce a deadline even when the driver emits no
    # output. Read only complete records; a UTF-8 code point may straddle writes.
    event_path = folder / "events.ndjson"
    with event_path.open("wb") as out, (folder / "driver.log").open("wb") as log:
        proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=out, stderr=log,
                                creationflags=HIDDEN, env={**os.environ, "PYTHONUTF8": "1"})
        try:
            deadline = time.monotonic() + 420
            pending = b""
            finished = False
            final = None
            with event_path.open("rb") as stream:
                while True:
                    if time.monotonic() > deadline:
                        raise RuntimeError("识别超过 7 分钟，已停止本次请求。")
                    rc = proc.poll()
                    block = stream.read(65536)
                    if not block:
                        if rc is None:
                            time.sleep(0.03)
                            continue
                        if not pending:
                            break
                        block = b"\n"
                    lines = (pending + block).split(b"\n")
                    pending = lines.pop()
                    if len(pending) > 65536:
                        raise RuntimeError("板端适配器返回了过长的数据行。")
                    for line in lines:
                        if not line.strip():
                            continue
                        item = json.loads(line)
                        if not isinstance(item, dict):
                            raise RuntimeError("板端适配器返回了无效事件。")
                        kind = item.get("type")
                        if kind == "error":
                            raise RuntimeError(str(item.get("message") or "板端识别失败。"))
                        if kind == "done":
                            finished = True
                        elif kind == "result" and isinstance(item.get("text"), str) and not finished:
                            finished = True
                            final = item
                        elif kind == "token" and isinstance(item.get("text"), str) and not finished:
                            yield item
                        elif kind == "progress" and isinstance(item.get("message"), str) and not finished:
                            yield item
                        else:
                            raise RuntimeError("板端适配器返回了未知或顺序错误的事件。")
            if rc or not finished:
                raise RuntimeError("板端适配器意外退出，未确认本次识别成功。")
            if final is not None:
                yield final
        finally:
            if proc.poll() is None:
                if hybrid:
                    (folder / "STOP").touch()
                    if stop_folder is not None and stop_folder.is_dir():
                        (stop_folder / "STOP").touch()
                    try:
                        proc.wait(timeout=90)
                    except subprocess.TimeoutExpired:
                        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                                       capture_output=True, timeout=20, check=False)
                else:
                    proc.kill()
                proc.wait()


def stream_tokens(wav_path):
    with _board_lock():
        state = get_status()
        if not state["ready"]:
            raise RuntimeError(state["detail"])
        with temporary_session() as folder:
            yield from _events([*_native_command(), "--wav", str(Path(wav_path).resolve())], folder)


def stream_hybrid(wav_path):
    state = get_hybrid_status()
    if not state["ready"]:
        raise RuntimeError(state["detail"])
    if DDR_QUALIFICATION.is_file():
        qualification = Path(json.loads(DDR_QUALIFICATION.read_text(encoding="utf-8"))["qualification"])
        # The DDR worker owns the common hardware mutex for its entire session.
        with temporary_session() as folder:
            voice = folder / "voice"
            yield from _events([str(PYTHON), str(HERE.parent / "board_test/voice_ddr.py"),
                                str(Path(wav_path).resolve()), "--cold-verification", str(qualification),
                                "--out", str(voice)], folder, hybrid=True, stop_folder=voice)
        return
    with _board_lock(), temporary_session() as folder:
        yield from _events([str(PYTHON), str(HERE / "board_hybrid.py"),
                            str(Path(wav_path).resolve()), str(folder)], folder, hybrid=True)
