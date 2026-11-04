`timescale 1ns/1ps
// v023 pipelined block address former (matrix storage contract).
//
// The original block_address_v020 is one combinational cone:
//    (block_row*ncb + block_col) * block_bytes + base
// and valid_rows/cols/extent/valid all resolve in the same cycle.  This module
// keeps the exact same arithmetic widths and truncation as v020 but splits the
// cone into three registered stages:
//
//   S1: nrb/ncb/block_bytes, block_row*ncb          (one 16x32 multiply)
//   S2: (+block_col), *block_bytes                  (add + one 32x32 multiply)
//   S3: +base, extent, row/col remainder, valid      (add/compare only)
//
// Handshake: in_valid/in_ready and out_valid/out_ready form a 3-stage elastic
// pipeline.  Operands are sampled only when in_valid && in_ready.  out_* are
// held stable until out_ready.  Latency is 3 cycles when not stalled.
// This is an integration candidate for the matrix worker: replace the
// combinational instance(s) with one instance per A/B/C address and wait for
// out_valid before moving from the request state to the storage request.
module block_address_v023(
 input wire clk,rst_n,
 input wire in_valid,output wire in_ready,
 input wire [31:0] base,
 input wire [15:0] rows,cols,block_row,block_col,
 input wire [1:0] encoding,
 output wire out_valid,input wire out_ready,
 output wire [31:0] address,
 output wire [15:0] valid_rows,valid_cols,
 output wire [39:0] extent_bytes,
 output wire valid
);
 // ---------------- stage 1 ----------------
 reg s1_valid;
 reg [31:0] s1_base;
 reg [15:0] s1_rows,s1_cols,s1_row,s1_col;
 reg [1:0] s1_encoding;
 reg [31:0] s1_nrb,s1_ncb,s1_bb;reg [63:0] s1_rowprod;
 wire [31:0] w_nrb=({16'd0,rows}+31)>>5;
 wire [31:0] w_ncb=({16'd0,cols}+31)>>5;
 wire [31:0] w_bb=encoding==0?32'd2048:encoding==1?32'd1024:32'd6144;
 wire [63:0] w_rowprod=block_row*w_ncb;
 // ---------------- stage 2 ----------------
 reg s2_valid;
 reg [31:0] s2_base,s2_nrb,s2_ncb,s2_bb;reg [39:0] s2_off;
 reg [15:0] s2_rows,s2_cols,s2_row,s2_col;
 reg [1:0] s2_enc;
 wire [63:0] w_off64=(s1_rowprod+{32'd0,s1_col})*{32'd0,s1_bb};
 wire [39:0] w_off=w_off64[39:0]; // v020 40-bit assignment context
 // ---------------- stage 3 ----------------
 reg s3_valid;
 reg [31:0] s3_base,s3_off,s3_nrb,s3_ncb,s3_bb;
 reg [15:0] s3_rows,s3_cols,s3_row,s3_col;
 reg [1:0] s3_enc;
 reg [39:0] s3_extent;
 reg [31:0] s3_address;
 reg [15:0] s3_vrows,s3_vcols;
 reg s3_valid_flag;
 wire [40:0] w_full={9'd0,s2_base}+{1'b0,s2_off};
 wire [15:0] w_vrows=(s2_rows-(s2_row<<5))>=32?16'd32:s2_rows-(s2_row<<5);
 wire [15:0] w_vcols=(s2_cols-(s2_col<<5))>=32?16'd32:s2_cols-(s2_col<<5);
 wire [63:0] w_extent64={32'd0,s2_nrb}*{32'd0,s2_ncb}*{32'd0,s2_bb};
 wire [39:0] w_extent=w_extent64[39:0];
 wire w_valid=s2_rows!=0&&s2_cols!=0&&s2_enc!=2'd3&&s2_nrb!=0&&s2_ncb!=0&&
  s2_row<s2_nrb&&s2_col<s2_ncb&&w_full[40:32]==0;

 // elastic ready chain
 wire s3_ready=out_ready||!s3_valid;
 wire s2_ready=!s2_valid||s3_ready;
 wire s1_ready=!s1_valid||s2_ready;
 assign in_ready=s1_ready;
 assign out_valid=s3_valid;
 assign address=s3_address;
 assign valid_rows=s3_vrows;
 assign valid_cols=s3_vcols;
 assign extent_bytes=s3_extent;
 assign valid=s3_valid_flag;

 always @(posedge clk)begin
  if(!rst_n)begin
   s1_valid<=0;s2_valid<=0;s3_valid<=0;
   s1_base<=0;s1_rows<=0;s1_cols<=0;s1_row<=0;s1_col<=0;s1_encoding<=0;
   s1_nrb<=0;s1_ncb<=0;s1_bb<=0;s1_rowprod<=0;
   s2_base<=0;s2_nrb<=0;s2_ncb<=0;s2_bb<=0;s2_off<=0;
   s2_rows<=0;s2_cols<=0;s2_row<=0;s2_col<=0;s2_enc<=0;
   s3_base<=0;s3_off<=0;s3_nrb<=0;s3_ncb<=0;s3_bb<=0;
   s3_rows<=0;s3_cols<=0;s3_row<=0;s3_col<=0;s3_enc<=0;
   s3_extent<=0;s3_address<=0;s3_vrows<=0;s3_vcols<=0;s3_valid_flag<=0;
  end else begin
   // stage 3
   if(s3_ready)begin
    s3_valid<=s2_valid;
    if(s2_valid)begin
     s3_base<=s2_base;s3_off<=s2_off;s3_nrb<=s2_nrb;s3_ncb<=s2_ncb;s3_bb<=s2_bb;
     s3_rows<=s2_rows;s3_cols<=s2_cols;s3_row<=s2_row;s3_col<=s2_col;s3_enc<=s2_enc;
     s3_address<=w_full[31:0];s3_extent<=w_extent;
     s3_vrows<=w_vrows;s3_vcols<=w_vcols;s3_valid_flag<=w_valid;
    end
   end
   // stage 2
   if(s2_ready)begin
    s2_valid<=s1_valid;
    if(s1_valid)begin
     s2_base<=s1_base;s2_nrb<=s1_nrb;s2_ncb<=s1_ncb;s2_bb<=s1_bb;
     s2_rows<=s1_rows;s2_cols<=s1_cols;s2_row<=s1_row;s2_col<=s1_col;s2_enc<=s1_encoding;
     s2_off<=w_off;
    end
   end
   // stage 1
   if(s1_ready)begin
    s1_valid<=in_valid;
    if(in_valid)begin
     s1_base<=base;s1_rows<=rows;s1_cols<=cols;s1_row<=block_row;s1_col<=block_col;
     s1_encoding<=encoding;s1_nrb<=w_nrb;s1_ncb<=w_ncb;s1_bb<=w_bb;s1_rowprod<=w_rowprod;
    end
   end
  end
 end
endmodule
