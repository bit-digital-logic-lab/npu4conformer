"""Persistent, exclusive A51A2493 hybrid session for the local operator server."""
import atexit
from contextlib import ExitStack
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
import uuid
import wave

from voice_ddr import (ASR, BIN, DEPLOY, HERE, IDENTITY, LEGACY, _board_lock, checked_cold_run,
                       command, ensure_server, frozen, identity, summarize)


class WarmDdrHybrid:
    def __init__(self, cold_verification=None):
        self.qualification = Path(cold_verification).resolve() if cold_verification else None
        self._op = threading.RLock()
        self._state = {"state": "cold", "detail": "板卡和模型尚未预热。"}
        self._stack = None
        self._xsdb = self._model = self._control = None
        self._timings = {}
        self._sequence = 0
        self._model_loads = self._identity_checks = 0
        atexit.register(self.close)

    def _set(self, state, detail):
        self._state = {"state": state, "detail": detail}

    def status(self):
        state = dict(self._state)
        proc = self._xsdb
        if state["state"] in {"ready", "busy"} and proc is not None and proc.poll() is not None:
            state = {"state": "failed", "detail": "常驻 XSDB 会话已退出，请重新预热。"}
        return dict(state, ready=state["state"] == "ready", model_load_count=self._model_loads,
                    identity_check_count=self._identity_checks, **self._timings)

    def _stop_xsdb(self):
        proc = self._xsdb
        if proc and proc.poll() is None:
            (self._control / "STOP").touch()
            try:
                proc.wait(timeout=65)
            except subprocess.TimeoutExpired:
                if proc.poll() is None:
                    subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                                   capture_output=True, timeout=15, check=False)
                proc.wait(timeout=10)
        self._xsdb = None

    def _cleanup(self):
        if self._stack:
            try:
                self._stack.close()
            finally:
                self._stack = self._model = None

    def start(self, emit_progress=lambda event: None):
        """Cold-start once. Waiters reuse the same live kernel/transport session."""
        with self._op:
            if self.status()["state"] == "ready":
                return self.status()
            self._cleanup()
            self._set("starting", "正在连接 AXU15EGB。")
            self._timings = {}
            self._sequence = 0
            self._stack = ExitStack()
            try:
                if self.qualification is None:
                    active = json.loads((HERE / "active_qualification.json").read_text(encoding="utf-8-sig"))
                    self.qualification = Path(active["qualification"]).resolve()
                self._stack.enter_context(_board_lock())
                begin = time.perf_counter()
                checked_cold_run(self.qualification)
                frozen.validate_inputs(frozen.CORE)
                emit_progress({"type": "progress", "message": self._state["detail"]})
                ensure_server("hw_server", 3121)
                ensure_server("cs_server", 3042)
                self._control = HERE / "warm_runs" / uuid.uuid4().hex
                self._control.mkdir(parents=True, exist_ok=False)
                stamp = self._control / "identity.txt"
                self._identity_checks += 1
                readback = command("vivado.bat", ["-mode", "batch", "-nojournal", "-log", str(self._control / "vivado.log"),
                                   "-source", str(HERE / "voice_identity.tcl"), "-tclargs"],
                                   [stamp], self._control, "identity", 90)
                if "VOICE_CURRENT_IMAGE_2493" not in readback:
                    raise RuntimeError("未读到 A51A2493 的实板身份。")
                identity(stamp)
                log = self._stack.enter_context((self._control / "xsdb.log").open("wb"))
                lease = self._control / "lease"
                lease.touch()
                stop = threading.Event()

                def heartbeat():
                    while not stop.wait(5):
                        lease.touch()

                thread = threading.Thread(target=heartbeat, name="ASR-board-lease", daemon=True)
                thread.start()
                self._stack.callback(thread.join, 6)
                self._stack.callback(stop.set)
                self._xsdb = subprocess.Popen(["cmd.exe", "/d", "/c", str(BIN / "xsdb.bat"), str(HERE / "warm_server.tcl"),
                         "--warm-live", str(self._control), str(DEPLOY / "core/inputs")], cwd=self._control,
                         stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
                self._stack.callback(self._stop_xsdb)
                sys.path[:0] = [str(LEGACY), str(ASR), str(ASR / "third_party/espnet")]
                from run_utterance import wait_file
                wait_file(self._control / "READY", self._xsdb, 90)
                xsdb_pid = int((self._control / "READY").read_text(encoding="ascii").strip())
                if xsdb_pid <= 1:
                    raise RuntimeError("XSDB 未返回当前调试器进程号。")
                tool_ready = time.perf_counter()
                self._set("starting", "已确认 2493，正在载入模型并预热 GPU。")
                emit_progress({"type": "progress", "message": self._state["detail"]})
                from asr_chip.backend import Recognizer, read_config
                config = read_config()
                config["threads"] = min(config["threads"], 2)
                self._model_loads += 1
                self._model = Recognizer(config, precision="fp32")
                self._stack.callback(self._model.close)
                model_ready = time.perf_counter()
                import numpy as np
                self._model.transcribe(np.zeros(8000, dtype=np.float32))
                self._model.synchronize()
                done = time.perf_counter()
                self._timings = dict(cold_seconds=done-begin, tool_check_seconds=tool_ready-begin,
                                     model_load_seconds=model_ready-tool_ready, kernel_warm_seconds=done-model_ready,
                                     kernel_warmup="0.5s synthetic silence on PC; no board calls",
                                     session_id=self._control.name, device=self._model.device, xsdb_pid=xsdb_pid,
                                     xsdb_launcher_pid=self._xsdb.pid,
                                     board_id=IDENTITY["usr_access"], board_serial=IDENTITY["serial"],
                                     hardware_identity_checked_utc=datetime.fromtimestamp(stamp.stat().st_mtime, timezone.utc).isoformat())
                self._set("ready", "板卡、XSDB 和模型已预热。")
                return self.status()
            except BaseException as exc:
                self._set("failed", str(exc))
                self._cleanup()
                raise

    def recognize(self, wav, outdir, emit):
        """Run one fresh 16 kHz mono PCM16 WAV; the result includes verified warm timing."""
        with self._op:
            if not self.status()["ready"]:
                raise RuntimeError(self.status()["detail"])
            started = time.perf_counter()
            path, out = Path(wav).resolve(), Path(outdir).resolve()
            with wave.open(str(path), "rb") as audio:
                if (audio.getframerate(), audio.getnchannels(), audio.getsampwidth(), audio.getcomptype()) != (16000, 1, 2, "NONE"):
                    raise ValueError("请输入 16 kHz 的单声道 PCM16 WAV。")
            from asr_chip.data import load_audio
            from local_preview import decode_tokens
            from run_utterance import BoardNorms, wait_file
            waveform = load_audio(path, sample_rate=16000, max_duration_seconds=30)
            out.mkdir(parents=True, exist_ok=False)
            self._set("busy", "正在用常驻板卡识别语音。")
            self._sequence += 1
            seq = self._sequence
            norms = BoardNorms(out, self._xsdb)
            profile = {"norm_roundtrip_seconds": 0.0, "norm_calls": 0}
            evaluate = norms.evaluate
            def observe_norm(*args, **kwargs):
                begin = time.perf_counter()
                try:
                    return evaluate(*args, **kwargs)
                finally:
                    profile["norm_roundtrip_seconds"] += time.perf_counter() - begin
                    profile["norm_calls"] += 1
            norms.evaluate = observe_norm
            model = self._model.decoder.asr_model
            decoder = self._model.decoder
            encode = model.encode
            beam_decode = decoder._decode_single_sample
            def observe_encode(*args, **kwargs):
                begin = time.perf_counter()
                try:
                    return encode(*args, **kwargs)
                finally:
                    profile["encoder_including_board_seconds"] = time.perf_counter() - begin
            def observe_decode(*args, **kwargs):
                begin = time.perf_counter()
                try:
                    return beam_decode(*args, **kwargs)
                finally:
                    profile["beam_decode_seconds"] = time.perf_counter() - begin
            first_token = None
            final = {}
            delivery_error = None
            try:
                norms.install(self._model.decoder.asr_model.encoder)
                model.encode = observe_encode
                decoder._decode_single_sample = observe_decode
                work = self._control / f"job_{seq:08d}"
                tmp = work.with_suffix(".new")
                tmp.write_text(out.as_posix(), encoding="utf-8")
                tmp.replace(work)

                def forward(event):
                    nonlocal first_token, delivery_error
                    if event["type"] == "result":
                        final.update(event)
                    else:
                        if event["type"] == "token" and first_token is None:
                            first_token = time.perf_counter() - started
                        if delivery_error is None:
                            try:
                                emit(event)
                            except Exception as exc:
                                # Finish the in-flight utterance even if the HTTP client leaves.
                                delivery_error = exc

                decode_tokens(self._model.decoder, waveform, forward)
                decoded = time.perf_counter()
                wait_file(out / "UTTERANCE_DONE", self._xsdb, 5)
                if not isinstance(final.get("text"), str):
                    raise RuntimeError("模型未返回本句文本。")
                measured = summarize(out, norms)
                final.update(**measured, **self._timings, mode="hybrid", transport="warm_XSDB_DDR_SQRT",
                             utterance_index=seq, setup_seconds=0.0, warm=True,
                             identity_check_count=self._identity_checks, model_load_count=self._model_loads,
                             audio_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), audio_seconds=len(waveform)/16000,
                             first_token_seconds=first_token, audio_to_text_seconds=decoded-started,
                             nominal_pl_ms=measured["sum_pl_cycles"]*20.625/1e6, cold_qualification=str(self.qualification))
                final["hot_seconds"] = time.perf_counter()-started
                profile["encoder_pc_and_sync_seconds"] = profile["encoder_including_board_seconds"] - profile["norm_roundtrip_seconds"]
                profile["board_graph_seconds"] = final["nominal_pl_ms"] / 1000
                profile["norm_host_and_transfer_seconds"] = profile["norm_roundtrip_seconds"] - profile["board_graph_seconds"]
                profile["other_seconds"] = final["hot_seconds"] - profile["encoder_including_board_seconds"] - profile["beam_decode_seconds"]
                profile["timing_basis"] = "Wall time, nested spans subtracted. No extra GPU synchronization. PL graph time derived from measured cycles at nominal clk_pl_0."
                final["profile"] = profile
                (out / "voice_result.json").write_text(json.dumps(final, indent=2, allow_nan=False), encoding="utf-8")
            except BaseException as exc:
                (out / "CANCEL").touch()
                self._set("failed", str(exc))
                try:
                    norms.restore()
                finally:
                    self._cleanup()
                raise
            else:
                norms.restore()
                self._set("ready", "板卡与模型保持就绪。")
            finally:
                if model.__dict__.get("encode") is observe_encode:
                    del model.encode
                if decoder.__dict__.get("_decode_single_sample") is observe_decode:
                    del decoder._decode_single_sample
            if delivery_error is not None:
                raise delivery_error
            emit(final)
            return final

    def close(self):
        with self._op:
            try:
                self._cleanup()
            finally:
                self._set("closed", "常驻板卡会话已关闭。")
