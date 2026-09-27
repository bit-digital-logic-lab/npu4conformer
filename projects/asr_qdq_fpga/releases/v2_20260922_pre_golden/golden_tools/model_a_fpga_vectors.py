#!/usr/bin/env python3
"""Random tensor -> actual Model A INT16-QDQ ONNX outputs, without speech/PyTorch.

Read-only model access. One case exercises Encoder, CTC and the complete
attention decoder (one next-token step using a supplied full prefix).
No frontend, autoregressive search, FPGA bus protocol or hidden Q-format assumed.
"""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import gc
import json
import math
from pathlib import Path
import platform
import sys
import time
import traceback
import numpy as np

from vector_io import (INPUT_KEYS, OUTPUT_KEYS, canonical, compare_array,
                       encode_feature_i16, load_npz, read_binary, read_json,
                       safe_child, save_tensor_set, sha256, verified_tensor_set, write_json)

VERSION = '1.0.0'
PARTS = ('encoder', 'ctc', 'decoder')
CONTRACTS = {
    'encoder': ({'feats': ('tensor(float)', 3)}, {'memory': ('tensor(float)', 3), 'memory_lengths': ('tensor(int64)', 1)}),
    'ctc': ({'memory': ('tensor(float)', 3)}, {'log_probs': ('tensor(float)', 3)}),
    'decoder': ({'memory': ('tensor(float)', 3), 'tokens': ('tensor(int64)', 2)}, {'log_probs': ('tensor(float)', 2)})}
DEFAULT_RUN = Path('temp/model_a_int16_runs/run01')


def utc():
    return datetime.now(timezone.utc).isoformat()


def stamp():
    return datetime.now().strftime('%Y%m%d_%H%M%S_%f')


def integer_list(text):
    try:
        values = [int(t.strip()) for t in text.split(',')]
    except ValueError as e:
        raise argparse.ArgumentTypeError('Use integers separated by commas') from e
    if not values or any(v < 1 for v in values) or len(values) != len(set(values)):
        raise argparse.ArgumentTypeError('Use distinct positive integers')
    return values


def _attr(node, key, default=None):
    from onnx import helper
    for a in node.attribute:
        if a.name == key:
            return helper.get_attribute_value(a)
    return default


class StaticValues:
    """Resolve only small constant/QDQ metadata expressions, never evaluate a network."""
    def __init__(self, model):
        self.initial = {i.name: i for i in model.graph.initializer}
        self.nodes = {v: n for n in model.graph.node for v in n.output}
        self.cache = {}

    def get(self, name, depth=0):
        from onnx import helper, numpy_helper
        if depth > 64:
            raise ValueError('Cyclic/deep constant expression')
        if name in self.cache:
            return self.cache[name]
        if name in self.initial:
            tensor = self.initial[name]
            if math.prod(tensor.dims) > 100000:
                raise ValueError(f'Refusing to materialize a large tensor as metadata: {name}')
            x = numpy_helper.to_array(tensor)
        elif name in self.nodes:
            n = self.nodes[name]
            if n.op_type == 'Constant':
                t = _attr(n, 'value')
                if t is not None:
                    if math.prod(t.dims) > 100000:
                        raise ValueError('Constant metadata too large')
                    x = numpy_helper.to_array(t)
                else:
                    choices = [('value_float', np.float32), ('value_floats', np.float32),
                               ('value_int', np.int64), ('value_ints', np.int64)]
                    found = [(val, dt) for key, dt in choices if (val := _attr(n, key)) is not None]
                    if len(found) != 1:
                        raise ValueError(f'Unsupported Constant: {name}')
                    x = np.array(found[0][0], dtype=found[0][1])
            elif n.op_type in ('Identity', 'Cast'):
                x = self.get(n.input[0], depth+1)
                if n.op_type == 'Cast':
                    x = x.astype(helper.tensor_dtype_to_np_dtype(_attr(n, 'to')))
            elif n.op_type == 'DequantizeLinear':
                if _attr(n, 'block_size', 0):
                    raise ValueError('Blocked constant DQ is not supported by this small metadata reader')
                q = self.get(n.input[0], depth+1)
                s = self.get(n.input[1], depth+1)
                z = self.get(n.input[2], depth+1) if len(n.input) >= 3 and n.input[2] else np.zeros_like(s, dtype=q.dtype)
                if s.ndim == 1 and s.size > 1:
                    axis = int(_attr(n, 'axis', 1))
                    if not -q.ndim <= axis < q.ndim:
                        raise ValueError(f'Invalid constant DQ axis: {name}')
                    shape = [1]*q.ndim
                    shape[axis] = s.size
                    s, z = s.reshape(shape), z.reshape(shape)
                x = (q.astype(s.dtype) - z.astype(s.dtype)) * s
            else:
                raise ValueError(f'Not a supported static metadata expression: {name} ({n.op_type})')
        else:
            raise KeyError(f'Constant {name!r} not present')
        x = np.array(x, copy=True)
        self.cache[name] = x
        return x


