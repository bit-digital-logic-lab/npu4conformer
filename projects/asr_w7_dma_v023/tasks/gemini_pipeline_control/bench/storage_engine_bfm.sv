`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// storage_engine_bfm.sv
// Storage BFM emulating the memory subsystem for block_engine.
// Handles A, B, C block read requests, streams beats with valid parity,
// accepts evictions and flushes, and captures output blocks for verification.
// -----------------------------------------------------------------------------
module storage_engine_bfm #(
    parameter integer M = 32,
    parameter integer N = 32,
    parameter integer K = 32
) (
    input  wire        clk,
    input  wire        reset,

    // Storage request channel from block_engine
    input  wire        req_valid,
    output reg         req_ready,
    input  wire        req_write,
    input  wire [31:0] req_address,
    input  wire [31:0] req_epoch,
    input  wire [15:0] req_layer,
    input  wire [15:0] req_matrix,
    input  wire [15:0] req_block_row,
    input  wire [15:0] req_block_col,
    input  wire [15:0] req_allowed_ops,
    input  wire [15:0] req_completed_ops,
    input  wire [1:0]  req_encoding,
    input  wire        req_block_valid,
    input  wire        req_in_operation,

    // Header channel to block_engine
    output reg         header_valid,
    input  wire        header_ready,
    output reg         header_exists,
    output reg         header_block_valid,
    output reg         header_in_operation,
    output reg  [31:0] header_epoch,
    output reg  [15:0] header_layer,
    output reg  [15:0] header_matrix,
    output reg  [15:0] header_block_row,
    output reg  [15:0] header_block_col,
    output reg  [15:0] header_allowed_ops,
    output reg  [15:0] header_completed_ops,
    output reg  [1:0]  header_encoding,

    // Data in channel to block_engine
    output reg         data_valid,
    input  wire        data_ready,
    output reg  [191:0] data_in,
    output reg  [9:0]  data_index,
    output reg         data_last,

    // Data out channel from block_engine (eviction/flush)
    input  wire        out_valid,
    output reg         out_ready,
    input  wire [47:0] out_data,
    input  wire [9:0]  out_index,
    input  wire        out_last,
    output reg         write_ack,
    output reg         write_error,

    // Configuration / memory inspection
    input  wire        c_exists_mode // 0 = fresh C (zero init), 1 = existing C
);

    // BFM Internal matrices
    reg [15:0] a_mem [0:M-1][0:K-1];
    reg [6:0]  w_mem [0:K-1][0:N-1];

    // Captured C blocks from writeback / flush: up to 4 blocks of 1024 words
    reg signed [47:0] c_captured [0:3][0:1023];
    reg [3:0] c_block_count;

    // BFM State
    localparam [2:0]
        S_IDLE        = 3'd0,
        S_HEADER      = 3'd1,
        S_STREAM_DATA = 3'd2,
        S_RECV_WRITE  = 3'd3,
        S_WRITE_ACK   = 3'd4;

    reg [2:0]  bfm_state;
    reg [1:0]  cur_encoding;
    reg [15:0] cur_brow, cur_bcol;
    reg [10:0] beat_cnt;

    // Pseudo-random stalls (optional)
    reg [31:0] lfsr;
    function [31:0] next_rnd;
        begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            next_rnd = lfsr;
        end
    endfunction

    // Helper: compute beat payload for A
    function [191:0] get_a_beat(input [9:0] b, input [15:0] brow, input [15:0] bcol);
        reg [191:0] payload;
        integer lane, r_phys, k_phys;
        reg [15:0] a_val;
        begin
            payload = 192'd0;
            r_phys = {b[9], b[8:5]}; // 0 to 31
            for (lane = 0; lane < 4; lane = lane + 1) begin
                k_phys = bcol * 32 + {b[4:2], lane[1:0]};
                if (r_phys < M && k_phys < K)
                    a_val = a_mem[r_phys][k_phys];
                else
                    a_val = 16'd0;
                payload[lane*48 +: 16] = a_val;
            end
            get_a_beat = payload;
        end
    endfunction

    // Helper: compute beat payload for B with proper parity
    function [191:0] get_b_beat(input [9:0] b, input [15:0] brow, input [15:0] bcol);
        reg [191:0] payload;
        integer lane, c_phys, k_phys;
        reg [6:0] w_val;
        reg [7:0] byte_val;
        begin
            payload = 192'd0;
            k_phys = brow * 32 + b[9:5];
            for (lane = 0; lane < 4; lane = lane + 1) begin
                c_phys = bcol * 32 + {b[4], b[3:2], lane[1:0]};
                if (k_phys < K && c_phys < N)
                    w_val = w_mem[k_phys][c_phys];
                else
                    w_val = 7'd0;
                // Even parity: ^byte_val == 0
                byte_val = {^w_val, w_val};
                payload[lane*48 +: 8] = byte_val;
            end
            get_b_beat = payload;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            req_ready           <= 1'b1;
            header_valid        <= 1'b0;
            header_exists       <= 1'b0;
            header_block_valid  <= 1'b0;
            header_in_operation <= 1'b0;
            header_epoch        <= 32'd0;
            header_layer        <= 16'd0;
            header_matrix       <= 16'd0;
            header_block_row    <= 16'd0;
            header_block_col    <= 16'd0;
            header_allowed_ops  <= 16'd0;
            header_completed_ops<= 16'd0;
            header_encoding     <= 2'd0;
            data_valid          <= 1'b0;
            data_in             <= 192'd0;
            data_index          <= 10'd0;
            data_last           <= 1'b0;
            out_ready           <= 1'b1;
            write_ack           <= 1'b0;
            write_error         <= 1'b0;
            bfm_state           <= S_IDLE;
            beat_cnt            <= 11'd0;
            c_block_count       <= 4'd0;
            lfsr                <= 32'hACE1_1234;
        end else begin
            case (bfm_state)
                S_IDLE: begin
                    req_ready <= 1'b1;
                    write_ack <= 1'b0;
                    if (req_valid && req_ready) begin
                        req_ready <= 1'b0;
                        cur_encoding <= req_encoding;
                        cur_brow     <= req_block_row;
                        cur_bcol     <= req_block_col;

                        if (req_write) begin
                            // Eviction or flush writeback
                            bfm_state <= S_RECV_WRITE;
                            out_ready <= 1'b1;
                            beat_cnt  <= 11'd0;
                        end else begin
                            // Read request: send header
                            header_valid         <= 1'b1;
                            header_epoch         <= req_epoch;
                            header_layer         <= req_layer;
                            header_matrix        <= req_matrix;
                            header_block_row     <= req_block_row;
                            header_block_col     <= req_block_col;
                            header_allowed_ops   <= req_allowed_ops;
                            header_completed_ops <= 16'd0;
                            header_encoding      <= req_encoding;
                            header_in_operation  <= 1'b0;

                            if (req_encoding == 2'd2) begin
                                // C block: fresh or existing
                                header_exists      <= c_exists_mode;
                                header_block_valid <= c_exists_mode;
                            end else begin
                                // A or B block: always exists and valid
                                header_exists      <= 1'b1;
                                header_block_valid <= 1'b1;
                            end
                            bfm_state <= S_HEADER;
                        end
                    end
                end

                S_HEADER: begin
                    if (header_valid && header_ready) begin
                        header_valid <= 1'b0;
                        if (cur_encoding == 2'd2 && !header_exists) begin
                            // Fresh C: no data stream needed!
                            bfm_state <= S_IDLE;
                            req_ready <= 1'b1;
                        end else begin
                            // Stream 256 beats for A, B, or existing C
                            beat_cnt   <= 11'd0;
                            bfm_state  <= S_STREAM_DATA;
                            data_valid <= 1'b1;
                            data_index <= 10'd0;
                            data_last  <= 1'b0;
                            if (cur_encoding == 2'd0)
                                data_in <= get_a_beat(10'd0, cur_brow, cur_bcol);
                            else if (cur_encoding == 2'd1)
                                data_in <= get_b_beat(10'd0, cur_brow, cur_bcol);
                            else
                                data_in <= 192'd0;
                        end
                    end
                end

                S_STREAM_DATA: begin
                    if (data_valid && data_ready) begin
                        if (beat_cnt == 1020) begin
                            data_valid <= 1'b0;
                            data_last  <= 1'b0;
                            bfm_state  <= S_IDLE;
                            req_ready  <= 1'b1;
                        end else begin
                            beat_cnt   <= beat_cnt + 11'd4;
                            data_valid <= 1'b1;
                            data_index <= beat_cnt + 10'd4;
                            data_last  <= (beat_cnt + 11'd4 == 1020);
                            if (cur_encoding == 2'd0)
                                data_in <= get_a_beat(beat_cnt + 10'd4, cur_brow, cur_bcol);
                            else if (cur_encoding == 2'd1)
                                data_in <= get_b_beat(beat_cnt + 10'd4, cur_brow, cur_bcol);
                            else
                                data_in <= 192'd0;
                        end
                    end
                end

                S_RECV_WRITE: begin
                    if (out_valid && out_ready) begin
                        c_captured[c_block_count][out_index] <= $signed(out_data);
                        if (out_last || beat_cnt == 1023) begin
                            out_ready     <= 1'b0;
                            write_ack     <= 1'b1;
                            write_error   <= 1'b0;
                            c_block_count <= c_block_count + 4'd1;
                            bfm_state     <= S_WRITE_ACK;
                        end else begin
                            beat_cnt <= beat_cnt + 11'd1;
                        end
                    end
                end

                S_WRITE_ACK: begin
                    write_ack <= 1'b0;
                    req_ready <= 1'b1;
                    bfm_state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
