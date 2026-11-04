"""随机特征的三组件数值检查；不替代音频、beam search 或 WER 验收。"""
from __future__ import annotations

import json
from pathlib import Path
import time
import numpy as np

from .assets import MODEL_ROOT, MODEL_FILES
from .backend import Recognizer, read_config, environment_info
from .data import file_sha256
from .evaluation import _write_new_json, _json_hash, _now, _implementation_hashes, _artifact_identity

OUTPUT_KEYS = ('encoder_memory', 'encoder_memory_lengths', 'ctc_log_probs', 'decoder_log_probs')
# 固定诊断阈值，仅输出元素比较结果；不据此宣布识别精度或外部模型等价。
PROBE_ATOL = 1e-4
PROBE_RTOL = 1e-4


def tensor_metrics(actual, reference):
    """以 FP64 汇总误差，避免 FP32 平方/求和损失；不忽略 NaN 或形状错误。"""
    actual, reference = np.asarray(actual), np.asarray(reference)
    if actual.shape != reference.shape or actual.dtype != reference.dtype:
        raise ValueError('output shape/dtype mismatch')
    if actual.size == 0 or not np.isfinite(actual).all() or not np.isfinite(reference).all():
        raise ValueError('output must be nonempty and finite')
    if actual.dtype.kind in 'iu':
        return {'kind': 'integer', 'elements': actual.size, 'equal': bool(np.array_equal(actual, reference))}
    if actual.dtype.kind != 'f':
        raise ValueError('only floating/integer outputs supported')
    left, right = actual.astype(np.float64), reference.astype(np.float64)
    delta = left - right
    absolute = np.abs(delta)
    sq_error, sq_reference = float(np.sum(delta ** 2)), float(np.sum(right ** 2))
    scale = np.linalg.norm(left) * np.linalg.norm(right)
    cosine = float(np.sum(left * right) / scale) if scale else None
    close = absolute <= PROBE_ATOL + PROBE_RTOL * np.abs(right)
    return {
        'kind': 'float', 'elements': actual.size,
        'max_abs_error': float(absolute.max()), 'sum_abs_error': float(absolute.sum()),
        'sum_squared_error': sq_error, 'sum_squared_reference': sq_reference,
        'mae': float(absolute.mean()), 'rmse': float(np.sqrt(sq_error / actual.size)),
        'relative_l2': float(np.sqrt(sq_error / sq_reference)) if sq_reference else None,
        'cosine': cosine, 'exact_equal': bool(np.array_equal(actual, reference)),
        'probe_atol': PROBE_ATOL, 'probe_rtol': PROBE_RTOL,
        'probe_close_elements': int(close.sum()), 'probe_allclose': bool(close.all()),
        'argmax_equal': int(np.sum(left.argmax(axis=-1) == right.argmax(axis=-1))),
        'argmax_total': int(left[..., 0].size),
    }


def compare_outputs(actual, reference):
    if set(actual) != set(OUTPUT_KEYS) or set(reference) != set(OUTPUT_KEYS):
        raise ValueError('output keys mismatch')
    result = {key: tensor_metrics(actual[key], reference[key]) for key in OUTPUT_KEYS}
    # 长度是离散接口约束，与不同精度模型的浮点误差区分开。
    if not result['encoder_memory_lengths']['equal']:
        raise ValueError('encoder output length mismatch')
    return result


def summarize_metrics(cases):
    if not cases:
        raise ValueError('cannot summarize empty cases')
    result = {}
    for key in OUTPUT_KEYS:
        rows = [case[key] for case in cases]
        if rows[0]['kind'] == 'integer':
            result[key] = {'cases': len(rows), 'all_equal': all(row['equal'] for row in rows)}
            continue
        elements = sum(row['elements'] for row in rows)
        absolute = sum(row['sum_abs_error'] for row in rows)
        square = sum(row['sum_squared_error'] for row in rows)
        reference = sum(row['sum_squared_reference'] for row in rows)
        result[key] = {
            'cases': len(rows), 'elements': elements,
            'max_abs_error': max(row['max_abs_error'] for row in rows),
            'mae': absolute / elements, 'rmse': (square / elements) ** 0.5,
            'relative_l2': (square / reference) ** 0.5 if reference else None,
            'min_case_cosine': min((row['cosine'] for row in rows if row['cosine'] is not None), default=None),
            'exact_equal_cases': sum(row['exact_equal'] for row in rows),
            'probe_allclose_cases': sum(row['probe_allclose'] for row in rows),
            'probe_atol': PROBE_ATOL, 'probe_rtol': PROBE_RTOL,
            'probe_close_fraction': sum(row['probe_close_elements'] for row in rows) / elements,
            'argmax_equal': sum(row['argmax_equal'] for row in rows),
            'argmax_total': sum(row['argmax_total'] for row in rows),
        }
    return result