def all_tensors(graph):
    """Enumerate tensors for external-file provenance, including nested attributes."""
    import onnx
    yield from graph.initializer
    for sparse in graph.sparse_initializer:
        yield sparse.values
        yield sparse.indices
    for node in graph.node:
        for a in node.attribute:
            if a.type == onnx.AttributeProto.TENSOR:
                yield a.t
            elif a.type == onnx.AttributeProto.TENSORS:
                yield from a.tensors
            elif a.type == onnx.AttributeProto.GRAPH:
                yield from all_tensors(a.g)
            elif a.type == onnx.AttributeProto.GRAPHS:
                for sub in a.graphs:
                    yield from all_tensors(sub)


def inspect_graph(path, part):
    import onnx
    path = Path(path).resolve()
    model = onnx.load(str(path), load_external_data=False)
    external = {}
    for tensor in all_tensors(model.graph):
        if tensor.data_location == onnx.TensorProto.EXTERNAL:
            items = {v.key: v.value for v in tensor.external_data}
            ext = safe_child(path.parent, items['location'])
            if not ext.is_file():
                raise FileNotFoundError(ext)
            external[str(ext)] = sha256(ext)
    onnx.external_data_helper.load_external_data_for_model(model, str(path.parent))
    values = StaticValues(model)
    params, parameter_keys, records = {}, {}, []
    def save_param(name):
        if name not in parameter_keys:
            value = values.get(name)
            key = f'{part}_p{len(parameter_keys):05d}'
            params[key] = value
            parameter_keys[name] = key
        return parameter_keys[name]
    for i, node in enumerate(model.graph.node):
        if node.op_type not in ('QuantizeLinear', 'DequantizeLinear'):
            continue
        scale = values.get(node.input[1])
        if not np.isfinite(scale).all() or np.any(scale <= 0):
            raise ValueError(f'{part}: invalid QDQ scale in {node.name}')
        zp_name = node.input[2] if len(node.input) > 2 and node.input[2] else None
        zp = values.get(zp_name) if zp_name else None
        records.append(dict(node_index=i, node_name=node.name, op_type=node.op_type,
                            inputs=list(node.input), outputs=list(node.output),
                            axis=int(_attr(node, 'axis', 1)), block_size=int(_attr(node, 'block_size', 0)),
                            scale_key=save_param(node.input[1]),
                            zero_point_key=save_param(zp_name) if zp_name else None,
                            quantized_dtype=str(zp.dtype) if zp is not None else 'implicit_or_input_defined',
                            is_graph_input_boundary=node.input[0] in {x.name for x in model.graph.input},
                            is_graph_output_boundary=any(x in {v.name for v in model.graph.output} for x in node.output)))
    qnodes = [r for r in records if r['op_type'] == 'QuantizeLinear']
    if not qnodes or any(r['quantized_dtype'] != 'int16' for r in qnodes):
        raise ValueError(f'{part}: expected the existing INT16 activation-QDQ graph; refusing a different precision model')
    norm, norm_error = None, None
    if part == 'encoder':
        try:
            mean, std = values.get('feature_mean'), values.get('feature_std')
            if mean.size != std.size or not np.isfinite(mean).all() or not np.isfinite(std).all() or np.any(std <= 0):
                raise ValueError('Invalid effective normalization constants')
            norm = (mean.astype(np.float32).reshape(-1), std.astype(np.float32).reshape(-1))
        except (ValueError, KeyError) as exc:
            norm_error = str(exc)
    info = dict(path=str(path), sha256=sha256(path), external_sha256=external,
                opsets=[{'domain':o.domain, 'version':o.version} for o in model.opset_import],
                ir_version=model.ir_version, op_counts=dict(Counter(n.op_type for n in model.graph.node)),
                activation_q_nodes=len(qnodes), qdq_nodes=records,
                initializer_metadata_keys=parameter_keys, normalization_read_error=norm_error)
    del model, values
    gc.collect()
    return info, params, norm


