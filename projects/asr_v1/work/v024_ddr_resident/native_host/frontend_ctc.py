"""CPU log-Mel input and greedy CTC readout for the board-resident pyf98 encoder."""
from io import BytesIO
from pathlib import Path
import sys

import numpy as np
import sentencepiece
import soundfile
import torch
from torch.nn import functional as F
import yaml

ASR = Path(__file__).resolve().parents[3] / "ASR"
sys.path[:0] = [str(ASR), str(ASR / "third_party" / "espnet")]
from asr_chip.assets import MODEL_FILES, MODEL_ID, MODEL_REVISION, MODEL_ROOT, file_hash
from espnet2.asr.frontend.default import DefaultFrontend


def pinned(suffix):
    names = [name for name in MODEL_FILES if name.endswith("/" + suffix)]
    if len(names) != 1:
        raise RuntimeError(f"Expected one pinned asset named {suffix}")
    path = MODEL_ROOT / names[0]
    if file_hash(path) != MODEL_FILES[names[0]]:
        raise ValueError(f"Model asset failed SHA-256 verification: {path.name}")
    return path


class HostFrontendCTC:
    """Call once at cold start. Input audio is mono 16 kHz. Encoder execution is external."""
    model_id = MODEL_ID
    revision = MODEL_REVISION

    def __init__(self):
        config = yaml.safe_load(pinned("config.yaml").read_text(encoding="utf-8"))
        if config["frontend"] != "default" or config["token_type"] != "bpe":
            raise ValueError("Unsupported frontend or tokenizer in pinned configuration")
        self.tokens = tuple(config["token_list"])
        if len(self.tokens) != 5000 or self.tokens[0] != "<blank>" or self.tokens[-1] != "<sos/eos>":
            raise ValueError("Unexpected CTC vocabulary")
        self.spm = sentencepiece.SentencePieceProcessor(model_file=str(pinned("bpe.model")))
        # The pinned checkpoint uses PyTorch ZIP serialization; only these three
        # tensor payloads are materialized and retained from the mapped state dict.
        state = torch.load(pinned("valid.acc.ave.pth"), map_location="cpu", mmap=True, weights_only=True)
        with torch.device("cpu"):
            self.frontend = DefaultFrontend(**config["frontend_conf"]).eval()
        with torch.no_grad():
            self.frontend.logmel.melmat.copy_(state["frontend.logmel.melmat"])
        self.ctc_weight = state["ctc.ctc_lo.weight"].detach().clone().contiguous()
        self.ctc_bias = state["ctc.ctc_lo.bias"].detach().clone().contiguous()
        if (self.ctc_weight.shape != (5000, 512) or self.ctc_bias.shape != (5000,) or
                self.ctc_weight.dtype != torch.float32 or self.ctc_bias.dtype != torch.float32):
            raise ValueError("Unexpected CTC projection shapes or dtype")

    @torch.inference_mode()
    def features(self, wav):
        """Read audio path or WAV bytes, return contiguous float32 [frames,80] before global MVN."""
        source = BytesIO(wav) if isinstance(wav, (bytes, bytearray, memoryview)) else wav
        with soundfile.SoundFile(source) as audio:
            if audio.samplerate != 16000 or audio.channels != 1:
                raise ValueError("音频应为 16 kHz 单声道")
            # Two valid 3x3 stride-2 subsamplers require at least seven feature frames.
            if not 1536 <= audio.frames <= 30 * 16000:
                raise ValueError("录音须介于 96 毫秒与 30 秒之间")
            samples = audio.read(dtype="float32")
        if not np.isfinite(samples).all():
            raise ValueError("输入音频包含非有限数")
        wave = torch.from_numpy(samples)[None, :]
        lengths = torch.tensor([samples.size], dtype=torch.long, device="cpu")
        values, frames = self.frontend(wave, lengths)
        result = values[0, :int(frames.item())].contiguous().numpy()
        if result.shape != (samples.size // 256 + 1, 80) or result.dtype != np.float32 or not np.isfinite(result).all():
            raise ValueError("前端输出格式异常")
        return result

    @torch.inference_mode()
    def decode(self, encoded):
        """Greedy CTC on board output [T,512]; original joint attention/CTC beam search is a separate path."""
        values = np.asarray(encoded)
        if values.ndim != 2 or values.shape[1] != 512 or values.shape[0] == 0 or values.dtype != np.float32:
            raise ValueError("需要非空 float32 编码器输出 [T,512]")
        if not np.isfinite(values).all():
            raise ValueError("板端编码器输出含非有限数")
        # A read-only DDR capture may be backed by immutable Python bytes.
        if not values.flags.c_contiguous or not values.flags.writeable:
            values = values.copy(order="C")
        logits = F.linear(torch.from_numpy(values), self.ctc_weight, self.ctc_bias)
        if not torch.isfinite(logits).all():
            raise ValueError("CTC 投影出现非有限数")
        path = logits.argmax(dim=-1).unique_consecutive().tolist()
        ids = [token for token in path if token not in (0, len(self.tokens) - 1)]
        pieces = [self.tokens[i] for i in ids]
        return {"text": self.spm.decode_pieces(pieces), "tokens": pieces, "token_ids": ids, "decoding": "ctc_greedy"}
