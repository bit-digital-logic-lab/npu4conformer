#!/usr/bin/env python3
"""Static integration-readiness audit + recommended filelist.

Read-only over the worker directories.  Checks real port names and duplicate
module definitions instead of trusting worker PASS strings.  Writes only under
this audit directory.
"""
import hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # .../v023_repair
OUT = Path(__file__).resolve().parents[1] / 'analysis'
OUT.mkdir(exist_ok=True)

FILES = {
    # graph
    'wc_graph_ctrl': ROOT/'ds_graph/rtl/wc_graph_ctrl.sv',
    'wc_graph_top': ROOT/'ds_graph/rtl/wc_graph_top.sv',
    # vector
    'vec_engine_pipe': ROOT/'ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv',
    'vec_axi_pipe': ROOT/'ds_vector/candidate/rtl/ddr_vector_axi_pipe.sv',
    'vec_lane': ROOT/'ds_vector/candidate/rtl/asr_fp32_lane_fixed.sv',
    'vec_desc': ROOT/'ds_vector/candidate/rtl/vector_desc_check_pipe.sv',
    'vec_engine_approx': ROOT/'ds_vector/candidate/rtl/ddr_vector_engine_approx.sv',
    # layout (two candidates share module name)
    'lay_step': ROOT/'ds_layout/rtl/ddr_layout_engine_v023.sv',
    'lay_burst': ROOT/'ds_layout/rtl/ddr_layout_engine_v023_burst.sv',
    'lay_axi': ROOT.parent/'work/rtl/ddr_layout_axi.sv',
    # matrix
    'mx_cluster': ROOT/'ds_matrix/candidate/rtl/matrix_p2_cluster_v2.sv',
    'mx_engine': ROOT/'ds_matrix/candidate/rtl/block_engine_prefetch_v2.sv',
    'mx_storage': ROOT/'ds_matrix/candidate/rtl/block_storage_stream_v2.sv',
    'mx_dma': ROOT/'ds_matrix/candidate/rtl/axi_dma_v020_multi_v2.sv',
    # control
    'ctl_plan': ROOT/'ds_control_fixes/candidate/rtl/pl_execution_plan_v023.sv',
    'ctl_csr': ROOT/'ds_control_fixes/candidate/rtl/plan_submit_csr_v023.sv',
    'ctl_scan': ROOT/'ds_control_fixes/candidate/rtl/ready_scan_banked_v1.sv',
    'ctl_addr': ROOT/'ds_control_fixes/candidate/rtl/block_address_v023.sv',
    'ctl_dma_multi': ROOT/'ds_control_fixes/candidate/rtl/axi_dma_v023_multi.sv',
    'ctl_dma_bounded': ROOT/'ds_control_fixes/candidate/rtl/axi_dma_v023_bounded.sv',
    # sealed shared RTL
    'sealed_dma19': ROOT.parent/'work/rtl/axi_dma_v019.sv',
    'sealed_alu': ROOT.parent/'work/rtl/asr_fp32_alu.sv',
    'sealed_div': ROOT.parent/'work/rtl/u16_divmod.sv',
    'sealed_fma_stub': ROOT.parent/'work/tests/fma_forbidden_stub.sv',
}

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest() if Path(p).is_file() else None

def moddefs(p):
    if not Path(p).is_file():
        return []
    txt = Path(p).read_text(errors='ignore')
    return re.findall(r'^\s*module\s+([A-Za-z_]\w*)', txt, re.M)

def ports(p):
    """Return declared identifiers in the ANSI port list, best effort."""
    if not Path(p).is_file():
        return set()
    txt = Path(p).read_text(errors='ignore')
    m = re.search(r'module\s+\w+\s*(#\s*\(.*?\)\s*)?\((.*?)\);', txt, re.S)
    body = m.group(2) if m else ''
    names = set()
    for part in re.split(r',(?![^\[]*\])', body):
        ids = re.findall(r'[A-Za-z_]\w*', re.sub(r"\[[^\]]*\]", '', part))
        # last identifier before optional default is normally the port name
        if ids:
            names.add(ids[-1])
    return names

def text(p):
    return Path(p).read_text(errors='ignore') if Path(p).is_file() else ''

info = {}
for k, p in FILES.items():
    info[k] = {'path': str(p.relative_to(ROOT.parent)),
               'exists': Path(p).is_file(), 'sha256': sha(p), 'modules': moddefs(p)}

