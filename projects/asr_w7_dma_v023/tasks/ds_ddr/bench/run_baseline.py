#!/usr/bin/env python3
"""可移植 baseline 复跑：只读 work/rtl 与 work/tests，产物写入本目录。
原脚本硬编码 Windows iverilog 路径，这里改成本机 iverilog；测试语义不变。
不修改输入模型、不生成 Vivado、不访问板卡。"""
import hashlib, json, os, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path('/home/yang/Desktop/项目')
WORK = ROOT / 'work'
OUT = Path(__file__).resolve().parent / 'baseline'
IVERILOG = shutil.which('iverilog') or '/home/yang/yosys-sta/oss-cad-suite/bin/iverilog'
VVP = shutil.which('vvp') or '/home/yang/yosys-sta/oss-cad-suite/bin/vvp'
FW = WORK / 'tests/fma_forbidden_stub.sv'
BFM = WORK / 'tests/axi128_memory_bfm.sv'
# Icarus 14 的 $value$plusargs %s 不能直接处理 UTF-8 路径；用 ASCII 短别名只替换 plusarg 文本。
ALIAS = Path('/tmp/opencode/dsddr_work')
if not ALIAS.exists():
    ALIAS.symlink_to(WORK)
# Icarus 14 的 $readmemh 不接受含中文的绝对路径；bench 输出也用 ASCII 别名。
OUT_ALIAS = Path('/tmp/opencode/dsddr_baseline')
OUT_ALIAS.parent.mkdir(parents=True, exist_ok=True)
if OUT_ALIAS.is_symlink() and not OUT_ALIAS.exists():
    OUT_ALIAS.unlink()
if not OUT_ALIAS.exists():
    OUT_ALIAS.symlink_to(OUT)
R = WORK / 'rtl'


def run(cmd, cwd, timeout=300):
    t = time.perf_counter()
    cp = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return cp, time.perf_counter() - t


