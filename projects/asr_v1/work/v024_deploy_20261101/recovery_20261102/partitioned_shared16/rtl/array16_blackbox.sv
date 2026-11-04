`timescale 1ns/1ps
(* black_box = "yes" *)
module array16_w7_c48_cfg #(
    parameter integer PIPE_STAGES = 4,
    parameter integer ACCUM_MODE  = 0,
    parameter integer CPA_PIPE    = 1
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         flush,
    input  wire         clear_sum,
    input  wire [255:0] a_left,
    input  wire [111:0] w_top,
    input  wire [15:0]  av,
    input  wire [15:0]  wv,
    input  wire [15:0]  positions,
    input  wire         clip,
    output wire [12287:0] sums,
    output wire         pipe_empty,
    output wire         drain_done,
    output wire [7:0]   pe_drain_cycles,
    output wire [7:0]   array_drain_cycles
);
endmodule
