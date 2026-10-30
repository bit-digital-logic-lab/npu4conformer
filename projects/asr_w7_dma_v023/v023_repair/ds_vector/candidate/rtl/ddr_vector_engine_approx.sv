`timescale 1ns/1ps
// Integration wrapper: candidate pipelined vector engine with gemini_approx core enabled.
// Keeps the baseline top-level port list; DIV/SQRT are approximate (not bitexact).
module ddr_vector_engine_approx (input wire clk,rst_n,start,input wire [511:0] descriptor,input wire [31:0] param_end,
 output wire ready,output wire busy,done,fault,output wire [7:0] error_code,numeric_flags,
 output wire [31:0] completed_elements,rejected_starts,
 output wire [63:0] cycles,read_compute_overlap,write_compute_overlap,
 output wire rd_request_valid,input wire rd_request_ready,
 output wire [31:0] rd_address,output wire [15:0] rd_beats,
 input wire rd_valid,output wire rd_ready,input wire [127:0] rd_data,
 input wire [15:0] rd_index,input wire rd_done,rd_error,
 output wire wr_request_valid,input wire wr_request_ready,
 output wire [31:0] wr_address,output wire [15:0] wr_beats,
 output wire wr_valid,input wire wr_ready,output wire [127:0] wr_data,
 output wire [15:0] wr_strobe,input wire wr_done,wr_error);
 ddr_vector_engine_pipe #(.CHUNK(256),.ARENA_BASE(32'h04000000),.ARENA_END(32'h08000000),
  .PARAM_BASE(32'h10000000),.PARAM_END(32'h40000000),.USE_APPROX_DIV_SQRT(1)) dut(.*);
endmodule
