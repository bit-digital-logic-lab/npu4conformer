`timescale 1ns/1ps
// V0.24 directed epilogue-lane contract: integer C48 -> I48/F32 ->
// single-rounding FMA(scale,bias) -> ReLU -> F32.  The fixture vectors are
// chosen so that single-rounding FMA differs from mul-then-add in FP32.
module tb_v024_epilogue;
 reg clk=0;
 always #4 clk=~clk;
 reg rst_n=0;

 reg [31:0] vec[0:191];
 reg [31:0] gold[0:63];
 reg [31:0] two[0:63];
 integer i, n, seen;
 integer fd;
 reg [1023:0] vecfile, outfile, goldfile, twofile;

 reg in_valid=0;
 reg signed [47:0] in_c48=0;
 reg [31:0] in_scale=0, in_bias=0;
 wire out_valid; wire out_ready = 1;
 wire signed [15:0] out_a16;
 wire [15:0] out_tag; wire out_last;
 wire fp32_valid, in_ready;
 wire [31:0] fp32_data;

 epilogue_lane_v024 u_lane (
  .clk(clk),.rst_n(rst_n),.flush(1'b0),
  .cfg_fma_mode(2'd1),.cfg_relu_en(1'b0),
  .in_scale(in_scale),.in_bias(in_bias),
  .in_valid(in_valid),.in_ready(in_ready),
  .in_c48(in_c48),.in_tag(16'd0),.in_last(1'b0),
  .out_valid(out_valid),.out_ready(out_ready),.out_a16(out_a16),
  .out_tag(out_tag),.out_last(out_last),
  .fp32_valid(fp32_valid),.fp32_data(fp32_data)
 );

 reg [31:0] results[0:63];
 always @(posedge clk) begin
  if (fp32_valid && seen < 64) begin
   results[seen] <= fp32_data;
   seen <= seen + 1;
  end
 end

 initial begin
  if (!$value$plusargs("vecfile=%s", vecfile)) vecfile="sim/fixtures/lane_vectors.hex";
  if (!$value$plusargs("goldfile=%s", goldfile)) goldfile="sim/fixtures/lane_gold.hex";
  if (!$value$plusargs("twofile=%s", twofile)) twofile="sim/fixtures/lane_muladd.hex";
  if (!$value$plusargs("outfile=%s", outfile)) outfile="logs/v024_lane_out.hex";
  $readmemh(vecfile, vec);
  $readmemh(goldfile, gold);
  $readmemh(twofile, two);
  seen = 0;
  repeat (10) @(posedge clk);
  rst_n = 1;
  repeat (5) @(posedge clk);
  for (i=0;i<64;i=i+1) begin
   @(posedge clk);
   in_valid <= 1;
   in_c48 <= {{16{vec[i*3][31]}}, vec[i*3]};
   in_scale <= vec[i*3+1];
   in_bias <= vec[i*3+2];
   while (!in_ready) @(posedge clk);
  end
  @(posedge clk);
  in_valid <= 0;
  repeat (40) @(posedge clk);
  fd=$fopen(outfile,"w");
  for (i=0;i<64;i=i+1) $fwrite(fd,"%08x\n",results[i]);
  $fclose(fd);
  n=0;
  for (i=0;i<64;i=i+1) if (results[i]!==gold[i]) n=n+1;
  $display("V024_LANE seen=%0d gold_mismatch=%0d muladd_diff_fixture=%0d",
    seen,n,(two[0]!==gold[0]) + (two[1]!==gold[1]) + (two[2]!==gold[2]));
  if (seen!=64 || n!=0) $display("V024_LANE_RESULT FAIL");
  else $display("V024_LANE_RESULT PASS");
  $finish;
 end
endmodule
