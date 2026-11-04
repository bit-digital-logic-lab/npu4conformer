"""One real WAV through A51A2493 SQRT/DDR and the original PC beam decoder."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
RESIDENT = HERE.parent
sys.path[:0] = [str(RESIDENT), str(RESIDENT / "operator_ui")]
from board_adapter import ASR, LEGACY, _board_lock
from run_board_2493 import BIN, command, ensure_server
from verify_ddr import DEPLOY, IDENTITY, frozen, identity


def checked_cold_run(path):
    result = json.loads(path.read_text(encoding="utf-8"))
    deployment = json.loads((path.parent.parent / "deployment.json").read_text(encoding="utf-8"))
    if not (all(result.get(k) == v for k, v in IDENTITY.items())
            and result.get("passed") is True and result.get("dump_words") == 8192
            and result.get("graph_starts") == 1 and deployment.get("stage") == "PASS"
            and deployment.get("verification", {}).get("output_sha256") == result.get("output_sha256")
            and result.get("output_sha256") and deployment.get("bit_sha256")):
        raise ValueError("需要同一次 A51A2493 上板部署的冷首图通过凭据。")


def summarize(directory, norms):
    with (directory / "telemetry.tsv").open() as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not (len(rows) == len(norms.rows) == len(norms.originals) == 61):
        raise RuntimeError("实板调用次数未覆盖 61 个归一化算子。")
    for row, norm in zip(rows, norms.rows):
        idx, count = int(row["id"]), int(row["words"])
        if (idx, count) != (norm["id"], norm["words"]) or int(row["cycles"]) <= 0 or norm["over_6e_6"]:
            raise RuntimeError(f"归一化 SQRT 调用 {idx} 读回不完整或超过数值误差范围。")
        raw = (directory / f"output_{idx:04}.bin").read_bytes()
        if len(raw) != 4*(count+1):
            raise RuntimeError(f"SQRT 原始输出长度不符: {idx}")
        response = (directory / norm["output_file"]).read_text().splitlines()
        if raw[:-4] != b"".join(struct.pack("<I", int(word, 16)) for word in response):
            raise RuntimeError(f"解码器所用数据与板卡原始读回不一致: {idx}")
        observed = int.from_bytes(raw[-4:], "little")
        target = int(row["witness_target"], 16)
        start = int(row["witness_before"], 16)
        end = int(row["witness_after"], 16)
        expected = 2.0 if target == 0x40000000 else 1.0
        witness = struct.unpack("<f", raw[-4:])[0]
        if (target not in (0x3F800000, 0x40000000) or observed != end or start == end
                or not abs(witness-expected) <= 6e-6*expected):
            raise RuntimeError(f"实板第 {idx} 次启动的输出标记不符。")
    return dict(hardware_calls=len(rows), sum_pl_cycles=sum(int(r["cycles"]) for r in rows),
                sqrt_words=sum(r["words"] for r in norms.rows),
                max_sqrt_relative_error=max(r["max_relative_error"] for r in norms.rows))


def _recognize(wav, qualification, directory, emit):
    frozen.validate_inputs(frozen.CORE)
    sys.path[:0] = [str(LEGACY), str(ASR), str(ASR / "third_party/espnet")]
    from run_utterance import BoardNorms, wait_file
    from asr_chip.backend import Recognizer, read_config
    from asr_chip.data import load_audio
    from local_preview import decode_tokens

    waveform = load_audio(wav, sample_rate=16000, max_duration_seconds=30)
    directory.mkdir(parents=True, exist_ok=False)
    inputs = DEPLOY / "core/inputs"
    started = time.perf_counter()
    with _board_lock():
        emit({"type": "progress", "message": "正在核对实板镜像和常驻 DDR 七节点计划。"})
        ensure_server("hw_server", 3121)
        ensure_server("cs_server", 3042)
        receipt = directory / "identity.txt"
        current = command("vivado.bat", ["-mode", "batch", "-nojournal", "-log", str(directory / "identity_vivado.log"),
                         "-source", str(HERE / "voice_identity.tcl"), "-tclargs"], [receipt], directory, "identity", 90)
        if "VOICE_CURRENT_IMAGE_2493" not in current:
            raise RuntimeError("无法确认本次语音连接的 FPGA 镜像。")
        identity(receipt)
        identity_utc = datetime.fromtimestamp(receipt.stat().st_mtime, tz=timezone.utc).isoformat()
        with (directory / "xsdb.log").open("wb") as log:
            server = subprocess.Popen(["cmd.exe", "/d", "/c", str(BIN / "xsdb.bat"), str(HERE / "voice_server.tcl"),
                    "--live-sqrt", str(directory), str(inputs)], cwd=directory, stdin=subprocess.DEVNULL,
                    stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            norms = BoardNorms(directory, server)
            recognizer = None
            final = {}
            try:
                wait_file(directory / "READY", server, 90)
                emit({"type": "progress", "message": "已确认 2493 及其计划和系数，正在加载英文模型。"})
                config = read_config()
                config["threads"] = min(2, config["threads"])
                recognizer = Recognizer(config, precision="fp32")
                norms.install(recognizer.decoder.asr_model.encoder)
                ready = time.perf_counter()
                emit({"type": "progress", "message": "实板处理 SQRT，电脑完成英文波束解码。"})

                def forward(event):
                    if event["type"] == "result":
                        final.update(event)
                    else:
                        emit(event)

                decode_tokens(recognizer.decoder, waveform, forward)
                elapsed = time.perf_counter() - ready
                if not isinstance(final.get("text"), str):
                    raise RuntimeError("本次推理未返回文本。")
                measured = summarize(directory, norms)
            finally:
                (directory / "STOP").touch()
                norms.restore()
                try:
                    if recognizer is not None:
                        recognizer.close()
                finally:
                    try:
                        rc = server.wait(timeout=75)
                    except subprocess.TimeoutExpired:
                        subprocess.run(["taskkill", "/PID", str(server.pid), "/T", "/F"], capture_output=True, timeout=15)
                        server.wait(timeout=10)
                        raise
            if rc:
                raise RuntimeError("本次 XSDB 会话异常退出。")
    final.update(**measured, board_id=IDENTITY["usr_access"], board_serial=IDENTITY["serial"],
                 hardware_identity_checked_utc=identity_utc, cold_qualification=str(qualification),
                 mode="hybrid", transport="CPU+AXU15EGB_DDR_SQRT_XSDB", audio_sha256=hashlib.sha256(wav.read_bytes()).hexdigest(),
                 audio_seconds=len(waveform)/16000, audio_to_text_seconds=elapsed,
                 setup_seconds=ready-started, nominal_pl_ms=measured["sum_pl_cycles"] * 20.625 / 1e6)
    (directory / "voice_result.json").write_text(json.dumps(final, indent=2, allow_nan=False), encoding="utf-8")
    emit(final)
    return final


class DdrHybridRecognizer:
    """An explicit hybrid operator bound to a qualified 2493 programming run."""

    def __init__(self, cold_verification):
        self.qualification = Path(cold_verification).resolve()
        checked_cold_run(self.qualification)

    def recognize(self, wav, output_directory, emit):
        """Acquire shared board lock and emit NDJSON-compatible event dicts."""
        return _recognize(Path(wav).resolve(), self.qualification, Path(output_directory).resolve(), emit)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wav", type=Path)
    parser.add_argument("--cold-verification", required=True, type=Path)
    parser.add_argument("--out", type=Path, default=HERE / "voice_runs" / datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    args = parser.parse_args()
    channel = sys.stdout
    sys.stdout = sys.stderr
    def emit(event):
        print(json.dumps(event, ensure_ascii=True), file=channel, flush=True)
    try:
        DdrHybridRecognizer(args.cold_verification).recognize(args.wav, args.out, emit)
    except Exception as exc:
        emit({"type": "error", "message": str(exc) or type(exc).__name__})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
