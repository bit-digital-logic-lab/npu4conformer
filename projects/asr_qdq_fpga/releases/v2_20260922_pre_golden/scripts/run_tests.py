"""Run reproducible offline RTL and Python tests; never opens a serial port."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--iverilog', default='iverilog')
    p.add_argument('--vvp', default='vvp')
    p.add_argument('--scalar-count', type=int, default=2000)
    a = p.parse_args()
    work = ROOT / 'build' / 'tests'
    work.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1',
               PYTHONPATH=os.pathsep.join([str(ROOT), str(ROOT / 'host')]),
               ASR_IVERILOG=a.iverilog, ASR_VVP=a.vvp)
    records = []
    def run(cmd):
        print('+', subprocess.list2cmdline([str(x) for x in cmd]), flush=True)
        completed = subprocess.run([str(x) for x in cmd], cwd=work, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(completed.stdout, end='', flush=True)
        records.append({'command': [str(x) for x in cmd], 'exit_code': completed.returncode,
                        'output': completed.stdout})
        report = {'physical_fpga_executed': False,
                  'all_commands_passed_so_far': all(r['exit_code'] == 0 for r in records),
                  'suite_complete': False, 'commands': records,
                  'rtl_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in sorted((ROOT / 'rtl').glob('*.sv'))}}
        (work / 'test_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        completed.check_returncode()
    rtl = sorted((ROOT / 'rtl').glob('*.sv'))
    for top in ['tb_asr_i16_mac', 'tb_asr_requant', 'tb_asr_command_engine', 'tb_asr_uart', 'tb_asr_fp32_reset']:
        exe = work / (top + '.vvp')
        run([a.iverilog, '-g2012', '-s', top, '-o', exe, *rtl, ROOT / 'sim' / (top + '.sv')])
        run([a.vvp, exe])
    run([sys.executable, '-B', ROOT / 'host' / 'fp32_reference.py', '--root', ROOT,
         '--work', work / 'scalar', '--count', a.scalar_count,
         '--iverilog', a.iverilog, '--vvp', a.vvp])
    run([sys.executable, '-B', ROOT / 'host' / 'integer_reference.py'])
    run([sys.executable, '-B', '-m', 'unittest', 'discover', '-s', ROOT / 'tests', '-v'])
    run([sys.executable, '-B', ROOT / 'tests' / 'test_stdio_bridge.py', a.vvp,
         work / 'stdio' / 'asr_stdio.vvp'])
    report_path = work / 'test_report.json'
    report = json.loads(report_path.read_text(encoding='utf-8'))
    report['suite_complete'] = True
    report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('PASS: offline tests only; no physical FPGA execution claimed.')

if __name__ == '__main__':
    main()
