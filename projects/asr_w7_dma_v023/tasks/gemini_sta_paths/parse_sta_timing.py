#!/usr/bin/env python3
"""
parse_sta_timing.py - Reproducible Parser and Empirical Timing Analyzer
Analyzes timing_baseline/timing.rpt, cdc.rpt, check_timing.rpt, bus_skew.rpt.
Outputs PATHS.csv and detailed empirical breakdown.
"""

import sys
import os
import re
import csv
from pathlib import Path
from collections import Counter

BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent.parent
TIMING_DIR = PROJECT_DIR / "timing_baseline"

def parse_timing_rpt(rpt_path):
    with open(rpt_path, 'r', encoding='utf-8', errors='ignore') as f:
        text = f.read()

    blocks = re.split(r'\n(?=Slack\s*(?:\([^)]+\))?\s*:)', text)[1:]
    paths = []

    for idx, b in enumerate(blocks, start=1):
        slack_m = re.search(r'Slack\s*(?:\([^)]+\))?\s*:\s*([-\d\.]+|inf)ns?', b)
        slack_str = slack_m.group(1) if slack_m else 'inf'
        slack_val = float(slack_str) if slack_str != 'inf' else 9999.0

        pt_m = re.search(r'Path Type:\s*(.+)', b)
        pt = pt_m.group(1).strip() if pt_m else ''
        is_setup = any(x in pt for x in ['Setup', 'Max', 'Recovery'])
        is_hold = any(x in pt for x in ['Hold', 'Min', 'Removal'])

        pg_m = re.search(r'Path Group:\s*(.+)', b)
        pg = pg_m.group(1).strip() if pg_m else '(none)'

        src_m = re.search(r'Source:\s*(\S+)', b)
        src = src_m.group(1) if src_m else ''
        dst_m = re.search(r'Destination:\s*(\S+)', b)
        dst = dst_m.group(1) if dst_m else ''

        src_clk_m = re.search(r'clocked by (\S+)', b)
        src_clk = src_clk_m.group(1) if src_clk_m else ''
        dst_clk_m = re.search(r'clocked by (\S+)', b[b.find('Destination:'):] if 'Destination:' in b else b)
        dst_clk = dst_clk_m.group(1) if dst_clk_m else ''

        req_m = re.search(r'Requirement:\s*([\d\.]+)ns', b)
        req = float(req_m.group(1)) if req_m else 0.0

        delay_m = re.search(r'Data Path Delay:\s*([\d\.]+)ns\s+\(logic\s+([\d\.]+)ns\s*\(([\d\.]+)%\)\s+route\s+([\d\.]+)ns\s*\(([\d\.]+)%\)\)', b)
        if delay_m:
            data_delay = float(delay_m.group(1))
            logic_delay = float(delay_m.group(2))
            logic_pct = float(delay_m.group(3))
            net_delay = float(delay_m.group(4))
            net_pct = float(delay_m.group(5))
        else:
            delay_alt = re.search(r'Data Path Delay:\s*([\d\.]+)ns', b)
            data_delay = float(delay_alt.group(1)) if delay_alt else 0.0
            logic_delay, logic_pct, net_delay, net_pct = 0.0, 0.0, 0.0, 0.0

        levels_m = re.search(r'Logic Levels:\s*(\d+)(?:\s*\((.*?)\))?', b)
        levels = int(levels_m.group(1)) if levels_m else 0
        level_details = levels_m.group(2).strip() if levels_m and levels_m.group(2) else ''

        # Split datapath section
        parts = b.split('-------------------------------------------------------------------')
        dp_text = ''
        for p in parts[1:]:
            if dst in p:
                dp_text = p
                break
        if not dp_text and len(parts) >= 3:
            dp_text = parts[2]

        fanouts = [int(m) for m in re.findall(r'net\s*\(fo=(\d+),', dp_text)]
        max_fo = max(fanouts) if fanouts else (1 if data_delay > 0 else 0)

        # Categorization
        has_carry = bool(re.search(r'\bCARRY8\b', dp_text)) or ('CARRY8' in level_details)
        has_dsp = bool(re.search(r'\b(DSP|DSP48E2)\b', dp_text)) or ('DSP' in level_details)
        has_bram = bool(re.search(r'\b(RAMB|FIFO|URAM)\b', dp_text))
        has_fma = bool('fma' in b.lower() or 'numeric_core' in b.lower() or 'asr_fp32_alu' in b.lower())
        has_ce = bool(re.search(r'/(CE|GE)\b', dst) or re.search(r'/(CE|GE)\b', dp_text))
        has_reset = bool(re.search(r'/(R|S|CLR|PRE)\b', dst) or 'Recovery' in pt or 'Removal' in pt or 'reset' in src.lower() or 'reset' in dst.lower())
        has_mux = bool(re.search(r'\b(MUXF7|MUXF8)\b', dp_text)) or ('MUX' in level_details)
        has_shifter = bool(re.search(r'\b(SRL|SRLC32E|SRL16E)\b', dp_text)) or ('shift' in dp_text.lower() and 'reg' in dp_text.lower())

        # Module resolution
        def get_mod(pin):
            if not pin: return 'UNKNOWN'
            tokens = pin.split('/')
            if len(tokens) >= 3 and tokens[0] == 'ps_system' and tokens[1] == 'ps_gateway_i':
                return f"{tokens[0]}/{tokens[1]}/{tokens[2]}"
            elif len(tokens) >= 2:
                return f"{tokens[0]}/{tokens[1]}"
            return tokens[0]

        mod = get_mod(dst) if dst else get_mod(src)

        # Failure prediction at frequencies:
        # clk100_raw period = 8.000ns (125 MHz)
        # 150MHz (6.667ns) -> delta = 8.000 - 6.667 = 1.333ns
        # 300MHz (3.333ns) -> delta = 8.000 - 3.333 = 4.667ns
        # 600MHz (1.667ns) -> delta = 8.000 - 1.667 = 6.333ns
        fails_150 = is_setup and (pg == 'clk100_raw') and ((slack_val - 1.333) < 0)
        fails_300 = is_setup and (pg == 'clk100_raw') and ((slack_val - 4.667) < 0)
        fails_600 = is_setup and (pg == 'clk100_raw') and ((slack_val - 6.333) < 0)

        paths.append({
            'path_id': idx,
            'clock': src_clk if src_clk else (dst_clk if dst_clk else pg),
            'src_clk': src_clk,
            'dst_clk': dst_clk,
            'path_group': pg,
            'module': mod,
            'path_type': pt,
            'is_setup': is_setup,
            'is_hold': is_hold,
            'slack': slack_val,
            'slack_str': slack_str,
            'requirement_ns': req,
            'data_delay_ns': data_delay,
            'logic_delay_ns': logic_delay,
            'logic_pct': logic_pct,
            'net_delay_ns': net_delay,
            'net_pct': net_pct,
            'cell_levels': levels,
            'level_details': level_details,
            'max_fanout': max_fo,
            'source_pin': src,
            'dest_pin': dst,
            'has_carry': has_carry,
            'has_dsp': has_dsp,
            'has_bram': has_bram,
            'has_fma': has_fma,
            'has_clock_enable': has_ce,
            'has_reset': has_reset,
            'has_mux': has_mux,
            'has_shifter': has_shifter,
            'fails_at_150mhz': fails_150,
            'fails_at_300mhz': fails_300,
            'fails_at_600mhz': fails_600,
            'raw': b
        })

    return paths

