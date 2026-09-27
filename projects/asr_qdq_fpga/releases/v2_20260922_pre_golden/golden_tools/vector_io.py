"""Portable, explicit tensor files for FPGA/ONNX correspondence tests."""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from typing import Any
import numpy as np

OUTPUT_KEYS = ('encoder_memory', 'encoder_memory_lengths', 'ctc_log_probs', 'decoder_log_probs')
INPUT_KEYS = ('feats', 'tokens')


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write_json(path: Path, data: Any) -> None:
    path = Path(path)
    text = json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    tmp = path.with_name(path.name + '.writing')
    with tmp.open('x', encoding='utf-8', newline='\n') as f:
        f.write(text)
    tmp.replace(path)


def safe_child(root: Path, relative: str) -> Path:
    root = Path(root).resolve()
    rel = Path(relative)
    target = (root / rel).resolve()
    if rel.is_absolute() or not target.is_relative_to(root):
        raise ValueError(f'Unsafe relative path: {relative!r}')
    return target


def canonical(array: np.ndarray) -> np.ndarray:
    x = np.asarray(array)
    if x.dtype.kind not in 'fiu' or x.dtype.itemsize not in (1, 2, 4, 8):
        raise TypeError(f'Unsupported portable tensor type: {x.dtype}')
    if not x.size or (x.dtype.kind == 'f' and not np.isfinite(x).all()):
        raise ValueError('Tensor is empty or contains NaN/Inf')
    # Preserve rank (including a scalar), never use reshape/broadcast to hide a mismatch.
    return np.array(x, dtype=x.dtype.newbyteorder('<'), order='C', copy=True)


