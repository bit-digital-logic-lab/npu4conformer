"""Run the repository's existing CI gates locally; never refresh hashes or push."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
COMMANDS = [
    ['git', 'diff', '--check'],
    [sys.executable, 'tools/check_repository.py'],
    [sys.executable, 'tools/run_checks.py', '--suite', 'python'],
    [sys.executable, 'tools/run_checks.py', '--suite', 'rtl'],
]


def main():
    for command in COMMANDS:
        print('+ ' + ' '.join(command), flush=True)
        subprocess.run(command, cwd=ROOT, check=True)
    print('PRE_PUSH_CHECKS_PASS (repository gates only; not full-model acceptance)')


if __name__ == '__main__':
    main()