def forward_components(recognizer, inputs):
    """复用已加载的原始网络；每个头都接本次 encoder 输出，绝不注入 golden。"""
    import torch
    feats = np.asarray(inputs['feats'])
    tokens = np.asarray(inputs['tokens'])
    if feats.dtype != np.float32 or feats.ndim != 3 or feats.shape[0] != 1 or feats.shape[2] != 80 or feats.shape[1] < 7:
        raise ValueError('feats must be [1,T>=7,80] float32')
    if not np.isfinite(feats).all():
        raise ValueError('feats must be finite')
    if tokens.dtype != np.int64 or tokens.ndim != 2 or tokens.shape[0] != 1 or tokens.shape[1] == 0:
        raise ValueError('tokens must be [1,L>=1] int64')
    if (tokens < 0).any() or (tokens >= 5000).any() or tokens[0,0] != 4999:
        raise ValueError('tokens outside vocabulary or missing sos')
    model = recognizer.decoder.asr_model
    if model.training or model.preencoder is not None or model.postencoder is not None:
        raise ValueError('requires eval Model A without pre/postencoder')
    if getattr(model.encoder, 'interctc_use_conditioning', False) or getattr(model.encoder, 'ctc_trim', False):
        raise ValueError('unsupported conditioned encoder')
    if model.normalize is None:
        raise ValueError('requires original GlobalMVN normalization')
    with torch.inference_mode():
        # 包中的 normalized 描述的是随机生成空间，feats 已乘 std 加 mean，
        # 因此是 MVN 之前的特征；这里只执行一次原模型的 MVN，跳过 waveform frontend。
        features = torch.from_numpy(feats.copy()).to(recognizer.device)
        lengths = torch.tensor([feats.shape[1]], dtype=torch.long, device=recognizer.device)
        prefix = torch.from_numpy(tokens.copy()).to(recognizer.device)
        normalized, lengths = model.normalize(features, lengths)
        memory, memory_lengths, _ = model.encoder(normalized, lengths)
        if isinstance(memory, tuple):
            raise ValueError('unexpected intermediate encoder outputs')
        ctc = model.ctc.log_softmax(memory)
        # 下三角布尔掩码，与 ESPnet score() 相同；每条独立前缀，不能沿用上条 cache。
        mask = torch.ones((1, prefix.shape[1], prefix.shape[1]), dtype=torch.bool, device=recognizer.device).tril()
        decoder, _ = model.decoder.forward_one_step(prefix, mask, memory, cache=None)
        tensors = dict(zip(OUTPUT_KEYS, (memory, memory_lengths, ctc, decoder)))
        outputs = {key: tensor.detach().cpu().numpy().copy() for key, tensor in tensors.items()}
    for key in ('ctc_log_probs', 'decoder_log_probs'):
        values = outputs[key].astype(np.float64)
        if not np.isfinite(values).all() or not np.allclose(np.exp(values).sum(axis=-1), 1.0, atol=1e-5, rtol=1e-5):
            raise ValueError(f'{key}: invalid log-probability normalization')
    return outputs


