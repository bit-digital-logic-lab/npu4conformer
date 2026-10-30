#!/usr/bin/env python3
"""理论下界 + 实测未满归因。
只读 bench/reports 与 sealed 计划统计；输出 bounds.json / BOUNDS.md。
频率是参数化计算，不是物理时序结论。"""
import json, struct
from pathlib import Path

T = Path(__file__).resolve().parent
R = T / 'reports'
ROOT = Path('/home/yang/Desktop/项目')
W = ROOT / 'work'
pw = json.loads((R / 'plan_workload.json').read_text())
board = pw['board']
dma = json.loads((R / 'dma_compare.json').read_text())
vec = json.loads((R / 'vector_dma_compare.json').read_text())
pp = json.loads((R / 'pingpong.json').read_text())

# 唯一输出元素数（不是 C 块读写次数）
m = json.loads((T.parent / 'fixtures/parameters002/manifest.json').read_text())
data = (W / 'assets/parameters002/parameters.bin').read_bytes()
PB = m['param_base']
def words(a, n):
    return struct.unpack_from('<' + str(n) + 'I', data, a - PB)
unique_c = 0
for key, p in m['v022_programs'].items():
    for op in m['v211_programs'][key]['ops']:
        if op[0] <= 2:
            cfg = words(op[5], op[6])
            nref = cfg[28]
            ntot = sum(cfg[29 + i * 12 + 3] for i in range(nref))
            unique_c += cfg[3] * ntot

