#!/usr/bin/env python3
"""从 sealed parameters002 的实际计划/shape 统计工作量、最小流量与下界输入。
只读 manifest/parameters.bin；输出 bench/reports/plan_workload.json。"""
import json, struct, hashlib
from pathlib import Path

ROOT = Path('/home/yang/Desktop/项目')
T = Path(__file__).resolve().parent
MAN = T.parent / 'fixtures/parameters002/manifest.json'
IMG = ROOT / 'work/assets/parameters002/parameters.bin'
OUT = T / 'reports'
OUT.mkdir(exist_ok=True)
m = json.loads(MAN.read_text())
data = IMG.read_bytes()
PB = m['param_base']


def words(addr, count):
    return struct.unpack_from('<' + str(count) + 'I', data, addr - PB)


def align(n, a=32):
    return (n + a - 1) // a * a


def tiles(n):
    return (n + 31) // 32


stats = dict(programs=0, matrix_ops=0, matrix_descriptors=0, mac_useful=0,
             mac_padded=0, a_bytes=0, w_bytes=0, c_bytes=0, c_write_bytes=0, c_read_bytes=0,
             blocks=0, vector_instr=0, vector_elements=0, layout_instr=0,
             layout_elements=0, layout_bytes=0, plan_instr=0)
per_kind = {}
rows = []
for key, p in m['v022_programs'].items():
    stats['programs'] += 1
    ops = m['v211_programs'][key]['ops']
    mac_u = mac_p = a_b = w_b = c_b = cw_b = cr_b = blocks = descs = 0
    for op in ops:
        if op[0] <= 2:
            cfg = words(op[5], op[6])
            mm, kk, nfull = cfg[3], cfg[4], cfg[5]
            nref = cfg[28]
            refs = [cfg[29 + i * 12:41 + i * 12] for i in range(nref)]
            ntot = sum(r[3] for r in refs)
            parts = (kk + 4095) // 4096
            mu = mm * kk * ntot
            mp = tiles(mm) * 32 * tiles(kk) * 32 * sum(tiles(r[3]) * 32 for r in refs)
            mac_u += mu
            mac_p += mp
            for part in range(parts):
                depth = min(4096, kk - part * 4096)
                a_b += tiles(mm) * tiles(depth) * 2048
                for r in refs:
                    w_b += tiles(depth) * tiles(r[3]) * 1024
            cb = tiles(mm) * tiles(ntot) * 6144
            c_b += cb * parts
            cw_b += cb * parts
            cr_b += cb * (parts - 1)
            blocks += tiles(mm) * tiles(kk) * sum(tiles(r[3]) for r in refs)
            descs += nref * parts
        # 计划指令
    pa, pc = p['plan_address'], p['plan_count']
    instructions = []
    for i in range(pc):
        w = words(pa + i * 64, 16)
        instructions.append(w)
        kind = w[1]
        if kind == 2:
            payload = words(w[4], 16)
            stats['vector_instr'] += 1
            stats['vector_elements'] += payload[6]
        elif kind == 3:
            payload = words(w[4], 32)
            stats['layout_instr'] += 1
            stats['layout_elements'] += payload[4]
            stats['layout_bytes'] += payload[4] * payload[5]
    stats['plan_instr'] += pc
    stats['matrix_ops'] += sum(1 for op in ops if op[0] <= 2)
    stats['matrix_descriptors'] += descs
    stats['mac_useful'] += mac_u
    stats['mac_padded'] += mac_p
    stats['a_bytes'] += a_b
    stats['w_bytes'] += w_b
    stats['c_bytes'] += c_b + cr_b
    stats['c_write_bytes'] += cw_b
    stats['c_read_bytes'] += cr_b
    stats['blocks'] += blocks
    kk = p['kind']
    per_kind.setdefault(kk, dict(n=0, mac=0, blocks=0, instr=0))
    per_kind[kk]['n'] += 1
    per_kind[kk]['mac'] += mac_u
    per_kind[kk]['blocks'] += blocks
    per_kind[kk]['instr'] += pc
    rows.append(dict(key=key, kind=kk, plan_count=pc, matrix_tasks=descs,
                     mac_useful=mac_u, mac_padded=mac_p, blocks=blocks,
                     a_bytes=a_b, w_bytes=w_b, c_bytes=c_b, c_write_bytes=cw_b, c_read_bytes=cr_b))

# 与板测计数器对照
board = json.loads((ROOT / 'work/BOARD_RESULT.json').read_text())
run = board['runs'][0]['closed_plan']
out = dict(
    source=dict(manifest=str(MAN), manifest_sha256=hashlib.sha256(MAN.read_bytes()).hexdigest(),
                image=str(IMG), image_sha256=hashlib.sha256(IMG.read_bytes()).hexdigest(),
                image_bytes=len(data)),
    scope='68 closed CONV/FFN plans; matrix + vector/layout plan instructions; excludes 591 legacy host queues.',
    stats=stats, per_kind=per_kind,
    board=dict(vector_elements=run['vector_elements'], layout_elements=run['layout_elements'],
               pl_instructions=run['pl_instructions'], matrix_descriptors=run['matrix_descriptors'],
               matrix_pe_cycles=run['matrix_pe_cycles'], matrix_queue_cycles=run['matrix_queue_cycles'],
               vector_cycles=run['vector_cycles'], layout_cycles=run['layout_cycles'],
               plan_fetch_cycles=run['plan_fetch_cycles'], whole_plan_cycles=run['whole_plan_cycles'],
               vector_layout_read_bytes=run['vector_layout_read_bytes'],
               vector_layout_write_bytes=run['vector_layout_write_bytes']),
    rows=rows)
(OUT / 'plan_workload.json').write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
print(json.dumps(stats, indent=2))
print('per_kind', json.dumps(per_kind, indent=2))
print('board', json.dumps(out['board'], indent=2))
