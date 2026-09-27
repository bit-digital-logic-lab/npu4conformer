// 中文说明：UART 8N1 发送器，依次发送起始位、低位优先八个数据位和停止位。
// busy 表示发送中，done 在一个完整字节结束时产生单拍脉冲。
`timescale 1ns/1ps
module uart_tx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200
)(
    input wire clk, rst_n, start,
    input wire [7:0] data,
    output reg txd, busy, done
);
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer CW = $clog2(DIV + 1);
    reg [CW-1:0] counter;
    reg [3:0] bit_index;
    reg [9:0] frame;
    always @(posedge clk) begin
        if (!rst_n) begin
            txd <= 1; busy <= 0; done <= 0;
            counter <= 0; bit_index <= 0; frame <= 10'h3ff;
        end else begin
            done <= 0;
            if (!busy) begin
                txd <= 1;
                if (start) begin
                    frame <= {1'b1, data, 1'b0}; txd <= 0;
                    counter <= DIV-1; bit_index <= 0; busy <= 1;
                end
            end else if (counter != 0) counter <= counter-1'b1;
            else if (bit_index == 9) begin
                txd <= 1; busy <= 0; done <= 1;
            end else begin
                bit_index <= bit_index+1'b1;
                txd <= frame[bit_index+1'b1]; counter <= DIV-1;
            end
        end
    end
endmodule
