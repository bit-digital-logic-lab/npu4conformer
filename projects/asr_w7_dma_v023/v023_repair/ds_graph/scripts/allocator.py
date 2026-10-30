#!/usr/bin/env python3
"""Global tensor lifetime + address allocator for the recovered graph set.

What is allocated:
  * 68 closed V022 programs: unique boundary input (Q16) and output (FP32)
    tensors, plus one scheduler-exclusive temporary arena.
  * 591 outer ledger tasks: unique logical A (Q16) and C48 destinations.

Why the temporary arena is shared: the 68 program extents sum to ~126.4 MB.
Two copies already exceed the 80 MiB owned arena.  Giving every program a
private extent would be an address-only illusion; the correct options are
scheduler exclusivity (used here) or on-chip residency / a larger arena.  The
report calls this out instead of claiming 68-way parallel residency.
"""
import json
from pathlib import Path

TASK = Path(__file__).resolve().parents[1]
A = TASK / 'analysis'
ARENA_BASE = 0x03000000
ARENA_LIMIT = 0x08000000
EXT_BASE = 0x08000000
EXT_LIMIT = 0x10000000


def align(x, n=64):
    return (x + n - 1) // n * n


class Region:
    def __init__(self, lo, hi, name):
        self.lo, self.hi, self.name = lo, hi, name
        self.free = [(lo, hi)]
        self.alloc = []

    def reserve(self, size, al=64, label=''):
        size = align(size, al)
        for i, (lo, hi) in enumerate(self.free):
            start = align(lo, al)
            if start + size <= hi:
                if start > lo:
                    self.free[i] = (lo, start)
                    self.free.insert(i + 1, (start + size, hi))
                else:
                    self.free[i] = (start + size, hi)
                self.alloc.append(dict(label=label, base=start, bytes=size,
                                       end=start + size, region=self.name))
                return start
        raise MemoryError('%s region exhausted for %s (%d bytes)' %
                          (self.name, label, size))

    def used(self):
        return sum(a['bytes'] for a in self.alloc)


def overlap(a0, a1, b0, b1):
    return a0 < b1 and b0 < a1


