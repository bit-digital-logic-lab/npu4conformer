"""Portable build entry for the two archived FPGA projects; no programming."""
from pathlib import Path
import argparse
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', choices=['head', 'asr'], required=True)
    p.add_argument('--action', choices=['create', 'build', 'hls', 'cosim', 'fma', 'numeric-sim'], required=True)
    p.add_argument('--run', default='board_rebuild_001')
    p.add_argument('--vivado', default='vivado')
    p.add_argument('--vitis-run', default='vitis-run')
    args = p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_]+', args.run):
        p.error('--run must contain only letters, digits and underscores')
    if args.project == 'head':
        root = ROOT / 'projects/conformer_attention_head'
        scripts = {'create': 'create_project.tcl', 'build': 'build.tcl',
                   'hls': 'hls.tcl', 'cosim': 'cosim.tcl'}
    else:
        root = ROOT / 'projects/asr_qdq_fpga/v5'
        scripts = {'build': 'build_board.tcl', 'fma': 'generate_fma_ip.tcl',
                   'numeric-sim': 'simulate_numeric.tcl'}
    if args.action not in scripts:
        p.error('Action is not applicable to the chosen project')
    script = root / 'scripts' / scripts[args.action]
    if args.action in ('hls', 'cosim'):
        command = [args.vitis_run, '--mode', 'hls', '--tcl', str(script)]
    else:
        command = [args.vivado, '-mode', 'batch', '-nojournal', '-nolog', '-source', str(script)]
        if args.project == 'asr' and args.action == 'build':
            command += ['-tclargs', args.run]
    (root / 'artifacts').mkdir(exist_ok=True)
    print(' '.join(command), flush=True)
    subprocess.run(command, cwd=root, check=True,
                   env={**os.environ, 'ASR_PYTHON': sys.executable})


if __name__ == '__main__':
    main()
