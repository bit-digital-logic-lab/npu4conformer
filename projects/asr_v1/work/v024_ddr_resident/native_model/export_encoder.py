"""Build the frozen pyf98 encoder's 2493 DDR parameter image without running inference."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile

import numpy as np
import torch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "ASR"))
from asr_chip.assets import MODEL_FILES, MODEL_REVISION, MODEL_ROOT

QUERY = ROOT / "work/v024_deploy_20261101/recovery_20261102/utterance_2492_1089_0001"
sys.path.insert(0, str(QUERY))
from matrix_query import quantize_weight

BASE = 0x10100000
END = 0x20000000
TILE = 32
KINDS = {"W7": 1, "F32": 2, "I64": 3}


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def padded(n):
    return (n + TILE - 1) // TILE * TILE


def align(out):
    out.write(bytes(-out.tell() % 64))
    return out.tell()


def is_projection(key, shape):
    return key.endswith(".weight") and len(shape) >= 2 and ".depthwise_conv." not in key


def layout_for(key):
    if key.startswith("encoder.embed.conv."):
        return "conv2d_im2col_c_kt_kf"
    if ".pointwise_conv" in key:
        return "conv1d_pointwise_input_channel"
    return "linear_input_feature"


def write_record(out, key, data):
    shape = list(data.shape)
    if not np.isfinite(data).all():
        raise ValueError(f"nonfinite parameter {key}")
    n = shape[0] if shape else 1
    k = data.size // n
    offset = align(out)
    rec = dict(key=key, shape=shape, n=n, k=k, elements=data.size, data_offset=offset,
               phys_addr=BASE + offset, scales_phys=0, bias_phys=0)
    if not is_projection(key, shape):
        kind = {np.dtype("float32"): "F32", np.dtype("int64"): "I64"}[data.dtype]
        data.astype("<f4" if kind == "F32" else "<i8", copy=False).tofile(out)
        rec.update(kind=kind, bytes=out.tell() - offset, layout="source_contiguous")
        return rec
    source = data.reshape(n, k)
    kt, nt = padded(k) // TILE, padded(n) // TILE
    tiles = np.zeros((kt, nt, TILE, TILE), dtype=np.uint8)
    scales = np.empty(n, dtype="<f4")
    for first in range(0, n, 128):
        chunk = source[first:first + 128]
        length = len(chunk)
        scale, packed, _ = quantize_weight(chunk)
        block = np.zeros((kt * TILE, padded(length)), dtype=np.uint8)
        block[:k, :length] = packed.T
        cols = padded(length) // TILE
        tiles[:, first // TILE:first // TILE + cols] = block.reshape(kt, TILE, cols, TILE).transpose(0, 2, 1, 3)
        scales[first:first + length] = scale
    tiles.tofile(out)
    scale_offset = align(out)
    scales.tofile(out)
    rec.update(kind="W7", kt=kt, nt=nt, bytes=tiles.nbytes, layout=layout_for(key),
               scale_offset=scale_offset, scales_phys=BASE + scale_offset, scale_bytes=scales.nbytes)
    return rec


def verify(path, records, arrays):
    """Read the hardware tile order back, decode the PE bits independently, compare every value."""
    mapped = np.memmap(path, np.uint8, "r")
    code = np.arange(128, dtype=np.int32)
    magnitudes = (code & 15) << ((code >> 4) & 3)
    levels, preferred = np.unique(magnitudes[:64], return_index=True)
    parity = np.array([v.bit_count() & 1 for v in range(128)], np.uint8)
    weight_count = 0
    error_sq = signal_sq = 0.
    for key, rec in records.items():
        raw = arrays[key]
        offset = rec["data_offset"]
        blob = mapped[offset:offset + rec["bytes"]]
        if rec["kind"] != "W7":
            if blob.tobytes() != raw.astype(raw.dtype.newbyteorder("<"), copy=False).tobytes():
                raise ValueError(f"auxiliary payload mismatch: {key}")
            continue
        k, n = rec["k"], rec["n"]
        weight = raw.reshape(n, k)
        packed = blob.reshape(rec["kt"], rec["nt"], TILE, TILE)
        actual = packed.transpose(1, 3, 0, 2).reshape(padded(n), padded(k))
        if actual[n:, :].any() or actual[:n, k:].any():
            raise ValueError(f"nonzero tile padding: {key}")
        scale = np.frombuffer(mapped, dtype="<f4", count=n, offset=rec["scale_offset"])
        peak = np.abs(weight).max(axis=1)
        if not np.array_equal(scale, np.where(peak == 0, np.float32(1), peak / np.float32(120))):
            raise ValueError(f"incorrect per-output scales: {key}")
        for first in range(0, n, 128):
            w = weight[first:first + 128]
            b = actual[first:first + len(w), :k]
            s = scale[first:first + len(w), None]
            x = np.abs(w) / s
            # Choose the closer bracketing magnitude, tie towards the smaller one.
            hi = np.searchsorted(levels, x).clip(0, len(levels) - 1)
            lo = np.maximum(0, hi - 1)
            index = np.where(x - levels[lo] <= levels[hi] - x, lo, hi)
            payload = b & 127
            if not (np.array_equal(payload & 63, preferred[index]) and
                    np.array_equal((payload >> 6) != 0, w < 0) and
                    np.array_equal(b >> 7, parity[payload])):
                raise ValueError(f"packed code mismatch: {key} at block {first}")
            recovered = np.where(payload & 64, -magnitudes[payload], magnitudes[payload]) * s
            error_sq += np.square(recovered - w, dtype=np.float64).sum()
            signal_sq += np.square(w, dtype=np.float64).sum()
            weight_count += w.size
    return dict(w7_values_checked=weight_count, all_records_verified=True,
                weight_relative_l2=float(np.sqrt(error_sq / signal_sq)),
                method="full binary readback, independent W7 bit decode, nearest-code/sign/parity/scale/padding and exact auxiliary bytes")


def write_header(path, records, size, checksum):
    lines = [
        "/* Generated by export_encoder.py from the pinned pyf98 encoder. */",
        "#ifndef ASR_MODEL_INDEX_H", "#define ASR_MODEL_INDEX_H",
        "#include <stddef.h>", "#include <stdint.h>",
        f"#define ASR_MODEL_DDR_BASE 0x{BASE:08X}u",
        f"#define ASR_MODEL_IMAGE_BYTES {size}u",
        f'#define ASR_MODEL_IMAGE_SHA256 "{checksum}"',
        "enum { ASR_TENSOR_W7=1, ASR_TENSOR_F32=2, ASR_TENSOR_I64=3, ASR_TENSOR_U32=4, ASR_TENSOR_U8=5 };",
        "typedef struct {", "    const char *key;",
        "    uint32_t phys_addr, scales_phys, bias_phys, k, n, kind, elements;",
        "} asr_tensor_t;", "static const asr_tensor_t asr_model_tensors[] = {",
    ]
    for key, r in sorted(records.items()):
        lines.append(f'    {{"{key}", 0x{r["phys_addr"]:08X}u, 0x{r["scales_phys"]:08X}u, '
                     f'0x{r["bias_phys"]:08X}u, {r["k"]}u, {r["n"]}u, ASR_TENSOR_{r["kind"]}, {r["elements"]}u}},')
    lines += ["};", f"#define ASR_MODEL_TENSOR_COUNT {len(records)}u",
              "static inline const asr_tensor_t *asr_lookup(const char *key) {",
              "    if (!key) return NULL;",
              "    unsigned lo = 0, hi = ASR_MODEL_TENSOR_COUNT;",
              "    while (lo < hi) {", "        unsigned mid = lo + (hi - lo) / 2;",
              "        const char *a = key, *b = asr_model_tensors[mid].key;",
              "        while (*a && *a == *b) { ++a; ++b; }",
              "        if (*a == *b) return &asr_model_tensors[mid];",
              "        if ((unsigned char)*a < (unsigned char)*b) hi = mid;",
              "        else lo = mid + 1;", "    }", "    return NULL;", "}", "#endif"]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    source_name = next(k for k in MODEL_FILES if k.endswith(".pth"))
    source = MODEL_ROOT / source_name
    if digest(source) != MODEL_FILES[source_name]:
        raise ValueError("checkpoint SHA-256 does not match the pinned CPU source")
    try:
        state = torch.load(source, map_location="cpu", weights_only=True, mmap=True)
    except RuntimeError:
        state = torch.load(source, map_location="cpu", weights_only=True)
    arrays = {k: t.detach().numpy() for k, t in state.items()
              if k.startswith(("encoder.", "normalize.", "frontend."))}
    if len(arrays) != 491 or len(state) != 654:
        raise ValueError("unexpected checkpoint inventory")
    if not (arrays["normalize.std"] > 0).all():
        raise ValueError("invalid source normalization standard deviations")
    arrays["frontend.inv_std"] = np.reciprocal(arrays["normalize.std"])
    with tempfile.TemporaryDirectory(dir=HERE) as tmp:
        staging = Path(tmp)
        image = staging / "weights.bin"
        with image.open("wb") as out:
            records = {k: write_record(out, k, v) for k, v in sorted(arrays.items())}
            size = align(out)
        if sum(r["kind"] == "W7" for r in records.values()) != 135 or BASE + size > END:
            raise ValueError("unexpected projection inventory or DDR overflow")
        for key, rec in records.items():
            if rec["kind"] == "W7" and key[:-6] + "bias" in records:
                rec["bias_phys"] = records[key[:-6] + "bias"]["phys_addr"]
        checked = verify(image, records, arrays)
        records["frontend.mean"] = dict(records["normalize.mean"], key="frontend.mean", alias_of="normalize.mean")
        checksum = digest(image)
        header = staging / "model_index.h"
        write_header(header, records, size, checksum)
        manifest = dict(format="pyf98-encoder-2493-w7p8-v1", model="pyf98/librispeech_conformer",
                        revision=MODEL_REVISION, checkpoint=source_name, source_sha256=MODEL_FILES[source_name],
                        quantizer=str((QUERY / "matrix_query.py").relative_to(ROOT)),
                        quantizer_sha256=digest(QUERY / "matrix_query.py"), image="weights.bin",
                        image_sha256=checksum, image_bytes=size, ddr_base=BASE, exclusive_end=BASE + size,
                        header_sha256=digest(header), source_tensors=491, w7_matrices=135,
                        encoder_layers=12, width=512, heads=8, ffn_width=2048,
                        input_layout="normalized row-major [F,80]; raw log-Mel may first use normalize.mean/std",
                        output_layout="encoder.after_norm output row-major [T,512] FP32",
                        aux="Source FP32/I64 little endian. frontend.mean aliases normalize.mean; frontend.inv_std is float32 reciprocal of normalize.std.",
                        tile_layout="W[N,K] -> B[K,N], bytes ordered [Ktile,Ntile,32 K rows,32 N cols]. Zero padding. Payloads aligned to 64 bytes.",
                        encoding="absW/scale nearest M<<P, tie toward smaller magnitude; P=0,1,2,3, M=0..15. Bits 7 parity, 6 sign, 5:4 P, 3:0 M. scale=max_abs_per_output/120.",
                        convolution="For 3x3 stride-2 valid Conv2d, input K flattens in order C_in, kernel_t, kernel_f. Pointwise Conv1d has contiguous C_in. Depthwise [512,1,31] stays FP32.",
                        verification=checked, tensors=records)
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        for name in ("weights.bin", "model_index.h", "manifest.json"):
            (staging / name).replace(HERE / name)
    print(json.dumps(dict(bytes=size, sha256=checksum, records=len(records), **checked)))


if __name__ == "__main__":
    main()
