`timescale 1ns/1ps
module asr_uart_top #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(input wire clk, input wire rst_n, input wire uart_rx, output wire uart_tx);
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) reset_sync<=0;
        else reset_sync<={reset_sync[0],1'b1};
    end
    wire reset_n=reset_sync[1];
    wire rx_valid,rx_error,tx_valid,tx_ready;
    wire [7:0] rx_data,tx_data;
    asr_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) receiver(
        .clk(clk),.rst_n(reset_n),.rx(uart_rx),.valid(rx_valid),
        .data(rx_data),.framing_error(rx_error));
    asr_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) transmitter(
        .clk(clk),.rst_n(reset_n),.valid(tx_valid),.ready(tx_ready),
        .data(tx_data),.tx(uart_tx));
    asr_command_engine #(.RX_TIMEOUT_CYCLES(CLK_HZ)) engine(
        .clk(clk),.rst_n(reset_n),.rx_valid(rx_valid),.rx_data(rx_data),
        .rx_error(rx_error),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .tx_data(tx_data),.busy());
endmodule
