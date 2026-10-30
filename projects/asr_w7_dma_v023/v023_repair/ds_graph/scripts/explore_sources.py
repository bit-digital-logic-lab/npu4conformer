#!/usr/bin/env python3
"""Resolve what the sealed V022 tree actually contains (read-only).

The 68 closed programs are in the V022 manifest.  The "outer 591" is not a
source file in the supplied tree, but the sealed board result does contain the
per-queue ledger: shape, parameter id/address, C address and measured cycles
for all 591 queue tasks.  This script recovers that ledger, labels every task
with its parameter name from the manifest directory, and records the files that
are genuinely absent (executor / profiled backend / ONNX).

No write outside this task directory.
"""
import hashlib
import json
import os
import re
import struct
import sys
import zipfile
from pathlib import Path

TASK = Path(__file__).resolve().parents[1]
PROJ = TASK.parents[1]
WORK = PROJ / 'work'
ZIP = PROJ / 'model_a_v0_22(1).zip'
MANIFEST = PROJ / 'tasks' / 'ds_pl_autonomy' / 'assets' / 'manifest_v022.json'
OUT = TASK / 'analysis'
OUT.mkdir(parents=True, exist_ok=True)

RESULT_MEMBER = 'model_a_v0_22/reports/case0000_board001/result.json'


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def numel(shape):
    n = 1
    for d in shape:
        n *= int(d)
    return n


def bounded_find(names, roots, max_files=250000):
    """Filename-only search; no content read, no downloads, no writes."""
    found = {n: [] for n in names}
    seen = 0
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            # never descend into virtualenvs / site-packages / caches
            dirnames[:] = [d for d in dirnames
                           if d not in ('site-packages', '__pycache__', '.git',
                                        '.venv', 'venv', 'node_modules', '.Xil')]
            for f in filenames:
                seen += 1
                if seen > max_files:
                    return found, seen
                for n in names:
                    if f == n:
                        found[n].append(os.path.join(dirpath, f))
    return found, seen