def run_vectors(zip_path, output_dir, *, config_path, artifact_path, model_root=MODEL_ROOT):
    """完整运行包中所有用例；冻结身份后比较，不训练、不调阈值、不覆盖已有结果。"""
    from .random_vectors import RandomVectorDataset
    destination = Path(output_dir).resolve()
    if destination.exists():
        raise FileExistsError(f'refuse to overwrite: {destination}')
    dataset = RandomVectorDataset(zip_path)
    config_path, artifact_path = Path(config_path).resolve(), Path(artifact_path).resolve()
    settings = read_config(config_path)
    artifact = _artifact_identity(artifact_path)
    source_paths = [Path(__file__), Path(__file__).with_name('random_vectors.py'), Path(__file__).with_name('__main__.py'),
                    Path(__file__).parents[1] / 'scripts/run_asr_awake.py']
    sources = {str(path.relative_to(Path(__file__).parents[1])): file_sha256(path) for path in source_paths}
    protocol = {
        'format': 'software4npu.random_vector_comparison', 'schema_version': 1, 'created_utc': _now(),
        'dataset': dataset.report, 'config': settings, 'config_path': str(config_path),
        'config_sha256': file_sha256(config_path), 'artifact': artifact,
        'original_model_files': dict(MODEL_FILES), 'core_implementation_sha256': _implementation_hashes(),
        'vector_implementation_sha256': sources, 'case_ids': list(dataset.case_ids),
        'precision_order': ['fp32', 'int16'], 'inference_arithmetic': 'fp32',
        'chain': 'supplied pre-MVN feats -> original GlobalMVN -> encoder -> own memory -> CTC and full-prefix decoder',
        'scope': 'random numerical stress test; no waveform/frontend/beam search/WER or hardware validation',
        'oracle': 'supplied external INT16-QDQ ONNX outputs; graph/weights absent; not proven equivalent to this model',
        'probe': {'atol': PROBE_ATOL, 'rtol': PROBE_RTOL, 'acceptance_threshold': False},
        'timing': 'synchronized software component call including host/device copies; excludes ZIP IO, comparison, model load and one first-case warmup; no audio duration or RTF',
        'training': False, 'tuning': False, 'int8': False, 'wer': None,
    }
    protocol['protocol_sha256'] = _json_hash(protocol)
    destination.mkdir(parents=True, exist_ok=False)
    _write_new_json(destination / 'protocol.json', protocol)
    reports = {}
    active = None
    try:
        for precision in protocol['precision_order']:
            if file_sha256(config_path) != protocol['config_sha256'] or file_sha256(artifact_path) != artifact['sha256']:
                raise ValueError('config/artifact changed during run')
            if file_sha256(Path(zip_path)) != dataset.report['archive_sha256']:
                raise ValueError('dataset changed during run')
            if _implementation_hashes() != protocol['core_implementation_sha256']:
                raise ValueError('core code changed during run')
            directory = destination / precision
            directory.mkdir()
            recognizer = Recognizer(settings, model_root=Path(model_root), precision=precision,
                                    artifact=artifact_path if precision == 'int16' else None)
            rows = []
            try:
                inputs, _ = dataset.load_case(dataset.case_ids[0])
                forward_components(recognizer, inputs)
                recognizer.synchronize()
                with (directory / 'cases.jsonl').open('x', encoding='utf-8') as stream:
                    for case_id in dataset.case_ids:
                        active = {'precision': precision, 'case_id': case_id}
                        inputs, expected = dataset.load_case(case_id)
                        recognizer.synchronize()
                        start = time.perf_counter()
                        actual = forward_components(recognizer, inputs)
                        recognizer.synchronize()
                        elapsed = time.perf_counter() - start
                        row = {'case_id': case_id, 'seconds': elapsed, 'vs_external_qdq': compare_outputs(actual, expected)}
                        if precision == 'int16':
                            with np.load(destination / 'fp32' / f'{case_id}.npz', allow_pickle=False) as original:
                                row['vs_local_fp32'] = compare_outputs(actual, dict(original))
                        # 保存实际输出，支持脱离 GPU 重算全部误差；不改外部 golden。
                        target = directory / f'{case_id}.npz'
                        with target.open('xb') as output:
                            np.savez_compressed(output, **actual)
                        row['output_sha256'] = file_sha256(target)
                        stream.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + '\n')
                        stream.flush()
                        rows.append(row)
                        if len(rows) % 20 == 0:
                            print(f'VECTOR {precision} {len(rows)}/{len(dataset.case_ids)}', flush=True)
                reports[precision] = {
                    'status': 'completed', 'cases': len(rows), 'device': recognizer.device,
                    'environment': environment_info(), 'model_load_seconds': recognizer.load_seconds,
                    'component_seconds': sum(row['seconds'] for row in rows),
                    'vs_external_qdq': summarize_metrics([row['vs_external_qdq'] for row in rows]),
                    'quantization_report': recognizer.quantization_report,
                }
                if precision == 'int16':
                    reports[precision]['vs_local_fp32'] = summarize_metrics([row['vs_local_fp32'] for row in rows])
                _write_new_json(directory / 'summary.json', reports[precision])
            finally:
                recognizer.close()
        if reports['fp32']['environment'] != reports['int16']['environment'] or reports['fp32']['device'] != reports['int16']['device']:
            raise ValueError('branch environment/device mismatch')
        if file_sha256(Path(zip_path)) != dataset.report['archive_sha256'] or file_sha256(artifact_path) != artifact['sha256']:
            raise ValueError('input files changed during run')
        if file_sha256(config_path) != protocol['config_sha256'] or _implementation_hashes() != protocol['core_implementation_sha256']:
            raise ValueError('config/core changed during run')
        if any(file_sha256(path) != sources[str(path.relative_to(Path(__file__).parents[1]))] for path in source_paths):
            raise ValueError('vector code changed during run')
        report = {'status': 'completed', 'protocol_sha256': protocol['protocol_sha256'],
                  'cases': len(dataset.case_ids), 'results': reports, 'wer': None,
                  'numerical_acceptance': 'not assigned; error statistics only',
                  'external_model_equivalence': 'unverified: original ONNX, weights and exporter unavailable',
                  'fpga_executed': False, 'created_utc': _now()}
        _write_new_json(destination / 'comparison.json', report)
        return report
    except BaseException as error:
        _write_new_json(destination / 'failure.json', {'status': 'failed', 'active_case': active,
                        'error': f'{type(error).__name__}: {error}', 'created_utc': _now()})
        raise