def make_session(path, threads):
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    return ort.InferenceSession(str(path), sess_options=options, providers=['CPUExecutionProvider'])


def validate_ports(part, session):
    expected_in, expected_out = CONTRACTS[part]
    answer = {}
    for label, actual, expect in [('inputs',session.get_inputs(),expected_in), ('outputs',session.get_outputs(),expected_out)]:
        by_name = {v.name:v for v in actual}
        if set(by_name) != set(expect):
            raise ValueError(f'{part} {label}: expected {list(expect)}, got {list(by_name)}')
        for name, (dtype, rank) in expect.items():
            v = by_name[name]
            if v.type != dtype or len(v.shape) != rank:
                raise ValueError(f'{part}/{name}: incompatible ONNX type/shape {v.type}/{v.shape}')
        answer[label] = [{'name':v.name,'type':v.type,'shape':list(v.shape)} for v in actual]
    return answer


def check_feed(session, feed):
    types = {'tensor(float)':np.dtype('float32'), 'tensor(int64)':np.dtype('int64')}
    for port in session.get_inputs():
        x = feed[port.name]
        if x.dtype != types[port.type] or x.ndim != len(port.shape):
            raise ValueError(f'{port.name}: input type/rank does not match graph')
        for declared, observed in zip(port.shape,x.shape):
            if isinstance(declared,int) and declared != observed:
                raise ValueError(f'{port.name}: graph expects {port.shape}, generated {x.shape}')
        if not x.size or not np.isfinite(x).all():
            raise ValueError('Empty/nonfinite input')


def checked_run(session, names, feed):
    check_feed(session,feed)
    outputs = session.run(names,feed)
    if len(outputs) != len(names):
        raise ValueError('Incorrect number of graph outputs')
    for name, x in zip(names,outputs):
        if not isinstance(x,np.ndarray) or not x.size or not np.isfinite(x).all():
            raise ValueError(f'Graph output {name} is empty/nonfinite/not a tensor')
    return outputs


def run_case(sessions, inputs, vocab_size):
    if set(inputs) != set(INPUT_KEYS):
        raise ValueError('Logical case inputs must be exactly feats and tokens')
    feats,tokens = inputs['feats'],inputs['tokens']
    if feats.shape[0] != 1 or tokens.shape[0] != 1 or np.any(tokens < 0) or np.any(tokens >= vocab_size):
        raise ValueError('Batch must be 1; all token IDs must be in vocabulary')
    memory,lengths = checked_run(sessions['encoder'], ['memory','memory_lengths'], {'feats':feats})
    if memory.dtype != np.float32 or lengths.dtype != np.int64 or memory.ndim != 3 or memory.shape[0] != 1 or lengths.shape != (1,):
        raise ValueError('Invalid encoder output contract')
    # No padded examples: all time steps are valid. Never silently crop or pad.
    if int(lengths[0]) != memory.shape[1]:
        raise ValueError('Encoder output contains padding or invalid length; this unpadded test adapter needs a matching FPGA contract')
    ctc = checked_run(sessions['ctc'],['log_probs'],{'memory':memory})[0]
    dec = checked_run(sessions['decoder'],['log_probs'],{'memory':memory, 'tokens':tokens})[0]
    if ctc.shape != (1,memory.shape[1],vocab_size) or dec.shape != (1,vocab_size):
        raise ValueError(f'Unexpected CTC/decoder shape: {ctc.shape}/{dec.shape}')
    if ctc.dtype != np.float32 or dec.dtype != np.float32:
        raise ValueError('Expected original FLOAT32 probability-output ports')
    return dict(encoder_memory=memory, encoder_memory_lengths=lengths,
                ctc_log_probs=ctc, decoder_log_probs=dec)


