`timescale 1ns/1ps
// 16x16 physical PE sub-array; the scheduler always exposes 32x32 logical blocks.
module array16_direct_v020(
 input wire clk,reset,flush,clear_sum,
 input wire [255:0] a_left,input wire [111:0] w_top,
 input wire [15:0] av,wv,input wire [15:0] positions,input wire clip,
 output wire [12287:0] sums
);
 wire [15:0] aa[0:15][0:16];wire [6:0] ww[0:16][0:15];
 wire va[0:15][0:16],vw[0:16][0:15];
 for(genvar r=0;r<16;r=r+1)begin:rows
  assign aa[r][0]=a_left[r*16+:16];assign va[r][0]=av[r];
  for(genvar c=0;c<16;c=c+1)begin:cols
   pe_direct_v020 pe(.clk(clk),.reset(reset),.flush(flush),.clear_sum(clear_sum),
    .a_in(aa[r][c]),.w_in(ww[r][c]),.av_in(va[r][c]),.wv_in(vw[r][c]),
    .positions(positions),.clip(clip),.a_out(aa[r][c+1]),.w_out(ww[r+1][c]),
    .av_out(va[r][c+1]),.wv_out(vw[r+1][c]),.sum(sums[(r*16+c)*48+:48]));
  end
 end
 for(genvar c=0;c<16;c=c+1)begin:top
  assign ww[0][c]=w_top[c*7+:7];assign vw[0][c]=wv[c];
 end
endmodule
