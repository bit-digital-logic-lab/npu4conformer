"""Run existing offline Python and RTL regressions without opening hardware."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
V5 = ROOT / 'projects/asr_qdq_fpga/v5'
FROZEN = V5.parent / 'releases/v2_20260922_pre_golden'
HEAD = ROOT / 'projects/conformer_attention_head'


def run(command, cwd):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=cwd, check=True,
                   env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}, timeout=180)


def python_checks():
    run([sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'tests', '-v'], V5)
    # The remaining two tests read golden/output tensors not distributed in Git.
    methods = ['test_equal_float', 'test_inside_then_outside_tolerance',
               'test_nonfinite', 'test_integer_exact', 'test_shape_and_dtype']
    run([sys.executable, '-B', '-m', 'unittest', '-v'] +
        ['test_independent_verifier.ComparatorChecks.' + name for name in methods],
        V5 / 'validation_case0001')


def rtl_checks():
    compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
    if not compiler or not runtime:
        raise SystemExit('RTL checks require iverilog and vvp on PATH.')
    output = ROOT / 'build/offline_rtl'
    output.mkdir(parents=True, exist_ok=True)
    arithmetic = [FROZEN / 'rtl' / (name + '.sv') for name in
                  ['asr_i16_mac', 'asr_requant', 'asr_fp32_alu']]
    vendor = V5 / 'vendor/verilog-ethernet/rtl'
    cases = {
        'tb_udp_command_bridge': [V5 / 'sim/tb_udp_command_bridge.sv',
                                  V5 / 'rtl/asr_udp_command_bridge.sv',
                                  FROZEN / 'v2/rtl/asr_command_engine_v2.sv', *arithmetic],
        'tb_udp_rx_guard': [V5 / 'sim/tb_udp_rx_guard.sv', V5 / 'rtl/asr_udp_rx_guard.sv'],
        'tb_ksz9031_init': [V5 / 'sim/tb_ksz9031_init.sv', V5 / 'rtl/asr_ksz9031_init.sv'],
        'tb_arp_direct_link': [V5 / 'sim/tb_arp_direct_link.sv'] +
                              [vendor / (name + '.v') for name in
                               ['arp', 'arp_cache', 'arp_eth_rx', 'arp_eth_tx', 'lfsr']],
    }
    markers = {'tb_udp_command_bridge': 'PASS tb_udp_command_bridge',
               'tb_udp_rx_guard': 'UDP_RX_GUARD_TEST_PASS',
               'tb_ksz9031_init': 'KSZ9031_INIT_TEST_PASS',
               'tb_arp_direct_link': 'PASS tb_arp_direct_link'}
    for top, sources in cases.items():
        image = output / (top + '.vvp')
        run([compiler, '-g2012', '-s', top, '-o', image, *sources], ROOT)
        completed = subprocess.run([runtime, str(image)], cwd=ROOT, text=True,
                                   capture_output=True, timeout=180, check=True)
        print(completed.stdout, end='')
        if completed.stderr:
            print(completed.stderr, file=sys.stderr, end='')
        if markers[top] not in completed.stdout:
            raise SystemExit('RTL test produced no PASS marker: ' + top)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--suite', choices=['python', 'rtl', 'head', 'all'], default='all')
    args = p.parse_args()
    if args.suite in ('python', 'all'):
        python_checks()
    if args.suite in ('rtl', 'all'):
        rtl_checks()
    if args.suite == 'head':
        if not (HEAD / 'weights/layer_0.pth').is_file():
            raise SystemExit('Prepare local head assets before running this suite.')
        run([sys.executable, '-B', '-m', 'unittest', 'host.test_full_head', '-v'], HEAD)
    print('OFFLINE_CHECKS_PASS: ' + args.suite)


if __name__ == '__main__':
    main()