def load_source(args):
    run = args.run_dir.expanduser().resolve()
    if not args.quant_name or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in args.quant_name):
        raise ValueError('Invalid quant-name')
    directory = run / args.quant_name
    bundle_path, qr_path, tokens_path = run/'bundle.json', directory/'report.json', run/'source_metadata/tokens.json'
    bundle, report, token_list = read_json(bundle_path),read_json(qr_path),read_json(tokens_path)
    if bundle.get('stage') != 'fp32_prepared' or report.get('status') != 'completed' or not report.get('all_components_converted'):
        raise ValueError('The existing FP32 preparation / INT16 conversion is not complete')
    if sha256(bundle_path) != report['source_bundle_sha256']:
        raise ValueError('bundle.json no longer matches the quantization report')
    if not isinstance(token_list,list) or not token_list or not all(isinstance(x,str) for x in token_list):
        raise ValueError('Invalid source_metadata/tokens.json')
    vocab = int(bundle['model']['vocab_size'])
    if len(token_list) != vocab:
        raise ValueError('Token list size differs from model metadata')
    if args.sos_id is None:
        indices = [i for i,t in enumerate(token_list) if t in ('<sos/eos>','<sos>')]
        if len(indices) != 1:
            raise ValueError('SOS cannot be unambiguously read from token list; supply verified --sos-id')
        sos = indices[0]
    else:
        sos = args.sos_id
    if not 0 <= sos < vocab:
        raise ValueError('SOS ID outside vocabulary')
    special = {int(bundle['model']['blank_id']),sos}
    special.update(i for i,t in enumerate(token_list) if t in ('<blank>','<sos/eos>','<sos>','<eos>','<unk>'))
    allowed = np.array([i for i in range(vocab) if i not in special],dtype=np.int64)
    if not allowed.size:
        raise ValueError('No legal nonspecial token IDs')
    if min(args.feature_frames) < 7 or max(args.feature_frames) > bundle['max_feature_frames'] or max(args.prefix_length) > bundle['max_prefix']:
        raise ValueError(f'Requested lengths exceed exported bounds: feature [7,{bundle["max_feature_frames"]}], prefix [1,{bundle["max_prefix"]}]')
    source_files = {str(p):sha256(p) for p in (bundle_path,qr_path,tokens_path)}
    info,params,norms = {},{},None
    for part in PARTS:
        path = directory/(part+'.onnx')
        actual = sha256(path)
        if actual != report['graph_sha256'][part]:
            raise ValueError(f'{part}: model hash differs from quantization report')
        print(f'INSPECT {part}: {path}',flush=True)
        graph_info,graph_params,norm = inspect_graph(path,part)
        if graph_info['sha256'] != actual:
            raise ValueError('Model changed during graph inspection')
        info[part] = graph_info
        params.update(graph_params)
        source_files[str(path)] = actual
        source_files.update(graph_info['external_sha256'])
        if part == 'encoder':
            norms = norm
    sessions = {}
    ports = {}
    for part in PARTS:
        print(f'LOAD INT16-QDQ {part}',flush=True)
        sessions[part] = make_session(info[part]['path'],args.threads)
        ports[part] = validate_ports(part,sessions[part])
    feature_port = sessions['encoder'].get_inputs()[0]
    fdim = feature_port.shape[-1]
    if not isinstance(fdim,int):
        if norms is None:
            raise ValueError('Feature dimension is symbolic and normalization constants unavailable')
        fdim = norms[0].size
    if args.feature_space == 'normalized' and (norms is None or norms[0].size != fdim):
        raise ValueError('Cannot read effective feature_mean/feature_std from encoder. Use --feature-space raw only deliberately; no silent fallback')
    if any(isinstance(sessions[p].get_outputs()[0].shape[-1],int) and sessions[p].get_outputs()[0].shape[-1] != vocab for p in ('ctc','decoder')):
        raise ValueError('Vocabulary dimension disagrees with graph ports')
    return dict(run=run,bundle=bundle,source_files=source_files,graphs=info,params=params,norms=norms,
                sessions=sessions,ports=ports,feature_dim=fdim,vocab=vocab,sos=sos,allowed=allowed)


def verify_sources(source_files):
    for path,expected in source_files.items():
        if sha256(Path(path)) != expected:
            raise ValueError(f'Protected source changed: {path}')


def random_case(seed,index,frames,prefix,fdim,allowed,sos,low,high,space,norms,wire_scale,wire_zero):
    rng = np.random.Generator(np.random.PCG64(np.random.SeedSequence([seed,index])))
    x = rng.uniform(low,high,size=(1,frames,fdim)).astype(np.float32)
    if space == 'normalized':
        if norms is None:
            raise ValueError('Normalization constants required')
        mean,std = norms
        x = np.ascontiguousarray(x*std.reshape(1,1,-1)+mean.reshape(1,1,-1),dtype=np.float32)
    tokens = rng.choice(allowed,size=(1,prefix)).astype(np.int64)
    tokens[0,0] = sos
    wire,wire_meta = None,None
    if wire_scale is not None:
        wire,x,wire_meta = encode_feature_i16(x,wire_scale,wire_zero)
    return {'feats':x,'tokens':tokens},wire,wire_meta


