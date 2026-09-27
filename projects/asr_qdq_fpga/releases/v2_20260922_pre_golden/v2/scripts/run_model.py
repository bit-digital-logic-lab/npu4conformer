"""Full, unmodified model on V2. Explicit hardware selection; no CPU fallback.

Run from ASR root: python -B -m v2.scripts.run_model --port COM8 --baud 921600
Smaller --frames/--tokens values select a NEW INPUT, not a smaller model and
not the pre-existing case's expected output. All layers/weights stay intact.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
import numpy as np
from host.model_manifest import DEFAULT_MODEL_DIR, DEFAULT_CASE_DIR, audit_model_a
from host.model_a import compare
from host.onnx_executor import OnnxExecutor as ReferenceExecutor, SoftwareBackend
from host.transport import open_link
from v2.host.onnx_executor import OnnxExecutor
from v2.host.transport import BufferedBackend


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', required=True)
    p.add_argument('--baud', type=int, default=921600)
    p.add_argument('--timeout', type=float, default=30)
    p.add_argument('--model-dir', type=Path, default=DEFAULT_MODEL_DIR)
    p.add_argument('--case-dir', type=Path, default=DEFAULT_CASE_DIR)
    p.add_argument('--frames', type=int)
    p.add_argument('--tokens', type=int)
    p.add_argument('--out', type=Path, default=Path('v2/reports/full_case0000'))
    p.add_argument('--max-seconds', type=float, default=0,
                   help='Optional explicit bounded experiment; 0 means no time limit')
    args=p.parse_args(argv)
    out=args.out.resolve()
    for protected in (args.model_dir.resolve(), args.case_dir.resolve()):
        if out==protected or protected in out.parents:
            p.error('Output must not be in original model/case directories')
    out.mkdir(parents=True,exist_ok=True)
    if (out/'result.json').exists():
        p.error('Choose a new output directory; refusing to overwrite an earlier run')
    report=dict(schema='asr-v2-full-model-run-1', started_utc=datetime.now(timezone.utc).isoformat(),
                physical_fpga_executed=False, completed=False, model_modified=False,
                full_layers=dict(encoder=12,decoder=6,width=512,vocabulary=5000),
                port=args.port,baud=args.baud,stages={},
                scope='All original Encoder/Decoder layers, one supplied token prefix; no audio/WER claim',
                numerical_contract='INT16 x INT16 -> signed48 -> FP32 scaling; V1 FTZ/approximations retained')
    backend=None
    started=time.perf_counter()
    status={}
    def save_status(force=False):
        now=time.perf_counter()
        if force or now-status.get('_last_save',0)>=15:
            status['_last_save']=now
            visible={k:v for k,v in status.items() if not k.startswith('_')}
            visible['elapsed_seconds']=now-started
            if backend is not None:
                visible['backend']=backend.report()
            (out/'progress.json').write_text(json.dumps(visible,indent=2,default=int)+'\n',encoding='utf-8')
            print(json.dumps(visible,default=int),flush=True)
    def progress(current,total,name,op):
        status.update(node=current,total_nodes=total,node_name=name,operator=op)
        save_status()
    try:
        audit=audit_model_a(args.model_dir)
        report['model_manifest']=audit
        if not audit['coverage_pass']:
            raise RuntimeError(str(audit['issues']))
        with np.load(args.case_dir/'inputs.npz') as data:
            feats,tokens=data['feats'].copy(),data['tokens'].copy()
        original_shapes=[list(feats.shape),list(tokens.shape)]
        if args.frames is not None:
            if not 7<=args.frames<=feats.shape[1]: raise ValueError('frames must be 7..original count')
            feats=feats[:,:args.frames].copy()
        if args.tokens is not None:
            if not 1<=args.tokens<=tokens.shape[1]: raise ValueError('tokens must be 1..original count')
            tokens=tokens[:,:args.tokens].copy()
        report.update(feats_shape=list(feats.shape),tokens_shape=list(tokens.shape),
                      original_shapes=original_shapes,
                      new_cropped_input=[list(feats.shape),list(tokens.shape)]!=original_shapes)
        np.savez(out/'inputs.npz',feats=feats,tokens=tokens)
        # Independent software reference is explicitly separated from evidence
        # of hardware execution. Never used to fill missing hardware results.
        reference_backend=SoftwareBackend()
        status['stage']='software_reference_encoder'
        encoder=ReferenceExecutor(args.model_dir/'encoder.onnx',reference_backend)
        reference_memory=encoder.run({'feats':feats},progress=progress)
        del encoder
        status['stage']='software_reference_decoder'
        decoder=ReferenceExecutor(args.model_dir/'decoder.onnx',reference_backend)
        reference_decoded=decoder.run({'memory':reference_memory['memory'],'tokens':tokens},progress=progress)
        del decoder
        np.savez(out/'software_reference.npz',encoder_memory=reference_memory['memory'],
                 encoder_memory_lengths=reference_memory['memory_lengths'],
                 decoder_log_probs=reference_decoded['log_probs'])
        backend=BufferedBackend(open_link(args.port,args.baud,args.timeout))
        report['physical_fpga_executed']=True
        hardware_started=time.perf_counter()
        original_request=backend.link.request
        def measured_request(*a,**kw):
            if args.max_seconds and time.perf_counter()-hardware_started>args.max_seconds:
                raise TimeoutError('Explicit experiment time budget exhausted between complete packets')
            result=original_request(*a,**kw)
            save_status()
            return result
        backend.link.request=measured_request
        status.update(stage='hardware_encoder',node=0)
        encoder=OnnxExecutor(args.model_dir/'encoder.onnx',backend)
        stage_start=time.perf_counter()
        memory=encoder.run({'feats':feats},progress=progress)
        report['stages']['encoder']=dict(elapsed_seconds=time.perf_counter()-stage_start,
                                          execution=encoder.last_stats)
        del encoder
        np.savez(out/'hardware_encoder.npz',**memory)
        status.update(stage='hardware_decoder',node=0)
        decoder=OnnxExecutor(args.model_dir/'decoder.onnx',backend)
        stage_start=time.perf_counter()
        decoded=decoder.run({'memory':memory['memory'],'tokens':tokens},progress=progress)
        report['stages']['decoder']=dict(elapsed_seconds=time.perf_counter()-stage_start,
                                          execution=decoder.last_stats)
        report['decoder_uses_actual_encoder_output']=True
        np.savez(out/'hardware_outputs.npz',encoder_memory=memory['memory'],
                 encoder_memory_lengths=memory['memory_lengths'],decoder_log_probs=decoded['log_probs'])
        report['software_reference_comparison']={
            'encoder_memory':compare(memory['memory'],reference_memory['memory']),
            'encoder_memory_lengths':compare(memory['memory_lengths'],reference_memory['memory_lengths']),
            'decoder_log_probs':compare(decoded['log_probs'],reference_decoded['log_probs'])}
        if not report['new_cropped_input']:
            with np.load(args.case_dir/'expected.npz') as expected:
                report['original_onnx_vectors_comparison']={
                    'encoder_memory':compare(memory['memory'],expected['encoder_memory']),
                    'decoder_log_probs':compare(decoded['log_probs'],expected['decoder_log_probs'])}
        report['completed']=True
        report['hardware_elapsed_seconds']=time.perf_counter()-hardware_started
        report['numerical_pass_atol_1e_3_rtol_1e_3']=all(
            c.get('atol_1e_3_rtol_1e_3_pass',False) for c in report['software_reference_comparison'].values())
        status['stage']='completed'
    except Exception as exc:
        report['error']=f'{type(exc).__name__}: {exc}'
        status.update(stage='failed',error=report['error'])
        print(report['error'],flush=True)
    finally:
        report['elapsed_seconds']=time.perf_counter()-started
        if backend is not None:
            report['backend']=backend.report()
            backend.close()
        save_status(force=True)
        (out/'result.json').write_text(json.dumps(report,indent=2,default=int)+'\n',encoding='utf-8')
    return 0 if report['completed'] and report.get('numerical_pass_atol_1e_3_rtol_1e_3') else 1


if __name__=='__main__':
    raise SystemExit(main())
