#!/usr/bin/env python3
"""Independent audit of ds_graph allocation/relocation/liveness claims.

Read-only inputs:
  ../ds_graph/analysis/*.json
  /home/yang/Desktop/项目/tasks/ds_pl_autonomy/assets/manifest_v022.json
  /home/yang/Desktop/项目/work/assets/parameters002/parameters.bin

This script does not trust the worker's PASS strings.  It re-parses the sealed
V022 plan/queue bytes and checks:
  1. live address conflicts in the claimed tensor allocation;
  2. whether 591 ledger A/C tensors alias the sealed 0x03000000..0x04000000
     matrix queue scratch;
  3. whether sealed queue/vector/layout payloads still contain old addresses
     (i.e. whether a real re-lowering was performed);
  4. alignment and region bounds.
Exit code 0 means the audit itself ran; the JSON has pass/blocker fields.
"""
import json, struct, sys, os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]          # .../项目
G = ROOT / 'v023_repair' / 'ds_graph'
MANIFEST = ROOT / 'tasks' / 'ds_pl_autonomy' / 'assets' / 'manifest_v022.json'
IMAGE = ROOT / 'work' / 'assets' / 'parameters002' / 'parameters.bin'
OUT = Path(__file__).resolve().parents[1] / 'analysis'
OUT.mkdir(exist_ok=True)

m = json.load(open(MANIFEST))
PB = m['param_base']
img = open(IMAGE, 'rb').read()
ga = json.load(open(G / 'analysis' / 'global_alloc.json'))
rm = json.load(open(G / 'analysis' / 'relocation_map.json'))
tm = json.load(open(G / 'analysis' / 'tensor_map.json'))

res = {'inputs': {}, 'liveness': {}, 'relocation': {}, 'sealed_payload': {},
       'blockers': [], 'warnings': [], 'pass': {}}
res['inputs'] = {
    'manifest_sha256': m.get('source_package_manifest_sha256'),
    'parameters_bytes': len(img),
    'parameters_sha256': m.get('image_sha256'),
    'tensor_count': len(tm.get('tensors', tm)) if isinstance(tm, dict) else len(tm),
}

# ---------- 1. liveness ----------
tensors = ga['tensors']
live_conflicts = []
for i in range(len(tensors)):
    a = tensors[i]
    if a.get('base') is None:
        continue
    a0, a1 = a['base'], a['base'] + a['bytes']
    la0, la1 = a['live']
    for j in range(i + 1, len(tensors)):
        b = tensors[j]
        if b.get('base') is None:
            continue
        b0, b1 = b['base'], b['base'] + b['bytes']
        if a0 >= b1 or b0 >= a1:
            continue
        lb0, lb1 = b['live']
        if la0 < lb1 and lb0 < la1:
            live_conflicts.append((a['name'], b['name'], hex(max(a0, b0)), a['live'], b['live']))
            if len(live_conflicts) >= 20:
                break
    if len(live_conflicts) >= 20:
        break

# 591 A/C alias sealed matrix scratch?
scratch_lo, scratch_hi = 0x03000000, 0x04000000
alias = [t for t in tensors
         if t.get('base') is not None and t['base'] < scratch_hi
         and t['base'] + t['bytes'] > scratch_lo]
alias_bytes = sum(min(t['base'] + t['bytes'], scratch_hi) - max(t['base'], scratch_lo)
                  for t in alias)
res['liveness'] = {
    'claimed_live_conflicts': ga.get('live_conflicts'),
    'independent_live_conflicts': len(live_conflicts),
    'conflict_examples': live_conflicts[:5],
    'sealed_scratch_range': [hex(scratch_lo), hex(scratch_hi)],
    'tensors_overlapping_sealed_scratch': len(alias),
    'bytes_overlapping_sealed_scratch': alias_bytes,
    'alias_examples': [{'name': t['name'], 'base': hex(t['base']), 'bytes': t['bytes'],
                        'live': t['live']} for t in alias[:5]],
    'shared_temp': ga.get('shared_temp'),
}
res['pass']['allocator_zero_live_conflicts_independent'] = (len(live_conflicts) == 0)
res['pass']['sealed_scratch_not_aliased'] = (len(alias) == 0)
if alias:
    res['blockers'].append(
        f'{len(alias)} allocated tensors ({alias_bytes} B) alias the sealed V022 matrix '
        f'queue scratch 0x03000000..0x04000000; direct SEQ execution would corrupt them')

# ---------- helpers ----------
def in_old_ranges(addr, prog):
    """classify an embedded address against this program's old boundary/temp ranges."""
    info = rm['closed68'].get(prog)
    if not info:
        return None
    if addr == info['input_old']:
        return 'input'
    if addr == info['output_old']:
        return 'output'
    if info['temp_old_base'] <= addr < info['temp_old_base'] + _temp_bytes(prog):
        return 'temp'
    if 0x03000000 <= addr < 0x04000000:
        return 'sealed_scratch'
    return None

def _temp_bytes(prog):
    c = _closed68().get(prog, {})
    return c.get('temp_bytes', 0)

