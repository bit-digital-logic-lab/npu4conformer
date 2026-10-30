#!/usr/bin/env python3
"""Corrected read/write and dependency-aware bounds for the 68 closed plans.

The 929293344 B figure in research/LOWER_BOUNDS.json is an aggregate without a
measured R/W split.  We keep it only as an explicitly-labelled scenario; the
measured vector/layout split is separate.  No claim of a universal lower bound
is made where per-segment DAG data is missing.
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / "BOUNDS.json"
MD = HERE / "BOUNDS.md"

USEFUL_MAC = 3461011968
PADDED_MAC = 3991404544
TRAFFIC_TOTAL = 929293344
VL_R = 452330768
VL_W = 355555088
BYTES_PER_CYCLE = 16

rows_compute = []
for f in (125, 150, 300, 600):
    rows_compute.append(dict(
        compute_MHz=f,
        MACs_per_cycle=256,
        useful_compute_lb_s=USEFUL_MAC / (256 * f * 1e6),
        padded_compute_lb_s=PADDED_MAC / (256 * f * 1e6),
        note="matrix compute only; excludes vector/layout/QDQ/padding and DAG stalls",
    ))

rows_vl = []
rows_total = []
for f in (125, 200, 250, 300, 333):
    bw = BYTES_PER_CYCLE * f * 1e6
    r_t = VL_R / bw
    w_t = VL_W / bw
    rows_vl.append(dict(
        AXI_MHz=f,
        bytes_per_cycle=BYTES_PER_CYCLE,
        one_direction_GB_s=bw / 1e9,
        read_cycles=VL_R // BYTES_PER_CYCLE,
        write_cycles=VL_W // BYTES_PER_CYCLE,
        read_only_lb_s=r_t,
        write_only_lb_s=w_t,
        shared_serialized_lb_s=(VL_R + VL_W) / bw,
        independent_max_lb_s=max(r_t, w_t),
        note="vector/layout measured R/W split; independent max assumes perfect overlap and no DDR read/write turnaround",
    ))
    rows_total.append(dict(
        AXI_MHz=f,
        total_bytes=TRAFFIC_TOTAL,
        shared_serialized_scenario_s=TRAFFIC_TOTAL / bw,
        independent_balanced_floor_s=(TRAFFIC_TOTAL / 2) / bw,
        independent_unknown_split_ceiling_s=TRAFFIC_TOTAL / bw,
        note="929293344 B aggregate has no measured R/W split; shared value is a scenario, not a universal bound",
    ))

pe_rows = []
for bw in (2.0, 4.0, 4.8):
    for f in (150, 300, 600):
        for tile, intensity in ((16 * 16 * 32, 2.6666666666666665),
                                (32 * 32 * 32, 3.5555555555555554),
                                (32 * 32 * 256, 8.533333333333333),
                                (64 * 128 * 256, 18.285714285714285)):
            pe_rows.append(dict(
                DDR_GB_s=bw, compute_MHz=f, tile_MACs=tile,
                MAC_per_byte=intensity,
                bandwidth_supported_PE_equivalent=bw * 1e9 * intensity / (f * 1e6),
            ))

result = dict(
    scope="68 closed plans only; logic/arithmetic accounting, not a whole-model or board measurement",
    sources=["research/LOWER_BOUNDS.json", "research/PE_BANDWIDTH_MATCH.json", "work/BOARD_RESULT.json", "work/CURRENT_WORK.txt"],
    measured_vector_layout=dict(read_bytes=VL_R, write_bytes=VL_W, total_bytes=VL_R + VL_W),
    aggregate_traffic=dict(bytes=TRAFFIC_TOTAL, measured_read_write_split=False),
    compute=rows_compute,
    vector_layout_memory_bounds=rows_vl,
    aggregate_memory_scenarios=rows_total,
    pe_bandwidth_examples=pe_rows,
    key_limits=dict(
        hp128_at_125MHz_GB_s=2.0,
        ddr4_config_800MHz_64bit_peak_GB_s=12.8,
        ps_axi_nominal_max_MHz=333,
        local_compute_domain_600MHz_requires_CDC=True,
        hp_burst_beats_recommended=16,
        sixteen_beat_is_not_a_defect=True,
        multiple_outstanding_needed_to_hide_latency=True,
        six_master_hp0_shared_not_6x2GB_s=True,
    ),
    dependency_correction=[
        "AXI read and write channels are independent; do not use total_bytes / one_direction_bandwidth as a universal lower bound.",
        "DDR controller read/write turnaround and arbitration make effective R+W bandwidth below 2x the one-direction peak.",
        "The 68 plans are a DAG. A valid schedule bound is per segment: T >= sum_s max(C_s/(256 f), R_s/BW_r_eff, W_s/BW_w_eff) for serialized segments, or the critical path when segments overlap. A single global max is optimistic; a global sum is pessimistic.",
        "The measured split (R=452330768, W=355555088) only proves 0.403942928 s on one shared 2 GB/s channel at 125 MHz; independent channels allow a lower bound of max(R,W)/2GB/s=0.226165384 s only under perfect overlap.",
        "929293344 B / 16 B / 125 MHz = 0.464646672 s is a shared-serialized scenario. With unknown split and independent channels the conditional range is [0.232323336, 0.464646672] s.",
        "16-beat 128-bit bursts are the AMD-recommended HP size; >16 beats split. The useful optimization is more outstanding transactions and hiding latency, not rejecting 16 beats.",
        "600 MHz is only a local compute-domain target; PS AXI is <=333 MHz nominal and requires CDC/async FIFO. No frequency is claimed by this task.",
    ],
)
OUT.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

lines = ["# Corrected bounds (logic/accounting only)", "",
         "No synthesis, Vivado, board run, or frequency claim. Matrix compute excludes vector/layout/QDQ/padding.",
         "", "## Measured 68-plan vector/layout R/W split", "",
         "| AXI MHz | R-only LB (s) | W-only LB (s) | shared R+W (s) | independent max (s) |",
         "|---:|---:|---:|---:|---:|"]
for r in rows_vl:
    lines.append(f"| {r['AXI_MHz']} | {r['read_only_lb_s']:.9f} | {r['write_only_lb_s']:.9f} | {r['shared_serialized_lb_s']:.9f} | {r['independent_max_lb_s']:.9f} |")
lines += ["", "R=452330768 B, W=355555088 B. Independent max is optimistic: it ignores DDR read/write turnaround and DAG dependencies.",
          "", "## Aggregate 929293344 B scenarios", "",
          "| AXI MHz | shared serialized (s) | independent balanced floor (s) | unknown-split ceiling (s) |",
          "|---:|---:|---:|---:|"]
for r in rows_total:
    lines.append(f"| {r['AXI_MHz']} | {r['shared_serialized_scenario_s']:.9f} | {r['independent_balanced_floor_s']:.9f} | {r['independent_unknown_split_ceiling_s']:.9f} |")
lines += ["", "The aggregate has no measured R/W split in the supplied artifacts. The shared value is a scenario, not a universal bound.",
          "", "## Matrix compute lower bound", "",
          "| MHz | useful (ms) | padded (ms) |", "|---:|---:|---:|"]
for r in rows_compute:
    lines.append(f"| {r['compute_MHz']} | {r['useful_compute_lb_s']*1e3:.6f} | {r['padded_compute_lb_s']*1e3:.6f} |")
lines += ["", "## PE / bandwidth examples (from research/PE_BANDWIDTH_MATCH.json)", "",
          "`P_eq <= B*I/f`; 256 PE at 300 MHz needs I>=38.4 MAC/B, at 600 MHz I>=76.8 MAC/B. A single HP128 at 125 MHz is 2 GB/s, distinct from the 12.8 GB/s DDR4 physical peak.",
          "", "| B GB/s | MHz | tile | I MAC/B | P_eq |", "|---:|---:|---|---:|---:|"]
for r in pe_rows:
    lines.append(f"| {r['DDR_GB_s']} | {r['compute_MHz']} | {r['tile_MACs']} MAC | {r['MAC_per_byte']:.4f} | {r['bandwidth_supported_PE_equivalent']:.2f} |")
MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"wrote {OUT} and {MD}")