# duplicate module definitions across the union
from collections import defaultdict
bymod = defaultdict(list)
for k in FILES:
    for m in info[k]['modules']:
        bymod[m].append(k)
dups = {m: ks for m, ks in bymod.items() if len(set(ks)) > 1}

checks = {}
# plan v023 contract
pp = ports(FILES['ctl_plan'])
checks['plan_v023_drain_ports'] = {
    'child_abort': 'child_abort' in pp,
    'child_drained': 'child_drained' in pp,
    'dma_abort': 'dma_abort' in pp,
    'drained': 'drained' in pp,
    'drain_timeout': 'drain_timeout' in pp,
    'isolation_req': 'isolation_req' in pp,
}
# graph top seq handshake
gp = ports(FILES['wc_graph_top'])
checks['graph_top_seq'] = {
    'has_seq_valid': 'seq_valid' in gp,
    'has_seq_ready': 'seq_ready' in gp,
    'has_seq_done': 'seq_done' in gp,
    'has_seq_abort': any(x in gp for x in ('seq_abort', 'seq_child_abort')),
    'has_seq_drained': any(x in gp for x in ('seq_drained', 'seq_child_drained')),
}
# engine abort contracts
for k in ('vec_engine_pipe', 'vec_axi_pipe', 'lay_burst', 'mx_cluster', 'mx_dma'):
    p = ports(FILES[k])
    checks[k + '_abort'] = {
        'abort': 'abort' in p,
        'aborted': 'aborted' in p,
        'drained': 'drained' in p,
    }
# DMA v023 claims
for k in ('ctl_dma_multi', 'ctl_dma_bounded', 'sealed_dma19', 'mx_dma'):
    t = text(FILES[k])
    checks[k + '_dma'] = {
        'addr_40bit': bool(re.search(r'\[39:0\]\s+m_axi_araddr', t) or 'm_axi_araddr' in t),
        'abort_port': 'input wire abort' in t,
        'drained_port': 'output reg drained' in t,
        'wstrb_popcount': 'pop16' in t or 'popcount' in t,
    }
# scan/address interfaces
sp = ports(FILES['ctl_scan'])
checks['ready_scan'] = {'type_3bit_flat': 'node_type_flat' in text(FILES['ctl_scan']) and 'MAX_NODES*3' in text(FILES['ctl_scan']),
                        'cand_id_7bit': 'cand_id' in sp}
ap = ports(FILES['ctl_addr'])
checks['block_address_v023'] = {'in_valid': 'in_valid' in ap, 'out_valid': 'out_valid' in ap,
                                'extent_40bit': 'extent_bytes' in ap}
# graph top still instantiates sealed wrapper names
gt = text(FILES['wc_graph_top'])
checks['graph_top_instances'] = {
    'ddr_vector_axi': 'ddr_vector_axi ' in gt or 'ddr_vector_axi vec' in gt,
    'ddr_vector_axi_pipe': 'ddr_vector_axi_pipe' in gt,
    'ddr_layout_axi': 'ddr_layout_axi' in gt,
}
checks['layout_candidate_module_name'] = {
    'step_module': moddefs(FILES['lay_step']),
    'burst_module': moddefs(FILES['lay_burst']),
}

blockers = []
warnings = []
if dups:
    blockers.append('duplicate module definitions in candidate union: ' +
                    '; '.join(f'{m}:{ks}' for m, ks in sorted(dups.items())))
if not all(checks['plan_v023_drain_ports'].values()):
    blockers.append('plan_v023 is missing at least one drain/isolation port')
if not checks['graph_top_seq']['has_seq_abort'] or not checks['graph_top_seq']['has_seq_drained']:
    blockers.append('wc_graph_top cannot carry plan_v023 child_abort/child_drained')
for k in ('vec_engine_pipe', 'vec_axi_pipe', 'lay_burst', 'mx_cluster', 'mx_dma'):
    if not all(checks[k + '_abort'].values()):
        blockers.append(f'{k} has no abort/aborted/drained contract')
if not checks['mx_dma_dma']['abort_port']:
    blockers.append('matrix DMA (axi_dma_v020_multi_v2) has no abort/drained; '
                    'matrix cluster cannot satisfy plan_v023 child contract')
if not checks['ctl_dma_multi_dma']['abort_port']:
    blockers.append('control multi DMA abort port missing')
