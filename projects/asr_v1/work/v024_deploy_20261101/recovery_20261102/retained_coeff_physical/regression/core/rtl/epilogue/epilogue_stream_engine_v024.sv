`timescale 1ns/1ps
// epilogue_stream_engine_v023.sv
// Top-Level Epilogue Fusion Engine for C48 -> A16 on-chip streaming.
//
// Repaired in gemini_stream_round2 for STREAM-1..4:
//   1. STREAM-1: A16 tag preserved cleanly without 128-bit packer pollution.
//      Both A16 and packed streams present correct tags to downstream consumers.
//   2. STREAM-2: Mutual exclusion / clean gating between A16 and packed beats;
//      eliminates repeated handshakes under packed backpressure (BP=2).
//   3. STREAM-3: Two-word broadcast parameter preload with idle-only writes,
//      supporting preloaded scale/bias prior to descriptor / burst processing.
//   4. STREAM-4: Reconfiguration drain safety: cfg_ready is held low while
//      any in-flight beats remain in the pipeline or packer, preventing scale/bias
//      corruption on in-flight beats.

module epilogue_stream_engine_v024 #(
    parameter TAG_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   param_rst_n, // Only true core reset; retain host coefficients across data-mode reset
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
    input  wire                   cfg_perchannel_en,

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
    output wire [TAG_WIDTH-1:0]    a16_packed_tag, // Packed beat carries the first half tag.
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
    // Parameter Preload DMA Memory & Real Semantics (STREAM-3)
    // =========================================================================
    // V0.24 parameter map (preload only while drained):
    //   addr  0..31 : per-channel scale for column 0..31
    //   addr 32..63 : per-channel bias  for column 0..31
    //   addr 64     : broadcast scale (legacy fallback)
    //   addr 65     : broadcast bias  (legacy fallback)
    // Per-channel mode never re-reads DDR per tile; the host preloads this
    // 256 B table once before START.  The legacy broadcast pair is unchanged
    // when cfg_perchannel_en=0.
    wire engine_idle;
    reg [31:0] preload_scale, preload_bias;
    reg scale_valid, bias_valid;
    reg [31:0] scale_tbl [0:31];
    reg [31:0] bias_tbl  [0:31];
    integer ti;
    assign param_wr_ready = param_rst_n && rst_n && engine_idle && !cfg_valid && (param_wr_addr < 8'd66);
    always @(posedge clk or negedge param_rst_n) begin
        if (!param_rst_n) begin
            scale_valid <= 1'b0;
            bias_valid <= 1'b0;
            preload_scale <= 32'h3f800000;
            preload_bias <= 32'd0;
            for (ti=0; ti<32; ti=ti+1) begin
                scale_tbl[ti] <= 32'h3f800000;
                bias_tbl[ti]  <= 32'd0;
            end
        end else if (abort) begin
            // Sticky table: keep it across an error flush, like the broadcast pair.
        end else if (param_wr_valid && param_wr_ready) begin
            if (param_wr_addr < 8'd32) scale_tbl[param_wr_addr[4:0]] <= param_wr_data;
            else if (param_wr_addr < 8'd64) bias_tbl[param_wr_addr[4:0]] <= param_wr_data;
            else if (param_wr_addr == 8'd64) begin
                preload_scale <= param_wr_data; scale_valid <= 1'b1;
            end else begin
                preload_bias <= param_wr_data; bias_valid <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Active Configuration Registers & Reconfiguration Protection (STREAM-4)
    // =========================================================================
    reg [1:0]           active_fma_mode;
    reg                 active_relu_en;
    reg                 active_spill_c48;
    reg                 active_spill_fp32;
    reg [31:0]          active_scale;
    reg [31:0]          active_bias;
    reg [TAG_WIDTH-1:0] active_tag;
    reg                 config_loaded;

    reg [15:0]          in_flight_beats;
    reg                 in_burst;

    reg                 active_perchannel_en;
    wire [31:0] eff_scale = scale_valid ? preload_scale : active_scale;
    wire [31:0] eff_bias  = bias_valid ? preload_bias : active_bias;

    // C48 stream is quadrant-major (see fusion_c48_framer): a segment is one
    // 16-column row of one 16x16 quadrant.  beat[7:2]=segment, beat[1:0]=pair.
    // Column of lane 0 = 16*quadrant_col_half + 4*pair_in_segment.
    reg [7:0] beat_cnt;
    wire [1:0] beat_in_seg = beat_cnt[1:0];
    wire [4:0] lane_col0 = {beat_cnt[6], beat_in_seg, 2'b00};
    wire [31:0] lane_scale0 = active_perchannel_en ? scale_tbl[lane_col0]      : eff_scale;
    wire [31:0] lane_scale1 = active_perchannel_en ? scale_tbl[lane_col0+1'b1] : eff_scale;
    wire [31:0] lane_scale2 = active_perchannel_en ? scale_tbl[lane_col0+2'd2] : eff_scale;
    wire [31:0] lane_scale3 = active_perchannel_en ? scale_tbl[lane_col0+2'd3] : eff_scale;
    wire [31:0] lane_bias0  = active_perchannel_en ? bias_tbl[lane_col0]       : eff_bias;
    wire [31:0] lane_bias1  = active_perchannel_en ? bias_tbl[lane_col0+1'b1]  : eff_bias;
    wire [31:0] lane_bias2  = active_perchannel_en ? bias_tbl[lane_col0+2'd2]  : eff_bias;
    wire [31:0] lane_bias3  = active_perchannel_en ? bias_tbl[lane_col0+2'd3]  : eff_bias;

    // Upstream & downstream handshake events
    wire lanes_ready;
    wire spill_ok = !active_spill_c48 || spill_ready;
    wire cval_fire = cval_valid && cval_ready;
    // Control updates win over new data; a burst cannot start with stale config.
    wire input_enabled = config_loaded && !abort && !(cfg_valid && cfg_ready) &&
                         !(param_wr_valid && param_wr_ready);
    assign cval_ready = lanes_ready && spill_ok && input_enabled;

    wire a16_fire = a16_valid && a16_ready;

    // 128-bit Packer state declarations needed for drainage check
    reg                  pack_has_half;
    reg                  p128_valid;

    // Engine is drained when no beats are in pipeline, packer, or active input burst:
    assign engine_idle = (in_flight_beats == 16'd0) && !pack_has_half && !p128_valid && !in_burst && !abort;
    assign cfg_ready = engine_idle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_fma_mode   <= 2'd0;
            active_relu_en    <= 1'b0;
            active_spill_c48  <= 1'b0;
            active_spill_fp32 <= 1'b0;
            active_scale      <= 32'h3f800000; // 1.0f
            active_bias       <= 32'h00000000; // 0.0f
            active_tag        <= {TAG_WIDTH{1'b0}};
            active_perchannel_en <= 1'b0;
            config_loaded     <= 1'b0;
            in_flight_beats   <= 16'd0;
            in_burst          <= 1'b0;
            beat_cnt          <= 8'd0;
        end else if (abort) begin
            config_loaded   <= 1'b0;
            in_flight_beats <= 16'd0;
            in_burst        <= 1'b0;
            beat_cnt        <= 8'd0;
        end else begin
            if (cfg_valid && cfg_ready) begin
                active_fma_mode   <= cfg_fma_mode;
                active_relu_en    <= cfg_relu_en;
                active_spill_c48  <= cfg_spill_c48;
                active_spill_fp32 <= cfg_spill_fp32;
                active_scale      <= cfg_scale;
                active_bias       <= cfg_bias;
                active_tag        <= cfg_tag;
                active_perchannel_en <= cfg_perchannel_en;
                config_loaded     <= 1'b1;
                beat_cnt          <= 8'd0;
            end

            case ({cval_fire, a16_fire})
                2'b10: in_flight_beats <= in_flight_beats + 16'd1;
                2'b01: in_flight_beats <= in_flight_beats - 16'd1;
                default: in_flight_beats <= in_flight_beats;
            endcase

            if (cval_fire) begin
                in_burst <= !cval_last;
                if (cval_last) beat_cnt <= 8'd0;
                else beat_cnt <= beat_cnt + 8'd1;
            end
        end
    end

    // =========================================================================
    // Spill Channel Management
    // =========================================================================
    assign spill_valid = cval_valid && lanes_ready && active_spill_c48 && input_enabled;
    assign spill_data  = cval_data;
    assign spill_tag   = cval_tag;
    assign spill_last  = cval_last;

    wire lanes_fire = cval_fire;

    // =========================================================================
    // 4 Parallel Epilogue Lanes
    // =========================================================================
    wire [3:0] lane_in_ready;
    assign lanes_ready = &lane_in_ready;

    wire [3:0] lane_out_valid;
    wire [3:0] lane_out_last;
    wire signed [15:0] lane_a16 [3:0];
    wire [TAG_WIDTH-1:0] lane_tag [3:0];

    wire lanes_downstream_ready;

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : gen_lanes
            epilogue_lane_v024 #(.TAG_WIDTH(TAG_WIDTH)) u_lane (
                .clk          (clk),
                .rst_n        (rst_n),
                .flush        (abort),
                .cfg_fma_mode (active_fma_mode),
                .cfg_relu_en  (active_relu_en),
                .in_scale     (g==0 ? lane_scale0 : g==1 ? lane_scale1 : g==2 ? lane_scale2 : lane_scale3),
                .in_bias      (g==0 ? lane_bias0  : g==1 ? lane_bias1  : g==2 ? lane_bias2  : lane_bias3),
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
    // Downstream A16 & 128-bit AXI Beat Packer (STREAM-1, STREAM-2)
    // =========================================================================
    reg [63:0]           pack_half_reg;
    reg [TAG_WIDTH-1:0]  pack_tag_reg;
    reg                  pack_last_reg;

    reg [127:0]          p128_data;
    reg [TAG_WIDTH-1:0]  p128_tag;
    reg                  p128_last;

    wire lanes_out_all_valid = &lane_out_valid;
    wire [63:0] cur_a16_data = {lane_a16[3], lane_a16[2], lane_a16[1], lane_a16[0]};
    wire [TAG_WIDTH-1:0] cur_a16_tag = lane_tag[0];
    wire cur_a16_last = lane_out_last[0];

    // Elastic fork: each lane beat is copied once into the A16 register and
    // the packer. Either consumer can stall without repeating a handshake.
    reg a16_pending;
    reg [63:0] a16_reg;
    reg [TAG_WIDTH-1:0] a16_tag_reg;
    reg a16_last_reg;
    wire packer_available = !p128_valid || a16_packed_ready;
    wire fork_fire = lanes_out_all_valid && lanes_downstream_ready;
    assign a16_valid = a16_pending && !abort;
    assign a16_data = a16_reg;
    assign a16_tag = a16_tag_reg;
    assign a16_last = a16_last_reg;
    assign a16_packed_tag = p128_tag;
    assign lanes_downstream_ready = (!a16_pending || a16_ready) && packer_available && !abort;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a16_pending <= 1'b0;
            a16_reg <= 64'd0;
            a16_tag_reg <= {TAG_WIDTH{1'b0}};
            a16_last_reg <= 1'b0;
        end else if (abort) begin
            a16_pending <= 1'b0;
        end else if (!a16_pending || a16_ready) begin
            a16_pending <= fork_fire;
            if (fork_fire) begin
                a16_reg <= cur_a16_data;
                a16_tag_reg <= cur_a16_tag;
                a16_last_reg <= cur_a16_last;
            end
        end
    end

    assign a16_packed_valid = p128_valid && !abort;
    assign a16_packed       = p128_data;
    assign a16_packed_last  = p128_last;

    wire packed_fire = a16_packed_valid && a16_packed_ready;

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
            pack_half_reg <= 64'd0;
            pack_tag_reg  <= {TAG_WIDTH{1'b0}};
            pack_has_half <= 1'b0;
            pack_last_reg <= 1'b0;
            p128_valid    <= 1'b0;
            p128_data     <= 128'd0;
            p128_tag      <= {TAG_WIDTH{1'b0}};
            p128_last     <= 1'b0;
        end else begin
            if (packed_fire) begin
                p128_valid <= 1'b0;
            end

            if (fork_fire) begin
                if (!pack_has_half) begin
                    if (cur_a16_last) begin
                        // Odd/single beat termination: emit zero-padded packed beat
                        p128_valid    <= 1'b1;
                        p128_data     <= {64'd0, cur_a16_data};
                        p128_tag      <= cur_a16_tag;
                        p128_last     <= 1'b1;
                        pack_has_half <= 1'b0;
                    end else begin
                        pack_half_reg <= cur_a16_data;
                        pack_tag_reg  <= cur_a16_tag;
                        pack_last_reg <= cur_a16_last;
                        pack_has_half <= 1'b1;
                    end
                end else begin
                    p128_valid    <= 1'b1;
                    p128_data     <= {cur_a16_data, pack_half_reg};
                    p128_tag      <= pack_tag_reg;
                    p128_last     <= cur_a16_last;
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
            if (cval_fire) begin
                stat_c48_beats_in <= stat_c48_beats_in + 32'd1;
                // Each beat is 4 elements. If not spilled, saves 4 * 6 bytes (24 bytes) of C48 DDR write
                // plus 24 bytes of C48 DDR read, plus intermediate FP32 traffic!
                if (!active_spill_c48) begin
                    stat_ddr_bytes_saved <= stat_ddr_bytes_saved + 32'd48; // 24B write + 24B read
                end
            end
            if (a16_fire) begin
                stat_a16_beats_out <= stat_a16_beats_out + 32'd1;
            end
            if (spill_valid && spill_ready) begin
                stat_spill_beats <= stat_spill_beats + 32'd1;
            end
        end
    end

endmodule
