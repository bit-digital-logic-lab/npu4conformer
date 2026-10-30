`timescale 1ns/1ps
// Bounded integer-index divider, not neural arithmetic. 16 registered steps.
module u16_divmod(input wire clk,rst_n,start,input wire [15:0] numerator,denominator,
 output wire ready,output reg done,error,output reg [15:0] quotient,remainder);
 reg busy;reg [4:0] step;reg [15:0] bits,divisor;reg [16:0] rem;
 wire [16:0] shifted={rem[15:0],bits[15]};wire subtract=shifted>={1'b0,divisor};
 wire [16:0] next_rem=subtract?shifted-{1'b0,divisor}:shifted;
 assign ready=!busy;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;step<=0;bits<=0;divisor<=0;rem<=0;done<=0;error<=0;quotient<=0;remainder<=0;end
  else begin
   done<=0;
   if(start&&!busy)begin
    bits<=numerator;divisor<=denominator;rem<=0;step<=0;error<=denominator==0;
    quotient<=0;remainder<=0;if(denominator==0)done<=1;else busy<=1;
   end else if(busy)begin
    bits<={bits[14:0],1'b0};rem<=next_rem;quotient<={quotient[14:0],subtract};step<=step+1;
    if(step==15)begin remainder<=next_rem[15:0];busy<=0;done<=1;end
   end
  end
 end
endmodule
