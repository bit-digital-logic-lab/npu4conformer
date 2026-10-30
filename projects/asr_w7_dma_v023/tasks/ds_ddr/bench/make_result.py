#!/usr/bin/env python3
"""汇总最终 result.json：输入 SHA、复跑命令、各实测报告摘要。只读输入。"""
import hashlib, json, subprocess
from pathlib import Path

T = Path(__file__).resolve().parent.parent
ROOT = Path('/home/yang/Desktop/项目')
W = ROOT / 'work'
R = T / 'bench/reports'


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


inputs = [
    W / 'DESIGN_CONTRACT_zh.txt', W / 'CURRENT_WORK.txt', W / 'BOARD_RESULT.json',
    W / 'BOARD_RESULT_zh.txt', W / 'clockInfo.txt',
    W / 'rtl/axi_dma_v019.sv', W / 'rtl/block_storage_dma_prefetch.sv',
    W / 'rtl/block_engine_l1bank_v020.sv', W / 'rtl/array16_direct_v020.sv',
    W / 'rtl/pe_direct_v020.sv', W / 'rtl/c_cache_banked4.sv',
    W / 'rtl/ddr_execution_cluster_v022.sv', W / 'rtl/pl_execution_plan_v022.sv',
    W / 'rtl/ddr_vector_axi.sv', W / 'rtl/ddr_vector_engine.sv',
    W / 'rtl/ddr_layout_axi.sv', W / 'rtl/ddr_layout_engine.sv',
    W / 'tests/axi128_memory_bfm.sv', W / 'tests/tb_vector_axi.sv',
    W / 'tests/tb_layout_axi.sv', W / 'tests/tb_plan_cluster.sv',
    W / 'host/fusion_backend.py', W / 'host/base_v021.py', W / 'host/backend_v021.py',
    W / 'host/parameters.py', W / 'host/plan_metrics.py',
    W / 'ps/vm_pl.c', W / 'ps/gateway_async.c', W / 'scripts/build_full.tcl',
    W / 'assets/parameters002/parameters.bin',
    T / 'fixtures/parameters002/manifest.json',
    ROOT / 'model_a_v0_22(1).zip',
    ROOT / 'IC_GIT_REFERENCES.txt',
]
sources = [
    T / 'candidate/axi_dma_v020_multi.sv', T / 'candidate/ab_pingpong_prefetch.sv',
    T / 'candidate/ddr_vector_axi_v020.sv', T / 'candidate/ddr_layout_axi_v020.sv',
    T / 'candidate/pl_graph_runner_v1.sv',
    T / 'bench/bfm/axi128_ddr_bfm_ds.sv', T / 'bench/tb_dma_compare.sv',
    T / 'bench/tb_ab_pingpong.sv', T / 'bench/tb_graph_runner.sv',
    T / 'bench/tb_strobe_account.sv', T / 'bench/run_strobe_account.py',
    T / 'INTERFACE.md',
]
reports = {
    'baseline': T / 'bench/baseline/result.json',
    'dma_compare': R / 'dma_compare.json',
    'vector_dma_compare': R / 'vector_dma_compare.json',
    'pingpong': R / 'pingpong.json',
    'graph_runner': R / 'graph_runner.json',
    'plan_workload': R / 'plan_workload.json',
    'bounds': R / 'bounds.json',
    'short_burst': R / 'short_burst.json',
    'strobe_account': R / 'strobe_account.json',
    'findings': T / 'FINDINGS.md',
    'report': T / 'REPORT.md',
    'historical': T / 'HISTORICAL_OPTIONS.md',
    'autonomy': T / 'docs/PL_AUTONOMY.md',
}
refs = {}
for ref in ['codex/kwt-ds-r6-bus128', 'codex/kwt-ds-r6-feed8x16', 'codex/kwt-ds-r6-resident_a',
            'codex/kwt-ds-r7-cacc', 'codex/kwt-ds-r7-fifo', 'codex/kwt-ds-r7-packing',
            'codex/kwt-ds-r7-resident_both', 'codex/kwt-ds-r6-traffic',
            'codex/kwt-bus-budget', 'codex/kwt-architecture',
            'verified/dataflow-v2-functional-20261024', 'archive/ws-before-prune-20261027']:
    try:
        refs[ref] = subprocess.check_output(
            ['git', 'rev-parse', '--short', ref], cwd='/home/yang/Desktop/ic设计竞赛',
            text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        refs[ref] = 'missing'

dma = json.loads((R / 'dma_compare.json').read_text())
base = json.loads((T / 'bench/baseline/result.json').read_text())
bounds = json.loads((R / 'bounds.json').read_text())
out = dict(
    task='ds_ddr', generated_by='tasks/ds_ddr/bench/make_result.py',
    scope='逻辑验证：Icarus RTL + 参数化 AXI128 共享 DDR BFM + sealed 计划统计；无综合/Vivado/板卡/联网。',
    hardware_accessed=False, synthesis=False, board=False, network=False,
    input_sha256={str(p): sha(p) for p in inputs if p.exists()},
    candidate_sha256={str(p): sha(p) for p in sources if p.exists()},
    git_refs=refs,
    baseline=dict(passed=base.get('passed'), host_seconds=base.get('host_seconds'),
                  tests=base.get('tests'), skipped=base.get('skipped')),
    dma_compare=dict(summary=[dict(scenario=r['scenario'], mode=r['mode_name'], dut=r['dut'],
                                   max_out=r['max_out'], cycles=r['cycles'],
                                   bus_util=r['bus_util'], read_util=r['read_util'],
                                   write_util=r['write_util'],
                                   speedup_vs_base=r.get('speedup_vs_base'), bubbles=dict(
                                       read=r['rbubble'], write=r['wbubble']))
                          for r in dma['results']]),
    vector_dma_compare=dict(note='小请求 vector/layout 负载下 v020 略慢；DMA 大范围微基准另见 dma_compare。'),
    pingpong=json.loads((R / 'pingpong.json').read_text())['results'],
    short_burst=json.loads((R / 'short_burst.json').read_text())['results'],
    strobe_account=json.loads((R / 'strobe_account.json').read_text()),
    graph_runner=json.loads((R / 'graph_runner.json').read_text())['cases'],
    plan_workload=bounds['workload'],
    frequency_table=bounds['frequency_table'],
    ddr_table=bounds['ddr_table'],
    burst_model=bounds['burst_model'],
    critical_path=bounds['critical_path'],
    reports={k: str(v) for k, v in reports.items()},
    commands=[
        'python3 bench/run_baseline.py',
        'python3 bench/analyze_plan_workload.py',
        'python3 bench/run_dma_compare.py',
        'python3 bench/run_vector_compare.py',
        'python3 bench/run_short_bursts.py',
        'python3 bench/run_strobe_account.py',
        'python3 bench/run_pingpong.py',
        'python3 bench/run_graph.py',
        'python3 bench/analyze_bounds.py',
        'python3 bench/make_result.py',
    ],
    honesty=[
        'Icarus/Verilator 逻辑仿真，不是板级 DDR；BFM 不建模 PS DDR 控制器、刷新、bank/row、PHY。',
        '300/600MHz 只是流水设计目标；没有综合/STA，不能宣称物理时序。',
        'DDR 用户域频率独立；不能把 125MHz 的字节界按 compute 频率乘。',
        '历史 wholecase 153.775s 的剩余时间不是纯 DDR 延迟；缺逐阶段 profile。',
        'v020 对大范围连续 DMA 有效；对当前 vector/layout 小请求负载略慢，说明瓶颈在算子串行/请求粒度。',
        'bench/bfm/axi128_ddr_bfm_ds.sv 是本任务钉住的修正版共享 BFM：修复了 W FIFO 死锁、AW 信用不递增、单 B 仅支持一笔在途 B、每拍换向导致 50% 上限；shared 文件仍由外部维护，二者已分开。',
        'pl_graph_runner_v1 只是控制骨架（op_* 桩、本地 64B 行读取），不是 68+591 节点 CASE 集成。',
        'matrix_pe_cycles 是 RUN-only；整块 520 拍/block=63.0 MAC/cycle 是 RTL 常数推导，不是板测计数器。',
        '历史 64bit 必然不够/300MHz 已达到只对特定 A16W12/预布局成立；本轮不外推。',
        '未实现完整 PL 自主图、591 legacy 静态化、host 一次上传/下载端到端。',
    ])
(T / 'result.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('RESULT_DONE', T / 'result.json')
