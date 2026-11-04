"""Loopback-only FPGA operator console, with flushed newline-delimited JSON events."""
import argparse
import atexit
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit
from urllib.request import urlopen
import wave
import webbrowser

import board_adapter

ROOT = Path(__file__).resolve().parent
STATIC = {"/": ("index.html", "text/html; charset=utf-8"),
          "/static/app.js": ("app.js", "text/javascript; charset=utf-8"),
          "/static/style.css": ("style.css", "text/css; charset=utf-8")}
MAX_FRAMES = 30 * 16000
MAX_BYTES = 2 * MAX_FRAMES + 65536
SLOT = threading.Lock()
APP_ID = "axu15egb-asr-operator-v024"
WARM = None
WARM_THREAD = None
WARM_LOCK = threading.RLock()


def warm_instance():
    global WARM
    with WARM_LOCK:
        if WARM is None:
            sys.path.insert(0, str(ROOT.parent / "native_host"))
            from backend import NativeHybrid
            WARM = NativeHybrid()
            atexit.register(WARM.close)
        return WARM


def hybrid_status():
    with WARM_LOCK:
        state = warm_instance().status()
        phase = state["state"]
        if WARM_THREAD is not None and WARM_THREAD.is_alive() and phase == "cold":
            phase = "starting"
        if phase == "closed":
            phase = "cold"
        return dict(state, phase=phase, ready=phase == "ready", label="板内 Conformer")


def begin_warmup():
    global WARM_THREAD
    with WARM_LOCK:
        instance = warm_instance()
        phase = instance.status()["state"]
        if phase not in ("ready", "busy", "starting") and not (WARM_THREAD and WARM_THREAD.is_alive()):
            def start():
                try:
                    instance.start(lambda event: print(event.get("message", ""), flush=True))
                except Exception as exc:
                    print(f"Warmup failed: {exc}", flush=True)
            WARM_THREAD = threading.Thread(target=start, daemon=True, name="ASR-warmup")
            WARM_THREAD.start()
    return hybrid_status()


MODES = {"board": board_adapter.get_status, "hybrid": hybrid_status}


def json_bytes(data):
    return json.dumps(data, ensure_ascii=False, allow_nan=False).encode("utf-8")


def status_of(mode):
    try:
        return MODES[mode]()
    except Exception as exc:
        return {"ready": False, "label": mode, "detail": str(exc)}


def check_wav(data):
    try:
        with wave.open(io.BytesIO(data), "rb") as audio:
            if (audio.getnchannels(), audio.getframerate(), audio.getsampwidth(), audio.getcomptype()) != (1, 16000, 2, "NONE"):
                raise ValueError("请使用 16 kHz、单声道、PCM16 的 WAV 录音。")
            n = audio.getnframes()
            if not 1536 <= n <= MAX_FRAMES:
                raise ValueError("录音须介于 96 毫秒与 30 秒之间。")
            if len(audio.readframes(n)) != 2 * n:
                raise ValueError("WAV 录音数据不完整。")
    except (wave.Error, EOFError) as exc:
        raise ValueError("无法读取 WAV 文件。") from exc


class Console(BaseHTTPRequestHandler):
    def reply(self, code, content_type, data):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def fail(self, code, message):
        self.reply(code, "application/json; charset=utf-8", json_bytes({"message": message, "error": message}))

    def local_request(self):
        port = self.server.server_port
        host = self.headers.get("Host", "").lower()
        origin = self.headers.get("Origin")
        if host not in (f"localhost:{port}", f"127.0.0.1:{port}") or (origin and origin != f"http://{host}"):
            self.fail(403, "请通过本机控制页访问。")
            return False
        return True

    def do_GET(self):
        if not self.local_request():
            return
        path = urlsplit(self.path).path
        if path == "/api/status":
            data = {mode: status_of(mode) for mode in MODES}
            self.reply(200, "application/json; charset=utf-8", json_bytes(dict(data, app=APP_ID, busy=SLOT.locked())))
        elif path == "/api/health":
            self.reply(200, "application/json", json_bytes({"app": APP_ID}))
        elif path in STATIC:
            file, kind = STATIC[path]
            self.reply(200, kind, (ROOT / "static" / file).read_bytes())
        else:
            self.fail(404, "未找到。")

    def emit(self, event):
        self.wfile.write(json_bytes(event) + b"\n")
        self.wfile.flush()

    def do_POST(self):
        if not self.local_request():
            return
        url = urlsplit(self.path)
        if url.path == "/api/warmup":
            try:
                state = begin_warmup()
                return self.reply(202, "application/json; charset=utf-8", json_bytes(state))
            except Exception as exc:
                return self.fail(503, str(exc))
        if url.path != "/api/recognize":
            return self.fail(404, "未找到。")
        mode = parse_qs(url.query).get("mode", ["board"])[0]
        if mode not in MODES:
            return self.fail(400, "未知运行模式。")
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self.fail(400, "无法读取上传大小。")
        if not 0 < size <= MAX_BYTES:
            return self.fail(413, "请使用 30 秒以内的录音。")
        self.connection.settimeout(30)
        audio = self.rfile.read(size)
        if len(audio) != size:
            return self.fail(400, "上传中断。")
        try:
            check_wav(audio)
        except ValueError as exc:
            return self.fail(400, str(exc))
        if not SLOT.acquire(blocking=False):
            return self.fail(409, "正在处理另一段录音，请稍后重试。")
        try:
            state = status_of(mode)
            if not state["ready"]:
                return self.fail(503, state["detail"])
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            self.emit({"type": "start", "mode": mode})
            started = time.monotonic()
            with board_adapter.temporary_session() as folder:
                wav = folder / "utterance.wav"
                wav.write_bytes(audio)
                if mode == "hybrid":
                    warm_instance().recognize(wav, folder / "voice", self.emit)
                else:
                    for event in board_adapter.stream_tokens(wav):
                        self.emit(event)
            self.emit({"type": "done", "seconds": round(time.monotonic() - started, 3)})
        except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
            pass
        except Exception as exc:
            self.emit({"type": "error", "message": str(exc) or type(exc).__name__})
        finally:
            SLOT.release()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default=8765, type=int)
    parser.add_argument("--open", action="store_true")
    args = parser.parse_args()
    url = f"http://127.0.0.1:{args.port}/"
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Console)
    except OSError:
        with urlopen(url + "api/health", timeout=2) as response:
            if json.load(response).get("app") != APP_ID:
                raise RuntimeError("控制台端口已被其他程序使用。")
        if args.open:
            webbrowser.open(url)
        return
    print(f"ASR V0.24  {url}", flush=True)
    if args.open:
        webbrowser.open(url)
    with server:
        server.serve_forever()


if __name__ == "__main__":
    main()
