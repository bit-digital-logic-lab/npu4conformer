"""Run the submitted WAV in one exclusive 2492 session, without transcript labels."""
import csv
import json
from pathlib import Path
import subprocess
import sys

from board_adapter import ASR, LEGACY


def recognize(wav, session, emit):
    sys.path[:0] = [str(LEGACY), str(ASR), str(ASR / "third_party/espnet")]
    from run_utterance import BoardNorms, start_bridge, wait_file
    from asr_chip.backend import Recognizer, read_config
    from asr_chip.data import load_audio
    from local_preview import decode_tokens

    waveform = load_audio(wav, sample_rate=16000, max_duration_seconds=30)
    emit("progress", message="正在通过 JTAG 核对 AXU15EGB 的镜像，并初始化计算核心。")
    with (session / "vivado-console.log").open("wb") as log:
        server = start_bridge(session, log, defer_checks=True)
        norms = BoardNorms(session, server)
        recognizer = None
        try:
            wait_file(session / "READY", server, 180)
            if (session / "STOP").exists():
                raise RuntimeError("请求已取消。")
            identity = dict(line.split("=", 1) for line in (session / "identity.txt").read_text().splitlines())
            board_id = f"0x{int(identity['usr_access'], 16):08X}"
            board_serial = identity["target"].rsplit("/", 1)[-1]
            if (board_id, board_serial, identity["part"]) != ("0xA51A2492", "210512180081", "xczu15"):
                raise RuntimeError("本次 JTAG 会话连接到了非指定板卡或镜像。")
            emit("progress", message="已确认 A51A2492。正在加载英文识别模型。")
            config = read_config()
            config["threads"] = min(config["threads"], 2)
            recognizer = Recognizer(config, precision="fp32")
            norms.install(recognizer.decoder.asr_model.encoder)
            emit("progress", message="正在用实板计算平方根，电脑解码整句。")
            final = {}

            def forward(event):
                if event["type"] == "result":
                    final.update(event)
                else:
                    emit(event["type"], **{k: v for k, v in event.items() if k != "type"})

            decode_tokens(recognizer.decoder, waveform, forward)
            with (session / "telemetry.tsv").open() as handle:
                telemetry = list(csv.DictReader(handle, delimiter="\t"))
            if not (len(norms.rows) == len(norms.originals) == len(telemetry) == 61):
                raise RuntimeError("实板归一化调用记录不完整。")
            for row, completed in zip(norms.rows, telemetry):
                if ((int(completed["id"]), int(completed["words"]), int(completed["status"]),
                     int(completed["completed"]), int(completed["error"]), int(completed["cycles"]) > 0)
                        != (row["id"], row["words"], 2, 7, 0, True)):
                    raise RuntimeError("实板算子未成功完成本次语音计算。")
            if not final or not isinstance(final.get("text"), str):
                raise RuntimeError("模型未返回有效的解码结果。")
        finally:
            (session / "STOP").touch()
            norms.restore()
            try:
                if recognizer is not None:
                    recognizer.close()
            finally:
                try:
                    rc = server.wait(timeout=65)
                except subprocess.TimeoutExpired:
                    if server.poll() is None:
                        # This launcher owns Vivado only. The shared hw_server
                        # and cs_server are independent processes.
                        subprocess.run(["taskkill", "/PID", str(server.pid), "/T", "/F"],
                                       capture_output=True, timeout=15, check=False)
                    server.wait(timeout=10)
                    raise RuntimeError("本次 Vivado 板卡会话未能正常关闭。")
        if rc:
            raise RuntimeError("开发板 JTAG 会话异常退出。")
        del final["type"]
        emit("result", **final, board_id=board_id, board_serial=board_serial,
             hardware_calls=len(telemetry), sum_pl_cycles=sum(int(r["cycles"]) for r in telemetry))


if __name__ == "__main__":
    output = sys.stdout
    # The legacy tools print diagnostics, including via atexit. Keep their
    # output out of the structured channel used by the operator page.
    sys.stdout = sys.stderr

    def emit(kind, **fields):
        print(json.dumps({"type": kind, **fields}, ensure_ascii=True), file=output, flush=True)

    try:
        recognize(Path(sys.argv[1]), Path(sys.argv[2]), emit)
    except Exception as exc:
        emit("error", message=str(exc) or type(exc).__name__)
        sys.exit(1)