def _closed68():
    global _c68
    try:
        return _c68
    except NameError:
        _c68 = json.load(open(G / 'analysis' / 'closed68.json'))
        return _c68

def map_old(addr, prog):
    info = rm['closed68'].get(prog)
    if not info:
        return None
    if addr == info['input_old']:
        return info['input_new']
    if addr == info['output_old']:
        return info['output_new']
    if info['temp_old_base'] <= addr < info['temp_old_base'] + _temp_bytes(prog):
        return info['temp_new_base'] + (addr - info['temp_old_base'])
    return None

def words(off, n):
    return struct.unpack_from('<' + str(n) + 'I', img, off)

# ---------- 2. sealed payload references ----------
dir_by_addr = {e['address']: e for e in m['directory']}
progs = m['v022_programs']
stats = {
    'programs': 0, 'instructions': 0, 'matrix_instructions': 0,
    'queue_descriptors': 0, 'queue_field_refs_old': 0,
    'queue_field_refs_old_mappable': 0, 'queue_field_refs_new': 0,
    'vec_descriptors': 0, 'lay_descriptors': 0,
    'vec_lay_old_refs': 0, 'vec_lay_old_mappable': 0, 'vec_lay_new_refs': 0,
    'moves_to_sealed_scratch': 0, 'queue_source_bytes': 0,
}
examples = []
mapping_missing = []
new_bases = set()
for t in tensors:
    if t.get('base') is not None:
        new_bases.add(t['base'])

for prog, p in progs.items():
    stats['programs'] += 1
    info = rm['closed68'][prog]
    temp_old_end = info['temp_old_base'] + _temp_bytes(prog)
    plan_off = p['plan_address'] - PB
    queue_entries = sorted([e for e in m['directory']
                     if e.get('name', '').startswith(f'v022/{prog}/matrix_queue_')],
                     key=lambda e: e['offset'])
    queue_by_addr = {e['address']: e for e in queue_entries}
    queue_cursor = 0

    for ii in range(p['plan_count']):
        w = words(plan_off + ii * 64, 16)
        magic, kind, ticket, dep, ptr, length = w[:6]
        stats['instructions'] += 1
        if magic != 0x22504c4e:
            res['warnings'].append(f'{prog} instruction {ii} bad magic')
            continue
        if kind == 1:
            stats['matrix_instructions'] += 1
            # Queue payloads are appended in matrix-op order and copied to
            # SB=0x03000000 by a layout move.  Pair by order and size.
            e = None
            if queue_cursor < len(queue_entries):
                cand = queue_entries[queue_cursor]
                if cand['bytes'] == length * 64:
                    e = cand
                    queue_cursor += 1
                else:
                    res['warnings'].append(
                        f'{prog} queue {ii} size mismatch {cand["bytes"]} != {length*64}')
            if e is None:
                e = queue_by_addr.get(ptr)
            if e is None:
                res['warnings'].append(f'{prog} queue {ii} not located (ptr={hex(ptr)})')
                continue
            qbytes = img[e['address'] - PB:e['address'] - PB + length * 64]
            stats['queue_source_bytes'] += len(qbytes)
            for d in range(length):
                q = struct.unpack_from('<16I', qbytes, d * 64)
                if q[0] != 0x51415352:
                    res['warnings'].append(f'{prog} queue {ii} desc {d} bad magic')
                    continue
                stats['queue_descriptors'] += 1
                # fields: abase=q[4], baddr=q[5], cbase=q[6]
                for fname, addr in (('A', q[4]), ('B', q[5]), ('C', q[6])):
                    if addr in new_bases:
                        stats['queue_field_refs_new'] += 1
                    k = in_old_ranges(addr, prog)
                    if k:
                        stats['queue_field_refs_old'] += 1
                        if map_old(addr, prog) is not None:
                            stats['queue_field_refs_old_mappable'] += 1
                        else:
                            mapping_missing.append((prog, ii, d, fname, hex(addr), k))
                        if len(examples) < 10:
                            examples.append({'kind': 'queue', 'prog': prog, 'field': fname,
                                             'old': hex(addr), 'class': k,
                                             'map': hex(map_old(addr, prog)) if map_old(addr, prog) is not None else None})
        elif kind in (2, 3):
            if kind == 2:
                stats['vec_descriptors'] += 1
            else:
                stats['lay_descriptors'] += 1
            poff = ptr - PB
            if poff < 0 or poff + length > len(img):
                res['warnings'].append(f'{prog} payload {ii} outside image')
                continue
            pw = words(poff, 4)
            addrs = []
            if kind == 2 and pw[0] == 0x22564543:
                vw = words(poff, 8)
                addrs = [('A', vw[2]), ('B', vw[3]), ('C', vw[4]), ('D', vw[5])]
            elif kind == 3 and pw[0] == 0x224c4159:
                lw = words(poff, 24)
                addrs = [('src', lw[2]), ('dst', lw[3])]
                if lw[3] == 0x03000000:
                    stats['moves_to_sealed_scratch'] += 1
            for fname, addr in addrs:
                if addr in new_bases:
                    stats['vec_lay_new_refs'] += 1
                k = in_old_ranges(addr, prog)
                if k:
                    stats['vec_lay_old_refs'] += 1
                    if map_old(addr, prog) is not None:
                        stats['vec_lay_old_mappable'] += 1
                    else:
                        mapping_missing.append((prog, ii, None, fname, hex(addr), k))
                    if len(examples) < 10:
                        examples.append({'kind': 'vec' if kind == 2 else 'lay',
                                         'prog': prog, 'field': fname,
                                         'old': hex(addr), 'class': k,
                                         'map': hex(map_old(addr, prog)) if map_old(addr, prog) is not None else None})

