#!/usr/bin/env bash
# 一键复跑（Icarus/Verilator/Python；不综合、不板卡、不联网）
set -euo pipefail
cd "$(dirname "$0")/.."
python3 bench/run_baseline.py
python3 bench/analyze_plan_workload.py
python3 bench/run_dma_compare.py
python3 bench/run_vector_compare.py
python3 bench/run_short_bursts.py
python3 bench/run_strobe_account.py
python3 bench/run_pingpong.py
python3 bench/run_graph.py
python3 bench/analyze_bounds.py
python3 bench/make_result.py
echo "DS_DDR_ALL_DONE"
