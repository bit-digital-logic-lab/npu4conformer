"""Measure hot PC feature packing and decode transported features locally using Model A."""
from datetime import datetime
from pathlib import Path
import json
import os
import sys
import time

HERE = Path(__file__).resolve().parent
ASR = HERE.parents[1] / "ASR"
sys.path[:0] = [str(ASR), str(ASR / "third_party/espnet")]
os.environ.update(HF_HUB_OFFLINE="1", WANDB_MODE="disabled", CUBLAS_WORKSPACE_CONFIG=":4096:8")
import numpy as np
import soundfile as sf
import torch
from asr_chip.backend import Recognizer, read_config
from asr_chip.metrics import compute_wer

DATA = ASR / "data/LibriSpeech"
PRIMARY = DATA / "test-clean/1089/134686/1089-134686-0001.flac"
FORMATS = ("fp32", "fp16", "int16", "int8", "int4")
DTYPES = {"fp32": "<f4", "fp16": "<f2", "int16": "<i2", "int8": "i1"}


def pcm(path):
    data, sr = sf.read(path, dtype="int16")
    if sr != 16000 or data.ndim != 1 or sf.info(path).subtype != "PCM_16":
        raise ValueError(f"unexpected PCM format {path}")
    return data


def sample_speakers(split, n, omit=()):
    speakers = [s for s in sorted((DATA/split).iterdir()) if s.is_dir() and s.name not in omit]
    selected = []
    for i in np.linspace(0, len(speakers)-1, n, dtype=int):
        clips = sorted(speakers[i].glob("*/*.flac"))
        selected.append(next(p for p in clips if 3 <= sf.info(p).duration <= 10))
    return selected


def pack(x, fmt, span):
    if fmt.startswith("fp"):
        return x.astype(DTYPES[fmt], copy=False).tobytes()
    half = 1 << (int(fmt[3:]) - 1)
    codes = np.clip(np.rint(x * (half/span)), -half, half-1)
    if fmt == "int4":
        n = codes.astype(np.int8).reshape(-1).view(np.uint8) & 15
        return (n[::2] | (n[1::2] << 4)).tobytes()
    return codes.astype(DTYPES[fmt]).tobytes()


def unpack(payload, fmt, span, shape):
    if fmt == "int4":
        packed = np.frombuffer(payload, dtype="u1")
        n = np.empty(packed.size*2, dtype=np.int8)
        n[::2] = packed & 15
        n[1::2] = packed >> 4
        codes = ((n ^ 8) - 8).astype(np.float32)
    else:
        codes = np.frombuffer(payload, dtype=DTYPES[fmt]).astype(np.float32)
    if fmt.startswith("int"):
        codes *= span / (1 << (int(fmt[3:])-1))
    return codes.reshape(shape)


def summary_ms(samples):
    return {"p50":float(np.median(samples)), "p95":float(np.percentile(samples,95))}


def run():
    recognizer = Recognizer(read_config(), precision="fp32")
    try:
        primary_pcm = pcm(PRIMARY)
        raw_baseline = recognizer.transcribe(primary_pcm.astype(np.float32)/32768)
        model = recognizer.decoder.asr_model
        # Sender runs the pinned frontend + normalization once, receiver starts at the encoder.
        frontend, norm = model.frontend.cpu().eval(), model.normalize.cpu().eval()
        model.frontend = model.normalize = None

        def features(data):
            waveform = torch.from_numpy(data).float().unsqueeze(0) * (1/32768)
            feats, lengths = frontend(waveform, torch.tensor([len(data)]))
            normalized, lengths = norm(feats, lengths)
            return normalized[0,:int(lengths[0])].numpy().copy(order="C")

        calibration = sample_speakers("dev-clean", 12)
        magnitudes = np.concatenate([np.abs(features(pcm(p))).reshape(-1) for p in calibration])
        # One shared, power-of-two full-scale for the signed formats. No per-frame scale is sent.
        quantile = float(np.percentile(magnitudes, 99.99))
        span = float(2**np.ceil(np.log2(quantile)))
        files = [PRIMARY, *sample_speakers("test-clean", 7, {"1089"})]
        rows = []
        for path in files:
            x = features(pcm(path))
            decoded = {}
            for fmt in FORMATS:
                wire = pack(x, fmt, span)
                y = unpack(wire, fmt, span, x.shape)
                decoded[fmt] = str(recognizer.decoder(y)[0][0])
            refs = path.with_name(path.stem.rsplit("-",1)[0]+".trans.txt")
            reference = dict(line.split(" ",1) for line in refs.read_text().splitlines())[path.stem]
            rows.append(dict(id=path.stem, feature_shape=list(x.shape), reference=reference, texts=decoded))
            print("DECODED", path.stem, flush=True)
        if rows[0]["texts"]["fp32"] != raw_baseline:
            raise ValueError("PCM path and transmitted FP32 features disagree on the primary utterance")
        x = features(primary_pcm)
        # Interleave formats to reduce order/thermal bias. No disk, hardware, transport or decode is timed.
        times = {fmt:{"quant_pack":[], "pcm_to_payload":[]} for fmt in FORMATS}
        for i in range(65):
            for j in range(len(FORMATS)):
                fmt = FORMATS[(j+i) % len(FORMATS)]
                start = time.perf_counter_ns()
                pack(x,fmt,span)
                direct = time.perf_counter_ns()
                pack(features(primary_pcm),fmt,span)
                end = time.perf_counter_ns()
                if i >= 5:
                    times[fmt]["quant_pack"].append((direct-start)/1e6)
                    times[fmt]["pcm_to_payload"].append((end-direct)/1e6)
        results = {}
        for fmt in FORMATS:
            size = len(pack(x,fmt,span))
            refs = [r["reference"] for r in rows]
            hyps = [r["texts"][fmt] for r in rows]
            wer = compute_wer(refs,hyps)
            results[fmt] = dict(payload_bytes=size, pack_ms=summary_ms(times[fmt]["quant_pack"]),
                pcm_to_payload_ms=summary_ms(times[fmt]["pcm_to_payload"]),
                gigabit_payload_only_ms=size*8/1e6,
                estimated_old_application_upload_ms=size*1000/(4539392/1.951413),
                identical_to_fp32=sum(h == r["texts"]["fp32"] for h,r in zip(hyps, rows)),
                word_errors=wer["errors"], reference_words=wer["reference_words"], wer_percent=wer["wer_percent"])
        report = dict(kind="PC input format experiment; FP32 encoder/decoder; no board or live Ethernet",
            device=recognizer.device, cpu_threads=torch.get_num_threads(), benchmark_rounds=60,
            primary=PRIMARY.stem, pcm_seconds=len(primary_pcm)/16000, float32_raw_audio_transcript=raw_baseline,
            calibration_dev_clips=[p.stem for p in calibration], calibration_p9999=quantile, full_scale=span,
            encoding="normalized Model A features; symmetric zero-point 0, RNE/saturate; signed step full_scale/2^(bits-1); fixed at startup; two signed int4 values per byte",
            old_upload_basis="V0.22 CASE0000 aggregate subgraph upload, 4539392 B / 1.951413 s. Extrapolation excludes per-utterance overhead.",
            inputs=rows, formats=results)
        out = HERE / ("input_precision_"+datetime.now().strftime("%Y%m%d_%H%M%S")+".json")
        out.write_text(json.dumps(report,indent=2),encoding="utf-8")
        print(out, json.dumps(results), flush=True)
    finally:
        recognizer.close()


if __name__ == "__main__":
    with torch.inference_mode():
        run()