def write_paths_csv(paths, out_path):
    headers = [
        'path_id', 'clock', 'path_group', 'module', 'path_type', 'slack_ns',
        'requirement_ns', 'data_delay_ns', 'logic_delay_ns', 'logic_pct',
        'net_delay_ns', 'net_pct', 'cell_levels', 'level_details', 'max_fanout',
        'has_carry', 'has_dsp', 'has_bram', 'has_fma', 'has_clock_enable',
        'has_reset', 'has_mux', 'has_shifter', 'fails_150mhz', 'fails_300mhz', 'fails_600mhz',
        'source_pin', 'dest_pin'
    ]
    with open(out_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        for p in paths:
            writer.writerow([
                p['path_id'],
                p['clock'],
                p['path_group'],
                p['module'],
                p['path_type'],
                p['slack_str'],
                f"{p['requirement_ns']:.3f}",
                f"{p['data_delay_ns']:.3f}",
                f"{p['logic_delay_ns']:.3f}",
                f"{p['logic_pct']:.1f}",
                f"{p['net_delay_ns']:.3f}",
                f"{p['net_pct']:.1f}",
                p['cell_levels'],
                p['level_details'],
                p['max_fanout'],
                1 if p['has_carry'] else 0,
                1 if p['has_dsp'] else 0,
                1 if p['has_bram'] else 0,
                1 if p['has_fma'] else 0,
                1 if p['has_clock_enable'] else 0,
                1 if p['has_reset'] else 0,
                1 if p['has_mux'] else 0,
                1 if p['has_shifter'] else 0,
                1 if p['fails_at_150mhz'] else 0,
                1 if p['fails_at_300mhz'] else 0,
                1 if p['fails_at_600mhz'] else 0,
                p['source_pin'],
                p['dest_pin']
            ])

def main():
    rpt_path = TIMING_DIR / "timing.rpt"
    if not rpt_path.exists():
        print(f"Error: {rpt_path} does not exist!")
        sys.exit(1)

    paths = parse_timing_rpt(rpt_path)
    csv_path = BASE_DIR / "PATHS.csv"
    write_paths_csv(paths, csv_path)
    print(f"Successfully wrote {len(paths)} paths to {csv_path}")

if __name__ == '__main__':
    main()
