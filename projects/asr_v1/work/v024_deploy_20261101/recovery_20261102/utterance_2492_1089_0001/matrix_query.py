"""Run all tiles of encoder block 0's attention query projection on the 2492 PE array."""
from pathlib import Path
import json
import time

import numpy as np
import torch


def write_packed(path, values):
    words = np.ascontiguousarray(values).view("<u4").reshape(-1)
    path.write_text("".join(f"{int(w):08x}\n" for w in words), encoding="ascii")


def quantize_weight(w):
    # Existing descriptor has p[0:3] = 0,1,2,3. A code is M << p, plus sign and parity.
    codes = np.arange(64, dtype=np.uint8)
    magnitudes = (codes.astype(np.int32) & 15) << (codes.astype(np.int32) >> 4)
    values, first = np.unique(magnitudes, return_index=True)
    scale = np.max(np.abs(w), axis=1) / 120
    scale = np.where(scale > 0, scale, np.float32(1))
    abs_w = np.abs(w) / scale[:, None]
    # Midpoints guarantee nearest magnitude, ties resolve toward smaller magnitude.
    idx = np.searchsorted((values[:-1] + values[1:]) * 0.5, abs_w)
    sign = (w < 0).astype(np.uint8)
    payload = codes[first[idx]] | (sign << 6)
    parity = np.array([int(i).bit_count() % 2 for i in range(128)], dtype=np.uint8)
    packed = payload | (parity[payload] << 7)
    signed = np.where(sign, -values[idx], values[idx])
    return scale, packed, signed


class MatrixQuery:
    def __init__(self, run, server, wait_file, encoder, defer_checks=False):
        self.run = run
        self.folder = run / "matrix"
        self.folder.mkdir()
        self.server = server
        self.wait_file = wait_file
        self.defer_checks = defer_checks
        self.layer = encoder.encoders[0].self_attn.linear_q
        self.original = self.layer.forward
        self.result = None
        self.layer.forward = self.forward

    def restore(self):
        self.layer.forward = self.original

    def forward(self, x):
        if self.result is not None or x.ndim != 3 or x.shape[0] != 1 or x.shape[-1] != 512:
            raise ValueError(f"unexpected query projection shape {tuple(x.shape)}")
        started = time.perf_counter()
        f = self.folder
        raw = x.detach().cpu().numpy()[0]
        w = self.layer.weight.detach().cpu().numpy()
        if w.shape != (512, 512):
            raise ValueError(f"unexpected query weights {w.shape}")
        np.save(f/"activation_fp32.npy", raw)
        np.save(f/"weight_fp32.npy", w)
        a_scale = float(np.abs(raw).max()) / 2047 or 1.
        rows = (len(raw) + 31) // 32
        aq = np.zeros((rows * 32, 512), dtype="<i2")
        aq[:len(raw)] = np.rint(raw / a_scale).astype("<i2")
        w_scale, packed, signed = quantize_weight(w)
        signed = signed.T.astype(np.int32)
        for b in range(rows):
            for k in range(16):
                write_packed(f/f"a_{b:02d}_{k:02d}.hex", aq[b*32:(b+1)*32, k*32:(k+1)*32])
        for k in range(16):
            for c in range(16):
                write_packed(f/f"w_{k:02d}_{c:02d}.hex", packed[c*32:(c+1)*32, k*32:(k+1)*32].T)
        tile = 0
        acc = np.zeros((rows*32, 512), dtype=np.int64)
        for b in range(rows):
            for k in range(16):
                a = aq[b*32:(b+1)*32, k*32:(k+1)*32].astype(np.int32)
                for c in range(16):
                    tile += 1
                    key = f"{tile:04d}"
                    temp = f/f"tile_{key}.tmp"
                    temp.write_text(f"{b} {k} {c}", encoding="ascii")
                    temp.replace(f/f"tile_{key}.req")
                    outpath = f/f"out_{key}.hex"
                    self.wait_file(outpath, self.server, 75)
                    words = np.array([int(v, 16) for v in outpath.read_text().splitlines()], dtype="<u4")
                    actual = words.view("<i2").reshape(32, 32)
                    # Independent integer product checks the decoded W7 semantics and every physical lane.
                    if not self.defer_checks:
                        gold = np.rint((a @ signed[k*32:(k+1)*32, c*32:(c+1)*32]).astype(np.float64) / 256)
                        if not np.array_equal(actual, gold):
                            i, j = np.argwhere(actual != gold)[0]
                            raise ValueError(f"tile {tile} lane {i},{j}: observed {actual[i,j]} expected {gold[i,j]}")
                    acc[b*32:(b+1)*32, c*32:(c+1)*32] += actual
        # Only physical return words are accumulated into the projection used by attention.
        projected = (acc[:len(raw)].astype(np.float64) * (256*a_scale) * w_scale[None, :]).astype(np.float32)
        if self.layer.bias is not None:
            bias = self.layer.bias.detach().cpu().numpy()
            np.save(f/"bias_fp32.npy", bias)
            projected += bias
        np.save(f/"query_from_board.npy", projected)
        oracle = self.original(x).detach().cpu().numpy()[0]
        diff = projected.astype(np.float64) - oracle
        logs = [[int(n) for n in l.split()] for l in (f/"telemetry.tsv").read_text().splitlines()]
        if len(logs) != tile or any(t[0] != i or t[5:8] != [2, 7, 0] or t[4] <= 0 for i,t in enumerate(logs,1)):
            raise ValueError("matrix telemetry incomplete")
        self.result = dict(layer="encoder.encoders.0.self_attn.linear_q", frames=len(raw), inputs=512, outputs=512,
                           tiles=tile, physical_partial_i16_values_checked=0 if self.defer_checks else tile*1024,
                           useful_macs=len(raw)*512*512,
                           hardware_tile_macs=tile*32**3, software_role="tile partition; exact integer sum of board A16 partials; dequantization and bias",
                           quantization="per-tensor input A16 uses peak 2047; per-output W7p8 nearest magnitude with positions 0,1,2,3; each partial RNE /256",
                           a_scale=a_scale, projection_vs_fp32_relative_l2=float(np.linalg.norm(diff)/np.linalg.norm(oracle)),
                           projection_vs_fp32_max_abs=float(np.abs(diff).max()), projection_seconds=time.perf_counter()-started,
                           graph_cycles=sum(t[4] for t in logs), graph_seconds=sum(t[4] for t in logs)/50e6)
        (f/"summary.json").write_text(json.dumps(self.result, indent=2), encoding="utf-8")
        return torch.from_numpy(projected).unsqueeze(0).to(device=x.device)
