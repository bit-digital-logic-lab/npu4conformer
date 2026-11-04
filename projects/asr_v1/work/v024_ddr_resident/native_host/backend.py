"""Operator backend with a board encoder and CPU-only frontend/CTC."""
from pathlib import Path
import hashlib
import sys
import threading
import time

HERE = Path(__file__).resolve().parent


class NativeHybrid:
    def __init__(self):
        self._operation = threading.RLock()
        self._state = {"state": "cold", "detail": "等待连接板内 Conformer 编码器。"}
        self.frontend = self.board = None
        self.cold_seconds = None

    def status(self):
        state = dict(self._state)
        connection = {}
        if state["state"] in ("ready", "busy") and self.board is not None:
            child = self.board.status()
            connection = {key: child[key] for key in ("session_id", "xsdb_pid", "model_sha256") if key in child}
            if child.get("state") == "failed":
                state = {"state": "failed", "detail": child.get("detail", "板卡连接已退出。")}
        return dict(state, ready=state["state"] == "ready", cold_seconds=self.cold_seconds,
                    encoder_location="AXU15EGB PS+PL", host_role="CPU log-Mel and greedy CTC", gpu_used=False,
                    **connection)

    def start(self, emit_progress=lambda event: None):
        with self._operation:
            if self.status()["ready"]:
                return self.status()
            self._state = {"state": "starting", "detail": "正在核对 A53 固件与板内模型。"}
            emit_progress({"type": "progress", "message": self._state["detail"]})
            started = time.perf_counter()
            try:
                sys.path.insert(0, str(HERE.parent / "native_ps"))
                from resident_host import BoardEncoder
                from frontend_ctc import HostFrontendCTC
                import torch
                torch.set_num_threads(4)
                if self.board is not None:
                    self.board.close()
                self.board = BoardEncoder()
                self.board.start(emit_progress)
                self._state = {"state": "starting", "detail": "板内编码器已连接，正在准备电脑前端与 CTC。"}
                emit_progress({"type": "progress", "message": self._state["detail"]})
                self.frontend = HostFrontendCTC()
                if torch.cuda.is_initialized() or "espnet2.asr.encoder.conformer_encoder" in sys.modules:
                    raise RuntimeError("电脑运行时超出前处理与 CTC 的允许范围。")
                self.cold_seconds = time.perf_counter() - started
                self._state = {"state": "ready", "detail": "板内 Conformer 已就绪，电脑执行前处理与 CTC。"}
                return self.status()
            except Exception as exc:
                self._state = {"state": "failed", "detail": str(exc)}
                if self.board is not None:
                    self.board.close()
                raise

    def recognize(self, wav, outdir, emit):
        with self._operation:
            if not self.status()["ready"]:
                raise RuntimeError(self.status()["detail"])
            self._state = {"state": "busy", "detail": "正在执行板内 Conformer。"}
            started = time.perf_counter()
            try:
                out = Path(outdir)
                out.mkdir(parents=True, exist_ok=False)
                features = self.frontend.features(wav)
                encoded_start = time.perf_counter()
                acquired = self.board.encode(features, out / "board", emit)
                encoded_end = time.perf_counter()
                import numpy as np
                shape = acquired["output_shape"]
                encoded = np.fromfile(acquired["encoded_f32"], dtype="<f4")
                if len(shape) != 2 or shape[1] != 512 or encoded.size != shape[0] * 512:
                    raise RuntimeError("板内编码器输出长度异常。")
                decoded = self.frontend.decode(encoded.reshape(shape))
                import torch
                if torch.cuda.is_initialized() or "espnet2.asr.encoder.conformer_encoder" in sys.modules:
                    raise RuntimeError("电脑运行时超出前处理与 CTC 的允许范围。")
                result = dict(decoded, type="result", mode="hybrid", encoder_location="AXU15EGB PS+PL",
                              gpu_used=False, board_id="0xA51A2493", pl_calls=acquired["pl_calls"],
                              hardware_calls=acquired["pl_calls"],
                              pc_conformer_loaded=False, decoding="ctc_greedy",
                              encoder_output_sha256=hashlib.sha256(Path(acquired["encoded_f32"]).read_bytes()).hexdigest(),
                              input_bytes=acquired["input_bytes"], output_bytes=acquired["output_bytes"],
                              board_seconds=acquired["board_seconds"], encoder_frames=shape[0],
                              frontend_seconds=encoded_start-started,
                              board_roundtrip_seconds=encoded_end-encoded_start,
                              ctc_and_readout_seconds=time.perf_counter()-encoded_end,
                              hot_seconds=time.perf_counter()-started, session_id=acquired["session_id"],
                              request_seq=acquired["request_seq"])
                self._state = {"state": "ready", "detail": "板内编码器保持就绪。"}
                emit(result)
                return result
            except Exception as exc:
                self._state = {"state": "failed", "detail": str(exc)}
                raise

    def close(self):
        with self._operation:
            if self.board is not None:
                self.board.close()
            self.frontend = self.board = None
            self._state = {"state": "closed", "detail": "板内编码器连接已关闭。"}