def main():
    if not ZIP.exists():
        raise SystemExit('sealed ZIP missing: %s' % ZIP)
    if not MANIFEST.exists():
        raise SystemExit('manifest missing: %s' % MANIFEST)
    z = zipfile.ZipFile(ZIP)
    man_bytes = MANIFEST.read_bytes()
    man = json.loads(man_bytes)
    result_bytes = z.read(RESULT_MEMBER)
    result = json.loads(result_bytes)
    by_id = {d['id']: d for d in man['directory']}

    # ---- 68 closed programs: real names, boundary shapes, plan pointers ----
    closed = {}
    values_meta = {}
    for key, p in man['v211_programs'].items():
        v = man['v022_programs'][key]
        iv = p['values'][p['input_id']]
        ov = p['values'][p['output_id']]
        ivn, ovn = numel(iv['shape']), numel(ov['shape'])
        closed[key] = dict(
            key=key, part=p['part'], kind=p['kind'], name=p['name'],
            input_tensor=p['input'], output_tensor=p['output'],
            input_id=p['input_id'], output_id=p['output_id'],
            input_shape=iv['shape'], output_shape=ov['shape'],
            input_elems=ivn, output_elems=ovn,
            input_bytes_q16=ivn * 2, output_bytes_f32=ovn * 4,
            output_bytes_q16=ovn * 2,
            input_local_addr=v['input_q_address'],
            output_local_addr=v['output_address'],
            plan_address=v['plan_address'], plan_count=v['plan_count'],
            matrix_tasks=v['matrix_tasks'],
            temp_base=v['temp_base'], temp_end=v['temp_end'],
            temp_bytes=v['temp_end'] - v['temp_base'],
            members=p['members'],
            original_nodes=len(p['members']),
        )
        values_meta[key] = dict(values=[
            dict(name=x['name'], shape=x['shape'], dtype=x['dtype'],
                 address=x['words'][0], q_address=x['words'][1],
                 scale_address=x['words'][2], elems=x['words'][3],
                 rank=x['words'][4], elem_bytes=x['words'][5])
            for x in p['values']])

    # ---- outer 591 queue ledger, labelled by parameter name ----
    tasks = result['native_matrix_tasks']
    ledger = []
    unlabelled = 0
    last_owner = None
    for i, t in enumerate(tasks):
        pid = t.get('param_id')
        d = by_id.get(pid) if pid is not None else None
        name = d['name'] if d else None
        shape = d['shape'] if d else None
        if d is not None:
            mm = re.match(r'(encoder//encoder/encoders\.\d+|decoder//decoders\.\d+)/', name)
            if mm:
                last_owner = mm.group(1)
        if d is None:
            unlabelled += 1
        ledger.append(dict(
            inferred_owner=last_owner if d is None else None,
            index=i, m=t['m'], k=t['k'], n=t['n'],
            mt=t['mt'], nt=t['nt'], kt=t['kt'],
            queue_base=t['queue_base'], queue_count=t['queue_count'],
            cbase=t['cbase'], cbytes=t['cbytes'],
            uploaded_bytes=t['uploaded_bytes'],
            extent_bytes=t['extent_bytes'],
            param_id=pid, param_B_address=t.get('param_B_address'),
            param_name=name, param_shape=shape,
            a_bytes_q16=t['m'] * t['k'] * 2,
            c48_bytes=t['cbytes'],
            expected_compute_cycles=t['expected_compute_cycles'],
            queue_cycles=t['queue_cycles'],
            compute_cycles=t['compute_cycles'],
            dma_read_bytes=t['dma_read_bytes'],
            dma_write_bytes=t['dma_write_bytes'],
            cookie=t.get('cookie'),
        ))

    # ---- non-matrix / host residual operator counts, from the same result ----
    ops = {}
    for part, st in result['stages'].items():
        e = st.get('execution', {})
        ops[part] = dict(operators=e.get('operators', {}),
                         static_folded=e.get('static_folded_nodes'),
                         dynamic_executed=e.get('dynamic_executed_nodes'),
                         fused_calls=st.get('fused_calls'),
                         logical_original_nodes=st.get('logical_original_nodes'),
                         seconds=st.get('seconds'))
    host = dict(
        ethernet=result['backend'].get('ethernet'),
        lowbit=result['backend'].get('lowbit'),
        ps_macros=result['backend'].get('ps_macros'),
        v021=result['backend'].get('v021'),
        matrix_control=result['backend'].get('matrix_control'),
        resident_scope=result['backend'].get('resident_scope'),
        ps_owns_full_onnx_graph=result['backend'].get('ps_owns_full_onnx_graph'),
        fusion_stats=result.get('fusion_stats'),
        plan_counter_delta=result['backend'].get('plan_counter_delta'),
    )


    # ---- non-matrix tensor-name catalogue (names only, no invented edges) ----
    op_names = sorted({op for part in ops.values() for op in part['operators']})
    tensor_names = {}
    for d in man['directory']:
        t = d.get('tensor')
        if not t:
            continue
        for op in op_names:
            if re.search(r'/%s(_\d+)?_output_' % re.escape(op), t):
                tensor_names.setdefault(op, set()).add(t)
                break
    tensor_catalogue = {op: dict(count=len(v), examples=sorted(v)[:5])
                        for op, v in sorted(tensor_names.items())}
    (OUT / 'nonmatrix_tensor_names.json').write_text(
        json.dumps(tensor_catalogue, indent=2) + '\n')

    # ---- owner-level structural grouping of the 591 ledger ----
    def owner_of(x):
        n = x.get('param_name')
        if n:
            m = re.match(r'(encoder//encoder/encoders\.\d+|decoder//decoders\.\d+)/', n)
            if m:
                return m.group(1)
            if 'embed' in n:
                return 'encoder//encoder/embed'
            if 'output_layer' in n:
                return 'decoder//decoder/output_layer'
        return x.get('inferred_owner') or 'unknown'
    groups = {}
    for x in ledger:
        o = owner_of(x)
        g = groups.setdefault(o, dict(owner=o, first=x['index'], last=x['index'],
                                      count=0, shapes=[], labelled=0))
        g['count'] += 1
        g['last'] = x['index']
        g['shapes'].append([x['m'], x['k'], x['n']])
        if x['param_name']:
            g['labelled'] += 1
    group_list = sorted(groups.values(), key=lambda g: g['first'])
    for g in group_list:
        g['unique_shapes'] = [list(x) for x in sorted({tuple(s) for s in g['shapes']})]
        g['task_indices'] = [g['first'], g['last']]
        del g['shapes']
    (OUT / 'outer591_groups.json').write_text(json.dumps(dict(
        total=len(ledger), groups=group_list,
        group_dependency_note='Owner order is the recorded host order. '
        'Encoder embed -> encoders.0..11, decoder decoders.0..5 -> output '
        'layer is a structural label; it is not a recovered tensor DAG.',
        per_encoder_tasks=groups.get('encoder//encoder/encoders.0', {}).get('count'),
        per_decoder_tasks=groups.get('decoder//decoders.0', {}).get('count'),
    ), indent=2) + '\n')

    # ---- missing source discovery (bounded, local, read-only) ----
    names = ['lowbit_executor.py', 'profiled_backend.py', 'vm_abi.py',
             'fusion_executor.py', 'onnx_executor.py']
    roots = [
        '/home/yang/Desktop/software4npu',
        '/home/yang/Desktop/当前工程文件',
        str(PROJ),
    ]
    found, scanned = bounded_find(names, roots, max_files=250000)
    onnx = []
    for dirpath, dirnames, filenames in os.walk('/home/yang/Desktop/software4npu'):
        dirnames[:] = [d for d in dirnames
                       if d not in ('.venv', 'venv', 'site-packages', '__pycache__', '.git')]
        for f in filenames:
            if f.endswith('.onnx'):
                onnx.append(os.path.join(dirpath, f))
                break
        if len(onnx) > 20:
            break

    # The exact model/executor path recorded by the board result is on D: and
    # is not present on this host.  Keep the provenance string verbatim.
    provenance = result.get('provenance', {})
    missing = dict(
        executor_default_path='lowbit_executor.py',
        backend_default_path='profiled_backend.py',
        abi_default_path='vm_abi.py',
        filename_search_roots=roots,
        files_scanned=scanned,
        found=found,
        onnx_files_outside_venv=onnx[:20],
        board_recorded_case_dir=provenance.get('case_dir'),
        board_recorded_model_hashes=provenance.get('model_sha256'),
        conclusion=('The 591 queue ledger is recoverable from the sealed board '
                    'result, but the source ONNX graph, Tensor-name edges and '
                    'the host executor that ordered them are absent.  A true '
                    'whole-model tensor DAG cannot be reconstructed from the '
                    'supplied read-only tree.  Ledger shape/parameter provenance '
                    'is complete; ledger dataflow edges are explicitly marked '
                    'unknown and are not claimed as a DAG.'),
    )

    source = dict(
        zip_path=str(ZIP),
        zip_sha256=sha_bytes(ZIP.read_bytes()),
        manifest_path=str(MANIFEST),
        manifest_sha256=sha_bytes(man_bytes),
        result_member=RESULT_MEMBER,
        result_member_sha256=sha_bytes(result_bytes),
        parameters002_sha256=man.get('image_sha256'),
        parameters002_bytes=man.get('image_bytes'),
        board_elapsed_seconds=result.get('elapsed_seconds'),
        board_carrier=result.get('carrier'),
        board_scope=result.get('scope'),
        provenance=provenance,
        closed68_count=len(closed),
        outer591_count=len(ledger),
        outer593_tasks_note=result['backend']['v021'].get('native_matrix_tasks'),
        outer591_unlabelled_params=unlabelled,
        nonmatrix_ops=ops,
        host_residual=host,
        missing_inputs=missing,
    )
    (OUT / 'source_ledger.json').write_text(json.dumps(source, indent=2) + '\n')
    (OUT / 'closed68.json').write_text(json.dumps(closed, indent=1) + '\n')
    (OUT / 'closed68_values.json').write_text(json.dumps(values_meta, indent=1) + '\n')
    (OUT / 'outer591_ledger.json').write_text(json.dumps(ledger, indent=1) + '\n')
    (OUT / 'nonmatrix_ops.json').write_text(json.dumps(ops, indent=1) + '\n')

    print(json.dumps(dict(
        closed68=len(closed), outer591=len(ledger), unlabelled=unlabelled,
        missing_conclusion=missing['conclusion'],
        found={k: len(v) for k, v in found.items()},
        onnx_outside_venv=len(onnx),
        manifest_sha256=source['manifest_sha256'],
        result_sha256=source['result_member_sha256'],
    ), indent=2))


if __name__ == '__main__':
    main()
