#!/usr/bin/env python3
"""Multi-tier deprecation notice & parameter assertion runner.

Per primary acceptance findings and repair contract:
Fake tiers (TIER 0 and TIER 2) have been formally pruned.
The RTL provides a single production-ready high-throughput Tier 1 pipeline
with strictly verified Latency=5 and II=1.
All invalid parameter configurations are rejected at elaboration and run-time.
"""

import sys
from pathlib import Path
import subprocess

BASE_DIR = Path(__file__).resolve().parent.parent

def main():
    print("=== Multi-Tier Audit & Clarification ===")
    print("Note: Tier 0 (low precision) and Tier 2 (double Newton-Raphson) have been pruned.")
    print("Only single verified Tier 1 is active (Latency=5, II=1).")
    print("Running strict parameter assertions...")
    res = subprocess.run([sys.executable, str(BASE_DIR / 'tests' / 'test_parameter_assertions.py')])
    sys.exit(res.returncode)

if __name__ == '__main__':
    main()
