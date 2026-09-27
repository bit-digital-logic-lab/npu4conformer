"""Diagnostic-only ORT comparison with saved physical Encoder checkpoints.

Creates an in-memory model clone with extra graph outputs. Never modifies the
original model, original golden data, frozen code, hardware, or a running harness.
ORT intermediate arrays are diagnostics, not new golden acceptance references.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import time
import traceback
import numpy as np
import onnx
from onnx import helper, numpy_helper, TensorProto
import onnxruntime as ort

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4194304), b''):
            h.update(block)
    return h.hexdigest()


def compare(actual, expected, atol=1e-3, rtol=1e-3):
    a, b = np.asarray(actual), np.asarray(expected)
    result = dict(actual_shape=list(a.shape), ort_shape=list(b.shape), actual_dtype=str(a.dtype),
                  ort_dtype=str(b.dtype), shape_match=a.shape == b.shape, dtype_match=a.dtype == b.dtype)
    if not result['shape_match'] or not result['dtype_match']:
        return dict(result, numerically_equal=False, bit_exact=False, within_diagnostic_tolerance=False)
    finite = bool(np.isfinite(a).all() and np.isfinite(b).all())
    different = a != b
    result.update(elements=int(a.size), all_finite=finite, numerically_equal=bool(not different.any()),
                  numeric_differing_elements=int(different.sum()), bit_exact=a.tobytes() == b.tobytes())
    if not finite:
        return dict(result, within_diagnostic_tolerance=False)
    delta = a.astype(np.float64) - b.astype(np.float64)
    absolute = np.abs(delta)
    floating = a.dtype.kind == 'f'
    limit = atol + rtol*np.abs(b.astype(np.float64)) if floating else np.zeros(a.shape)
    failed = absolute > limit
    result.update(atol=atol if floating else 0, rtol=rtol if floating else 0,
                  within_diagnostic_tolerance=bool(not failed.any()), failing_elements=int(failed.sum()),
                  max_abs_error=float(absolute.max(initial=0)), rms_error=float(np.sqrt(np.mean(delta*delta))),
                  first_numeric_differences=[])
    for index in np.argwhere(different)[:8]:
        location = tuple(index)
        result['first_numeric_differences'].append(dict(index=index.tolist(), actual=a[location].item(),
                                                        ort=b[location].item(), delta=float(delta[location])))
    if a.dtype == np.dtype('int16'):
        result['signed_int16_difference_histogram'] = {
            str(int(value)): int(count) for value, count in zip(*np.unique(delta[different].astype(np.int64), return_counts=True))}
    return result


def options(threads):
    value = ort.SessionOptions()
    value.intra_op_num_threads = threads
    value.inter_op_num_threads = 1
    value.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    value.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    return value


def probe_int16(options_value):
    graph = helper.make_graph([
        helper.make_node('QuantizeLinear', ['x', 'scale', 'zero'], ['q']),
        helper.make_node('DequantizeLinear', ['q', 'scale', 'zero'], ['y'])],
        'int16_opset21_support_probe', [helper.make_tensor_value_info('x', TensorProto.FLOAT, [2])],
        [helper.make_tensor_value_info('q', TensorProto.INT16, [2]), helper.make_tensor_value_info('y', TensorProto.FLOAT, [2])],
        [numpy_helper.from_array(np.array(.125, np.float32), 'scale'),
         numpy_helper.from_array(np.array(0, np.int16), 'zero')])
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid('', 21)], ir_version=9)
    session = ort.InferenceSession(model.SerializeToString(), sess_options=options_value, providers=['CPUExecutionProvider'])
    q, y = session.run(None, {'x': np.array([.25, -1.5], np.float32)})
    assert q.dtype == np.int16 and q.tolist() == [2, -12]
    assert y.tolist() == [.25, -1.5]
    return dict(pass_probe=True, opset=21, q_dtype=str(q.dtype), q=q.tolist(), dq=y.tolist(), providers=session.get_providers())


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run', type=Path, default=ROOT/'runs/case_0001_full_chain_001')
    p.add_argument('--case', type=Path, default=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\random200_v1\cases\case_0001'))
    p.add_argument('--model', type=Path, default=Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_int16_runs\run01\int16_qdq_fix01\encoder.onnx'))
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--threads', type=int, help='Default: original dataset generator thread count')
    args = p.parse_args(argv)
    out = args.out.resolve()
    if (ROOT/'diagnostics').resolve() not in out.parents:
        p.error('This bounded diagnostic writes only a fresh validation_case0001/diagnostics child')
    out.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    report = dict(scope='diagnostic-only; NOT new golden acceptance data', hardware_accessed=False,
                  original_model_modified=False, original_golden_modified=False, frozen_modified=False,
                  started_utc=datetime.now(timezone.utc).isoformat(), completed=False,
                  original_run=str(args.run.resolve()), checkpoints_are_sparse=True,
                  first_difference_limit='First among saved checkpoints in original graph topological order, not necessarily first unsaved graph operation',
                  versions=dict(onnx=onnx.__version__, onnxruntime=ort.__version__, numpy=np.__version__),
                  script_sha256=sha(__file__))

    def save():
        (out/'diagnostic_report.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n', encoding='utf-8')

    try:
        dataset_file = args.case.parent.parent/'dataset.json'
        dataset = json.loads(dataset_file.read_text(encoding='utf-8-sig'))
        case_meta = json.loads((args.case/'case.json').read_text(encoding='utf-8-sig'))
        run_manifest = json.loads((args.run/'run_manifest.json').read_text(encoding='utf-8-sig'))
        model_hash, input_hash, expected_hash = sha(args.model), sha(args.case/'inputs.npz'), sha(args.case/'expected.npz')
        assert model_hash == dataset['onnx_models']['encoder']['sha256'] == run_manifest['provenance']['model_sha256']['encoder']
        assert input_hash == run_manifest['provenance']['inputs_sha256']
        assert expected_hash == run_manifest['provenance']['expected_sha256']
        assert case_meta['case_id'] == 'case_0001' and case_meta['feature_frames'] == 128
        assert input_hash == '0c416a25d6bf1b8c6f0537c77e25020e2ebec5cfb8fd70d32bcf7c16dbba08a3'
        assert expected_hash == '947fe5090bd97a097c0b3f0ba42541c3bb39ac5a0d9626cd999255634421641d'
        report['source_hashes'] = dict(encoder_onnx=model_hash, inputs_npz=input_hash, original_expected_npz=expected_hash,
                                     dataset_json=sha(dataset_file), physical_run_manifest=sha(args.run/'run_manifest.json'))
        threads = args.threads if args.threads is not None else int(dataset['threads'])
        if threads < 1:
            raise ValueError('Thread count must be positive')
        report['ort_configuration'] = dict(provider='CPUExecutionProvider', graph_optimization='ORT_DISABLE_ALL',
                                           execution_mode='ORT_SEQUENTIAL', intra_op_num_threads=threads, inter_op_num_threads=1,
                                           original_dataset_threads=dataset['threads'])
        session_options = options(threads)
        report['int16_opset21_probe'] = probe_int16(session_options)
        save()
        print(json.dumps(dict(phase='INT16_OPSET21_SUPPORTED', configuration=report['ort_configuration'])), flush=True)
        index_file = args.run/'checkpoints/index.jsonl'
        entries = []
        for line in index_file.read_text(encoding='utf-8').splitlines():
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue  # Decoder may currently be appending its own last line.
            if item['stage'] == 'hardware_encoder':
                entries.append(item)
        if not entries:
            raise ValueError('No complete saved physical Encoder checkpoints')
        (out/'encoder_checkpoint_index_snapshot.json').write_text(json.dumps(entries, indent=2)+'\n', encoding='utf-8')
        report['checkpoint_files'] = len(entries)
        model = onnx.load(args.model)
        original_outputs = [value.name for value in model.graph.output]
        producers = {name: (index, node) for index, node in enumerate(model.graph.node) for name in node.output if name}
        try:
            inferred = onnx.shape_inference.infer_shapes(model, strict_mode=False)
            types = {value.name: value for value in list(inferred.graph.input)+list(inferred.graph.value_info)+list(inferred.graph.output)}
            report['shape_inference'] = 'success'
        except Exception as exc:
            types = {value.name: value for value in list(model.graph.input)+list(model.graph.value_info)+list(model.graph.output)}
            report['shape_inference'] = f'fallback: {type(exc).__name__}: {exc}'
        clone = onnx.ModelProto()
        clone.CopyFrom(model)
        actuals, metadata = {}, {}
        added = set(original_outputs)
        fallback = []
        for entry in entries:
            checkpoint = args.run/'checkpoints'/entry['file']
            if checkpoint.parent.resolve() != (args.run/'checkpoints').resolve() or sha(checkpoint) != entry['sha256']:
                raise ValueError(f'Physical checkpoint hash/path mismatch: {entry["file"]}')
            with np.load(checkpoint, allow_pickle=False) as arrays:
                for name in arrays.files:
                    actual = arrays[name].copy()
                    if list(actual.shape) != entry['outputs'][name]:
                        raise ValueError('Checkpoint shape disagrees with saved index')
                    position, node = producers[name]
                    if node.name != entry['node_name'] or node.op_type != entry['operator']:
                        raise ValueError('Checkpoint node does not match original ONNX')
                    actuals[name] = actual
                    metadata[name] = dict(tensor=name, topological_index=position, node_name=node.name,
                                          operator=node.op_type, checkpoint=entry['file'], checkpoint_sha256=entry['sha256'])
                    if name not in added:
                        if name in types and types[name].HasField('type'):
                            clone.graph.output.append(types[name])
                        else:
                            clone.graph.output.append(helper.make_tensor_value_info(name, helper.np_dtype_to_tensor_dtype(actual.dtype), list(actual.shape)))
                            fallback.append(name)
                        added.add(name)
        report.update(original_opsets={item.domain or 'ai.onnx': item.version for item in model.opset_import},
                      appended_checkpoint_outputs=len(added)-len(original_outputs), fallback_output_annotations=fallback,
                      node_graph_unchanged=[node.SerializeToString() for node in clone.graph.node] == [node.SerializeToString() for node in model.graph.node])
        serialized = clone.SerializeToString()
        report['in_memory_augmented_model_sha256'] = hashlib.sha256(serialized).hexdigest()
        save()
        session = ort.InferenceSession(serialized, sess_options=session_options, providers=['CPUExecutionProvider'])
        with np.load(args.case/'inputs.npz', allow_pickle=False) as arrays:
            inputs = {value.name: arrays[value.name].copy() for value in session.get_inputs()}
        output_names = [value.name for value in session.get_outputs()]
        compute_start = time.perf_counter()
        diagnostic = dict(zip(output_names, session.run(output_names, inputs)))
        report['ort_inference_seconds'] = time.perf_counter()-compute_start
        ordered = sorted(actuals, key=lambda name: metadata[name]['topological_index'])
        comparisons = [dict(metadata[name], comparison=compare(actuals[name], diagnostic[name])) for name in ordered]
        report['comparisons'] = comparisons
        report['first_numeric_difference'] = next((row for row in comparisons if not row['comparison']['numerically_equal']), None)
        report['first_int16_difference'] = next((row for row in comparisons if row['comparison']['actual_dtype'] == 'int16' and not row['comparison']['numerically_equal']), None)
        report['first_outside_diagnostic_tolerance'] = next((row for row in comparisons if not row['comparison']['within_diagnostic_tolerance']), None)
        report['all_checkpoint_tensors_compared'] = len(comparisons)
        with np.load(args.case/'expected.npz', allow_pickle=False) as arrays:
            report['diagnostic_final_ort_vs_original_golden'] = {
                name: compare(diagnostic[name], arrays['encoder_'+name]) for name in original_outputs}
        if (args.run/'hardware_encoder.npz').is_file():
            with np.load(args.run/'hardware_encoder.npz', allow_pickle=False) as arrays:
                report['physical_final_vs_diagnostic_ort'] = {name: compare(arrays[name], diagnostic[name]) for name in original_outputs}
        print(json.dumps(dict(first_numeric_difference=report['first_numeric_difference'],
                              first_int16_difference=report['first_int16_difference'],
                              first_outside_diagnostic_tolerance=report['first_outside_diagnostic_tolerance'])), flush=True)
        assert sha(args.model) == model_hash and sha(args.case/'inputs.npz') == input_hash and sha(args.case/'expected.npz') == expected_hash
        assert all(sha(args.run/'checkpoints'/entry['file']) == entry['sha256'] for entry in entries)
        report.update(completed=True, all_original_sources_unchanged=True,
                      diagnostic_outputs_saved_as_new_golden=False,
                      diagnostic_final_bit_exact_original_golden=all(item['bit_exact'] for item in report['diagnostic_final_ort_vs_original_golden'].values()))
    except BaseException as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
        traceback.print_exc()
    finally:
        report.update(finished_utc=datetime.now(timezone.utc).isoformat(), elapsed_seconds=time.perf_counter()-started)
        save()
    return 0 if report['completed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
