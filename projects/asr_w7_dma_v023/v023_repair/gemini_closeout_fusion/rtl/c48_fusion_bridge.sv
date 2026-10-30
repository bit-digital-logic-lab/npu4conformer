`timescale 1ns/1ps
// c48_fusion_bridge.sv
// Streaming fusion bridge connecting matrix C48 collector to epilogue_stream_engine.
// Features:
//   1. Elastic FIFO buffer with credit tracking to absorb pipeline / BRAM skid.
//   2. Native backpressure (cval_ready) propagation to matrix engine.
//   3. Configurable burst framing & last generation (supports full block 256 beats,
//      segment 4 beats, and arbitrary odd tail lengths).
//   4. Tag routing and handshake telemetry.
//   5. Mathematical FIFO capacity guarantee: with DEPTH=16 and SKID_MARGIN=2,
//      overflow is strictly impossible even under arbitrary backpressure.

module c48_fusion_bridge #(
    parameter integer DATA_WIDTH  = 192,
    parameter integer TAG_WIDTH   = 16,
    parameter integer FIFO_DEPTH  = 16,
    parameter integer SKID_MARGIN = 2
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   abort,

    // ---------------- Matrix Collector Interface ----------------
    input  wire                   cval_valid,
    output wire                   cval_ready,
    input  wire [DATA_WIDTH-1:0]  cval_data,
    input  wire [TAG_WIDTH-1:0]   cval_tag,
    input  wire                   cval_last,

    // Matrix segment command sync (instant ack for on-chip streaming)
    input  wire                   cseg_valid,
    output wire                   cseg_ready,

    // Optional framing override (0: use cval_last; 1: count-based last for odd-tail tests)
    input  wire                   cfg_framing_mode,
    input  wire [15:0]            cfg_burst_len,

    // ---------------- Epilogue Fusion Engine Interface ----------------
    output wire                   stream_valid,
    input  wire                   stream_ready,
    output wire [DATA_WIDTH-1:0]  stream_data,
    output wire [TAG_WIDTH-1:0]   stream_tag,
    output wire                   stream_last,

    // ---------------- Telemetry & Diagnostics ----------------
    output reg  [31:0]            stat_in_beats,
    output reg  [31:0]            stat_out_beats,
    output reg  [31:0]            stat_stall_cycles,
    output wire [7:0]             stat_fifo_occupancy,
    output reg  [7:0]             stat_fifo_max_occupancy,
    output wire                   stat_fifo_overflow,
    output wire                   stat_fifo_underflow
);

    // CSEG instant handshake: matrix engine segment commands are acknowledged immediately
    assign cseg_ready = 1'b1;

    // Synchronous circular FIFO implementation
    localparam integer AW = $clog2(FIFO_DEPTH);

    reg [DATA_WIDTH-1:0] fifo_data [0:FIFO_DEPTH-1];
    reg [TAG_WIDTH-1:0]  fifo_tag  [0:FIFO_DEPTH-1];
    reg                  fifo_last [0:FIFO_DEPTH-1];

    reg [AW:0] wr_ptr;
    reg [AW:0] rd_ptr;
    wire [AW:0] fifo_count = wr_ptr - rd_ptr;

    assign stat_fifo_occupancy = fifo_count;

    // Credit-based ready: grant cval_ready only if credit > SKID_MARGIN
    wire has_space = (fifo_count <= (FIFO_DEPTH - SKID_MARGIN));
    assign cval_ready = has_space && !abort;

    wire in_fire = cval_valid && cval_ready;
    wire out_fire = stream_valid && stream_ready;

    // Dynamic framing counter for odd tail / arbitrary length verification
    reg [15:0] beat_counter;
    wire eff_last = cfg_framing_mode ? (beat_counter + 16'd1 >= cfg_burst_len) : cval_last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            beat_counter <= 0;
            stat_in_beats <= 0;
            stat_fifo_max_occupancy <= 0;
        end else if (abort) begin
            wr_ptr <= 0;
            beat_counter <= 0;
        end else begin
            if (fifo_count > stat_fifo_max_occupancy) begin
                stat_fifo_max_occupancy <= fifo_count;
            end

            if (in_fire) begin
                fifo_data[wr_ptr[AW-1:0]] <= cval_data;
                fifo_tag[wr_ptr[AW-1:0]]  <= cval_tag;
                fifo_last[wr_ptr[AW-1:0]] <= eff_last;
                wr_ptr <= wr_ptr + 1'b1;
                stat_in_beats <= stat_in_beats + 32'd1;

                if (eff_last) begin
                    beat_counter <= 0;
                end else begin
                    beat_counter <= beat_counter + 16'd1;
                end
            end
        end
    end

    // FIFO Read Side
    wire fifo_empty = (wr_ptr == rd_ptr);
    assign stream_valid = !fifo_empty && !abort;
    assign stream_data  = fifo_data[rd_ptr[AW-1:0]];
    assign stream_tag   = fifo_tag[rd_ptr[AW-1:0]];
    assign stream_last  = fifo_last[rd_ptr[AW-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            stat_out_beats <= 0;
            stat_stall_cycles <= 0;
        end else if (abort) begin
            rd_ptr <= 0;
        end else begin
            if (out_fire) begin
                rd_ptr <= rd_ptr + 1'b1;
                stat_out_beats <= stat_out_beats + 32'd1;
            end

            if (stream_valid && !stream_ready) begin
                stat_stall_cycles <= stat_stall_cycles + 32'd1;
            end
        end
    end

    // Safety checks
    assign stat_fifo_overflow  = (fifo_count > FIFO_DEPTH);
    assign stat_fifo_underflow = (fifo_empty && stream_ready && !stream_valid);

endmodule
