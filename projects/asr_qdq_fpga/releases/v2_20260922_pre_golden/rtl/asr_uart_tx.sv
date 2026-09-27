`timescale 1ns/1ps
module asr_uart_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
)(input wire clk, input wire rst_n, input wire valid, output wire ready,
  input wire [7:0] data, output wire tx);
    localparam integer DIVISOR = (CLK_HZ + BAUD/2) / BAUD;
    reg busy;
    reg [9:0] shift;
    reg [3:0] bit_index;
    reg [31:0] count;
    assign ready=!busy;
    assign tx=busy ? shift[0] : 1'b1;
    always @(posedge clk) begin
        if (!rst_n) begin busy<=0; shift<=10'h3ff; bit_index<=0; count<=0; end
        else if (!busy) begin
            if (valid) begin
                busy<=1; shift<={1'b1,data,1'b0}; bit_index<=0; count<=DIVISOR-1;
            end
        end else if (count!=0) count<=count-1;
        else if (bit_index==9) busy<=0;
        else begin shift<={1'b1,shift[9:1]}; bit_index<=bit_index+1; count<=DIVISOR-1; end
    end
endmodule
