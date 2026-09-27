`timescale 1ns/1ps
`default_nettype none
// Clause-22 master, 1 MHz MDC from 50 MHz. Read turnaround is always tristated.
module asr_mdio_master # (parameter integer HALF_CYCLES = 25) (
    input wire clk, input wire rst,
    input wire start, input wire read_op,
    input wire [4:0] phy_addr, input wire [4:0] reg_addr,
    input wire [15:0] write_data,
    output reg busy = 0, output reg done = 0,
    output reg [15:0] read_data = 0,
    output reg mdc = 0, inout wire mdio
);
    reg [63:0] frame;
    reg [5:0] bit_index;
    reg [$clog2(HALF_CYCLES+1)-1:0] divider;
    reg reading;
    reg [15:0] read_shift;
    (* ASYNC_REG = "TRUE" *) reg mdio_sync1 = 1, mdio_sync2 = 1;
    always @(posedge clk) begin
        mdio_sync1 <= mdio;
        mdio_sync2 <= mdio_sync1;
    end
    assign mdio = busy && (!reading || bit_index >= 18) ? frame[bit_index] : 1'bz;
    always @(posedge clk) begin
        done <= 0;
        if (rst) begin
            busy <= 0; mdc <= 0; divider <= 0; read_data <= 0;
            frame <= 0; bit_index <= 0; reading <= 0; read_shift <= 0;
        end else if (!busy) begin
            mdc <= 0;
            if (start) begin
                frame <= {32'hffffffff, 2'b01, (read_op ? 2'b10 : 2'b01),
                          phy_addr, reg_addr, 2'b10, write_data};
                bit_index <= 63; reading <= read_op; busy <= 1;
                divider <= HALF_CYCLES-1; read_shift <= 0;
            end
        end else if (divider != 0) begin
            divider <= divider-1'b1;
        end else begin
            divider <= HALF_CYCLES-1;
            mdc <= !mdc;
            if (!mdc) begin
                if (reading && bit_index < 16)
                    read_shift <= {read_shift[14:0], mdio_sync2};
            end else if (bit_index == 0) begin
                busy <= 0; done <= 1; read_data <= read_shift;
            end else begin
                bit_index <= bit_index-1'b1;
            end
        end
    end
endmodule

// KSZ9031RNX identified by ID 0022:162x before any register writes.
// Implements the manufacturer's FLP 16 ms workaround, DS00002117K section 7.3.
// No RGMII skew register is written: RX delay remains the PHY reset default.
module asr_ksz9031_init #(
    parameter integer RESET_CYCLES = 1000000,
    parameter integer SETTLE_CYCLES = 10000,
    parameter integer POLL_CYCLES = 2500000,
    parameter integer MDIO_HALF_CYCLES = 25
)(
    input wire clk, input wire rst,
    output reg phy_reset_n = 0,
    output wire mdc, inout wire mdio,
    output reg [31:0] phy_id = 0,
    output reg config_done = 0, output reg config_error = 0,
    output reg [15:0] basic_status = 0
);
    localparam ST_RESET=0, ST_SETTLE=1, ST_LAUNCH=2, ST_WAIT=3, ST_POLL=4, ST_ERROR=5;
    reg [2:0] state = ST_RESET;
    reg [31:0] delay_count = 0;
    reg [4:0] address = 3;
    reg [5:0] scan_count = 0;
    reg [3:0] step = 0;
    reg [15:0] id_high = 0;
    reg mdio_start = 0;
    reg transaction_read;
    reg [4:0] transaction_reg;
    reg [15:0] transaction_data;
    wire mdio_busy, mdio_done;
    wire [15:0] mdio_read_data;
    always @* begin
        transaction_read = 0; transaction_reg = 0; transaction_data = 0;
        case (step)
            0: begin transaction_read=1; transaction_reg=2; end
            1: begin transaction_read=1; transaction_reg=3; end
            2: begin transaction_reg=4; transaction_data=16'h0141; end // 100/10 full only
            3: begin transaction_reg=9; transaction_data=16'h0200; end // 1000 full only
            4: begin transaction_reg=13; transaction_data=16'h0000; end
            5: begin transaction_reg=14; transaction_data=16'h0004; end
            6: begin transaction_reg=13; transaction_data=16'h4000; end
            7: begin transaction_reg=14; transaction_data=16'h0006; end
            8: begin transaction_reg=13; transaction_data=16'h0000; end
            9: begin transaction_reg=14; transaction_data=16'h0003; end
            10: begin transaction_reg=13; transaction_data=16'h4000; end
            11: begin transaction_reg=14; transaction_data=16'h1a80; end
            12: begin transaction_reg=0; transaction_data=16'h1200; end // AN enable/restart
            default: begin transaction_read=1; transaction_reg=1; end
        endcase
    end
    asr_mdio_master #(.HALF_CYCLES(MDIO_HALF_CYCLES)) master (
        .clk(clk), .rst(rst), .start(mdio_start), .read_op(transaction_read),
        .phy_addr(address), .reg_addr(transaction_reg), .write_data(transaction_data),
        .busy(mdio_busy), .done(mdio_done), .read_data(mdio_read_data), .mdc(mdc), .mdio(mdio)
    );
    always @(posedge clk) begin
        mdio_start <= 0;
        if (rst) begin
            state <= ST_RESET; delay_count <= 0; phy_reset_n <= 0;
            address <= 3; scan_count <= 0; step <= 0; id_high <= 0;
            phy_id <= 0; config_done <= 0; config_error <= 0; basic_status <= 0;
        end else begin
            case (state)
                ST_RESET: if (delay_count == RESET_CYCLES-1) begin
                    phy_reset_n <= 1; delay_count <= 0; state <= ST_SETTLE;
                end else delay_count <= delay_count+1'b1;
                ST_SETTLE: if (delay_count == SETTLE_CYCLES-1) begin
                    delay_count <= 0; state <= ST_LAUNCH;
                end else delay_count <= delay_count+1'b1;
                ST_LAUNCH: if (!mdio_busy) begin mdio_start <= 1; state <= ST_WAIT; end
                ST_WAIT: if (mdio_done) begin
                    if (step == 0) begin
                        id_high <= mdio_read_data; step <= 1; state <= ST_LAUNCH;
                    end else if (step == 1) begin
                        phy_id <= {id_high, mdio_read_data};
                        if (id_high == 16'h0022 && (mdio_read_data & 16'hfff0) == 16'h1620) begin
                            step <= 2; state <= ST_LAUNCH;
                        end else if (scan_count == 31) begin
                            config_error <= 1; state <= ST_ERROR;
                        end else begin
                            address <= address+1'b1; scan_count <= scan_count+1'b1;
                            step <= 0; state <= ST_LAUNCH;
                        end
                    end else if (step == 12) begin
                        config_done <= 1; step <= 13; delay_count <= 0; state <= ST_POLL;
                    end else if (step == 13) begin
                        basic_status <= mdio_read_data; delay_count <= 0; state <= ST_POLL;
                    end else begin
                        step <= step+1'b1; state <= ST_LAUNCH;
                    end
                end
                ST_POLL: if (delay_count == POLL_CYCLES-1) begin
                    delay_count <= 0; state <= ST_LAUNCH;
                end else delay_count <= delay_count+1'b1;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