def generate(args):
    output = args.output_dir.expanduser().resolve()
    run = args.run_dir.expanduser().resolve()
    if output.is_relative_to(run) or run.is_relative_to(output):
        raise ValueError('Output directory must be separate from the protected run directory')
    output.mkdir(parents=True,exist_ok=False)
    report = dict(tool_version=VERSION,created_utc=utc(),status='generating',requested=args.count,
                  completed=0,real_model_inference_completed=False,fpga_executed=False,
                  golden_definition='Actual existing INT16-QDQ ONNX via CPUExecutionProvider, not PyTorch FP32',
                  scope='All three neural components; fixed externally supplied prefix; no frontend/beam-search/WER')
    report_path = output/'generation_report.json'
    write_json(report_path,report)
    started = time.perf_counter()
    try:
        source = load_source(args)
        import onnx,onnxruntime
        (output/'cases').mkdir()
        qp = output/'quantization_parameters.npz'
        with qp.open('xb') as f:
            np.savez(f,**source['params'])
        write_json(output/'graph_quantization.json',{
            'graphs':source['graphs'],
            'parameter_values_file':qp.name,'parameter_values_sha256':sha256(qp),
            'note':'Graph Q/DQ metadata, NOT a guessed FPGA port Q-format, bus layout or integer-only golden model'})
        specs = [dict(case_id=f'case_{i:04d}',case_index=i,
                      feature_frames=args.feature_frames[i % len(args.feature_frames)],
                      prefix_length=args.prefix_length[(i // len(args.feature_frames)) % len(args.prefix_length)])
                 for i in range(args.count)]
        dataset = dict(format_version=1,tool_version=VERSION,created_utc=utc(),
            case_count=args.count,source_files_sha256=source['source_files'],
            onnx_models={p:dict(path=source['graphs'][p]['path'],sha256=source['graphs'][p]['sha256']) for p in PARTS},
            ports=source['ports'],feature_dim=source['feature_dim'],vocab_size=source['vocab'],sos_id=source['sos'],
            seed=args.seed,prng='numpy.Generator(PCG64(SeedSequence([seed,case_index])))',
            feature_space=args.feature_space,random_distribution='uniform',low=args.low,high=args.high,
            normalization='feats=effective_ONNX_feature_mean+effective_ONNX_feature_std*U(low,high)' if args.feature_space=='normalized' else 'feats=U(low,high)',
            feature_wire_scale=args.feature_wire_scale,feature_wire_zero_point=args.feature_wire_zero_point,
            threads=args.threads,provider='CPUExecutionProvider',graph_optimization='ORT_DISABLE_ALL',
            versions={'python':platform.python_version(),'numpy':np.__version__,'onnx':onnx.__version__,'onnxruntime':onnxruntime.__version__},
            test_scope='Encoder(feats) -> {CTC(memory), full-prefix Decoder(memory,tokens)}; no waveform frontend, no search loop, no hardware bus validation',
            output_keys=list(OUTPUT_KEYS),specifications=specs,
            companion_files_sha256={'graph_quantization.json':sha256(output/'graph_quantization.json'),qp.name:sha256(qp)},
            scripts_sha256={p.name:sha256(p) for p in (Path(__file__).resolve(),Path(__file__).resolve().with_name('vector_io.py'))})
        write_json(output/'dataset.json',dataset)
        index = output/'cases.jsonl'
        with index.open('x',encoding='utf-8',newline='\n') as idx:
            for spec in specs:
                uid,i = spec['case_id'],spec['case_index']
                directory = output/'cases'/uid
                directory.mkdir(exist_ok=False)
                inputs,wire,wire_meta = random_case(args.seed,i,spec['feature_frames'],spec['prefix_length'],
                    source['feature_dim'],source['allowed'],source['sos'],args.low,args.high,
                    args.feature_space,source['norms'],args.feature_wire_scale,args.feature_wire_zero_point)
                input_desc = save_tensor_set(directory,'inputs',inputs,hex_bytes=args.hex)
                # Run the persisted logical values, not an unsaved precursor to a wire quantization.
                restored_inputs = verified_tensor_set(directory,input_desc)
                for k in INPUT_KEYS:
                    if canonical(restored_inputs[k]).tobytes() != canonical(inputs[k]).tobytes():
                        raise ValueError('Serialized model input changed')
                case_start = time.perf_counter()
                expected = run_case(source['sessions'],restored_inputs,source['vocab'])
                output_desc = save_tensor_set(directory,'expected',expected,hex_bytes=args.hex)
                verified_tensor_set(directory,output_desc)
                case = dict(**spec,seed_entropy=[args.seed,i],inputs=input_desc,expected=output_desc,
                    inference_seconds=time.perf_counter()-case_start,
                    edges=[{'source':'inputs.feats','destination':'encoder.feats'},
                           {'source':'expected.encoder_memory','destination':'ctc.memory', 'whole_chain_rule':'FPGA must use its own encoder output; reference memory is for isolated head tests only'},
                           {'source':'expected.encoder_memory','destination':'decoder.memory'},
                           {'source':'inputs.tokens','destination':'decoder.tokens'}],
                    decoder_evaluation='One next-token distribution at fixed supplied full prefix, not whole beam-search transcription')
                if wire is not None:
                    case['feature_wire'] = save_tensor_set(directory,'feature_wire',{'feats_i16':wire},hex_bytes=args.hex)
                    case['feature_wire_contract'] = wire_meta
                    # Prove the transmitted int16 code reconstructs the same saved ONNX input.
                    w = verified_tensor_set(directory,case['feature_wire'])['feats_i16']
                    back = (w.astype(np.float32)-np.float32(args.feature_wire_zero_point))*np.float32(args.feature_wire_scale)
                    if canonical(back).tobytes() != canonical(inputs['feats']).tobytes():
                        raise ValueError('Wire input does not reproduce actual model input')
                write_json(directory/'case.json',case)
                idx.write(json.dumps({'case_id':uid,'case_file':f'cases/{uid}/case.json','case_sha256':sha256(directory/'case.json')},allow_nan=False)+'\n')
                idx.flush()
                report.update(completed=i+1,elapsed_seconds=time.perf_counter()-started)
                write_json(report_path,report)
                print(f'CASE {i+1}/{args.count}: {uid} feats={inputs["feats"].shape} tokens={inputs["tokens"].shape} memory={expected["encoder_memory"].shape}',flush=True)
        verify_sources(source['source_files'])
        report.update(status='completed',real_model_inference_completed=True,source_files_unchanged=True,
                      dataset_sha256=sha256(output/'dataset.json'),cases_index_sha256=sha256(index),
                      elapsed_seconds=time.perf_counter()-started,
                      oracle_scope='Actual INT16-QDQ software reference; FPGA numerical/bitwise equivalence not yet measured')
        write_json(report_path,report)
        print(f'GENERATE COMPLETE: {args.count} input/output pairs\nDATASET: {output}\nREPORT: {report_path}',flush=True)
        return 0
    except BaseException as exc:
        report.update(status='interrupted' if isinstance(exc,KeyboardInterrupt) else 'failed',
                      error=f'{type(exc).__name__}: {exc}',traceback=traceback.format_exc(),
                      elapsed_seconds=time.perf_counter()-started)
        write_json(report_path,report)
        raise


def load_dataset(directory):
    root = Path(directory).resolve()
    report,dataset = read_json(root/'generation_report.json'),read_json(root/'dataset.json')
    if report.get('status') != 'completed' or not report.get('real_model_inference_completed'):
        raise ValueError('Dataset generation is incomplete; partial cases are not a completed FPGA test set')
    if sha256(root/'dataset.json') != report['dataset_sha256'] or sha256(root/'cases.jsonl') != report['cases_index_sha256']:
        raise ValueError('Dataset/index hash mismatch')
    for p,h in dataset['companion_files_sha256'].items():
        if sha256(safe_child(root,p)) != h:
            raise ValueError('Companion metadata changed')
    rows = [json.loads(line) for line in (root/'cases.jsonl').read_text(encoding='utf-8').splitlines() if line.strip()]
    if len(rows) != dataset['case_count'] or len({r['case_id'] for r in rows}) != len(rows):
        raise ValueError('Case count/uniqueness mismatch')
    if [r['case_id'] for r in rows] != [r['case_id'] for r in dataset['specifications']]:
        raise ValueError('Case order/identity differs from frozen specifications')
    return root,dataset,rows


def load_case(root,row):
    path = safe_child(root,row['case_file'])
    if sha256(path) != row['case_sha256']:
        raise ValueError(f'Case hash mismatch: {row["case_id"]}')
    case = read_json(path)
    if case['case_id'] != row['case_id']:
        raise ValueError('Case identity mismatch')
    inputs = verified_tensor_set(path.parent,case['inputs'])
    expected = verified_tensor_set(path.parent,case['expected'])
    if set(inputs) != set(INPUT_KEYS) or set(expected) != set(OUTPUT_KEYS):
        raise ValueError('Case keys are incomplete')
    if 'feature_wire' in case:
        q = verified_tensor_set(path.parent,case['feature_wire'])['feats_i16']
        c = case['feature_wire_contract']
        x = (q.astype(np.float32)-np.float32(c['zero_point']))*np.float32(c['scale'])
        if canonical(x).tobytes() != canonical(inputs['feats']).tobytes():
            raise ValueError('Stored feature wire/logical input correspondence broken')
    return case,inputs,expected


def result_report_path(args,root,label):
    path = (args.report or root.parent/f'{root.name}_{label}_{stamp()}.json').resolve()
    if path.is_relative_to(root):
        raise ValueError('Write comparison reports outside the frozen golden dataset')
    if getattr(args,'actual_dir',None) is not None:
        actual_root = args.actual_dir.resolve()
        if path.is_relative_to(actual_root):
            raise ValueError('Write comparison reports outside FPGA output files')
    if path.exists():
        raise FileExistsError(f'Report already exists: {path}')
    path.parent.mkdir(parents=True,exist_ok=True)
    return path


def replay(args):
    root,dataset,rows = load_dataset(args.vectors)
    out = result_report_path(args,root,'replay')
    verify_sources(dataset['source_files_sha256'])
    sessions = {p:make_session(dataset['onnx_models'][p]['path'],args.threads) for p in PARTS}
    for p in PARTS:
        validate_ports(p,sessions[p])
    results = []
    for i,row in enumerate(rows):
        case,inputs,expected = load_case(root,row)
        got = run_case(sessions,inputs,dataset['vocab_size'])
        comparisons = {k:compare_array(expected[k],got[k],atol=args.atol,rtol=args.rtol) for k in OUTPUT_KEYS}
        results.append(dict(case_id=row['case_id'],tensors=comparisons))
        print(f'REPLAY {i+1}/{len(rows)} {row["case_id"]}',flush=True)
    verify_sources(dataset['source_files_sha256'])
    passed = all(v['structural_passed'] and v['numeric_threshold_passed'] for r in results for v in r['tensors'].values())
    write_json(out,dict(command='replay',created_utc=utc(),processed=len(rows),expected=len(rows),
                        passed=passed,fpga_executed=False,atol=args.atol,rtol=args.rtol,results=results))
    print(f'REPLAY {"PASSED" if passed else "FAILED"}: {out}')
    return 0 if passed else 2


def compare(args):
    root,dataset,rows = load_dataset(args.vectors)
    actual_root = args.actual_dir.expanduser().resolve()
    if actual_root.is_relative_to(root) or root.is_relative_to(actual_root):
        raise ValueError('FPGA actual directory must be separate from the golden dataset')
    out = result_report_path(args,root,'fpga_compare')
    results,failures = [],[]
    for row in rows:
        uid = row['case_id']
        try:
            case,inputs,expected = load_case(root,row)
            actual_path = actual_root/uid/('outputs.'+args.format)
            before = sha256(actual_path)
            actual = load_npz(actual_path) if args.format=='npz' else read_binary(actual_path,case['expected'])
            if set(actual) != set(OUTPUT_KEYS):
                raise ValueError(f'Expected output keys {OUTPUT_KEYS}; got {list(actual)}')
            comps = {k:compare_array(expected[k],actual[k],atol=args.atol,rtol=args.rtol) for k in OUTPUT_KEYS}
            if sha256(actual_path) != before:
                raise ValueError('FPGA file changed during comparison')
            results.append(dict(case_id=uid,actual_path=str(actual_path),actual_sha256=before,tensors=comps))
        except Exception as e:
            failures.append(dict(case_id=uid,error=f'{type(e).__name__}: {e}'))
    structural = not failures and all(v['structural_passed'] for r in results for v in r['tensors'].values())
    integer_ok = structural and all(r['tensors']['encoder_memory_lengths']['numeric_threshold_passed'] is True for r in results)
    configured = args.atol is not None
    passed = (structural and all(v['numeric_threshold_passed'] is True for r in results for v in r['tensors'].values())) if configured else None
    report = dict(command='compare',created_utc=utc(),expected=len(rows),processed=len(results),
        structural_passed=structural,integer_outputs_equal=integer_ok,fpga_numeric_thresholds_configured=configured,fpga_numeric_threshold_passed=passed,
        bitwise_equal_all=structural and all(v.get('bitwise_equal',False) for r in results for v in r['tensors'].values()),
        atol=args.atol,rtol=args.rtol,declared_execution_mode=args.mode,
        execution_mode_verified_by_tool=False,
        note='Compares supplied files; does not operate hardware or prove which inputs/bitstream produced them. Integer lengths exact; FLOAT outputs in ONNX logical domain.',
        failures=failures,results=results)
    write_json(out,report)
    print(json.dumps({k:report[k] for k in ('expected','processed','structural_passed','integer_outputs_equal','fpga_numeric_thresholds_configured','fpga_numeric_threshold_passed')},indent=2))
    print(f'COMPARE REPORT: {out}')
    return 2 if not structural or not integer_ok or passed is False else 0


def parse_args(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command',required=True)
    g = sub.add_parser('generate',help='Create random inputs and actual INT16-QDQ reference outputs')
    g.add_argument('--run-dir',type=Path,default=DEFAULT_RUN)
    g.add_argument('--quant-name',default='int16_qdq_fix01')
    g.add_argument('--output-dir',type=Path,required=True)
    g.add_argument('--count',type=int,default=200)
    g.add_argument('--seed',type=int,default=20260918)
    g.add_argument('--feature-frames',type=integer_list,default=[128],help='One fixed length or comma-separated lengths; no padding')
    g.add_argument('--prefix-length',type=integer_list,default=[16],help='One fixed length or comma-separated lengths; includes SOS')
    g.add_argument('--feature-space',choices=['normalized','raw'],default='normalized')
    g.add_argument('--low',type=float,default=-2.0)
    g.add_argument('--high',type=float,default=2.0)
    g.add_argument('--sos-id',type=int,help='Only required if token metadata has no unambiguous SOS')
    g.add_argument('--feature-wire-scale',type=float,help='OPTIONAL verified FPGA scalar int16 feature-port scale; not inferred from ONNX')
    g.add_argument('--feature-wire-zero-point',type=int,default=0)
    g.add_argument('--hex',action='store_true',help='Additionally write byte-oriented HEX: one 8-bit byte per line')
    g.add_argument('--threads',type=int,default=4)
    r = sub.add_parser('replay',help='Replay all saved inputs through the same source graphs; not FPGA verification')
    r.add_argument('--vectors',type=Path,required=True)
    r.add_argument('--threads',type=int,default=4)
    r.add_argument('--atol',type=float,default=0.0)
    r.add_argument('--rtol',type=float,default=0.0)
    r.add_argument('--report',type=Path)
    c = sub.add_parser('compare',help='Compare supplied FPGA outputs; float tolerances optional and must be chosen explicitly')
    c.add_argument('--vectors',type=Path,required=True)
    c.add_argument('--actual-dir',type=Path,required=True)
    c.add_argument('--format',choices=['npz','bin'],default='npz')
    c.add_argument('--mode',choices=['chained','isolated-components'],default='chained')
    c.add_argument('--atol',type=float)
    c.add_argument('--rtol',type=float)
    c.add_argument('--report',type=Path)
    args = p.parse_args(argv)
    if hasattr(args,'threads') and args.threads < 1:
        p.error('threads must be positive')
    if args.command=='generate':
        if args.count < 1 or args.seed < 0:
            p.error('count must be positive and seed nonnegative')
        if not all(math.isfinite(v) for v in (args.low,args.high)) or args.low >= args.high:
            p.error('Require finite low < high')
        if not np.isfinite(np.float32(args.low)) or not np.isfinite(np.float32(args.high)):
            p.error('Random range must fit float32')
        if args.feature_wire_scale is not None:
            s = np.float32(args.feature_wire_scale)
            if not np.isfinite(s) or s <= 0 or not -32768<=args.feature_wire_zero_point<=32767:
                p.error('Invalid int16 feature wire scale / zero point')
        elif args.feature_wire_zero_point != 0:
            p.error('--feature-wire-zero-point requires --feature-wire-scale')
    else:
        if (args.atol is None) != (args.rtol is None):
            p.error('Supply both --atol and --rtol, or neither')
        if args.atol is not None and any(not math.isfinite(v) or v<0 for v in (args.atol,args.rtol)):
            p.error('Tolerances must be finite and nonnegative')
    return args


def main(argv=None):
    args = parse_args(argv)
    return {'generate':generate,'replay':replay,'compare':compare}[args.command](args)


if __name__=='__main__':
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print('Interrupted. Preserve partial directory; it is NOT a completed golden set.',file=sys.stderr)
        raise SystemExit(130)
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)
