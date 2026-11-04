"""Single-utterance Model A inference with real encoder SQRT results returned by AXU15EGB."""
from datetime import datetime
from pathlib import Path
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
RECOVERY = HERE.parent
DEPLOY = RECOVERY.parent
ASR = DEPLOY.parent.parent / "ASR"
PHYSICAL = RECOVERY / "retained_coeff_physical"
UTTERANCE = "1089-134686-0001"
AUDIO = ASR / "data/LibriSpeech/test-clean/1089/134686" / (UTTERANCE + ".flac")
sys.path[:0] = [str(ASR), str(ASR / "third_party/espnet"), str(RECOVERY)]
os.environ.update(CUBLAS_WORKSPACE_CONFIG=":4096:8", HF_HUB_OFFLINE="1", WANDB_MODE="disabled")
from run_partitioned_board_once import ensure_server, BIN


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def wait_file(path, server, timeout):
    start = time.perf_counter()
    while not path.is_file():
        failure = (path.parent.parent if path.parent.name == "matrix" else path.parent) / "FAILED"
        if failure.exists():
            raise RuntimeError(failure.read_text())
        if server.poll() is not None:
            raise RuntimeError(f"Vivado exited {server.returncode} before {path.name}")
        if time.perf_counter() - start > timeout:
            raise TimeoutError(path.name)
        time.sleep(0.01)


def start_bridge(run, log, defer_checks):
    review = read_json(PHYSICAL / "reports/PHYSICAL_REVIEW.json")
    probes = PHYSICAL / "physical/build/candidate_A51A2492.ltx"
    if (review["status"] != "PASS" or review["debug_probes_sha256"] != digest(probes)
            or review["bitstream_sha256"] != digest(probes.with_suffix(".bit"))):
        raise RuntimeError("2492 physical evidence mismatch")
    ensure_server("hw_server", 3121)
    ensure_server("cs_server", 3042)
    return subprocess.Popen([
        "cmd.exe", "/d", "/c", str(BIN / "vivado.bat"), "-mode", "batch", "-nojournal",
        "-log", str(run / "vivado.log"), "-source", str(HERE / "serve.tcl"),
        "-tclargs", str(run), str(DEPLOY / "host/load_run_verify.tcl"), str(probes), str(int(defer_checks))
    ], cwd=run, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)


class BoardNorms:
    def __init__(self, run, server):
        self.run = run
        self.server = server
        self.rows = []
        self.originals = []

    def evaluate(self, name, data):
        import numpy as np
        words = np.ascontiguousarray(data, dtype="<f4").reshape(-1)
        if not 0 < len(words) <= 1024 or not np.all(np.isfinite(words) & (words > 0)):
            raise ValueError(f"invalid layer input {name}: {words.shape}")
        key = f"{len(self.rows)+1:04d}"
        request = self.run / f"request_{key}.hex"
        response = self.run / f"response_{key}.hex"
        begin = time.perf_counter()
        temporary = request.with_suffix(".tmp")
        temporary.write_text("".join(f"{int(w):08x}\n" for w in words.view("<u4")), encoding="ascii")
        temporary.replace(request)
        wait_file(response, self.server, 75)
        returned = np.array([int(x, 16) for x in response.read_text().splitlines()], dtype="<u4").view("<f4")
        if len(returned) != len(words) or not np.all(np.isfinite(returned) & (returned > 0)):
            raise ValueError(f"invalid board readback for {name}")
        # Double-precision square roots are diagnostics only. Return the exact JTAG payload.
        reference = np.sqrt(words.astype(np.float64))
        rel = np.abs(returned - reference) / reference
        self.rows.append(dict(id=int(key), layer=name, words=len(words), seconds=time.perf_counter()-begin,
                              max_relative_error=float(rel.max()), over_6e_6=int((rel > 6e-6).sum()),
                              input_file=request.name, output_file=response.name,
                              input_sha256=digest(request), output_sha256=digest(response)))
        return returned

    def install(self, encoder):
        import torch
        for name, norm in encoder.named_modules():
            if not (isinstance(norm, torch.nn.LayerNorm) and tuple(norm.normalized_shape) == (512,)
                    and getattr(norm, "dim", -1) == -1):
                continue
            self.originals.append((norm, norm.forward))

            def forward(x, layer=norm, label=name):
                var, mean = torch.var_mean(x, dim=-1, correction=0, keepdim=True)
                values = (var + layer.eps).detach().cpu().numpy()
                actual = self.evaluate(label, values)
                denom = torch.from_numpy(actual).to(device=x.device).reshape_as(var)
                y = (x - mean) / denom
                if layer.weight is not None:
                    y = y * layer.weight
                if layer.bias is not None:
                    y = y + layer.bias
                return y

            norm.forward = forward
        if not self.originals:
            raise RuntimeError("no encoder LayerNorm matched")

    def restore(self):
        for module, forward in self.originals:
            module.forward = forward


