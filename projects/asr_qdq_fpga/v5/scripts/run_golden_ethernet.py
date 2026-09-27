"""Original case_0000 acceptance over Ethernet; never a generated reference.

No device or socket access occurs on import or with --validate-only. All dynamic
Encoder arithmetic uses V5 FMA-compatible FPGA execution; Decoder preserves the
independently golden-tested V2 arithmetic commands on the same V5 FPGA. The parent
deployment workflow, not this script, owns bitstream programming and NIC setup.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import time
import traceback
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ASR = ROOT.parent
sys.path.insert(0, str(ROOT / 'host'))
from frozen_imports import FROZEN, require_frozen_modules

COMMON_FILE = ASR / 'golden_validation' / 'scripts' / 'golden_common.py'
spec = importlib.util.spec_from_file_location('v4_original_golden_common', COMMON_FILE)
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


def utc():
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.writing')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    os.replace(temporary, path)


def source_hashes():
    files = [Path(__file__).resolve(), COMMON_FILE]
    files.extend(sorted((ROOT / 'host').glob('*.py')))
    return {str(path): common.sha(path) for path in files}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--case-dir', type=Path, required=True, help='Original pinned golden case directory')
    p.add_argument('--model-dir', type=Path, required=True, help='Original encoder/decoder ONNX directory')
    p.add_argument('--host', default='169.254.35.4', help='FPGA IPv4; never configure the NIC here')
    p.add_argument('--bind-ip', '--local-host', dest='local_host', default='169.254.147.66')
    p.add_argument('--port', type=int, default=49152)
    p.add_argument('--timeout', type=float, default=5.0)
    p.add_argument('--retries', type=int, default=2, help='Only identical sequence/data retries, with FPGA deduplication')
    p.add_argument('--scope', choices=('full_chain', 'decoder_only'), default='full_chain')
    p.add_argument('--deadline-utc', help='Timezone-aware absolute deadline, checked for every network transaction')
    p.add_argument('--out', type=Path)
    p.add_argument('--bitstream', type=Path, help='Deployed V5 bitstream file, provenance only; never programs it')
    p.add_argument('--baseline', type=Path, default=ASR/'golden_validation/reports/case_0000_v2_20260922_170622/hardware_outputs.npz')
    p.add_argument('--validate-only', action='store_true', help='Validate original files; no device access or writes')
    p.add_argument('--allow-hardware', action='store_true', help='Explicitly enable Ethernet transactions')
    args = p.parse_args(argv)
    if args.timeout <= 0 or not 0 <= args.retries <= 10:
        p.error('timeout must be positive and retries must be between 0 and 10')
    cutoff = datetime.fromisoformat(args.deadline_utc.replace('Z', '+00:00')) if args.deadline_utc else None
    if cutoff is not None and (cutoff.tzinfo is None or cutoff <= datetime.now(timezone.utc)):
        p.error('Deadline must be timezone-aware and in the future')
    common.verify_freeze(FROZEN)
    inputs, expected, provenance = common.load_golden(FROZEN, args.case_dir, args.model_dir)
    baseline = baseline_provenance = None
    if args.scope == 'decoder_only':
        baseline_result = args.baseline.parent / 'result.json'
        if not args.baseline.is_file() or not baseline_result.is_file():
            p.error('decoder_only requires the prior physical V2 output and its result.json')
        previous = common.read_json(baseline_result)
        if not all(previous.get(key) is True for key in ('completed', 'physical_fpga_executed', 'golden_pass', 'end_provenance_verified')):
            p.error('Prior physical V2 run must be complete, provenance-verified and golden-pass')
        if previous.get('scope') != 'decoder_only' or previous.get('provenance') != provenance:
            p.error('Prior physical V2 run must have the same isolated Decoder scope and original provenance')
        with np.load(args.baseline, allow_pickle=False) as saved:
            baseline = saved['decoder_log_probs'].copy()
        if not common.compare_golden(baseline, expected['decoder_log_probs'])['pass_golden']:
            p.error('Prior physical V2 output no longer agrees with original golden data')
        baseline_provenance = dict(path=str(args.baseline.resolve()), sha256=common.sha(args.baseline),
                                   result_path=str(baseline_result.resolve()), result_sha256=common.sha(baseline_result),
                                   required_bit_exact=True)
    if args.validate_only:
        print(json.dumps(dict(validation='PASS', hardware_accessed=False, provenance=provenance,
                              v2_physical_baseline=baseline_provenance), indent=2))
        return 0
    if not args.allow_hardware or args.out is None or args.bitstream is None:
        p.error('Physical execution requires --allow-hardware, --out and --bitstream')
    if not args.bitstream.is_file():
        p.error('The recorded deployed bitstream must exist')
    out = args.out.resolve()
    if (ROOT / 'reports').resolve() not in out.parents:
        p.error('--out must be a fresh child of v5/reports')
    out.mkdir(parents=True, exist_ok=False)
    for filename in ('inputs.npz', 'expected.npz', 'inputs.bin', 'expected.bin', 'case.json'):
        shutil.copy2(args.case_dir / filename, out / filename)
    shutil.copy2(Path(__file__), out / Path(__file__).name)
    shutil.copy2(COMMON_FILE, out / 'golden_common.py')
    from ethernet_transport import EthernetBackend, open_link
    from compat_ethernet import CompatEthernetBackend
    from onnx_executor_v5 import OnnxExecutor as CompatExecutor
    _, _, executor_module = require_frozen_modules()
    import onnx
    hashes = source_hashes()
    report = dict(schema='asr-original-golden-ethernet-v5', started_utc=utc(), pid=os.getpid(),
                  completed=False, physical_fpga_executed=False, golden_pass=False, acceptance_pass=False,
                  scope=args.scope, golden_pass_scope=args.scope,
                  scope_description=('Original case_0000 Encoder 12 layers -> Decoder 6 layers, one call each'
                                     if args.scope == 'full_chain' else
                                     'Original case_0000 isolated complete Decoder; original tokens and golden encoder memory'),
                  full_chain_tested=False, encoder_hardware_executed=False,
                  ctc_included=False, new_cropped_input=False, model_modified=False,
                  cpu_arithmetic_fallback=False, golden_reference_regenerated=False,
                  numerical_implementation='Encoder V5 physical FMA/MLAS order; Decoder legacy V2 physical arithmetic; original INT16 QDQ graph',
                  cpu_work='Static constant folding, storage/indexing and protocol packing; no dynamic numerical fallback',
                  transport='IPv4 UDP', fpga_endpoint=[args.host, args.port], local_host=args.local_host,
                  deadline_utc=cutoff.isoformat() if cutoff else None,
                  per_attempt_timeout_seconds=args.timeout, identical_packet_retries=args.retries,
                  provenance=provenance, frozen_root=str(FROZEN),
                  freeze_manifest_sha256=common.sha(FROZEN / 'FREEZE_MANIFEST.json'),
                  bitstream_file=str(args.bitstream.resolve()), bitstream_file_sha256=common.sha(args.bitstream),
                  bitstream_readback_hash_available=False, source_sha256=hashes,
                  versions=dict(python=platform.python_version(), numpy=np.__version__, onnx=onnx.__version__),
                  acceptance=dict(float_atol=1e-3, float_rtol=1e-3, integer_exact=True,
                                  dtype_shape_finite_required=True, criterion_fixed_before_hardware=True),
                  stages={}, golden_comparisons={})
    if baseline_provenance is not None:
        report['v2_physical_baseline'] = baseline_provenance
    atomic_json(out / 'run_manifest.json', report)
    backend = link = None
    started = time.perf_counter()
    deadline_monotonic = started + (cutoff - datetime.now(timezone.utc)).total_seconds() if cutoff else None
    status = dict(stage='opening_ethernet', node=0, total_nodes=0)
    last_save = 0.0
    checkpoints = 0
    trace_nodes = 0

    def check_deadline():
        if deadline_monotonic is not None and time.perf_counter() >= deadline_monotonic:
            raise TimeoutError('Acceptance deadline reached; incomplete is neither a numeric pass nor numeric fail')

    def save_status(force=False):
        nonlocal last_save
        now = time.perf_counter()
        if force or now - last_save >= 10:
            last_save = now
            visible = dict(status, pid=os.getpid(), elapsed_seconds=now-started,
                           last_update_utc=utc(), golden_comparisons=report['golden_comparisons'])
            if backend is not None:
                visible['backend'] = backend.report()
            atomic_json(out / 'progress.json', visible)
            print(json.dumps(visible), flush=True)

    def progress(current, total, name, op):
        check_deadline()
        status.update(node=current, total_nodes=total, node_name=name, operator=op)
        save_status()

    def trace(node, outputs):
        nonlocal checkpoints, trace_nodes
        trace_nodes += 1
        if trace_nodes > 20 and node.op_type not in ('LayerNormalization', 'Softmax', 'LogSoftmax'):
            return
        destination = out / 'checkpoints'
        destination.mkdir(exist_ok=True)
        checkpoints += 1
        filename = f'{status["stage"]}_{checkpoints:04d}.npz'
        np.savez(destination / filename, **outputs)
        with (destination / 'index.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(dict(file=filename, stage=status['stage'], node_name=node.name,
                                         operator=node.op_type, outputs={k: list(v.shape) for k, v in outputs.items()},
                                         sha256=common.sha(destination / filename))) + '\n')

    try:
        check_deadline()
        save_status(True)
        link = open_link(args.host, args.port, local_host=args.local_host,
                         timeout=args.timeout, retries=args.retries, deadline=deadline_monotonic)
        backend = CompatEthernetBackend(link) if args.scope=='full_chain' else EthernetBackend(link)
        original_exchange = link.exchange

        def measured_exchange(*a, **kw):
            check_deadline()
            result = original_exchange(*a, **kw)
            save_status()
            check_deadline()
            return result

        link.exchange = measured_exchange
        report['live_protocol'] = dict(info='ASR2', version=backend.version,
                                       memory_words=backend.memory_words, ethernet=link.report())
        atomic_json(out / 'run_manifest.json', report)
        if args.scope == 'full_chain':
            status.update(stage='hardware_encoder', node=0, total_nodes=0)
            encoder = CompatExecutor(args.model_dir / 'encoder.onnx', backend)
            stage_start = time.perf_counter()
            report['physical_fpga_executed'] = True
            memory = encoder.run({'feats': inputs['feats']}, progress=progress, trace=trace)
            report['encoder_hardware_executed'] = True
            np.savez(out / 'hardware_encoder.npz', **memory)
            report['stages']['encoder'] = dict(seconds=time.perf_counter()-stage_start, execution=encoder.last_stats)
            del encoder
            for key in ('memory', 'memory_lengths'):
                report['golden_comparisons']['encoder_' + key] = common.compare_golden(memory[key], expected['encoder_' + key])
            atomic_json(out / 'encoder_golden_comparison.json', report['golden_comparisons'])
            save_status(True)
        else:
            memory = {'memory': expected['encoder_memory'].copy()}
            report['decoder_input_source'] = 'User original golden encoder_memory; isolated Decoder ONLY'
        status.update(stage='hardware_decoder', node=0, total_nodes=0)
        trace_nodes = 0
        if args.scope=='full_chain':
            report['encoder_backend']=backend.report()
            # Same physical link and resident engine; old command semantics for
            # independently verified Decoder. No golden memory substitution.
            backend=EthernetBackend(link)
        decoder = executor_module.OnnxExecutor(args.model_dir / 'decoder.onnx', backend)
        stage_start = time.perf_counter()
        report['physical_fpga_executed'] = True
        decoded = decoder.run({'memory': memory['memory'], 'tokens': inputs['tokens']}, progress=progress, trace=trace)
        report['stages']['decoder'] = dict(seconds=time.perf_counter()-stage_start, execution=decoder.last_stats)
        report['decoder_uses_actual_encoder_output'] = args.scope == 'full_chain'
        hardware = dict(decoder_log_probs=decoded['log_probs'])
        if args.scope == 'full_chain':
            hardware.update(encoder_memory=memory['memory'], encoder_memory_lengths=memory['memory_lengths'])
        np.savez(out / 'hardware_outputs.npz', **hardware)
        report['golden_comparisons']['decoder_log_probs'] = common.compare_golden(decoded['log_probs'], expected['decoder_log_probs'])
        report['full_chain_tested'] = args.scope == 'full_chain'
        report['completed'] = True
        report['golden_pass'] = common.all_golden_pass(report['golden_comparisons'], args.scope)
        if baseline is not None:
            report['v2_physical_comparison'] = common.compare_golden(decoded['log_probs'], baseline, atol=0, rtol=0)
            report['transport_regression_pass'] = bool(report['v2_physical_comparison']['pass_golden'] and
                                                       report['v2_physical_comparison'].get('bit_exact'))
        common.verify_freeze(FROZEN)
        _, _, after = common.load_golden(FROZEN, args.case_dir, args.model_dir)
        if after != provenance or source_hashes() != hashes:
            raise RuntimeError('Golden/model/harness changed during run')
        if common.sha(args.bitstream) != report['bitstream_file_sha256']:
            raise RuntimeError('Recorded bitstream artifact changed during run')
        if baseline is not None and common.sha(args.baseline) != report['v2_physical_baseline']['sha256']:
            raise RuntimeError('Physical V2 baseline changed during run')
        if baseline_provenance is not None and common.sha(baseline_result) != baseline_provenance['result_sha256']:
            raise RuntimeError('Physical V2 baseline acceptance report changed during run')
        report['end_provenance_verified'] = True
        report['acceptance_pass'] = report['golden_pass'] and report.get('transport_regression_pass', True)
        status['stage'] = ('completed_pass' if report['acceptance_pass'] else
                           'completed_golden_fail' if not report['golden_pass'] else 'completed_transport_regression_fail')
    except BaseException as exc:
        report.update(golden_pass=False, acceptance_pass=False, error=f'{type(exc).__name__}: {exc}')
        report['deadline_exceeded'] = deadline_monotonic is not None and time.perf_counter() >= deadline_monotonic
        status.update(stage='failed', error=report['error'])
        traceback.print_exc()
    finally:
        if backend is not None:
            report['backend'] = backend.report()
            backend.close()
        elif link is not None:
            link.stream.close()
        if link is not None:
            report['ethernet_after_close'] = link.report()
            if not link.close_confirmed or link.poisoned:
                report['acceptance_pass']=False
                status.update(stage='failed_session_close')
        report.update(finished_utc=utc(), elapsed_seconds=time.perf_counter()-started, checkpoint_files=checkpoints)
        atomic_json(out / 'result.json', report)
        save_status(True)
    return 0 if report['completed'] and report['acceptance_pass'] and report.get('end_provenance_verified') else 1


if __name__ == '__main__':
    raise SystemExit(main())
