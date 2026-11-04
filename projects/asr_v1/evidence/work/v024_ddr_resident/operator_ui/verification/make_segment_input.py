"""Generate a 20-second fake microphone recording from the two prior board examples."""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import soundfile as sf

target = Path(sys.argv[1]).resolve()
target.parent.mkdir(parents=True, exist_ok=True)
folder = Path(__file__).resolve().parents[4] / "ASR/data/LibriSpeech/test-clean/1089/134686"
audio = np.zeros(320000, dtype=np.int16)
segments = []
for clip, at in [("1089-134686-0003", 32000), ("1089-134686-0001", 192000)]:
    samples, rate = sf.read(folder / (clip + ".flac"), dtype="int16")
    assert samples.ndim == 1 and rate == 16000
    audio[at:at + len(samples)] = samples
    segments.append({"clip": clip, "offset_samples": at, "speech_samples": len(samples)})
sf.write(target, audio, 16000, subtype="PCM_16", format="WAV")
path = target.with_suffix(".json")
path.write_text(json.dumps({"samples": len(audio), "rate": 16000, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                            "segments": segments}, indent=2), encoding="utf-8")
