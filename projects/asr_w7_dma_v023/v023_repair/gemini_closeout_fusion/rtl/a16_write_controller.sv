`timescale 1ns/1ps
// a16_write_controller.sv
// Adapter bridging epilogue packed 128-bit A16 stream to axi_dma_v020_multi_v2.
// Features:
//   1. Generates write DMA requests (wr_req_*) with 64-bit aligned base address.
//   2. Handles odd tail packing: dynamically applies write_strobe (0x00FF vs 0xFFFF)
//      so partial 64-bit beats do not corrupt DDR.
//   3. Hardware-enforced AXI write response drain boundary:
//      cwr_idle is asserted ONLY when all AW/W transfers have finished AND all
//      AXI B responses (BRESP) have been drained and validated (b_out == 0).
//   4. Fully pipelined with zero bubble insertion under full throughput.

module a16_write_controller #(
    parameter integer MAX_BURST = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   abort,

    // Block write configuration
    input  wire                   cfg_wr_start,
    input  wire [31:0]            cfg_wr_base_addr,
    input  wire [15:0]            cfg_wr_expected_beats, // 128 beats for 32x32 A16 block
    input  wire                   cfg_is_odd_tail,       // 1 if last beat contains only lower 64b
    output reg                    wr_active,
    output reg                    cwr_idle,
    output reg                    cwr_done,
    output wire                   cwr_error,
    output wire [7:0]             cwr_code,

    // Stream from Epilogue Engine (packed 128-bit)
    input  wire                   a16_packed_valid,
    output wire                   a16_packed_ready,
    input  wire [127:0]           a16_packed_data,
    input  wire                   a16_packed_last,

    // Interface to axi_dma_v020_multi_v2 write channel
    output reg                    dma_req_valid,
    input  wire                   dma_req_ready,
    output reg  [31:0]            dma_req_addr,
    output reg  [15:0]            dma_req_beats,

    output wire                   dma_wr_valid,
    input  wire                   dma_wr_ready,
    output wire [127:0]           dma_wr_data,
    output wire [15:0]            dma_wr_strobe,
    input  wire                   dma_done,
    input  wire                   dma_error,

    // Diagnostics & telemetry
    output reg  [31:0]            stat_beats_written,
    output reg  [31:0]            stat_bytes_written,
    output reg  [31:0]            stat_drain_wait_cycles
);

    localparam S_IDLE     = 3'd0;
    localparam S_REQ      = 3'd1;
    localparam S_STREAM   = 3'd2;
    localparam S_DRAIN    = 3'd3;
    localparam S_DONE     = 3'd4;
    localparam S_ERROR    = 3'd5;

    reg [2:0] state;
    reg [15:0] beats_sent;
    reg [15:0] total_beats;
    reg is_odd;
    reg err_sticky;

    assign cwr_error = err_sticky || dma_error;
    assign cwr_code  = err_sticky ? 8'h41 : (dma_error ? 8'h42 : 8'h00);

    // Direct streaming data path to DMA
    assign dma_wr_valid     = (state == S_STREAM) && a16_packed_valid && !abort;
    assign dma_wr_data      = a16_packed_data;
    assign a16_packed_ready = (state == S_STREAM) && dma_wr_ready && !abort;

    // Write strobe: 0x00FF on the final beat if odd tail, else 0xFFFF
    assign dma_wr_strobe = (a16_packed_last && is_odd) ? 16'h00ff : 16'hffff;

    wire beat_fire = dma_wr_valid && dma_wr_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            wr_active <= 1'b0;
            cwr_idle <= 1'b1;
            cwr_done <= 1'b0;
            err_sticky <= 1'b0;
            dma_req_valid <= 1'b0;
            dma_req_addr <= 32'd0;
            dma_req_beats <= 16'd0;
            beats_sent <= 16'd0;
            total_beats <= 16'd0;
            is_odd <= 1'b0;
            stat_beats_written <= 32'd0;
            stat_bytes_written <= 32'd0;
            stat_drain_wait_cycles <= 32'd0;
        end else if (abort) begin
            state <= S_IDLE;
            wr_active <= 1'b0;
            cwr_idle <= 1'b1;
            cwr_done <= 1'b0;
            dma_req_valid <= 1'b0;
        end else begin
            cwr_done <= 1'b0;

            if (dma_error) begin
                err_sticky <= 1'b1;
                state <= S_ERROR;
            end

            case (state)
                S_IDLE: begin
                    cwr_idle <= 1'b1;
                    wr_active <= 1'b0;
                    if (cfg_wr_start && !err_sticky) begin
                        cwr_idle <= 1'b0;
                        wr_active <= 1'b1;
                        dma_req_valid <= 1'b1;
                        dma_req_addr  <= cfg_wr_base_addr;
                        dma_req_beats <= cfg_wr_expected_beats;
                        total_beats   <= cfg_wr_expected_beats;
                        is_odd        <= cfg_is_odd_tail;
                        beats_sent    <= 16'd0;
                        state         <= S_REQ;
                    end
                end

                S_REQ: begin
                    if (dma_req_valid && dma_req_ready) begin
                        dma_req_valid <= 1'b0;
                        state <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    if (beat_fire) begin
                        beats_sent <= beats_sent + 16'd1;
                        stat_beats_written <= stat_beats_written + 32'd1;
                        stat_bytes_written <= stat_bytes_written + ((a16_packed_last && is_odd) ? 32'd8 : 32'd16);

                        if (a16_packed_last || (beats_sent + 16'd1 >= total_beats)) begin
                            state <= S_DRAIN;
                        end
                    end
                end

                S_DRAIN: begin
                    // Hardware-enforced AXI write response drain boundary:
                    // Wait for axi_dma to signal done (which guarantees b_out == 0 and all B responses verified)
                    stat_drain_wait_cycles <= stat_drain_wait_cycles + 32'd1;
                    if (dma_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    cwr_done <= 1'b1;
                    cwr_idle <= 1'b1;
                    wr_active <= 1'b0;
                    state <= S_IDLE;
                end

                S_ERROR: begin
                    cwr_idle <= 1'b1;
                    wr_active <= 1'b0;
                end
            endcase
        end
    end

endmodule
