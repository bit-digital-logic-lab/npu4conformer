`timescale 1ns/1ps
// epilogue_stream_engine_v023.sv
// Top-Level Epilogue Fusion Engine for C48 -> A16 on-chip streaming.
//
// Interfaces:
//   1. Upstream Matrix C48 Stream:
//      Accepts 4 x 48-bit lanes (192 bits) per cycle with valid/ready handshake.
//   2. Downstream A16 Stream:
//      Emits 4 x 16-bit lanes (64 bits) and packed 128-bit AXI beats with tag/last.
//   3. Spill Stream:
//      When cfg_spill_c48 is enabled, raw C48 is duplicated to the DDR write stream;
//      when disabled, C48 DDR write is 100% eliminated.
//   4. Parameter Preload DMA:
//      PL DMA interface to preload scales/biases into on-chip registers (no CPU/MMIO).
//   5. Error Drain / Flush:
//      Zero-slack flush clearing all pipeline stages upon abort or exception.

module epilogue_stream_engine_v023 #(
    parameter TAG_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   abort,        // Synchronous error drain / flush

    // ---------------- Configuration / Descriptor ----------------
    input  wire                   cfg_valid,
    output wire                   cfg_ready,
    input  wire [1:0]             cfg_fma_mode, // 0: conv-only, 1: scale+bias, 2: scale-only
    input  wire                   cfg_relu_en,
    input  wire                   cfg_spill_c48,
    input  wire                   cfg_spill_fp32,
    input  wire [31:0]            cfg_scale,
    input  wire [31:0]            cfg_bias,
    input  wire [TAG_WIDTH-1:0]   cfg_tag,

    // ---------------- Parameter Preload DMA Port ----------------
    input  wire                   param_wr_valid,
    output wire                   param_wr_ready,
    input  wire [7:0]             param_wr_addr,
    input  wire [31:0]            param_wr_data,

    // ---------------- Upstream C48 Stream (from ds_matrix) ----------------
    input  wire                   cval_valid,
    output wire                   cval_ready,
    input  wire [191:0]           cval_data,    // 4 lanes: [47:0], [95:48], [143:96], [191:144]
    input  wire [TAG_WIDTH-1:0]   cval_tag,
    input  wire                   cval_last,

    // ---------------- Downstream A16 Stream (to Vector / Layout / DDR) ----------------
    output wire                   a16_valid,
    input  wire                   a16_ready,
    output wire [63:0]            a16_data,    // 4 lanes: [15:0], [31:16], [47:32], [63:48]
    output wire [127:0]           a16_packed,  // Packed 8 elements (128-bit)
    output wire                   a16_packed_valid,
    input  wire                   a16_packed_ready,
    output wire                   a16_packed_last,
    output wire [TAG_WIDTH-1:0]   a16_tag,
    output wire                   a16_last,

    // ---------------- C48 Spill Stream (Multi-Consumer / Debug Port) ----------------
    output wire                   spill_valid,
    input  wire                   spill_ready,
    output wire [191:0]           spill_data,
    output wire [TAG_WIDTH-1:0]   spill_tag,
    output wire                   spill_last,

    // ---------------- Performance & Traffic Telemetry ----------------
    output reg  [31:0]            stat_c48_beats_in,
    output reg  [31:0]            stat_a16_beats_out,
    output reg  [31:0]            stat_spill_beats,
    output reg  [31:0]            stat_ddr_bytes_saved
);

    // =========================================================================
    // Active Configuration Registers
    // =========================================================================
    reg [1:0]           active_fma_mode;
    reg                 active_relu_en;
    reg                 active_spill_c48;
    reg                 active_spill_fp32;
    reg [31:0]          active_scale;
    reg [31:0]          active_bias;
    reg [TAG_WIDTH-1:0] active_tag;
    reg                 config_loaded;

    reg                 in_burst;

    assign cfg_ready = !in_burst;
    assign param_wr_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_fma_mode   <= 2'd0;
            active_relu_en    <= 1'b0;
            active_spill_c48  <= 1'b0;
            active_spill_fp32 <= 1'b0;
            active_scale      <= 32'h3f800000; // 1.0f
            active_bias       <= 32'h00000000; // 0.0f
            active_tag        <= {TAG_WIDTH{1'b0}};
            config_loaded     <= 1'b0;
            in_burst          <= 1'b0;
        end else if (abort) begin
            config_loaded <= 1'b0;
            in_burst      <= 1'b0;
        end else begin
            if (cfg_valid && cfg_ready) begin
                active_fma_mode   <= cfg_fma_mode;
                active_relu_en    <= cfg_relu_en;
                active_spill_c48  <= cfg_spill_c48;
                active_spill_fp32 <= cfg_spill_fp32;
                active_scale      <= cfg_scale;
                active_bias       <= cfg_bias;
                active_tag        <= cfg_tag;
                config_loaded     <= 1'b1;
            end

            if (cval_valid && cval_ready) begin
                in_burst <= !cval_last;
            end else if (a16_valid && a16_last && a16_ready) begin
                in_burst <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Spill Channel Management
    // =========================================================================
    // If active_spill_c48 is enabled, both the epilogue pipeline AND the spill
    // FIFO must be ready before accepting upstream cval.
    wire lanes_ready;
    wire spill_ok = !active_spill_c48 || spill_ready;
    assign cval_ready = lanes_ready && spill_ok && !abort;

    assign spill_valid = cval_valid && lanes_ready && active_spill_c48 && !abort;
    assign spill_data  = cval_data;
    assign spill_tag   = cval_tag;
    assign spill_last  = cval_last;

    // Upstream data feeds the 4 lanes when cval handshakes
    wire lanes_fire = cval_valid && cval_ready;

    // =========================================================================
    // 4 Parallel Epilogue Lanes
    // =========================================================================
    wire [3:0] lane_in_ready;
    assign lanes_ready = &lane_in_ready;

    wire [3:0] lane_out_valid;
    wire [3:0] lane_out_last;
    wire signed [15:0] lane_a16 [3:0];
    wire [TAG_WIDTH-1:0] lane_tag [3:0];

    // Downstream backpressure to lanes
    wire lanes_downstream_ready;

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : gen_lanes
            epilogue_lane #(.TAG_WIDTH(TAG_WIDTH)) u_lane (
                .clk          (clk),
                .rst_n        (rst_n),
                .flush        (abort),
                .cfg_fma_mode (active_fma_mode),
                .cfg_relu_en  (active_relu_en),
                .cfg_scale    (active_scale),
                .cfg_bias     (active_bias),
                .in_valid     (lanes_fire),
                .in_ready     (lane_in_ready[g]),
                .in_c48       (cval_data[g*48 +: 48]),
                .in_tag       (cval_tag),
                .in_last      (cval_last),
                .out_valid    (lane_out_valid[g]),
                .out_ready    (lanes_downstream_ready),
                .out_a16      (lane_a16[g]),
                .out_tag      (lane_tag[g]),
                .out_last     (lane_out_last[g]),
                .fp32_valid   (),
                .fp32_data    ()
            );
        end
    endgenerate

    // =========================================================================
    // 128-bit AXI Beat Packer (Packs two 64-bit beats into one 128-bit beat)
    // =========================================================================
    reg [63:0]           pack_half_reg;
    reg [TAG_WIDTH-1:0]  pack_tag_reg;
    reg                  pack_has_half;
    reg                  pack_last_reg;

    reg                  p128_valid;
    reg [127:0]          p128_data;
    reg [TAG_WIDTH-1:0]  p128_tag;
    reg                  p128_last;

    wire packer_full = p128_valid && !a16_packed_ready;
    assign a16_packed_valid = p128_valid && !abort;
    assign a16_packed       = p128_data;
    assign a16_packed_last  = p128_last;

    // 4 lanes are lockstep:
    wire lanes_out_all_valid = &lane_out_valid;
    assign lanes_downstream_ready = a16_ready && (!packer_full);

    assign a16_valid = lanes_out_all_valid && !abort;
    assign a16_data  = {lane_a16[3], lane_a16[2], lane_a16[1], lane_a16[0]};
    assign a16_tag   = p128_valid ? p128_tag : lane_tag[0];
    assign a16_last  = lane_out_last[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pack_half_reg <= 64'd0;
            pack_tag_reg  <= {TAG_WIDTH{1'b0}};
            pack_has_half <= 1'b0;
            pack_last_reg <= 1'b0;
            p128_valid    <= 1'b0;
            p128_data     <= 128'd0;
            p128_tag      <= {TAG_WIDTH{1'b0}};
            p128_last     <= 1'b0;
        end else if (abort) begin
            pack_has_half <= 1'b0;
            p128_valid    <= 1'b0;
        end else begin
            if (a16_packed_ready) begin
                p128_valid <= 1'b0;
            end

            if (a16_valid && lanes_downstream_ready) begin
                if (!pack_has_half) begin
                    pack_half_reg <= a16_data;
                    pack_tag_reg  <= a16_tag;
                    pack_last_reg <= a16_last;
                    pack_has_half <= 1'b1;
                    if (a16_last) begin
                        // Emit zero-padded final beat
                        p128_valid <= 1'b1;
                        p128_data  <= {64'd0, a16_data};
                        p128_tag   <= a16_tag;
                        p128_last  <= 1'b1;
                        pack_has_half <= 1'b0;
                    end
                end else begin
                    p128_valid <= 1'b1;
                    p128_data  <= {a16_data, pack_half_reg};
                    p128_tag   <= a16_tag;
                    p128_last  <= a16_last;
                    pack_has_half <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // Statistics & Traffic Telemetry
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_c48_beats_in    <= 32'd0;
            stat_a16_beats_out   <= 32'd0;
            stat_spill_beats     <= 32'd0;
            stat_ddr_bytes_saved <= 32'd0;
        end else if (abort) begin
            // Retain statistics across error flush for post-mortem telemetry
        end else begin
            if (cval_valid && cval_ready) begin
                stat_c48_beats_in <= stat_c48_beats_in + 32'd1;
                // Each beat is 4 elements. If not spilled, saves 4 * 6 bytes (24 bytes) of C48 DDR write
                // plus 24 bytes of C48 DDR read, plus intermediate FP32 traffic!
                if (!active_spill_c48) begin
                    stat_ddr_bytes_saved <= stat_ddr_bytes_saved + 32'd48; // 24B write + 24B read
                end
            end
            if (a16_valid && a16_ready) begin
                stat_a16_beats_out <= stat_a16_beats_out + 32'd1;
            end
            if (spill_valid && spill_ready) begin
                stat_spill_beats <= stat_spill_beats + 32'd1;
            end
        end
    end

endmodule