# 唯一权重块（1KiB）与唯一张量地址范围；用于 compulsory lower bound
wblocks = set()
tranges = []
for key, p in m['v211_programs'].items():
    for v in p['values']:
        w = v['words']; n = w[3]; dt = w[4]
        size = {1: 4, 2: 2}.get(dt, 4) * n
        a = w[1] if dt == 2 and w[1] else w[0]
        if 0x03000000 <= a < 0x08000000 and size > 0:
            tranges.append((a, a + size))
    for op in p['ops']:
        if op[0] <= 2:
            cfg = words(op[5], op[6]); kk = cfg[4]; nref = cfg[28]
            for i in range(nref):
                r = cfg[29 + i * 12:41 + i * 12]
                nt = r[4]; parts = (kk + 4095) // 4096
                for part in range(parts):
                    depth = min(4096, kk - part * 4096)
                    a = r[0] + (part * 4096 // 32) * nt * 1024
                    size = ((depth + 31) // 32) * nt * 1024
                    for b in range(a, a + size, 1024):
                        wblocks.add(b)
tranges.sort(); merged = []
for a, b in tranges:
    if merged and a <= merged[-1][1]:
        merged[-1] = (merged[-1][0], max(merged[-1][1], b))
    else:
        merged.append((a, b))
unique_tensor = sum(b - a for a, b in merged)
unique_weight = len(wblocks) * 1024
boundary_in = 4539392
boundary_out = 16508928
onchip_lb = unique_weight + boundary_in + boundary_out
all_inter_lb = onchip_lb + 2 * unique_tensor

F0 = 125_000_000
st = pw['stats']
mac_u, mac_p = st['mac_useful'], st['mac_padded']
pe_cyc = board['matrix_pe_cycles']
mat_q = board['matrix_queue_cycles']
vec_cyc = board['vector_cycles']
lay_cyc = board['layout_cycles']
fetch = board['plan_fetch_cycles']
whole = board['whole_plan_cycles']
vec_read = board['vector_layout_read_bytes']
vec_write = board['vector_layout_write_bytes']
mat_bytes = st['a_bytes'] + st['w_bytes'] + st['c_write_bytes'] + st['c_read_bytes']
total_bytes = mat_bytes + vec_read + vec_write

def sc(cycles, f):
    return cycles / f

# DMA 场景索引
def get(scenario, dut, mode, maxout=None):
    for r in dma['results']:
        if r['scenario'] == scenario and r['dut'] == dut and r['mode'] == mode and \
           (maxout is None or r['max_out'] == maxout):
            return r
    return None

bursts = 256
burst_model = {}
for L in (8, 32, 64):
    br = get(f'lat{L}_bp0', 'base', 0)
    bc = get(f'lat{L}_bp0', 'cand', 0, 8)
    bw = get(f'lat{L}_bp0', 'base', 1)
    cw = get(f'lat{L}_bp0', 'cand', 1, 8)
    burst_model[L] = dict(
        base_read_cycles=br['cycles'], cand_read_cycles=bc['cycles'],
        base_write_cycles=bw['cycles'], cand_write_cycles=cw['cycles'],
        model_base_read=bursts * (L + 16),
        model_cand_read=4096 + L,
        cand_read_overhead=bc['cycles'] - (4096 + L),
        base_read_util=br['read_util'], cand_read_util=bc['read_util'],
        base_write_util=bw['write_util'], cand_write_util=cw['write_util'])

# 频率参数表（计算域；DDR 用户域独立）
freq_rows = []
for f in (125_000_000, 300_000_000, 600_000_000):
    freq_rows.append(dict(
        compute_hz=f,
        matrix_actual_schedule_s=sc(pe_cyc, f),
        matrix_ideal256_s=sc(mac_p / 256, f),
        matrix_useful256_s=sc(mac_u / 256, f),
        vector_schedule_s=sc(vec_cyc, f),
        layout_schedule_s=sc(lay_cyc, f),
        whole_plan_schedule_s=sc(whole, f),
        matrix_queue_schedule_s=sc(mat_q, f),
        note='whole_plan 是当前串行计划的整段；DDR 用户域不随 compute_hz 变化。'))

ddr_rows = []
for f in (125_000_000, 200_000_000, 250_000_000, 300_000_000):
    ddr_rows.append(dict(
        ddr_user_hz=f, peak_GBps=16 * f / 1e9,
        actual_bytes_lb_s=total_bytes / 16 / f,
        vector_layout_bytes_lb_s=(vec_read + vec_write) / 16 / f,
        matrix_bytes_lb_s=mat_bytes / 16 / f,
        actual_effective_MBps=total_bytes / (whole / F0) / 1e6,
        note='半双工共享数据通道，每 cycle 最多一个 16B beat；不含命令/延迟。'))

# 关键路径/重叠边界
stage_sum = mat_q + vec_cyc + lay_cyc + fetch
out = dict(
    scope='由 sealed 计划统计 + 历史板测计数器 + 本次 Icarus AXI BFM 推导；非板级、非 STA。',
    workload=dict(mac_useful=mac_u, mac_padded=mac_p, unique_c48=unique_c, blocks=st['blocks'],
                  matrix_pe_cycles=pe_cyc, matrix_queue_cycles=mat_q,
                  vector_cycles=vec_cyc, layout_cycles=lay_cyc,
                  fetch_cycles=fetch, whole_plan_cycles=whole,
                  matrix_bytes=mat_bytes, matrix_c_read_bytes=st['c_read_bytes'], vector_read_bytes=vec_read,
                  vector_write_bytes=vec_write, total_bytes=total_bytes,
                  mac_per_cycle_padded=round(mac_p / pe_cyc, 3),
                  mac_per_cycle_useful=round(mac_u / pe_cyc, 3),
                  matrix_full_block_cycles=st['blocks'] * 520,
                  matrix_full_block_seconds=st['blocks'] * 520 / F0,
                  matrix_full_block_mac_per_cycle=round(mac_p / (st['blocks'] * 520), 3),
                  c48_per_cycle=round(unique_c / pe_cyc, 4),
                  c48_bits_per_cycle=round(unique_c * 48 / pe_cyc, 2),
                  onboard_operand_bits_per_cycle=368,
                  onboard_operand_B_per_cycle=46,
                  matrix_DDR_B_per_cycle=round(mat_bytes / pe_cyc, 3),
                  compulsory=dict(unique_weight_B=unique_weight, unique_tensor_range_B=unique_tensor,
                   boundary_input_B=boundary_in, boundary_output_B=boundary_out,
                   onchip_intermediate_lower_B=onchip_lb, all_intermediate_ddr_lower_B=all_inter_lb,
                   actual_total_B=total_bytes,
                   note='onchip 假设中间量全片内；all_intermediate 假设唯一张量范围各写/读一次（粗下界）。')),
    frequency_table=freq_rows, ddr_table=ddr_rows, burst_model=burst_model,
    critical_path=dict(
        stage_sum_cycles=stage_sum, whole_plan_cycles=whole,
        apparent_overlap_cycles=whole - stage_sum,
        stage_sum_seconds=stage_sum / F0, whole_seconds=whole / F0,
        serial_fraction=round(stage_sum / whole, 6),
        naive_max_seconds=max(mat_q, vec_cyc, lay_cyc, fetch) / F0,
        note='68 个计划按 host 依赖串行启动；matrix/vector/layout 是有依赖的阶段，不能把总和取 max。'
             'naive_max 只作为“若完全独立”的对照，不是可实现调度。'),
    vector_dma=dict(
        note='原 vector/layout 夹具只换 DMA；小请求负载下 v020 略慢于 v019，说明该负载是引擎串行/请求粒度受限，'
             '不是 DMA 在途深度受限。',
        vector_base_add_scalar=next(r['cycles'] for r in vec['results'] if r['kind'] == 'vector' and r['dut'] == 'base' and r['fixture'] == 'add_scalar' and r['mode'] == 0),
        vector_cand_add_scalar=next(r['cycles'] for r in vec['results'] if r['kind'] == 'vector' and r['dut'] == 'cand' and r['fixture'] == 'add_scalar' and r['mode'] == 0),
        layout_base_case0000=next(r['cycles'] for r in vec['results'] if r['kind'] == 'layout' and r['dut'] == 'base' and r['fixture'] == 'case0000_embed_conv0' and r['mode'] == 0),
        layout_cand_case0000=next(r['cycles'] for r in vec['results'] if r['kind'] == 'layout' and r['dut'] == 'cand' and r['fixture'] == 'case0000_embed_conv0' and r['mode'] == 0)),
    pingpong=pp['results'],
    honesty=[
        '125MHz 是历史板级 PL 时钟；300/600MHz 只是流水目标，未做 STA。',
        'DDR 用户域频率独立，不能随 compute_hz 乘频；表中分开列。',
        '历史 wholecase 153.775s 与 PL plans 12.4866s 的差不是纯 DDR 延迟；缺逐阶段 profile。',
        'C48 唯一输出数由计划 shape 统计；board c_bytes 是块级读写字节，两者口径不同。'])

(R / 'bounds.json').write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')

# 简表
lines = ['# 下界与未满归因（自动生成，详见 result.json/bounds.json）', '',
         f'- useful MAC: {mac_u:,}; padded MAC: {mac_p:,}; unique C48: {unique_c:,}',
         f'- matrix PE cycles: {pe_cyc:,} -> padded {mac_p/pe_cyc:.2f} MAC/cycle, useful {mac_u/pe_cyc:.2f}',
         f'- C48 retire: {unique_c/pe_cyc:.3f}/cycle = {unique_c*48/pe_cyc:.1f} bit/cycle; A/W 片上供数 368 bit/cycle',
         f'- matrix DDR bytes: {mat_bytes:,} B = {mat_bytes/pe_cyc:.2f} B/PE-cycle (16B/cycle 通道的 {100*mat_bytes/pe_cyc/16:.2f}%)',
         f'- vector/layout bytes: {vec_read+vec_write:,} B; total {total_bytes:,} B',
         f'- whole plan {whole/F0:.4f}s; stage sum {stage_sum/F0:.4f}s; overlap { (whole-stage_sum)/F0:.4f}s',
         f'- naive max(stage) {max(mat_q,vec_cyc,lay_cyc,fetch)/F0:.4f}s（仅独立假设，不采用）',
         '', '| compute MHz | matrix RUN-only s | matrix 256MAC/s | vector s | layout s | whole schedule s |',
         '|---:|---:|---:|---:|---:|---:|']
for r in freq_rows:
    lines.append(f"| {r['compute_hz']/1e6:.0f} | {r['matrix_actual_schedule_s']:.4f} | {r['matrix_ideal256_s']:.4f} | "
                 f"{r['vector_schedule_s']:.4f} | {r['layout_schedule_s']:.4f} | {r['whole_plan_schedule_s']:.4f} |")
lines += ['', '| DDR MHz | peak GB/s | total bytes LB s | vector/layout LB s | matrix LB s | actual effective MB/s |',
          '|---:|---:|---:|---:|---:|---:|']
for r in ddr_rows:
    lines.append(f"| {r['ddr_user_hz']/1e6:.0f} | {r['peak_GBps']:.2f} | {r['actual_bytes_lb_s']:.4f} | "
                 f"{r['vector_layout_bytes_lb_s']:.4f} | {r['matrix_bytes_lb_s']:.4f} | {r['actual_effective_MBps']:.1f} |")
lines += ['', f"- compulsory on-chip-intermediate LB: {onchip_lb:,} B (weights {unique_weight:,} + boundary in {boundary_in:,} + out {boundary_out:,})", f"- all-intermediate-DDR coarse LB: {all_inter_lb:,} B; actual total {total_bytes:,} B = {total_bytes/onchip_lb:.2f}× on-chip LB", f"- unique tensor range {unique_tensor:,} B; actual vector/layout {vec_read+vec_write:,} B = {(vec_read+vec_write)/max(1,unique_tensor):.1f}× unique tensor range", '', '| latency | base read | cand read | base write | cand write | base read util | cand read util |',
          '|---:|---:|---:|---:|---:|---:|---:|']
for L, r in burst_model.items():
    lines.append(f"| {L} | {r['base_read_cycles']} | {r['cand_read_cycles']} | {r['base_write_cycles']} | "
                 f"{r['cand_write_cycles']} | {r['base_read_util']:.3f} | {r['cand_read_util']:.3f} |")
lines += ['', f"Ping-pong: serial {pp['results'][0]['cycles']} cycles, prefetch {pp['results'][1]['cycles']} cycles, "
              f"speedup {pp['results'][1]['speedup_vs_serial']:.3f}×, overlap {pp['results'][1]['overlap']} cycles."]
(R / 'BOUNDS.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('\n'.join(lines))
