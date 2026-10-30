#!/usr/bin/env python3
"""pl_graph_runner_v1 三例：正常乱序依赖、循环依赖 fault、子算子 fault。"""
import json, re, shutil, subprocess
from pathlib import Path

T = Path(__file__).resolve().parent
ROOT = T.parent
OUT = T / 'candidate'
LOGS = T / 'logs/graph'
REPORTS = T / 'reports'
for d in (OUT, LOGS, REPORTS):
    d.mkdir(parents=True, exist_ok=True)
IVERILOG, VVP = shutil.which('iverilog'), shutil.which('vvp')
exe = OUT / 'tb_graph_runner.vvp'
cp = subprocess.run([IVERILOG, '-g2012', '-s', 'tb_graph_runner', '-o', str(exe),
                     str(T / 'tb_graph_runner.sv'), str(ROOT / 'candidate/pl_graph_runner_v1.sv')],
                    capture_output=True, text=True)
(LOGS / 'compile.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
if cp.returncode:
    raise SystemExit('compile failed')
rows = []
pat = re.compile(r'GRAPH_RESULT case=(\d+) completed=(\d+) seq=(\d+) fault=(\d+) err=(\w+) pass=(\d+)')
for c in (0, 1, 2):
    cp = subprocess.run([VVP, '-i', str(exe), f'+case={c}'], capture_output=True, text=True, timeout=120)
    (LOGS / f'case{c}.log').write_text(cp.stdout + cp.stderr, encoding='utf-8')
    m = pat.search(cp.stdout)
    if cp.returncode or not m:
        raise SystemExit(f'case {c} failed')
    d = dict(zip(['case', 'completed', 'seq', 'fault', 'err', 'pass'], m.groups()))
    for k in d:
        d[k] = int(d[k]) if k != 'err' else '0x' + d[k]
    rows.append(d)
out = dict(scope='Icarus RTL 控制骨架；op_* 为子算子握手桩，不是完整 CASE 集成。',
           cases=rows,
           note='case0 节点表顺序 0,3,1,2，依赖 1←0、2←0、3←1|2，实测启动 0,2,1,3；'
                'case1 循环依赖 fault=1/err=04；case2 子算子 fault=1/err=05。')
(REPORTS / 'graph_runner.json').write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
print(json.dumps(out, indent=2))
