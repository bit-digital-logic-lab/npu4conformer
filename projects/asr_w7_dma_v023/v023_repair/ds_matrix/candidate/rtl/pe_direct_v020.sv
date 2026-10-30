`timescale 1ns/1ps
// A16 * W7(S/J/M), exact clipping, three product pipeline stages, INT48 sum.
// The coefficient is never expanded to an INT16 operand for multiplication.
module pe_direct_v020(
 input wire clk,reset,flush,clear_sum,
 input wire [15:0] a_in,input wire [6:0] w_in,
 input wire av_in,wv_in,input wire [15:0] positions,input wire clip,
 output reg [15:0] a_out,output reg [6:0] w_out,
 output reg av_out,wv_out,output reg signed [47:0] sum
);
 wire [3:0] p=positions[w_in[5:4]*4+:4];
 wire saturated=clip && p==12 && w_in[3:0]>=8;
 reg [15:0] mag0,mag1;
 reg [3:0] m0,p0,p1;
 reg neg0,neg1,sat0,sat1;
 reg [2:0] valid;
 reg [19:0] raw1;
 reg signed [31:0] product2;
 (* use_dsp="no" *) wire [19:0] raw_product=mag0*m0;
 wire [31:0] aligned={12'd0,raw1}<<p1;
 wire [31:0] magnitude=aligned-(sat1?{16'd0,mag1}:32'd0);
 always @(posedge clk) begin
  if(reset || flush)begin
   a_out<=0;w_out<=0;av_out<=0;wv_out<=0;valid<=0;
   mag0<=0;mag1<=0;m0<=0;p0<=0;p1<=0;neg0<=0;neg1<=0;sat0<=0;sat1<=0;
   raw1<=0;product2<=0;
  end else begin
   a_out<=a_in;w_out<=w_in;av_out<=av_in;wv_out<=wv_in;
   valid<={valid[1:0],av_in&&wv_in};
   if(av_in&&wv_in)begin
    mag0<=a_in[15]?(~a_in+16'd1):a_in;
    m0<=saturated?4'd8:w_in[3:0];p0<=p;
    neg0<=a_in[15]^w_in[6];sat0<=saturated;
   end
   if(valid[0])begin raw1<=raw_product;mag1<=mag0;p1<=p0;neg1<=neg0;sat1<=sat0;end
   if(valid[1])product2<=neg1?-$signed(magnitude):$signed(magnitude);
  end
  if(reset||clear_sum)sum<=0;
  else if(!flush&&valid[2])sum<=sum+$signed({{16{product2[31]}},product2});
 end
endmodule