def main():
    closed = json.loads((A / 'closed68.json').read_text())
    ledger = json.loads((A / 'outer591_ledger.json').read_text())

    arena = Region(ARENA_BASE, ARENA_LIMIT, 'arena')
    ext = Region(EXT_BASE, EXT_LIMIT, 'external')

    tensors = []
    tid = 0
    for i, (key, p) in enumerate(closed.items()):
        # Boundary tensors are globally unique.  Input is Q16 (what V022 reads);
        # output is the FP32 Dequantize output (what the graph consumes).
        ib = ext.reserve(p['input_bytes_q16'], 64, 'in:' + key)
        ob = ext.reserve(p['output_bytes_f32'], 64, 'out:' + key)
        it = dict(id=tid, name='%s::in' % key, kind='input_q16',
                  tensor=p['input_tensor'], base=ib, bytes=p['input_bytes_q16'],
                  old_addr=p['input_local_addr'], live=(0, i + 1), version=1,
                  owner=key, region='external')
        ot = dict(id=tid + 1, name='%s::out' % key, kind='output_f32',
                  tensor=p['output_tensor'], base=ob, bytes=p['output_bytes_f32'],
                  old_addr=p['output_local_addr'], live=(i + 1, 68), version=1,
                  owner=key, region='external')
        tid += 2
        tensors += [it, ot]
        p['global_input_tid'] = it['id']
        p['global_output_tid'] = ot['id']
        p['global_input_base'] = ib
        p['global_output_base'] = ob

    # 591 ledger A/C: unique addresses so a future parallel scheduler cannot
    # alias them.  The current control test still replays host order.
    for t in ledger:
        ab = arena.reserve(t['a_bytes_q16'], 64, 'ledgerA:%d' % t['index'])
        cb = arena.reserve(t['c48_bytes'], 64, 'ledgerC:%d' % t['index'])
        t['global_a_base'] = ab
        t['global_c_base'] = cb
        t['global_a_tid'] = tid
        t['global_c_tid'] = tid + 1
        tid += 2
        tensors.append(dict(id=t['global_a_tid'], name='ledger%03d::A' % t['index'],
                            kind='a_q16', tensor=None, base=ab,
                            bytes=t['a_bytes_q16'], old_addr=t['queue_base'],
                            live=(t['index'], t['index'] + 1), version=1,
                            owner='ledger%03d' % t['index'], region='arena'))
        tensors.append(dict(id=t['global_c_tid'], name='ledger%03d::C48' % t['index'],
                            kind='c48', tensor=None, base=cb,
                            bytes=t['c48_bytes'], old_addr=t['cbase'],
                            live=(t['index'] + 1, t['index'] + 2), version=1,
                            owner='ledger%03d' % t['index'], region='arena'))

    # One scheduler-exclusive temp extent.  Every closed program uses the same
    # base; no two closed programs are dispatched concurrently by the SEQ
    # owner, so this is not a WAW/WAR conflict.
    max_temp = max(p['temp_bytes'] for p in closed.values())
    temp_base = arena.reserve(max_temp, 65536, 'shared_seq_temp')
    for key, p in closed.items():
        p['global_temp_base'] = temp_base
        p['global_temp_end'] = temp_base + p['temp_bytes']
        p['temp_offset_delta'] = temp_base - p['temp_base']

    # Old-address false conflicts: same old boundary address, different tensor.
    old_pairs = []
    for i in range(len(tensors)):
        for j in range(i + 1, len(tensors)):
            a, b = tensors[i], tensors[j]
            if a['old_addr'] is None or b['old_addr'] is None:
                continue
            if a['old_addr'] == b['old_addr'] and a['name'] != b['name']:
                old_pairs.append(dict(a=a['name'], b=b['name'],
                                      old_addr=a['old_addr'],
                                      live_a=a['live'], live_b=b['live'],
                                      same_old_base=True))
    old_overlap_live = sum(1 for p in old_pairs
                           if overlap(p['live_a'][0], p['live_a'][1],
                                      p['live_b'][0], p['live_b'][1]))

    # Verify the new allocation: any two tensors whose live ranges overlap
    # must not overlap in address.
    conflicts = []
    for i in range(len(tensors)):
        for j in range(i + 1, len(tensors)):
            a, b = tensors[i], tensors[j]
            if not overlap(a['live'][0], a['live'][1], b['live'][0], b['live'][1]):
                continue
            if overlap(a['base'], a['base'] + a['bytes'],
                       b['base'], b['base'] + b['bytes']):
                conflicts.append(dict(a=a['name'], b=b['name'],
                                      base_a=a['base'], base_b=b['base']))
    if conflicts:
        raise SystemExit('allocator produced %d live conflicts' % len(conflicts))

    # Deliberate negative example: two simultaneously-live boundary outputs at
    # one address.  The independent checker must reject this.
    bad = dict(a=tensors[3]['name'], b=tensors[5]['name'],
               live_a=tensors[3]['live'], live_b=tensors[5]['live'],
               base=tensors[3]['base'], bytes=max(tensors[3]['bytes'],
                                                  tensors[5]['bytes']))

    out = dict(
        arena=dict(base=ARENA_BASE, limit=ARENA_LIMIT,
                   used=arena.used(), free=ARENA_LIMIT - ARENA_BASE - arena.used()),
        external=dict(base=EXT_BASE, limit=EXT_LIMIT,
                      used=ext.used(), free=EXT_LIMIT - EXT_BASE - ext.used()),
        tensor_count=len(tensors),
        live_conflicts=len(conflicts),
        old_same_base_pairs=len(old_pairs),
        old_same_base_pairs_live_simultaneously=old_overlap_live,
        old_same_base_pair_examples=old_pairs[:8],
        shared_temp=dict(base=temp_base, bytes=max_temp,
                         policy='single SEQ engine owns the shared temp extent; '
                                'two concurrent 30.3MB extents do not fit the '
                                '80MiB arena (sum of all 68 extents ~126.4MB)',
                         peak_parallel_temp_extents=1,
                         max_parallel_if_2x_temp='infeasible: 2*max_temp + A/C '
                                                 'exceeds the 80MiB arena'),
        closed68=dict(count=len(closed),
                      global_input_bytes=sum(p['input_bytes_q16'] for p in closed.values()),
                      global_output_bytes=sum(p['output_bytes_f32'] for p in closed.values())),
        ledger591=dict(count=len(ledger),
                       global_a_bytes=sum(t['a_bytes_q16'] for t in ledger),
                       global_c_bytes=sum(t['c48_bytes'] for t in ledger)),
        tensors=tensors,
        negative_example=bad,
    )
    (A / 'global_alloc.json').write_text(json.dumps(out, indent=2) + '\n')
    (A / 'closed68.json').write_text(json.dumps(closed, indent=1) + '\n')
    (A / 'outer591_ledger.json').write_text(json.dumps(ledger, indent=1) + '\n')
    (A / 'relocation_map.json').write_text(json.dumps(dict(
        closed68={k: dict(input_old=p['input_local_addr'],
                          input_new=p['global_input_base'],
                          output_old=p['output_local_addr'],
                          output_new=p['global_output_base'],
                          temp_old_base=p['temp_base'],
                          temp_new_base=p['global_temp_base'],
                          temp_delta=p['temp_offset_delta'],
                          input_tid=p['global_input_tid'],
                          output_tid=p['global_output_tid'])
                  for k, p in closed.items()},
        ledger591=[dict(index=t['index'], a_new=t['global_a_base'],
                        c_old=t['cbase'], c_new=t['global_c_base'],
                        param_B=t['param_B_address'])
                   for t in ledger],
        note='Interior 0x03000000 matrix queue and A/C payload pointers inside '
             'the sealed V022 plans are not rewritten here.  The global map is '
             'for the WCPG control graph and for an integration-time plan '
             're-lowering; executing the old V022 payload under new addresses '
             'without that lowering would be a data-corruption bug.'),
        indent=2) + '\n')
    print(json.dumps({k: v for k, v in out.items()
                      if k not in ('tensors', 'old_same_base_pair_examples')}, indent=2))


if __name__ == '__main__':
    main()