if 'block_address_v020' in text(FILES['mx_engine']):
    warnings.append('matrix engine still instantiates the combinational block_address_v020; '
                    'control block_address_v023 is not integrated')
if 'axi_dma_v019' in text(FILES['vec_axi_pipe']):
    warnings.append('vector candidate wrapper still uses single-outstanding axi_dma_v019; '
                    'multi-outstanding v023 DMA is not wired')
if 'axi_dma_v019' in text(FILES['wc_graph_top']):
    warnings.append('graph fetch uses single-outstanding axi_dma_v019')

res = {
    'verdict': 'blocked' if blockers else 'ready',
    'files': info,
    'duplicate_modules': dups,
    'checks': checks,
    'blockers': blockers,
    'warnings': warnings,
    'filelist_recommendation': {
        'note': 'one choice per duplicate module; see filelist_integrated.f',
        'layout_choice': 'ds_layout/rtl/ddr_layout_engine_v023_burst.sv (final candidate; step version is diagnostic)',
        'vector_choice': 'ds_vector candidate wrapper + engine; use a shim or the audit top because its module is ddr_vector_axi_pipe, not ddr_vector_axi',
        'matrix_choice': 'matrix_p2_cluster_v2 is NOT a drop-in for the graph MAT queue handshake; adapter or re-lowering missing',
        'shared_dma': 'work/rtl/axi_dma_v019.sv is still used by vector/layout wrappers; the v023 multi/bounded modules are separate tops',
    },
}
(OUT / 'interface_audit.json').write_text(json.dumps(res, indent=2))

# Generate a recommended filelist skeleton (not a claim that it compiles as a
# whole system).  Paths are relative to v023_repair.
fl = []
def add(comment, p):
    fl.append(f'// {comment}')
    fl.append(str(p))
add('shared sealed DMA (vector/layout wrappers + graph fetch)', FILES['sealed_dma19'].relative_to(ROOT.parent))
add('shared exact FP32 ALU and divider', FILES['sealed_alu'].relative_to(ROOT.parent))
add('shared divider', FILES['sealed_div'].relative_to(ROOT.parent))
add('FMA vendor stub (compile-only; op17 not covered)', FILES['sealed_fma_stub'].relative_to(ROOT.parent))
add('graph controller', FILES['wc_graph_ctrl'].relative_to(ROOT.parent))
add('graph top (needs integrator copy with ddr_vector_axi_pipe instance)', FILES['wc_graph_top'].relative_to(ROOT.parent))
add('vector candidate (unique modules)', FILES['vec_engine_pipe'].relative_to(ROOT.parent))
add('vector descriptor validator', FILES['vec_desc'].relative_to(ROOT.parent))
add('vector fixed lane', FILES['vec_lane'].relative_to(ROOT.parent))
add('vector AXI wrapper (module ddr_vector_axi_pipe)', FILES['vec_axi_pipe'].relative_to(ROOT.parent))
add('layout AXI wrapper', FILES['lay_axi'].relative_to(ROOT.parent))
add('layout candidate: burst version ONLY (same module name as step version)', FILES['lay_burst'].relative_to(ROOT.parent))
add('matrix unified cluster', FILES['mx_cluster'].relative_to(ROOT.parent))
add('matrix engine', FILES['mx_engine'].relative_to(ROOT.parent))
add('matrix storage', FILES['mx_storage'].relative_to(ROOT.parent))
add('matrix DMA (no abort/drain yet)', FILES['mx_dma'].relative_to(ROOT.parent))
add('control plan v023', FILES['ctl_plan'].relative_to(ROOT.parent))
add('control CSR v023', FILES['ctl_csr'].relative_to(ROOT.parent))
add('control ready scan', FILES['ctl_scan'].relative_to(ROOT.parent))
add('control pipelined block address', FILES['ctl_addr'].relative_to(ROOT.parent))
add('control multi DMA (abort/drain capable)', FILES['ctl_dma_multi'].relative_to(ROOT.parent))
add('control bounded DMA (plan fetch)', FILES['ctl_dma_bounded'].relative_to(ROOT.parent))
(OUT / 'filelist_integrated.f').write_text('\n'.join(fl) + '\n')

print(json.dumps({'verdict': res['verdict'], 'duplicate_modules': dups,
                  'blockers': blockers, 'warnings': warnings}, indent=2))
sys.exit(0)