stats['old_refs_total'] = stats['queue_field_refs_old'] + stats['vec_lay_old_refs']
stats['old_refs_mappable'] = stats['queue_field_refs_old_mappable'] + stats['vec_lay_old_mappable']
stats['new_refs_total'] = stats['queue_field_refs_new'] + stats['vec_lay_new_refs']
stats['mapping_missing_examples'] = mapping_missing[:10]
stats['mapping_missing_count'] = len(mapping_missing)
stats['reference_examples'] = examples
res['sealed_payload'] = stats
res['pass']['direct_seq_payload_is_re_lowered'] = (
    stats['old_refs_total'] == 0 and stats['moves_to_sealed_scratch'] == 0)
if stats['old_refs_total'] or stats['moves_to_sealed_scratch']:
    res['blockers'].append(
        f'sealed V022 payload still contains {stats["old_refs_total"]} old boundary/temp '
        f'references and {stats["moves_to_sealed_scratch"]} move(s) to 0x03000000; '
        f'{stats["new_refs_total"]} new-address references found. Direct execution under '
        f'global_alloc addresses is not safe; re-lowering was not performed')

# ---------- 3. relocation coverage/alignment ----------
align_bad = [t['name'] for t in tensors
             if t.get('base') is not None and (t['base'] % 64) != 0]
region_bad = []
for t in tensors:
    if t.get('base') is None:
        continue
    lo, hi = ga['arena']['base'], ga['arena']['limit'] if t['region'] == 'arena' else ga['external']['limit']
    if t['base'] < lo or t['base'] + t['bytes'] > hi:
        region_bad.append(t['name'])

closed = rm['closed68']
boundary_old = []
for k, v in closed.items():
    boundary_old += [v['input_old'], v['output_old']]
res['relocation'] = {
    'closed68_entries': len(closed),
    'unique_old_inputs': len({v['input_old'] for v in closed.values()}),
    'unique_old_outputs': len({v['output_old'] for v in closed.values()}),
    'unique_new_inputs': len({v['input_new'] for v in closed.values()}),
    'unique_new_outputs': len({v['output_new'] for v in closed.values()}),
    'unaligned_new_tensors': len(align_bad),
    'unaligned_examples': align_bad[:5],
    'out_of_region_tensors': len(region_bad),
    'out_of_region_examples': region_bad[:5],
    'relocation_note_present': 'not rewritten' in str(rm.get('note', '')),
}
res['pass']['new_addresses_aligned_64'] = (len(align_bad) == 0)
res['pass']['new_addresses_in_declared_regions'] = (len(region_bad) == 0)
res['pass']['relocation_map_is_explicit_about_no_relowering'] = res['relocation']['relocation_note_present']

# ---------- 4. known structural findings from interface audit ----------
res['structural'] = {
    'wc_graph_top_seq_ports': ['seq_valid', 'seq_ready', 'seq_base', 'seq_count',
                               'seq_done', 'seq_fault', 'seq_error'],
    'wc_graph_top_seq_has_abort_drained': False,
    'plan_v023_requires': ['child_abort', 'child_drained', 'dma_abort',
                           'drain_timeout', 'isolation_req', 'drained'],
    'vector_engine_has_abort': False,
    'layout_engine_has_abort': False,
    'matrix_cluster_has_abort_drained': False,
    'note': 'SEQ occupies matrix+vector+layout internally. WCPG only prevents a new SEQ '
            'when direct engines are active; a MAT/VEC/LAY node can start while SEQ is '
            'active, so a mixed plan needs an explicit SEQ-exclusive gate or re-lowering.',
}
res['pass']['seq_abort_contract_wired'] = False
res['blockers'].append(
    'wc_graph_top SEQ handshake has no abort/drained; plan_v023 child_abort/child_drained '
    'cannot be connected. Vector/layout engines and matrix cluster expose no abort/drained')
res['blockers'].append(
    'WCPG treats SEQ/MAT/VEC/LAY as independent engines, but a V022 SEQ program drives '
    'the same matrix/vector/layout hardware. A mixed plan can dispatch MAT/VEC/LAY while '
    'SEQ is running; no arbiter/exclusive gate exists')

res['pass']['overall_integration_ready'] = all(res['pass'].values())
res['verdict'] = 'blocked' if res['blockers'] else 'ready'

(OUT / 'graph_relocation_audit.json').write_text(json.dumps(res, indent=2))
print(json.dumps({k: res[k] for k in ('verdict', 'pass', 'blockers')}, indent=2))
print('wrote', OUT / 'graph_relocation_audit.json')
sys.exit(0)