def main():
    defer_checks = "--defer-tile-checks" in sys.argv[1:]
    started = time.perf_counter()
    run = HERE / "runs" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    run.mkdir(parents=True, exist_ok=False)
    print("RUN", run, flush=True)
    with (run / "console.log").open("wb") as log:
        server = start_bridge(run, log, defer_checks)
        norms = BoardNorms(run, server)
        recognizer = None
        matrix = None
        try:
            wait_file(run / "READY", server, 180)
            setup_seconds = time.perf_counter() - started
            print(f"BOARD READY after {setup_seconds:.3f}s", flush=True)
            from asr_chip.backend import CHECKPOINT_SHA256, Recognizer, read_config
            from asr_chip.data import load_audio
            from asr_chip.metrics import compute_wer
            recognizer = Recognizer(read_config(), precision="fp32")
            norms.install(recognizer.decoder.asr_model.encoder)
            if "--matrix-query" in sys.argv[1:]:
                from matrix_query import MatrixQuery
                matrix = MatrixQuery(run, server, wait_file, recognizer.decoder.asr_model.encoder, defer_checks)
            recognizer.synchronize()
            start = time.perf_counter()
            audio = load_audio(AUDIO, sample_rate=16000)
            transcript = recognizer.transcribe(audio)
            recognizer.synchronize()
            end = time.perf_counter()
            rows = norms.rows
            block_ids = {int(m.group(1)) for row in rows
                         if (m := re.search(r"(?:^|\.)encoders\.(\d+)\.", row["layer"]))}
            if block_ids != set(range(12)) or len({row["layer"] for row in rows}) != len(norms.originals):
                raise RuntimeError(f"incomplete encoder module coverage: {sorted(block_ids)}, {len(rows)} calls")
            # Fetch the answer key only after the recognizer produced its output.
            refs = dict(line.split(" ", 1) for line in AUDIO.with_name("1089-134686.trans.txt").read_text().splitlines())
            expected = refs[UTTERANCE]
            baseline = read_json(HERE / "software_baseline.json")
            with (run / "telemetry.tsv").open() as handle:
                telemetry = [{k: int(v) for k, v in row.items()} for row in csv.DictReader(handle, delimiter="\t")]
            if len(telemetry) != len(rows):
                raise RuntimeError("board/host call counts differ")
            for t, row in zip(telemetry, rows):
                if (row["id"], row["words"], 2, 7, 0) != (t["id"], t["words"], t["status"], t["completed"], t["error"]):
                    raise RuntimeError(f"invalid graph receipt: {t}")
            seconds = end - start
            cycles = sum(t["cycles"] for t in telemetry)
            result = dict(experiment="one real utterance, host FP32 Model A with live FPGA SQRT",
                          full_native_v024_fpga_graph=False, tile_readback_and_poison_checks=not defer_checks,
                          fpga_scope="per-frame SQRT in encoder LayerNorm; other six nodes in each reused fixture do not feed this ASR",
                          host_scope="audio frontend, mean and variance, affine normalization, all ASR matrix operations, CTC/attention beam decoding",
                          device=recognizer.device, checkpoint_sha256=CHECKPOINT_SHA256, decoding=recognizer.config["decoding"],
                          audio_path=str(AUDIO), audio_sha256=digest(AUDIO), audio_samples=len(audio), audio_seconds=len(audio)/16000,
                          reference=expected, transcript=transcript, wer=compute_wer([expected], [transcript]),
                          software_baseline=baseline, software_wer=compute_wer([expected],[baseline["text"]]),
                          identity=(run/"identity.txt").read_text(), board_setup_seconds=setup_seconds,
                          model_load_seconds=recognizer.load_seconds, audio_to_text_seconds=seconds,
                          cold_script_entry_to_text_seconds=end-started, rtf=seconds/(len(audio)/16000),
                          board_calls=len(rows), encoder_blocks=len(block_ids), useful_sqrt_words=sum(row["words"] for row in rows),
                          clock_hz=50000000, full_fixture_cycles=cycles, full_fixture_seconds=cycles/50000000,
                          summed_board_roundtrip_including_checks_seconds=sum(row["seconds"] for row in rows),
                          max_sqrt_relative_error=max(row["max_relative_error"] for row in rows),
                          words_over_6e_6=sum(row["over_6e_6"] for row in rows), calls=rows)
            if matrix is not None:
                if matrix.result is None:
                    raise RuntimeError("query projection was not executed")
                result.update(experiment="one real utterance, live W7p8 first query projection and encoder SQRT",
                              fpga_scope="all tiles of encoder block 0 query projection; per-frame SQRT in encoder LayerNorm",
                              host_scope="audio, remaining model, attention and beam decode; query tile assembly, dequantization and bias",
                              matrix_query=matrix.result, sqrt_fixture_cycles=cycles, sqrt_fixture_seconds=cycles/50e6,
                              full_fixture_cycles=cycles+matrix.result["graph_cycles"],
                              full_fixture_seconds=(cycles+matrix.result["graph_cycles"])/50e6,
                              total_board_graphs=len(rows)+matrix.result["tiles"])
        finally:
            norms.restore()
            if matrix is not None:
                matrix.restore()
            save_json(run / "completed_calls.json", norms.rows)
            (run / "STOP").touch()
            if recognizer is not None:
                recognizer.close()
            rc = server.wait(timeout=160)
            save_json(run / "process.json", dict(vivado_exit_code=rc))
        if rc:
            raise RuntimeError(f"Vivado returned {rc}")
        save_json(run / "result.json", result)
        print("RESULT", result["transcript"], result["audio_to_text_seconds"], result["board_calls"], flush=True)


if __name__ == "__main__":
    main()
