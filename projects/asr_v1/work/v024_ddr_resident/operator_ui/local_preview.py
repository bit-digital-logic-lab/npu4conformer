"""Read-only observer for the project's English Model A beam decoder."""
import os
from pathlib import Path
import sys
import wave

ASR = Path(__file__).resolve().parents[3] / "ASR"
sys.path[:0] = [str(ASR), str(ASR / "third_party/espnet")]
from asr_chip.assets import MODEL_FILES, MODEL_ROOT

_recognizer = None


def status():
    ready = all((MODEL_ROOT / name).is_file() for name in MODEL_FILES)
    return {"ready": ready, "label": "电脑预览", "detail": (
        "本机英文 Model A 解码，确定一个词元就显示一个。" if ready else "本机模型文件不完整。")}


def recognize(path, emit):
    global _recognizer
    if _recognizer is None:
        emit({"type": "progress", "message": "首次载入本机英文模型…"})
        os.environ.update(HF_HUB_OFFLINE="1", WANDB_MODE="disabled")
        from asr_chip.backend import Recognizer, read_config
        config = read_config()
        config["threads"] = min(2, config["threads"])
        _recognizer = Recognizer(config)

    import numpy as np
    with wave.open(str(path), "rb") as recording:
        pcm = np.frombuffer(recording.readframes(recording.getnframes()), dtype="<i2")
    audio = pcm.astype(np.float32) / 32768
    emit({"type": "progress", "message": "电脑正在编码音频并解码…"})
    decode_tokens(_recognizer.decoder, audio, emit)


def decode_tokens(decoder, audio, emit):
    import torch
    beam = decoder.beam_search
    original = beam.post_process
    sent = []
    pieces = []
    rendered = ""

    def add(token_id, phase):
        nonlocal rendered
        piece = decoder.converter.ids2tokens([token_id])[0]
        pieces.append(piece)
        decoded = decoder.tokenizer.tokens2text(pieces)
        if not decoded.startswith(rendered):
            raise RuntimeError("分词器解码前缀发生变化。")
        emit({"type": "token", "id": token_id, "piece": piece,
              "text": decoded[len(rendered):], "phase": phase})
        rendered = decoded
        sent.append(token_id)

    def observe(i, maxlen, minlen, maxlenratio, best, ended):
        active = original(i, maxlen, minlen, maxlenratio, best, ended)
        # An eventual winner can only be a surviving branch or the current
        # best completed branch. Completed scores and lengths never change.
        if len(active):
            if hasattr(active, "length"):
                rows = [row[1:length] for row, length in zip(active.yseq.tolist(), active.length.tolist())]
            else:
                rows = [hyp.yseq.tolist()[1:] for hyp in active]
            if ended:
                def rank(hyp):
                    return hyp.score / (len(hyp.yseq) - 1) if beam.normalize_length else hyp.score
                rows.append(max(ended, key=rank).yseq.tolist()[1:-1])
            candidates = [[n for n in row if n != 0][len(sent):] for row in rows]
            for column in zip(*candidates):
                if any(n != column[0] for n in column):
                    break
                add(column[0], "stable")
        return active

    beam.post_process = observe
    try:
        with torch.inference_mode():
            hypotheses = decoder(audio)
    finally:
        del beam.post_process
    if not hypotheses:
        raise RuntimeError("模型没有产生解码结果。")
    text, tokens, token_ids, _ = hypotheses[0]
    if list(token_ids[:len(sent)]) != sent:
        raise RuntimeError("增量词元与最终候选不一致。")
    for token_id in token_ids[len(sent):]:
        add(token_id, "final")
    emit({"type": "result", "text": text or "", "tokens": tokens, "token_ids": token_ids})