def load_npz(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as f:
        if len(f.files) != len(set(f.files)):
            raise ValueError(f'Duplicate NPZ entries: {path}')
        return {key: np.array(f[key], copy=True, order='C') for key in f.files}


def save_tensor_set(directory: Path, stem: str, tensors: dict[str, np.ndarray], *, hex_bytes=False) -> dict:
    """NPZ + tightly packed little-endian binary + explicit tensor byte offsets.

    Optional HEX is byte oriented: one 8-bit byte/line, NOT an int16-word file.
    No bus framing, tile reordering, stride padding or byte swapping is implied.
    """
    directory = Path(directory)
    arrays = {key: canonical(value) for key, value in tensors.items()}
    npz = directory / (stem + '.npz')
    binary = directory / (stem + '.bin')
    with npz.open('xb') as f:
        np.savez(f, **arrays)
    entries, offset = [], 0
    with binary.open('xb') as f:
        for key, value in arrays.items():
            payload = value.tobytes(order='C')
            f.write(payload)
            entries.append(dict(key=key, shape=list(value.shape), dtype=value.dtype.str,
                                logical_dtype=value.dtype.name, order='C', byte_order='little',
                                offset_bytes=offset, nbytes=len(payload),
                                elements=int(value.size), element_bytes=value.dtype.itemsize,
                                tensor_sha256=hashlib.sha256(payload).hexdigest()))
            offset += len(payload)
    desc = dict(npz=npz.name, npz_sha256=sha256(npz), binary=binary.name,
                binary_sha256=sha256(binary), binary_bytes=offset,
                packing='C-order, little-endian, concatenated, no padding', tensors=entries)
    if hex_bytes:
        hp = directory / (stem + '.hex')
        with binary.open('rb') as src, hp.open('x', encoding='ascii', newline='\n') as dst:
            for block in iter(lambda: src.read(65536), b''):
                dst.write(''.join(f'{v:02x}\n' for v in block))
        desc.update(hex=hp.name, hex_sha256=sha256(hp), hex_element_bits=8)
    return desc


def read_binary(path: Path, desc: dict) -> dict[str, np.ndarray]:
    path = Path(path)
    if path.stat().st_size != desc['binary_bytes']:
        raise ValueError(f'Binary byte count mismatch: {path}')
    result = {}
    with path.open('rb') as f:
        for item in desc['tensors']:
            dt = np.dtype(item['dtype'])
            shape = tuple(int(v) for v in item['shape'])
            count = math.prod(shape)
            if count * dt.itemsize != item['nbytes'] or any(v < 1 for v in shape):
                raise ValueError(f'Invalid tensor descriptor: {item["key"]}')
            f.seek(item['offset_bytes'])
            block = f.read(item['nbytes'])
            if len(block) != item['nbytes']:
                raise ValueError('Truncated binary tensor')
            result[item['key']] = np.frombuffer(block, dtype=dt).reshape(shape).copy()
    return result


def verified_tensor_set(directory: Path, desc: dict) -> dict[str, np.ndarray]:
    directory = Path(directory)
    for fkey, hkey in [('npz','npz_sha256'), ('binary','binary_sha256'), ('hex','hex_sha256')]:
        if fkey in desc and sha256(safe_child(directory, desc[fkey])) != desc[hkey]:
            raise ValueError(f'File hash mismatch: {desc[fkey]}')
    npz = load_npz(safe_child(directory, desc['npz']))
    raw = read_binary(safe_child(directory, desc['binary']), desc)
    if set(npz) != set(raw):
        raise ValueError('NPZ/binary tensor keys differ')
    for item in desc['tensors']:
        key = item['key']
        x = npz[key]
        if list(x.shape) != item['shape'] or x.dtype.str != item['dtype']:
            raise ValueError(f'NPZ shape/dtype mismatch for {key}')
        block = canonical(x).tobytes(order='C')
        if hashlib.sha256(block).hexdigest() != item['tensor_sha256'] or block != raw[key].tobytes(order='C'):
            raise ValueError(f'NPZ/binary data mismatch for {key}')
    return npz


def encode_feature_i16(x: np.ndarray, scale: float, zero_point: int) -> tuple[np.ndarray, np.ndarray, dict]:
    """Explicit optional board INPUT adapter, not an inferred ONNX graph boundary.

    Rounds x/scale in float32 to nearest-even, adds integer zero point, saturates.
    The returned float32 reconstruction MUST be the actual ONNX input.
    """
    s = np.float32(scale)
    if not np.isfinite(s) or s <= 0 or not -32768 <= zero_point <= 32767:
        raise ValueError('Feature wire scale must be positive float32; zero point must fit int16')
    divided = np.asarray(x, dtype=np.float32) / s
    if not np.isfinite(divided).all():
        raise ValueError('Nonfinite feature/scale ratio; choose a valid wire scale')
    rounded = np.rint(divided).astype(np.float64) + int(zero_point)
    saturation = (rounded < -32768) | (rounded > 32767)
    q = np.clip(rounded, -32768, 32767).astype('<i2')
    restored = (q.astype(np.float32) - np.float32(zero_point)) * s
    return q, np.ascontiguousarray(restored), dict(
        scale=float(s), zero_point=int(zero_point), dtype='<i2',
        rounding='nearest_even_on_float32_ratio', overflow='saturate',
        formula='q=clip(round_even(feats/scale)+zero_point,-32768,32767); model_input=(q-zero_point)*scale',
        saturated_elements=int(saturation.sum()), elements=int(q.size),
        saturation_fraction=float(saturation.mean()),
        quantized_graph_input_adapter=False, caller_supplied_external_wire_contract=True)


def compare_array(reference, actual, *, atol: float | None, rtol: float | None) -> dict:
    ref, got = np.asarray(reference), np.asarray(actual)
    result = dict(shape_reference=list(ref.shape), shape_actual=list(got.shape),
                  dtype_reference=str(ref.dtype), dtype_actual=str(got.dtype),
                  structural_passed=False, numeric_threshold_passed=False)
    if ref.shape != got.shape:
        return dict(result, reason='shape_mismatch')
    # Big-endian floats with the same kind/width represent the same logical dtype.
    if (ref.dtype.kind, ref.dtype.itemsize) != (got.dtype.kind, got.dtype.itemsize):
        return dict(result, reason='dtype_mismatch; decode FPGA output to the declared logical dtype')
    if not ref.size or not np.isfinite(ref).all() or not np.isfinite(got).all():
        return dict(result, reason='empty_or_nonfinite')
    result['structural_passed'] = True
    unequal = ref != got
    result.update(elements=int(ref.size), equal_elements=int((~unequal).sum()),
                  exact_values_equal=bool(not unequal.any()),
                  bitwise_equal=canonical(ref).tobytes() == canonical(got).tobytes())
    if ref.dtype.kind in 'iu':
        result.update(numeric_threshold_passed=bool(not unequal.any()), comparison='exact_integer',
                      mismatched_elements=int(unequal.sum()))
        return result
    r, a = ref.astype(np.float64), got.astype(np.float64)
    err = np.abs(a-r)
    worst_flat = int(err.argmax())
    worst = tuple(int(v) for v in np.unravel_index(worst_flat, ref.shape))
    denominator = float(np.linalg.norm(r.ravel()))
    numerator = float(np.linalg.norm((a-r).ravel()))
    result.update(max_abs=float(err.max()), mean_abs=float(err.mean()),
                  rmse=float(np.sqrt(np.mean((a-r)**2))),
                  relative_l2=numerator/denominator if denominator else (0.0 if not numerator else None),
                  reference_l2=denominator, absolute_error_l2=numerator,
                  worst_index=list(worst), reference_at_worst=float(r[worst]), actual_at_worst=float(a[worst]))
    if ref.ndim and ref.shape[-1] > 1:
        equal_top = np.argmax(ref, axis=-1) == np.argmax(got, axis=-1)
        result.update(last_axis_top1_equal=int(equal_top.sum()), last_axis_top1_total=int(equal_top.size))
    if atol is None or rtol is None:
        result.update(numeric_threshold_passed=None, comparison='measure_only_no_fpga_tolerance')
    else:
        if not math.isfinite(atol) or not math.isfinite(rtol) or atol < 0 or rtol < 0:
            raise ValueError('Tolerances must be finite and nonnegative')
        bad = err > (atol + rtol*np.abs(r))
        result.update(numeric_threshold_passed=bool(not bad.any()),
                      outside_tolerance_elements=int(bad.sum()), outside_tolerance_fraction=float(bad.mean()),
                      comparison='abs(actual-reference)<=atol+rtol*abs(reference)', atol=atol, rtol=rtol)
    return result
