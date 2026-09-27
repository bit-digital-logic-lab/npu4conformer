// 中文说明：UART 8N1 接收器，输入先通过两级同步器避免异步直接进入状态机。
// 在各数据位中心采样；检查停止位，异常通过 framing_error 上报。
`timescale 1ns/1ps
// UART 8N1 receiver; asynchronous input crosses a two-register synchronizer.
module uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200
)(
    input wire clk, rst_n, rxd,
    output reg [7:0] data,
    output reg valid, framing_error
);
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer CW = $clog2(DIV + 1);
    localparam [1:0] IDLE=0, START=1, DATA=2, STOP=3;
    (* ASYNC_REG = "TRUE" *) reg rx_meta, rx_sync;
    reg [1:0] state;
    reg [CW-1:0] counter;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
        else begin rx_meta <= rxd; rx_sync <= rx_meta; end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            data <= 0; valid <= 0; framing_error <= 0;
            state <= IDLE; counter <= 0; bit_index <= 0; shift <= 0;
        end else begin
            valid <= 0; framing_error <= 0;
            case (state)
                IDLE: if (!rx_sync) begin counter <= DIV/2-1; state <= START; end
                START: if (counter != 0) counter <= counter-1'b1;
                    else if (!rx_sync) begin
                        counter <= DIV-1; bit_index <= 0; state <= DATA;
                    end else state <= IDLE;
                DATA: if (counter != 0) counter <= counter-1'b1;
                    else begin
                        shift[bit_index] <= rx_sync; counter <= DIV-1;
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index+1'b1;
                    end
                STOP: if (counter != 0) counter <= counter-1'b1;
                    else begin
                        if (rx_sync) begin data <= shift; valid <= 1; end
                        else framing_error <= 1;
                        state <= IDLE;
                    end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
