"""Golden acceptance utilities. No hardware access and no generated oracle."""
import hashlib
import json
from pathlib import Path
import sys
import numpy as np

KEYS = ('encoder_memory', 'encoder_memory_lengths', 'decoder_log_probs')


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def verify_freeze(root):
    root = Path(root).resolve()
    manifest = read_json(root / 'FREEZE_MANIFEST.json')
    for relative, expected in manifest['sha256'].items():
        path = (root / relative).resolve()
        if root not in path.parents or sha(path) != expected:
            raise ValueError(f'Frozen artifact mismatch: {relative}')
    return manifest


def load_golden(frozen, case_dir, model_dir):
    frozen, case_dir, model_dir = map(lambda x: Path(x).resolve(), (frozen, case_dir, model_dir))
    # Reader itself is included in the verified V2 snapshot.
    sys.path.insert(0, str(frozen / 'golden_tools'))
    from vector_io import verified_tensor_set
    dataset_root = case_dir.parent.parent
    dataset = read_json(dataset_root / 'dataset.json')
    generation = read_json(dataset_root / 'generation_report.json')
    for filename, key in (('dataset.json', 'dataset_sha256'), ('cases.jsonl', 'cases_index_sha256')):
        if sha(dataset_root / filename) != generation[key]:
            raise ValueError(f'Golden provenance mismatch: {filename}')
    if dataset.get('provider') != 'CPUExecutionProvider' or dataset.get('graph_optimization') != 'ORT_DISABLE_ALL':
        raise ValueError('Unexpected original golden generator configuration')
    indexed = [json.loads(line) for line in (dataset_root / 'cases.jsonl').read_text().splitlines()]
    entry = next(x for x in indexed if (dataset_root / x['case_file']).resolve() == case_dir / 'case.json')
    if sha(case_dir / 'case.json') != entry['case_sha256']:
        raise ValueError('Case metadata hash mismatch')
    meta = read_json(case_dir / 'case.json')
    if meta['case_id'] != 'case_0000':
        raise ValueError('This run is explicitly bound to case_0000')
    if (meta['feature_frames'], meta['prefix_length']) != (128, 16):
        raise ValueError('This acceptance run requires original 128-frame/16-token input')
    inputs = verified_tensor_set(case_dir, meta['inputs'])
    expected = verified_tensor_set(case_dir, meta['expected'])
    contract = {'feats': ((1, 128, 80), np.dtype('float32')), 'tokens': ((1, 16), np.dtype('int64'))}
    for name, (shape, dtype) in contract.items():
        if inputs[name].shape != shape or inputs[name].dtype != dtype:
            raise ValueError(f'Input contract mismatch: {name}')
    output_contract = {'encoder_memory': ((1, 31, 512), np.dtype('float32')),
                       'encoder_memory_lengths': ((1,), np.dtype('int64')),
                       'decoder_log_probs': ((1, 5000), np.dtype('float32'))}
    for name, (shape, dtype) in output_contract.items():
        if expected[name].shape != shape or expected[name].dtype != dtype:
            raise ValueError(f'Golden output contract mismatch: {name}')
    model_hashes = {}
    for name in ('encoder', 'decoder'):
        path = model_dir / f'{name}.onnx'
        model_hashes[name] = sha(path)
        if model_hashes[name] != dataset['onnx_models'][name]['sha256']:
            raise ValueError(f'Original ONNX changed: {name}')
    provenance = dict(case_id=meta['case_id'], case_dir=str(case_dir),
                      dataset_sha256=sha(dataset_root / 'dataset.json'),
                      case_sha256=sha(case_dir / 'case.json'),
                      inputs_sha256=sha(case_dir / 'inputs.npz'), expected_sha256=sha(case_dir / 'expected.npz'),
                      model_sha256=model_hashes, generator_versions=dataset['versions'],
                      golden_source='User existing ONNX Runtime CPU expected.npz, not custom Python executor',
                      npz_binary_tensor_hashes_verified=True)
    return inputs, expected, provenance


def compare_golden(actual, expected, atol=1e-3, rtol=1e-3):
    a, b = np.asarray(actual), np.asarray(expected)
    result = dict(pass_golden=False, actual_shape=list(a.shape), expected_shape=list(b.shape),
                  actual_dtype=str(a.dtype), expected_dtype=str(b.dtype),
                  shape_match=a.shape == b.shape, dtype_match=a.dtype == b.dtype,
                  atol=atol, rtol=rtol)
    if not (result['shape_match'] and result['dtype_match']):
        return result
    finite = bool(np.isfinite(a).all() and np.isfinite(b).all())
    result.update(all_finite=finite, bit_exact=a.tobytes(order='C') == b.tobytes(order='C'), elements=int(a.size))
    if not finite:
        result['nonfinite_actual_elements'] = int((~np.isfinite(a)).sum())
        result['nonfinite_expected_elements'] = int((~np.isfinite(b)).sum())
        return result
    if b.dtype.kind in 'iu':
        unequal = a != b
        result.update(acceptance='Exact integer equality, no floating tolerance',
                      atol=0, rtol=0, failing_elements=int(unequal.sum()), pass_golden=not bool(unequal.any()))
        return result
    delta = a.astype(np.float64) - b.astype(np.float64)
    absolute = np.abs(delta)
    limit = atol + rtol * np.abs(b.astype(np.float64))
    failed = absolute > limit
    worst = np.unravel_index(int(np.argmax(absolute)), a.shape)
    result.update(acceptance='Every element: abs(actual-golden) <= atol + rtol*abs(golden)',
                  pass_golden=not bool(failed.any()), failing_elements=int(failed.sum()),
                  max_abs_error=float(absolute.max()), rms_error=float(np.sqrt(np.mean(delta * delta))),
                  worst_abs_index=[int(x) for x in worst], worst_actual=float(a[worst]), worst_expected=float(b[worst]),
                  first_failing_indices=np.argwhere(failed)[:8].tolist())
    return result


def all_golden_pass(comparisons, scope='full_chain'):
    if scope not in ('full_chain', 'decoder_only'):
        raise ValueError('Unknown acceptance scope')
    required = KEYS if scope == 'full_chain' else ('decoder_log_probs',)
    return set(comparisons) == set(required) and all(comparisons[k].get('pass_golden') is True for k in required)
