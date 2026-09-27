`timescale 1ns/1ps
module asr_uart_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
)(input wire clk, input wire rst_n, input wire rx,
  output reg valid, output reg [7:0] data, output reg framing_error);
    localparam integer DIVISOR = (CLK_HZ + BAUD/2) / BAUD;
    localparam [1:0] IDLE=0, START=1, DATA=2, STOP=3;
    (* ASYNC_REG = "TRUE" *) reg sync1, sync2;
    reg [1:0] state;
    reg [31:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk) begin
        if (!rst_n) begin sync1<=1; sync2<=1; end
        else begin sync1<=rx; sync2<=sync1; end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; count<=0; bit_index<=0; shift<=0;
            valid<=0; data<=0; framing_error<=0;
        end else begin
            valid<=0; framing_error<=0;
            case (state)
                IDLE: if (!sync2) begin state<=START; count<=DIVISOR/2-1; end
                START: if (count!=0) count<=count-1;
                       else if (sync2) state<=IDLE;
                       else begin state<=DATA; count<=DIVISOR-1; bit_index<=0; end
                DATA: if (count!=0) count<=count-1;
                      else begin
                          shift[bit_index]<=sync2; count<=DIVISOR-1;
                          if (bit_index==7) state<=STOP;
                          else bit_index<=bit_index+1;
                      end
                STOP: if (count!=0) count<=count-1;
                      else begin
                          state<=IDLE;
                          if (sync2) begin data<=shift; valid<=1; end
                          else framing_error<=1;
                      end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
