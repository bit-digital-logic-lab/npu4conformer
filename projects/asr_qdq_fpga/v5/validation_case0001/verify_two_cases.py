"""Read-only scalar verification against two pre-existing pinned golden files.

No inference, FPGA access, deployment-comparator import, or regenerated oracle.
The only output is a fresh JSON file beneath this validation directory.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import math
import numpy as np

ROOT = Path(__file__).resolve().parent
V5 = ROOT.parent
GOLD = Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\random200_v1\cases')
BITSTREAM_SHA = 'e07da6cad366c43947f358432d0fccc482f4020462cfb8663508602e1119aab5'
CASES = {
    'case_0000': {
        'run': V5 / 'reports/case_0000_v5_b001_full_chain_001',
        'inputs_sha': 'f312ca8cabedd451c360c46fdcffc1f9704ae61ae1d5cb16e703804d9dbe2496',
        'expected_sha': 'da4e158e5ff4da8b0615e8a0fb70bbf365d7b061524af921bef3565db49c4d99',
        'result_sha': 'a1669bafa1444bab6a23e7aa844a00aa2f6dd797c8703261a1afa49602f30b3a',
        'outputs_sha': 'a1b2f2083d3e865461548c6b5ed4f8f9fd06c0b9d8c8685e4ac70493017e5c4a',
    },
    'case_0001': {
        'run': ROOT / 'runs/case_0001_full_chain_001',
        'inputs_sha': '0c416a25d6bf1b8c6f0537c77e25020e2ebec5cfb8fd70d32bcf7c16dbba08a3',
        'expected_sha': '947fe5090bd97a097c0b3f0ba42541c3bb39ac5a0d9626cd999255634421641d',
    },
}
KEYS = ('encoder_memory', 'encoder_memory_lengths', 'decoder_log_probs')
CONTRACT = {
    'encoder_memory': ((1, 31, 512), np.dtype('float32')),
    'encoder_memory_lengths': ((1,), np.dtype('int64')),
    'decoder_log_probs': ((1, 5000), np.dtype('float32')),
}


def sha(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4194304), b''):
            result.update(block)
    return result.hexdigest()


def compare(key, actual, expected):
    shape, dtype = CONTRACT[key]
    matches = actual.shape == expected.shape == shape and actual.dtype == expected.dtype == dtype
    report = dict(shape=list(actual.shape), dtype=str(actual.dtype),
                  shape_dtype_match=bool(matches), elements=int(actual.size),
                  bit_exact=bool(matches and actual.tobytes() == expected.tobytes()), passed=False)
    if not matches:
        return report
    failed = 0
    maximum = 0.0
    sum_squared = 0.0
    maximum_tolerance_fraction = 0.0
    all_finite = True
    first_failures = []
    for index, (x, y) in enumerate(zip(actual.flat, expected.flat)):
        if dtype.kind in 'iu':
            difference = abs(int(x) - int(y))
            is_bad = difference != 0
        else:
            x, y = float(x), float(y)
            finite = math.isfinite(x) and math.isfinite(y)
            all_finite = all_finite and finite
            difference = abs(x - y) if finite else 0.0
            tolerance = 0.001 + 0.001 * abs(y) if finite else 0.001
            is_bad = not finite or difference > tolerance
            maximum_tolerance_fraction = max(maximum_tolerance_fraction, difference / tolerance)
        maximum = max(maximum, difference)
        sum_squared += difference * difference
        if is_bad:
            failed += 1
            if len(first_failures) < 8:
                first_failures.append(index)
    report.update(passed=failed == 0, all_finite=all_finite, failed_elements=failed,
                  max_abs_error=maximum, rms_error=math.sqrt(sum_squared / actual.size),
                  max_tolerance_fraction=maximum_tolerance_fraction,
                  first_failing_flat_indices=first_failures)
    return report


def verify_case(case_id, config):
    run = config['run']
    result_file = run / 'result.json'
    outputs_file = run / 'hardware_outputs.npz'
    result = json.loads(result_file.read_text(encoding='utf-8'))
    required_true = ('completed', 'physical_fpga_executed', 'encoder_hardware_executed',
                     'full_chain_tested', 'end_provenance_verified',
                     'decoder_uses_actual_encoder_output')
    if not all(result.get(key) is True for key in required_true):
        raise ValueError(f'{case_id}: incomplete or unproven physical chain')
    if any(result.get(key) is not False for key in
           ('cpu_arithmetic_fallback', 'model_modified', 'golden_reference_regenerated')):
        raise ValueError(f'{case_id}: deployment provenance flags changed')
    if result['scope'] != 'full_chain' or result['provenance']['case_id'] != case_id:
        raise ValueError(f'{case_id}: scope or identity mismatch')
    if result['bitstream_file_sha256'] != BITSTREAM_SHA:
        raise ValueError(f'{case_id}: different deployed bitstream record')
    if result['acceptance'] != dict(float_atol=0.001, float_rtol=0.001,
                                    integer_exact=True, dtype_shape_finite_required=True,
                                    criterion_fixed_before_hardware=True):
        raise ValueError(f'{case_id}: acceptance criterion changed')
    case_dir = GOLD / case_id
    for name, field in (('inputs.npz', 'inputs_sha'), ('expected.npz', 'expected_sha')):
        if sha(case_dir / name) != config[field]:
            raise ValueError(f'{case_id}: original {name} changed')
    for path, field in ((result_file, 'result_sha'), (outputs_file, 'outputs_sha')):
        if field in config and sha(path) != config[field]:
            raise ValueError(f'{case_id}: previous accepted artifact changed')
    if (result['provenance']['inputs_sha256'] != config['inputs_sha'] or
            result['provenance']['expected_sha256'] != config['expected_sha']):
        raise ValueError(f'{case_id}: run did not use pinned original case')
    with np.load(outputs_file, allow_pickle=False) as actual, np.load(case_dir / 'expected.npz', allow_pickle=False) as expected:
        comparisons = {key: compare(key, actual[key], expected[key]) for key in KEYS}
        actual_top = int(np.argmax(actual['decoder_log_probs']))
        expected_top = int(np.argmax(expected['decoder_log_probs']))
    link = result['ethernet_after_close']
    clean = (link['close_confirmed'] is True and link['closed'] is True and
             link['active'] is False and link['poisoned'] is False and
             link['datagrams_sent'] == link['datagrams_received'])
    return dict(case_id=case_id, original_golden_path=str(case_dir / 'expected.npz'),
                original_inputs_sha256=config['inputs_sha'], original_golden_sha256=config['expected_sha'],
                result_path=str(result_file), result_sha256=sha(result_file),
                hardware_outputs_sha256=sha(outputs_file), comparisons=comparisons,
                elapsed_seconds=result['elapsed_seconds'],
                encoder_seconds=result['stages']['encoder']['seconds'],
                decoder_seconds=result['stages']['decoder']['seconds'],
                original_model_sha256=result['provenance']['model_sha256'],
                host_implementation_sha256={str(Path(k).name): v for k, v in result['source_sha256'].items()
                                           if Path(k).parent.name == 'host'},
                bitstream_sha256=result['bitstream_file_sha256'],
                decoder_top1_actual=actual_top, decoder_top1_expected=expected_top,
                decoder_top1_matches=actual_top == expected_top,
                deployment_declared_golden_pass=result['golden_pass'],
                deployment_declared_acceptance_pass=result['acceptance_pass'],
                independent_matches_deployment_verdict=(
                    result['acceptance_pass'] == (clean and all(c['passed'] for c in comparisons.values()))
                    and result['golden_pass'] == all(c['passed'] for c in comparisons.values())),
                clean_session=clean, ethernet=link,
                pass_all=clean and all(c['passed'] for c in comparisons.values()))


def inspect_input_difference():
    """Check arrays themselves differ, not merely ZIP metadata or filenames."""
    comparisons = {}
    with np.load(GOLD / 'case_0000/inputs.npz', allow_pickle=False) as first, np.load(GOLD / 'case_0001/inputs.npz', allow_pickle=False) as second:
        if set(first.files) != set(second.files):
            raise ValueError('Original input contracts differ')
        for key in sorted(first.files):
            a, b = first[key], second[key]
            same_contract = a.shape == b.shape and a.dtype == b.dtype
            comparisons[key] = dict(same_shape_dtype=same_contract,
                                    elements=int(a.size),
                                    differing_elements=int(np.count_nonzero(a != b)) if same_contract else None)
    if not all(row['same_shape_dtype'] for row in comparisons.values()):
        raise ValueError('Second case is not a same-shape comparison')
    if not any(row['differing_elements'] > 0 for row in comparisons.values()):
        raise ValueError('Second original input is actually identical')
    return comparisons


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    if ROOT not in out.parents or out.exists():
        parser.error('fresh JSON output within validation_case0001 required')
    cases = {key: verify_case(key, value) for key, value in CASES.items()}
    first, second = cases.values()
    same_models = first['original_model_sha256'] == second['original_model_sha256']
    same_host = first['host_implementation_sha256'] == second['host_implementation_sha256']
    different_inputs = first['original_inputs_sha256'] != second['original_inputs_sha256']
    input_comparison = inspect_input_difference()
    report = dict(created_utc=datetime.now(timezone.utc).isoformat(), cases=cases,
                  verifier_sha256=sha(__file__), independent_original_golden_check=True,
                  comparator='Scalar Python float64 element loop; no deployment comparator import',
                  criterion='Each float abs(actual-golden) <= 0.001 + 0.001*abs(golden); integers exact',
                  scope='Two original random 128-frame/16-token Encoder->Decoder forward calls; not full ASR coverage',
                  no_fpga_access=True, no_inference_or_regenerated_golden=True,
                  same_models=same_models, same_host_implementation=same_host,
                  different_original_inputs=different_inputs,
                  original_input_tensor_comparison=input_comparison,
                  pass_all=same_models and same_host and different_inputs and all(c['pass_all'] for c in cases.values()))
    with out.open('x', encoding='utf-8') as stream:
        json.dump(report, stream, indent=2, allow_nan=False)
    print(json.dumps(report, indent=2, allow_nan=False))
    return 0 if report['pass_all'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
