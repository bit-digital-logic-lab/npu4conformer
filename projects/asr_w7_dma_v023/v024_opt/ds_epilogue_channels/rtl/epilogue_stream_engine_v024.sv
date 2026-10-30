`timescale 1ns/1ps
// epilogue_stream_engine_v024.sv
// Per-column scale/bias epilogue with ping-pong parameter banks, A16 and an
// optional independent 4xFP32 post-ReLU output.
//
// Derived from v023_repair/primary_stream_fix/candidate/
// epilogue_stream_engine_v023.sv (the primary_stream_fix fork, NOT the old
// Gemini biasvalid-bug version).  The v023 A16/packed fork, scalar preload
// semantics, config-drain protection and abort behavior are preserved.
//
// v024 additions:
//   * two banks x 32 columns of 32-bit scale and 32-bit bias, per-entry valid;
//   * cval_bc / cval_col sideband with explicit bc/column mapping;
//   * DMA writes to the inactive bank while the active bank streams;
//   * active-bank writes only when the engine is fully drained;
//   * independent fp32x4 valid/ready channel (post-ReLU).
//
// Scope: module-level logic simulation only.  No synthesis/STA/board claim.

module epilogue_stream_engine_v024 #(
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
    input  wire                   cfg_table_en,
    input  wire                   cfg_bank,
    input  wire [15:0]            cfg_bc,
    input  wire [31:0]            cfg_scale,
    input  wire [31:0]            cfg_bias,
    input  wire [TAG_WIDTH-1:0]   cfg_tag,

    // ---------------- Parameter Preload DMA Port ----------------
    // addr[7]=1: table write, addr[6]=bank, addr[5]=kind (0 scale/1 bias),
    // addr[4:0]=column.  addr 0/1: legacy broadcast scale/bias.
    input  wire                   param_wr_valid,
    output wire                   param_wr_ready,
    input  wire [7:0]             param_wr_addr,
    input  wire [15:0]            param_wr_bc,
    input  wire [31:0]            param_wr_data,

    // ---------------- Upstream C48 Stream (from ds_matrix) ----------------
    input  wire                   cval_valid,
    output wire                   cval_ready,
    input  wire [191:0]           cval_data,    // 4 lanes: [47:0], [95:48], [143:96], [191:144]
    input  wire [TAG_WIDTH-1:0]   cval_tag,
    input  wire [15:0]            cval_bc,
    input  wire [4:0]             cval_col,     // first of 4 columns, 0,4,...,28
    input  wire                   cval_last,

    // ---------------- Downstream A16 Stream ----------------
    output wire                   a16_valid,
    input  wire                   a16_ready,
    output wire [63:0]            a16_data,     // 4 lanes: [15:0], [31:16], [47:32], [63:48]
    output wire [127:0]           a16_packed,   // Packed 8 elements (128-bit)
    output wire                   a16_packed_valid,
    input  wire                   a16_packed_ready,
    output wire                   a16_packed_last,
    output wire [TAG_WIDTH-1:0]   a16_packed_tag,
    output wire [TAG_WIDTH-1:0]   a16_tag,
    output wire                   a16_last,

    // ---------------- Optional independent 4xFP32 post-ReLU output ----------------
    output wire                   fp32x4_valid,
    input  wire                   fp32x4_ready,
    output wire [127:0]           fp32x4_data,   // lane3..lane0
    output wire [TAG_WIDTH-1:0]   fp32x4_tag,
    output wire                   fp32x4_last,

    // ---------------- C48 Spill Stream ----------------
    output wire                   spill_valid,
    input  wire                   spill_ready,
    output wire [191:0]           spill_data,
    output wire [TAG_WIDTH-1:0]   spill_tag,
    output wire                   spill_last,

    // ---------------- Performance & Traffic Telemetry ----------------
    output reg  [31:0]            stat_c48_beats_in,
    output reg  [31:0]            stat_a16_beats_out,
    output reg  [31:0]            stat_spill_beats,
    output reg  [31:0]            stat_ddr_bytes_saved,
    output reg  [31:0]            stat_fp32_beats_out,
    output reg  [31:0]            stat_table_hits,
    output reg  [31:0]            stat_table_misses,
    output reg  [31:0]            stat_col_align_err,
    output reg  [31:0]            stat_param_rejects
);

    localparam integer NCOL = 32;

    // =========================================================================
    // Parameter tables: 2 banks x 32 columns x (scale,bias), per-entry valid
    // =========================================================================
    reg [31:0] tbl_scale [0:63];   // {bank,col}
    reg [31:0] tbl_bias  [0:63];
    reg [63:0] tbl_scale_vld;      // one bit per {bank,col}
    reg [63:0] tbl_bias_vld;
    reg [15:0] bank_bc [0:1];
    reg [1:0]  bank_bc_vld;

    // Scalar broadcast preload (legacy primary_stream_fix behavior)
    reg [31:0] preload_scale, preload_bias;
    reg        scale_valid, bias_valid;

    // =========================================================================
    // Active configuration
    // =========================================================================
    reg [1:0]           active_fma_mode;
    reg                 active_relu_en;
    reg                 active_spill_c48;
    reg                 active_spill_fp32;
    reg                 active_table_en;
    reg                 active_bank;
    reg [15:0]          active_bc;
    reg [31:0]          active_scale;
    reg [31:0]          active_bias;
    reg [TAG_WIDTH-1:0] active_tag;
    reg                 config_loaded;

    reg [15:0]          in_flight_beats;
    reg                 in_burst;

    wire [31:0] eff_scale = scale_valid ? preload_scale : active_scale;
    wire [31:0] eff_bias  = bias_valid ? preload_bias : active_bias;

    // =========================================================================
    // Handshake / idle
    // =========================================================================
    wire lanes_ready;
    wire spill_ok = !active_spill_c48 || spill_ready;
    wire cval_fire = cval_valid && cval_ready;
    wire cfg_fire  = cfg_valid && cfg_ready;
    wire a16_fire  = a16_valid && a16_ready;

    reg                  pack_has_half;
    reg                  p128_valid;

    // Two-consumer fork state: one source beat is held until both the A16
    // register and the packer have taken it.  This prevents re-presenting the
    // same converter beat when one consumer drains before the other.
    reg                  src_valid;
    reg [63:0]           src_a16;
    reg [TAG_WIDTH-1:0]  src_tag;
    reg                  src_last;
    reg                  a16_taken;
    reg                  pack_taken;

    // FP32 channel state is produced by the lanes; declared here for idle.
    wire [3:0] lane_fp32_valid;
    wire       fp32_any_pending = |lane_fp32_valid;

    // Engine is drained when no beats are in the pipeline, packer, FP32 fork,
    // or an active input burst remains.
    wire engine_idle = (in_flight_beats == 16'd0) && !src_valid &&
                       !pack_has_half && !p128_valid && !in_burst &&
                       !fp32_any_pending && !abort;
    assign cfg_ready = engine_idle;

    // =========================================================================
    // Parameter write decode / acceptance
    // =========================================================================
    wire legacy_addr_ok = (param_wr_addr == 8'h00) || (param_wr_addr == 8'h01);
    wire legacy_scale   = (param_wr_addr == 8'h00);
    wire legacy_bias    = (param_wr_addr == 8'h01);
    wire table_addr_ok  = param_wr_addr[7];
    wire table_bank     = param_wr_addr[6];
    wire table_kind     = param_wr_addr[5];       // 0 scale, 1 bias
    wire [4:0] table_col= param_wr_addr[4:0];

    // A table write to the inactive bank can preload while the active bank
    // streams.  A write to the active bank requires a fully drained engine.
    wire param_ready_legacy = legacy_addr_ok && engine_idle;
    wire param_ready_table  = table_addr_ok &&
                              ((table_bank != active_bank) || engine_idle);
    assign param_wr_ready = rst_n && !abort && !cfg_valid &&
                            (param_ready_legacy || param_ready_table);

    wire param_fire = param_wr_valid && param_wr_ready;
    wire legacy_fire = param_fire && legacy_addr_ok;
    wire table_fire  = param_fire && table_addr_ok;

    // A legacy write, or a table write to the active bank, changes the
    // parameters that the next beat would capture; do not accept a beat on
    // that same cycle.  Inactive-bank preload does not stall input.
    wire param_touches_active = param_wr_valid && param_wr_ready &&
                                (legacy_addr_ok ||
                                 (table_addr_ok && (table_bank == active_bank)));

    wire input_enabled = config_loaded && !abort && !cfg_fire &&
                         !param_touches_active;
    assign cval_ready = lanes_ready && spill_ok && input_enabled;

    // =========================================================================
    // Reset / abort / config / counters
    // =========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1) begin
                tbl_scale[i] <= 32'd0;
                tbl_bias[i]  <= 32'd0;
            end
            tbl_scale_vld <= 64'd0;
            tbl_bias_vld  <= 64'd0;
            bank_bc[0]    <= 16'd0;
            bank_bc[1]    <= 16'd0;
            bank_bc_vld   <= 2'd0;

            preload_scale <= 32'h3f800000;
            preload_bias  <= 32'd0;
            scale_valid   <= 1'b0;
            bias_valid    <= 1'b0;

            active_fma_mode   <= 2'd0;
            active_relu_en    <= 1'b0;
            active_spill_c48  <= 1'b0;
            active_spill_fp32 <= 1'b0;
            active_table_en   <= 1'b0;
            active_bank       <= 1'b0;
            active_bc         <= 16'd0;
            active_scale      <= 32'h3f800000;
            active_bias       <= 32'd0;
            active_tag        <= {TAG_WIDTH{1'b0}};
            config_loaded     <= 1'b0;
            in_flight_beats   <= 16'd0;
            in_burst          <= 1'b0;
        end else if (abort) begin
            // Flush all parameter validity, consistent with v023's abort rule.
            for (i = 0; i < 64; i = i + 1) begin
                tbl_scale_vld[i] <= 1'b0;
                tbl_bias_vld[i]  <= 1'b0;
            end
            bank_bc_vld     <= 2'd0;
            scale_valid     <= 1'b0;
            bias_valid      <= 1'b0;
            config_loaded   <= 1'b0;
            in_flight_beats <= 16'd0;
            in_burst        <= 1'b0;
            active_table_en <= 1'b0;
        end else begin
            if (cfg_fire) begin
                active_fma_mode   <= cfg_fma_mode;
                active_relu_en    <= cfg_relu_en;
                active_spill_c48  <= cfg_spill_c48;
                active_spill_fp32 <= cfg_spill_fp32;
                active_table_en   <= cfg_table_en;
                active_bank       <= cfg_bank;
                active_bc         <= cfg_bc;
                active_scale      <= cfg_scale;
                active_bias       <= cfg_bias;
                active_tag        <= cfg_tag;
                config_loaded     <= 1'b1;
            end

            // Legacy broadcast writes
            if (legacy_fire) begin
                if (legacy_scale) begin
                    preload_scale <= param_wr_data;
                    scale_valid   <= 1'b1;
                end else if (legacy_bias) begin
                    preload_bias <= param_wr_data;
                    bias_valid   <= 1'b1;
                end
            end

            // Table writes
            if (table_fire) begin
                if (table_kind) begin
                    tbl_bias[{table_bank, table_col}]  <= param_wr_data;
                    tbl_bias_vld[{table_bank, table_col}] <= 1'b1;
                end else begin
                    tbl_scale[{table_bank, table_col}] <= param_wr_data;
                    tbl_scale_vld[{table_bank, table_col}] <= 1'b1;
                end
                bank_bc[table_bank]  <= param_wr_bc;
                bank_bc_vld[table_bank] <= 1'b1;
            end

            case ({cval_fire, a16_fire})
                2'b10: in_flight_beats <= in_flight_beats + 16'd1;
                2'b01: in_flight_beats <= in_flight_beats - 16'd1;
                default: in_flight_beats <= in_flight_beats;
            endcase

            if (cval_fire) begin
                in_burst <= !cval_last;
            end
        end
    end

    // =========================================================================
    // Per-column table read (4 lanes x scale/bias = 8 read ports)
    // =========================================================================
    wire col_align_ok = (cval_col[1:0] == 2'b00);
    wire bc_match     = active_table_en && config_loaded && col_align_ok &&
                        (bank_bc_vld[active_bank]) &&
                        (bank_bc[active_bank] == active_bc) &&
                        (cval_bc == active_bc);

    wire [31:0] lane_scale [0:3];
    wire [31:0] lane_bias  [0:3];
    wire [3:0]  lane_tbl_scale_hit;
    wire [3:0]  lane_tbl_bias_hit;

    genvar gg;
    generate
        for (gg = 0; gg < 4; gg = gg + 1) begin : gen_tbl_read
            wire [5:0] col_now = {1'b0, cval_col} + gg[5:0];
            wire       col_in_range = (col_now < 6'd32);
            wire [5:0] idx = {active_bank, col_now[4:0]};
            wire       entry_ok = bc_match && col_in_range;
            wire       s_hit = entry_ok && tbl_scale_vld[idx];
            wire       b_hit = entry_ok && tbl_bias_vld[idx];
            assign lane_tbl_scale_hit[gg] = s_hit;
            assign lane_tbl_bias_hit[gg]  = b_hit;
            assign lane_scale[gg] = s_hit ? tbl_scale[idx] : eff_scale;
            assign lane_bias[gg]  = b_hit ? tbl_bias[idx]  : eff_bias;
        end
    endgenerate

    wire [3:0] table_hit_lanes = {lane_tbl_scale_hit[3] & lane_tbl_bias_hit[3],
                                  lane_tbl_scale_hit[2] & lane_tbl_bias_hit[2],
                                  lane_tbl_scale_hit[1] & lane_tbl_bias_hit[1],
                                  lane_tbl_scale_hit[0] & lane_tbl_bias_hit[0]};
    wire [2:0] table_hit_count = {2'd0, table_hit_lanes[0]} +
                                 {2'd0, table_hit_lanes[1]} +
                                 {2'd0, table_hit_lanes[2]} +
                                 {2'd0, table_hit_lanes[3]};

    // =========================================================================
    // Spill channel
    // =========================================================================
    assign spill_valid = cval_valid && lanes_ready && active_spill_c48 && input_enabled;
    assign spill_data  = cval_data;
    assign spill_tag   = cval_tag;
    assign spill_last  = cval_last;

    // =========================================================================
    // Four parallel epilogue lanes
    // =========================================================================
    wire [3:0] lane_in_ready;
    assign lanes_ready = &lane_in_ready;

    wire [3:0] lane_out_valid;
    wire [3:0] lane_out_last;
    wire signed [15:0] lane_a16 [0:3];
    wire [TAG_WIDTH-1:0] lane_tag [0:3];

    wire [3:0] lane_fp32_ready;
    wire [3:0] lane_fp32_last;
    wire [31:0] lane_fp32_data [0:3];
    wire [TAG_WIDTH-1:0] lane_fp32_tag [0:3];

    wire lanes_downstream_ready;
    wire fp32_all_valid = &lane_fp32_valid;
    assign fp32x4_valid = fp32_all_valid && !abort;
    assign fp32x4_data  = {lane_fp32_data[3], lane_fp32_data[2],
                           lane_fp32_data[1], lane_fp32_data[0]};
    assign fp32x4_tag   = lane_fp32_tag[0];
    assign fp32x4_last  = lane_fp32_last[0];

    // All four lanes are lockstep (common input beat and common downstream
    // ready).  Do not drain a lone lane if a skew ever appears; the TB
    // watchdog will report a deadlock instead of silently dropping a beat.
    assign lane_fp32_ready[0] = fp32_all_valid ? fp32x4_ready : 1'b0;
    assign lane_fp32_ready[1] = fp32_all_valid ? fp32x4_ready : 1'b0;
    assign lane_fp32_ready[2] = fp32_all_valid ? fp32x4_ready : 1'b0;
    assign lane_fp32_ready[3] = fp32_all_valid ? fp32x4_ready : 1'b0;

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : gen_lanes
            epilogue_lane #(.TAG_WIDTH(TAG_WIDTH)) u_lane (
                .clk            (clk),
                .rst_n          (rst_n),
                .flush          (abort),
                .cfg_fma_mode   (active_fma_mode),
                .cfg_relu_en    (active_relu_en),
                .cfg_scale      (lane_scale[g]),
                .cfg_bias       (lane_bias[g]),
                .fp32_en        (active_spill_fp32),
                .in_valid       (cval_fire),
                .in_ready       (lane_in_ready[g]),
                .in_c48         (cval_data[g*48 +: 48]),
                .in_tag         (cval_tag),
                .in_last        (cval_last),
                .out_valid      (lane_out_valid[g]),
                .out_ready      (lanes_downstream_ready),
                .out_a16        (lane_a16[g]),
                .out_tag        (lane_tag[g]),
                .out_last       (lane_out_last[g]),
                .fp32_out_valid (lane_fp32_valid[g]),
                .fp32_out_ready (lane_fp32_ready[g]),
                .fp32_out_data  (lane_fp32_data[g]),
                .fp32_out_tag   (lane_fp32_tag[g]),
                .fp32_out_last  (lane_fp32_last[g])
            );
        end
    endgenerate

    // =========================================================================
    // Downstream A16 & 128-bit AXI beat packer
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

    // Two-consumer elastic fork.  A16 and packed each have their own ready;
    // the shared source beat is released only after both have taken it.
    wire packer_available = !p128_valid || a16_packed_ready;
    wire src_free = !src_valid;
    wire src_load = lanes_out_all_valid && src_free && !abort;
    wire pack_fire = src_valid && !pack_taken && packer_available && !abort;

    assign a16_valid = src_valid && !a16_taken && !abort;
    assign a16_data = src_a16;
    assign a16_tag = src_tag;
    assign a16_last = src_last;
    assign a16_packed_tag = p128_tag;
    assign lanes_downstream_ready = src_free && !abort;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_valid <= 1'b0;
            src_a16 <= 64'd0;
            src_tag <= {TAG_WIDTH{1'b0}};
            src_last <= 1'b0;
            a16_taken <= 1'b0;
            pack_taken <= 1'b0;
        end else if (abort) begin
            src_valid <= 1'b0;
            a16_taken <= 1'b0;
            pack_taken <= 1'b0;
        end else begin
            if (a16_fire) a16_taken <= 1'b1;
            if (pack_fire) pack_taken <= 1'b1;
            if (src_load) begin
                src_valid <= 1'b1;
                src_a16 <= cur_a16_data;
                src_tag <= cur_a16_tag;
                src_last <= cur_a16_last;
                a16_taken <= 1'b0;
                pack_taken <= 1'b0;
            end else if (src_valid && a16_taken && pack_taken) begin
                src_valid <= 1'b0;
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

            if (pack_fire) begin
                if (!pack_has_half) begin
                    if (src_last) begin
                        // Odd/single beat termination: emit zero-padded packed beat
                        p128_valid    <= 1'b1;
                        p128_data     <= {64'd0, src_a16};
                        p128_tag      <= src_tag;
                        p128_last     <= 1'b1;
                        pack_has_half <= 1'b0;
                    end else begin
                        pack_half_reg <= src_a16;
                        pack_tag_reg  <= src_tag;
                        pack_last_reg <= src_last;
                        pack_has_half <= 1'b1;
                    end
                end else begin
                    p128_valid    <= 1'b1;
                    p128_data     <= {src_a16, pack_half_reg};
                    p128_tag      <= pack_tag_reg;
                    p128_last     <= src_last;
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
            stat_fp32_beats_out  <= 32'd0;
            stat_table_hits      <= 32'd0;
            stat_table_misses    <= 32'd0;
            stat_col_align_err   <= 32'd0;
            stat_param_rejects   <= 32'd0;
        end else if (abort) begin
            // Retain statistics across error flush for post-mortem telemetry
        end else begin
            if (cval_fire) begin
                stat_c48_beats_in <= stat_c48_beats_in + 32'd1;
                if (!active_spill_c48) begin
                    stat_ddr_bytes_saved <= stat_ddr_bytes_saved + 32'd48;
                end
                if (active_table_en) begin
                    stat_table_hits   <= stat_table_hits + {29'd0, table_hit_count};
                    stat_table_misses <= stat_table_misses +
                                         32'd4 - {29'd0, table_hit_count};
                end
                if (!col_align_ok)
                    stat_col_align_err <= stat_col_align_err + 32'd1;
            end
            if (a16_fire) begin
                stat_a16_beats_out <= stat_a16_beats_out + 32'd1;
            end
            if (spill_valid && spill_ready) begin
                stat_spill_beats <= stat_spill_beats + 32'd1;
            end
            if (fp32x4_valid && fp32x4_ready) begin
                stat_fp32_beats_out <= stat_fp32_beats_out + 32'd1;
            end
            // Count held table writes that target the active bank while busy.
            if (param_wr_valid && !param_wr_ready && table_addr_ok &&
                (table_bank == active_bank) && !engine_idle) begin
                stat_param_rejects <= stat_param_rejects + 32'd1;
            end
        end
    end

endmodule