def compile_tb(tag, top, src, extra=()):
    out = OUT / tag
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    exe = out / f'{tag}.vvp'
    cp, dt = run([IVERILOG, '-g2012', *extra, '-s', top, '-o', str(exe), *map(str, src)], out)
    (out / 'compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode != 0:
        raise RuntimeError(f'{tag} compile failed: ' + (cp.stdout + cp.stderr)[-2000:])
    return out, exe


def sim(out, exe, args, name, timeout=300):
    cp, dt = run([VVP, '-i', str(exe), *args], out, timeout)
    (out / f'{name}.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    return cp, dt


results = []


def record(tag, passed, detail, seconds):
    results.append(dict(test=tag, passed=bool(passed), detail=detail, host_seconds=round(seconds, 3)))
    print(('PASS' if passed else 'FAIL'), tag, detail, f'{seconds:.2f}s', flush=True)
    if not passed:
        raise RuntimeError(f'{tag}: {detail}')


def fixture_cases(path):
    return json.loads((path / 'meta.json').read_text())


# ---------- CSR ----------
def test_csr():
    out, exe = compile_tb('csr001', 'tb_plan_csr', [WORK / 'tests/tb_plan_csr.sv', R / 'plan_submit_csr.sv'])
    cp, dt = sim(out, exe, [], 'sim')
    record('csr001', cp.returncode == 0 and 'V022_PLAN_CSR_PASS' in cp.stdout, 'AXIL CSR 单测', dt)


# ---------- vector core (transactional BFM) ----------
def test_vector_rtl():
    src = [WORK / 'tests/tb_vector.sv', FW, R / 'ddr_vector_engine.sv', R / 'asr_fp32_alu.sv']
    out, exe = compile_tb('vector_rtl', 'tb_vector', src)
    total = 0.0
    rows = []
    for case in fixture_cases(WORK / 'tests/vector_fixtures'):
        modes = range(10) if case['name'] == 'add_scalar' else [0]
        for mode in modes:
            f = ALIAS / 'tests/vector_fixtures' / case['name']
            cp, dt = sim(out, exe, [f'+folder={f.as_posix()}', f'+nbytes={case["output_bytes"]}', f'+mode={mode}'],
                         f'{case["name"]}_{mode}')
            total += dt
            ok = cp.returncode == 0 and 'V022_VECTOR_PASS' in cp.stdout
            rows.append(dict(name=case['name'], mode=mode, passed=ok))
            if not ok:
                record('vector_rtl', False, f'{case["name"]}/{mode}', dt)
    record('vector_rtl', True, f'{len(rows)} 个数值/背压用例', total)


# ---------- vector + 2 real AXI DMAs ----------
def test_vector_axi():
    src = [WORK / 'tests/tb_vector_axi.sv', BFM, FW, R / 'ddr_vector_axi.sv',
           R / 'ddr_vector_engine.sv', R / 'asr_fp32_alu.sv', R / 'axi_dma_v019.sv']
    out, exe = compile_tb('vector_axi', 'tb_vector_axi', src)
    total = 0.0
    rows = []
    for case in fixture_cases(WORK / 'tests/vector_fixtures'):
        modes = range(10) if case['name'] == 'add_scalar' else [0]
        for mode in modes:
            f = ALIAS / 'tests/vector_fixtures' / case['name']
            cp, dt = sim(out, exe, [f'+folder={f.as_posix()}', f'+nbytes={case["output_bytes"]}', f'+mode={mode}'],
                         f'{case["name"]}_{mode}')
            total += dt
            ok = cp.returncode == 0 and 'V022_VECTOR_AXI_PASS' in cp.stdout
            rows.append(dict(name=case['name'], mode=mode, passed=ok))
            if not ok:
                record('vector_axi', False, f'{case["name"]}/{mode}', dt)
    record('vector_axi', True, f'{len(rows)} 个真实 AXI 用例', total)


# ---------- plan + 3 real AXI DMAs ----------
def test_plan_rtl():
    src = [WORK / 'tests/tb_plan_cluster.sv', BFM, FW, R / 'ddr_execution_cluster.sv',
           R / 'pl_execution_plan.sv', R / 'ddr_vector_axi.sv', R / 'ddr_vector_engine.sv',
           R / 'asr_fp32_alu.sv', R / 'axi_dma_v019.sv']
    out, exe = compile_tb('plan_rtl', 'tb_plan_cluster', src)
    folder = ALIAS / 'tests/plan_fixture'
    total = 0.0
    for mode in range(15):
        cp, dt = sim(out, exe, [f'+folder={folder.as_posix()}', f'+mode={mode}'], f'mode{mode}')
        total += dt
        ok = cp.returncode == 0 and 'V022_PLAN_CLUSTER_PASS' in cp.stdout
        if not ok:
            record('plan_rtl', False, f'mode{mode}', dt)
    record('plan_rtl', True, '15 个计划/错误/依赖用例', total)


# ---------- layout + 2 real AXI DMAs ----------
def test_layout_rtl():
    src = [WORK / 'tests/tb_layout_axi.sv', BFM, R / 'ddr_layout_axi.sv', R / 'ddr_layout_engine.sv',
           R / 'u16_divmod.sv', R / 'axi_dma_v019.sv']
    out, exe = compile_tb('layout_rtl', 'tb_layout_axi', src)
    total = 0.0
    rows = []
    for case in fixture_cases(WORK / 'tests/layout_fixtures'):
        modes = range(13) if case['name'] == 'copy_i16' else [0]
        for mode in modes:
            f = ALIAS / 'tests/layout_fixtures' / case['name']
            cp, dt = sim(out, exe, [f'+folder={f.as_posix()}', f'+nbytes={case["output_bytes"]}', f'+mode={mode}'],
                         f'{case["name"]}_{mode}', timeout=600)
            total += dt
            ok = cp.returncode == 0 and 'V022_LAYOUT_AXI_PASS' in cp.stdout
            rows.append(dict(name=case['name'], mode=mode, passed=ok))
            if not ok:
                record('layout_rtl', False, f'{case["name"]}/{mode}', dt)
    record('layout_rtl', True, f'{len(rows)} 个布局用例', total)


# ---------- coefficient reuse ----------
def test_reuse():
    out = OUT / 'reuse_rtl'
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    text = (WORK / 'tests/tb_vector_axi.sv').read_text()
    text = text.replace('gold[0:4095]', 'gold[0:16383]').replace('completed_elements!=1001', 'completed_elements!=desc_words[6]')
    tb = out / 'tb.sv'
    tb.write_text(text, encoding='utf-8')
    src = [tb, BFM, FW, R / 'ddr_vector_axi.sv', R / 'ddr_vector_engine.sv', R / 'asr_fp32_alu.sv', R / 'axi_dma_v019.sv']
    exe = out / 'reuse.vvp'
    cp, _ = run([IVERILOG, '-g2012', '-s', 'tb_vector_axi', '-o', str(exe), *map(str, src)], out)
    (out / 'compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    if cp.returncode != 0:
        record('reuse_rtl', False, 'compile', 0)
    total = 0.0
    for case in fixture_cases(WORK / 'tests/reuse_fixtures'):
        f = ALIAS / 'tests/reuse_fixtures' / case['name']
        cp, dt = sim(out, exe, [f'+folder={f.as_posix()}', f'+nbytes={case["output_bytes"]}', '+mode=0'], case['name'])
        total += dt
        ok = cp.returncode == 0 and 'V022_VECTOR_AXI_PASS' in cp.stdout
        if not ok:
            record('reuse_rtl', False, case['name'], dt)
    record('reuse_rtl', True, '6 个周期复用用例', total)


# ---------- alignment sweep ----------
def test_alignment():
    out = OUT / 'alignment'
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    rows = []

    def hexbytes(p):
        return bytearray(int(x, 16) for x in p.read_text().split())

    for kind in ('vector', 'layout'):
        tb = (WORK / f'tests/tb_{kind}_axi.sv').read_text()
        if kind == 'layout':
            tb = tb.replace('ddr.memory[65536+j]', "ddr.memory[desc_words[3]-32'h04000000+j]")
        path = out / f'tb_{kind}_axi.sv'
        path.write_text(tb, encoding='utf-8')
        names = ('ddr_vector_axi.sv', 'ddr_vector_engine.sv', 'asr_fp32_alu.sv', 'axi_dma_v019.sv') \
            if kind == 'vector' else ('ddr_layout_axi.sv', 'ddr_layout_engine.sv', 'u16_divmod.sv', 'axi_dma_v019.sv')
        src = [path, BFM, *[R / x for x in names]]
        if kind == 'vector':
            src.append(FW)
        exe = out / f'{kind}.vvp'
        cp, _ = run([IVERILOG, '-g2012', '-s', f'tb_{kind}_axi', '-o', str(exe), *map(str, src)], out)
        (out / f'{kind}_compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
        if cp.returncode != 0:
            record('alignment', False, f'{kind} compile', 0)
        selected = (('add_scalar', 4, 4, 0), ('i16_to_float', 2, 0, 0), ('i48_to_float', 14, 0, 0), ('round_i16', 12, 0, 0)) \
            if kind == 'vector' else (('copy_i16', 2, 0, 2), ('unpack_c48_compact', 14, 0, 14),
                                      ('unpack_nchw_fp32', 4, 0, 4), ('depthwise_31', 2, 0, 2))
        for name, ashift, bshift, dshift in selected:
            original = WORK / f'tests/{kind}_fixtures' / name
            folder = out / name
            folder.mkdir(exist_ok=True)
            sim_folder = OUT_ALIAS / 'alignment' / name
            memory = hexbytes(original / 'memory.hex')
            w = [int(x, 16) for x in (original / 'descriptor.hex').read_text().split()]
            gold = (original / 'gold.hex').read_text()
            nbytes = len(gold.split())
            if kind == 'vector':
                size = 6 if w[1] & (1 << 13) else 2 if w[1] & (1 << 8) else 4
                n = w[6]
                at = w[2] - 0x04000000
                data = memory[at:at + n * size]
                memory[at + ashift:at + ashift + n * size] = data
                w[2] += ashift
                if bshift:
                    at = w[3] - 0x04000000
                    data = memory[at:at + 4]
                    memory[at + bshift:at + bshift + 4] = data
                    w[3] += bshift
            else:
                data = memory[:65500]
                memory[ashift:ashift + len(data)] = data
                w[2] += ashift
                w[3] += dshift
            (folder / 'memory.hex').write_text(''.join(f'{x:02x}\n' for x in memory))
            (folder / 'gold.hex').write_text(gold)
            (folder / 'descriptor.hex').write_text(''.join(f'{x:08x}\n' for x in w))
            cp, dt = sim(out, exe, [f'+folder={sim_folder.as_posix()}', f'+nbytes={nbytes}', '+mode=0'], name, timeout=600)
            ok = cp.returncode == 0 and f'V022_{kind.upper()}_AXI_PASS' in cp.stdout
            rows.append(dict(name=f'{kind}/{name}', passed=ok))
            if not ok:
                record('alignment', False, f'{kind}/{name}', dt)
    record('alignment', True, f'{len(rows)} 个非对齐用例', 0)


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    started = time.time()
    skipped = [
        dict(test='matrix_epoch', reason='依赖 model_a_v0_21_1/tests/tb_queue.sv 与 W7/A16/C48 逐场景 vectors；本目录缺失，未编造。'),
        dict(test='layout_cluster', reason='依赖生成脚本与 5 端口 harness；本阶段先保留原始 RTL 逻辑测试，后续单独移植。'),
        dict(test='protocol_native', reason='依赖 model_a_v0_21_1_board_20261013_001/async002 与 Windows mock 外设；不在本次逻辑验证范围。'),
    ]
    for fn in (test_csr, test_vector_rtl, test_vector_axi, test_plan_rtl, test_layout_rtl, test_reuse, test_alignment):
        try:
            fn()
        except Exception as e:
            results.append(dict(test=fn.__name__, passed=False, detail=str(e)))
            print('FAIL', fn.__name__, e, flush=True)
    summary = dict(passed=all(r['passed'] for r in results), hardware_accessed=False,
                   scope='真实 Icarus RTL/BFM baseline；非 FPGA、非板级、非真实 DDR 带宽。',
                   iverilog=subprocess.run([IVERILOG, '-V'], capture_output=True, text=True).stdout.splitlines()[0],
                   tests=results, skipped=skipped, host_seconds=round(time.time() - started, 3),
                   source_sha256={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in
                                  [R / x for x in ('axi_dma_v019.sv', 'block_storage_dma_prefetch.sv', 'ddr_execution_cluster_v022.sv', 'pl_execution_plan_v022.sv')]})
    (OUT / 'result.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('BASELINE_DONE', summary['passed'], summary['host_seconds'], flush=True)
    sys.exit(0 if summary['passed'] else 1)
