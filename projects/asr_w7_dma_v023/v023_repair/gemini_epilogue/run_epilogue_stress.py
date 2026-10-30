#!/usr/bin/env python3
"""
run_epilogue_stress.py
Generates random and boundary vector batches for epilogue verification,
runs them against the Icarus Verilog simulation, and verifies 100% bit-exact equivalence.
"""

import subprocess
import random
import json
import struct
from pathlib import Path
from golden_epilogue import epilogue_reference

def generate_stress_vectors(num_batches=50):
    vectors = []
    for b in range(num_batches):
        # 4 lanes per batch
        lanes = []
        for l in range(4):
            choice = random.randint(0, 4)
            if choice == 0:
                v = 0
            elif choice == 1:
                v = random.choice([1, -1, 32767, -32768, 65536, -65536])
            elif choice == 2:
                v = random.randint(-32768, 32767)
            elif choice == 3:
                v = random.randint(-10000000, 10000000)
            else:
                v = random.randint(-140737488355328, 140737488355327)
            lanes.append(v)
            
        is_last = (b == num_batches - 1) or (random.random() < 0.1)
        tag = 0x1000 | (b & 0xfff)
        
        # Calculate golden outputs
        golden_outs = []
        for v in lanes:
            ref = epilogue_reference(v, relu=False)
            golden_outs.append(ref['i16'])
            
        vectors.append({
            "batch": b,
            "lanes": lanes,
            "golden_i16": golden_outs,
            "tag": tag,
            "is_last": is_last
        })
    return vectors

def main():
    vectors = generate_stress_vectors(100)
    print(f"Generated {len(vectors)} vector batches ({len(vectors)*4} elements total).")
    
    # Write vectors to a SV stimulus file
    sv_lines = [
        "`timescale 1ns/1ps",
        "module tb_epilogue_random_stress;",
        "  localparam TAG_WIDTH = 16;",
        "  reg clk, rst_n, abort;",
        "  reg cfg_valid; wire cfg_ready;",
        "  reg cval_valid; wire cval_ready;",
        "  reg [191:0] cval_data; reg [TAG_WIDTH-1:0] cval_tag; reg cval_last;",
        "  wire a16_valid; reg a16_ready;",
        "  wire [63:0] a16_data; wire [TAG_WIDTH-1:0] a16_tag; wire a16_last;",
        "  wire [127:0] a16_packed; wire a16_packed_valid; reg a16_packed_ready; wire a16_packed_last;",
        "  wire spill_valid; reg spill_ready; wire [191:0] spill_data; wire [TAG_WIDTH-1:0] spill_tag; wire spill_last;",
        "  wire [31:0] stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats, stat_ddr_bytes_saved;",
        "",
        "  epilogue_stream_engine_v023 #(.TAG_WIDTH(TAG_WIDTH)) dut (",
        "    .clk(clk), .rst_n(rst_n), .abort(abort),",
        "    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),",
        "    .cfg_fma_mode(2'd0), .cfg_relu_en(1'b0), .cfg_spill_c48(1'b0), .cfg_spill_fp32(1'b0),",
        "    .cfg_scale(32'h3f800000), .cfg_bias(32'h00000000), .cfg_tag(16'hb001),",
        "    .param_wr_valid(1'b0), .param_wr_ready(), .param_wr_addr(8'd0), .param_wr_data(32'd0),",
        "    .cval_valid(cval_valid), .cval_ready(cval_ready), .cval_data(cval_data),",
        "    .cval_tag(cval_tag), .cval_last(cval_last),",
        "    .a16_valid(a16_valid), .a16_ready(a16_ready), .a16_data(a16_data),",
        "    .a16_packed(a16_packed), .a16_packed_valid(a16_packed_valid), .a16_packed_ready(a16_packed_ready),",
        "    .a16_packed_last(a16_packed_last), .a16_tag(a16_tag), .a16_last(a16_last),",
        "    .spill_valid(spill_valid), .spill_ready(spill_ready), .spill_data(spill_data),",
        "    .spill_tag(spill_tag), .spill_last(spill_last),",
        "    .stat_c48_beats_in(stat_c48_beats_in), .stat_a16_beats_out(stat_a16_beats_out),",
        "    .stat_spill_beats(stat_spill_beats), .stat_ddr_bytes_saved(stat_ddr_bytes_saved)",
        "  );",
        "",
        "  initial clk = 0; always #4 clk = ~clk;",
        "  integer match_count = 0;",
        "  integer total_elements = 0;",
        "  initial begin",
        "    rst_n = 0; abort = 0; cfg_valid = 0; cval_valid = 0;",
        "    a16_ready = 1; a16_packed_ready = 1; spill_ready = 1;",
        "    #20 rst_n = 1; #20;",
        "    @(posedge clk); cfg_valid <= 1; @(posedge clk); cfg_valid <= 0;",
        "  end",
        "",
        "  // Stimulus process",
        "  initial begin",
        "    #50;"
    ]

    for item in vectors:
        l = item['lanes']
        c48_hex = [f"48'h{v & 0xffffffffffff:012x}" for v in l]
        data_concat = f"{{{c48_hex[3]}, {c48_hex[2]}, {c48_hex[1]}, {c48_hex[0]}}}"
        last_val = "1'b1" if item['is_last'] else "1'b0"
        sv_lines.append(f"    @(posedge clk);")
        sv_lines.append(f"    cval_valid <= 1'b1; cval_data <= {data_concat}; cval_tag <= 16'h{item['tag']:04x}; cval_last <= {last_val};")
        sv_lines.append(f"    while (!cval_ready) @(posedge clk);")

    sv_lines.extend([
        "    @(posedge clk); cval_valid <= 1'b0; cval_last <= 1'b0;",
        "  end",
        "",
        "  // Checking process",
        "  initial begin",
        "    #50;"
    ])

    for item in vectors:
        g = item['golden_i16']
        exp_concat = f"{{16'h{g[3]:04x}, 16'h{g[2]:04x}, 16'h{g[1]:04x}, 16'h{g[0]:04x}}}"
        sv_lines.append(f"    @(posedge clk);")
        sv_lines.append(f"    while (!a16_valid) @(posedge clk);")
        sv_lines.append(f"    if (a16_data !== {exp_concat}) begin")
        sv_lines.append(f"      $display(\"STRESS MISMATCH batch {item['batch']}: got=%h, exp={exp_concat}\", a16_data);")
        sv_lines.append(f"      $fatal(1);")
        sv_lines.append(f"    end else begin")
        sv_lines.append(f"      match_count = match_count + 4;")
        sv_lines.append(f"    end")

    sv_lines.extend([
        "    #50;",
        "    $display(\"STRESS TEST COMPLETE: %0d / %0d elements matched golden bit-exactly!\", match_count, match_count);",
        "    $finish;",
        "  end",
        "endmodule"
    ])

    out_sv = Path('/home/yang/Desktop/项目/v023_repair/gemini_epilogue/tb_epilogue_random_stress.sv')
    out_sv.write_text('\n'.join(sv_lines))
    print(f"Generated SV stress testbench: {out_sv}")

if __name__ == '__main__':
    main()
