`timescale 1ns/1ps
// c_cache_readout_bridge.sv
// Credit-gated C-Cache readout bridge for matrix engines lacking streaming ready.
// Features:
//   1. Tracks downstream credit (free FIFO capacity) before issuing BRAM reads.
//   2. Honors synchronous 1-cycle BRAM latency (rd_valid @ T -> rd_data @ T+1).
//   3. Stalls address generation immediately when credit is exhausted.
//   4. Guarantees 0-loss and 0-overflow during arbitrary backpressure stalls.
//   5. Emits framed C48 4-lane beats with tag and last flags to epilogue stream.

module c_cache_readout_bridge #(
    parameter integer DATA_WIDTH = 192,
    parameter integer TAG_WIDTH  = 16,
    parameter integer FIFO_DEPTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   abort,

    // Command trigger: start readout of a block from C-cache
    input  wire                   readout_start,
    input  wire [8:0]             cfg_start_group,
    input  wire [8:0]             cfg_num_groups,   // typically 64 for 1 quadrant, 256 for 32x32 block
    input  wire [TAG_WIDTH-1:0]   cfg_base_tag,
    output reg                    readout_busy,
    output reg                    readout_done,

    // Interface to c_cache_banked4_pipe read port (synchronous 1-cycle latency)
    output wire                   cache_rd_valid,
    input  wire                   cache_rd_ready,
    output wire [8:0]             cache_rd_group,
    input  wire [DATA_WIDTH-1:0]  cache_rd_data,

    // Streaming output towards Epilogue Stream Engine (or bridge FIFO)
    output wire                   out_valid,
    input  wire                   out_ready,
    output wire [DATA_WIDTH-1:0]  out_data,
    output wire [TAG_WIDTH-1:0]   out_tag,
    output wire                   out_last,

    // Telemetry & diagnostics
    output reg  [31:0]            stat_read_requests,
    output reg  [31:0]            stat_read_beats,
    output reg  [31:0]            stat_credit_stall_cycles
);

    // Skid FIFO between BRAM read port and downstream consumer
    localparam integer AW = $clog2(FIFO_DEPTH);
    reg [DATA_WIDTH-1:0] fifo_data [0:FIFO_DEPTH-1];
    reg [TAG_WIDTH-1:0]  fifo_tag  [0:FIFO_DEPTH-1];
    reg                  fifo_last [0:FIFO_DEPTH-1];

    reg [AW:0] wr_ptr;
    reg [AW:0] rd_ptr;
    wire [AW:0] fifo_count = wr_ptr - rd_ptr;

    // In-flight read tracking (BRAM read has 1 cycle latency)
    reg in_flight;
    reg [TAG_WIDTH-1:0] in_flight_tag;
    reg                 in_flight_last;

    // Available credit = free space in FIFO minus in-flight read
    wire [AW:0] total_allocated = fifo_count + (in_flight ? 1'b1 : 1'b0);
    wire has_credit = (total_allocated < (FIFO_DEPTH - 1));

    // Group address counter
    reg [8:0] cur_group;
    reg [8:0] remaining_groups;

    wire can_issue_read = readout_busy && (remaining_groups > 0) && has_credit && cache_rd_ready && !abort;
    assign cache_rd_valid = can_issue_read;
    assign cache_rd_group = cur_group;

    // Address generation & issue tracking
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            readout_busy <= 1'b0;
            readout_done <= 1'b0;
            cur_group <= 9'd0;
            remaining_groups <= 9'd0;
            in_flight <= 1'b0;
            in_flight_tag <= {TAG_WIDTH{1'b0}};
            in_flight_last <= 1'b0;
            stat_read_requests <= 32'd0;
            stat_credit_stall_cycles <= 32'd0;
        end else if (abort) begin
            readout_busy <= 1'b0;
            readout_done <= 1'b0;
            remaining_groups <= 9'd0;
            in_flight <= 1'b0;
        end else begin
            readout_done <= 1'b0;

            if (readout_start && !readout_busy) begin
                readout_busy <= 1'b1;
                cur_group <= cfg_start_group;
                remaining_groups <= cfg_num_groups;
            end else if (readout_busy) begin
                if (can_issue_read) begin
                    cur_group <= cur_group + 9'd1;
                    remaining_groups <= remaining_groups - 9'd1;
                    in_flight <= 1'b1;
                    in_flight_tag <= cfg_base_tag + (cfg_num_groups - remaining_groups);
                    in_flight_last <= (remaining_groups == 9'd1);
                    stat_read_requests <= stat_read_requests + 32'd1;
                end else begin
                    in_flight <= 1'b0;
                    if (readout_busy && (remaining_groups > 0) && !has_credit) begin
                        stat_credit_stall_cycles <= stat_credit_stall_cycles + 32'd1;
                    end
                end

                // Completion check: all requested groups issued, drained through BRAM and FIFO
                if ((remaining_groups == 0) && !in_flight && (wr_ptr == rd_ptr)) begin
                    readout_busy <= 1'b0;
                    readout_done <= 1'b1;
                end
            end else begin
                in_flight <= 1'b0;
            end
        end
    end

    // Capturing synchronous BRAM read data into FIFO (Cycle T+1)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            stat_read_beats <= 0;
        end else if (abort) begin
            wr_ptr <= 0;
        end else begin
            if (in_flight) begin
                fifo_data[wr_ptr[AW-1:0]] <= cache_rd_data;
                fifo_tag[wr_ptr[AW-1:0]]  <= in_flight_tag;
                fifo_last[wr_ptr[AW-1:0]] <= in_flight_last;
                wr_ptr <= wr_ptr + 1'b1;
                stat_read_beats <= stat_read_beats + 32'd1;
            end
        end
    end

    // FIFO Readout towards Stream Engine
    wire fifo_empty = (wr_ptr == rd_ptr);
    assign out_valid = !fifo_empty && !abort;
    assign out_data  = fifo_data[rd_ptr[AW-1:0]];
    assign out_tag   = fifo_tag[rd_ptr[AW-1:0]];
    assign out_last  = fifo_last[rd_ptr[AW-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (abort) begin
            rd_ptr <= 0;
        end else begin
            if (out_valid && out_ready) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
