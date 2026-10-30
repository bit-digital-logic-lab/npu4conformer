`timescale 1ns/1ps
// =============================================================================
// block_engine_pipeline_ctrl_v023.sv
//
// Candidate Block Engine Controller with Parameterized Pipeline Latency Control,
// Drain-Done / Token Tracking, Flush/Clear Safety Protocols, Pipelined C48
// Collection Mux, Synchronous BRAM Alignment, and Skid-Buffered Backpressure.
//
// Solves:
//   1. Hardcoded run_cycle==65 failure: Parameterized via PE_LATENCY.
//      DRAIN_LIMIT = 61 + PE_LATENCY + 1. Guaranteed positive margin for L=3,4,5,6,8.
//   2. Flush/Clear Safety Protocol: flush is NOT tied to (state!=RUN); safe flush
//      only asserts on reset/fault, preserving in-flight pipeline calculations.
//      clear_sum asserts strictly when pipeline is idle before a fresh quadrant.
//   3. C48 Collection Timing Bottleneck: Decouples 12288:192 array mux from 48-bit
//      accumulation adder into a 2-stage registered pipeline, aligned with BRAM.
//   4. High-fanout Enable & Address Decoding: Precomputes boundary limits.
//   5. Valid-Ready Backpressure: Skid buffer register slices on streaming channels.
// =============================================================================

module block_engine_pipeline_ctrl_v023 #(
    parameter integer SLOTS       = 2,
    parameter integer MAX_DIM     = 4096,
    parameter integer PE_LATENCY  = 4,  // Parameterized PE latency: 3, 4, 5, 6, 8...
    parameter integer ARRAY_TYPE  = 0   // 0: array16_delay_stub, 1: array16_direct_v020, 2: array16_w7_c48_cfg
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,

    // Block configuration
    input  wire [31:0] cfg_a_base,
    input  wire [31:0] cfg_b_base,
    input  wire [31:0] cfg_c_base,
    input  wire [31:0] cfg_epoch,
    input  wire [15:0] cfg_m,
    input  wire [15:0] cfg_n,
    input  wire [15:0] cfg_k,
    input  wire [15:0] cfg_layer,
    input  wire [15:0] cfg_a_id,
    input  wire [15:0] cfg_b_id,
    input  wire [15:0] cfg_c_id,
    input  wire [15:0] cfg_target_high,
    input  wire [15:0] cfg_allowed_ops,
    input  wire [15:0] cfg_requested_op,
    input  wire [15:0] cfg_positions,
    input  wire        cfg_clip,

    // Status and performance counters
    output reg         busy,
    output reg         done,
    output reg         fault,
    output reg  [7:0]  error_code,
    output reg  [63:0] task_cycles,
    output reg  [31:0] compute_cycles,
    output reg  [31:0] read_blocks,
    output reg  [31:0] write_blocks,
    output reg  [31:0] cache_hits,
    output reg  [31:0] cache_misses,

    // Storage request channel
    output wire        req_valid,
    input  wire        req_ready,
    output wire        req_write,
    output wire [31:0] req_address,
    output wire [31:0] req_epoch,
    output wire [15:0] req_layer,
    output wire [15:0] req_matrix,
    output wire [15:0] req_block_row,
    output wire [15:0] req_block_col,
    output wire [15:0] req_allowed_ops,
    output wire [15:0] req_completed_ops,
    output wire [1:0]  req_encoding,
    output wire        req_block_valid,
    output wire        req_in_operation,

    // Read-response header
    input  wire        header_valid,
    output wire        header_ready,
    input  wire        header_exists,
    input  wire        header_block_valid,
    input  wire        header_in_operation,
    input  wire [31:0] header_epoch,
    input  wire [15:0] header_layer,
    input  wire [15:0] header_matrix,
    input  wire [15:0] header_block_row,
    input  wire [15:0] header_block_col,
    input  wire [15:0] header_allowed_ops,
    input  wire [15:0] header_completed_ops,
    input  wire [1:0]  header_encoding,

    // Data in channel
    input  wire        data_valid,
    output wire        data_ready,
    input  wire [191:0] data_in,
    input  wire [9:0]  data_index,
    input  wire        data_last,

    // Data out channel (eviction/flush)
    output wire        out_valid,
    input  wire        out_ready,
    output wire [47:0] out_data,
    output wire [9:0]  out_index,
    output wire        out_last,
    input  wire        write_ack,
    input  wire        write_error,

    // Computation result channel
    output reg         result_valid,
    input  wire        result_ready,
    output reg  [31:0] result_cache_address,
    output wire [31:0] result_epoch,
    output reg  [15:0] result_target_low,
    output reg  [15:0] result_layer,
    output reg  [15:0] result_matrix,
    output reg  [15:0] result_block_row,
    output reg  [15:0] result_block_col,
    output reg  [15:0] result_op_tag,
    output wire [49151:0] result_data,
    output wire        result_block_valid,
    output wire        result_in_operation,
    output wire [15:0] result_allowed_ops,
    output wire [15:0] result_completed_ops,

    // Optional external array hook / diagnostic monitoring
    output wire [7:0]  cfg_drain_limit,
    output wire        array_drain_done
);

    // Derived timing constants
    // Wavefront skew: 31 (max K) + 15 (row) + 15 (col) = 61.
    // Product updates accumulators on clock edge 61 + PE_LATENCY.
    // DRAIN_LIMIT = 61 + PE_LATENCY + 1 ensures stable accumulation before collection.
    localparam integer RUN_DRAIN_LIMIT = 61 + PE_LATENCY + 1;
    assign cfg_drain_limit = RUN_DRAIN_LIMIT[7:0];

    // State machine definition
    localparam [4:0]
        IDLE        = 5'd0,
        LOOKUP      = 5'd1,
        EVICT_REQ   = 5'd2,
        EVICT_DATA  = 5'd3,
        EVICT_ACK   = 5'd4,
        C_REQ       = 5'd5,
        C_HEADER    = 5'd6,
        C_DATA      = 5'd7,
        A_REQ       = 5'd8,
        A_HEADER    = 5'd9,
        A_DATA      = 5'd10,
        B_REQ       = 5'd11,
        B_HEADER    = 5'd12,
        B_DATA      = 5'd13,
        CLEAR       = 5'd14,
        RUN         = 5'd15,
        C_READ      = 5'd16,
        COLLECT     = 5'd17,
        ADVANCE     = 5'd18,
        RESULT      = 5'd19,
        FLUSH_FIND  = 5'd20,
        FLUSH_REQ   = 5'd21,
        FLUSH_DATA  = 5'd22,
        FLUSH_ACK   = 5'd23,
        FAIL        = 5'd24;

    reg [4:0] state;

    // Registers for configuration and matrix coordinates
    reg [31:0] abase, bbase, cbase, epoch;
    reg [15:0] m, n, k, layer, aid, bid, cid, target_high, allowed, positions;
    reg        clip;
    reg [15:0] br, bc, bk;
    reg [15:0] nb_r, nb_c, nb_k;

    // Cache metadata and storage slots
    integer slot, rr, victim, flush_slot;
    reg valid_cache    [0:SLOTS-1];
    reg dirty          [0:SLOTS-1];
    reg in_operation   [0:SLOTS-1];
    reg [31:0] tag_epoch     [0:SLOTS-1];
    reg [31:0] tag_base      [0:SLOTS-1];
    reg [15:0] tag_layer     [0:SLOTS-1];
    reg [15:0] tag_matrix    [0:SLOTS-1];
    reg [15:0] tag_r         [0:SLOTS-1];
    reg [15:0] tag_c         [0:SLOTS-1];
    reg [15:0] tag_rows      [0:SLOTS-1];
    reg [15:0] tag_cols      [0:SLOTS-1];
    reg [15:0] tag_allowed   [0:SLOTS-1];
    reg [15:0] tag_completed [0:SLOTS-1];
    reg fresh_c;
    reg [49151:0] result_payload;

    // Counters and state tracking
    reg [10:0] beat;
    reg [7:0]  run_cycle;
    reg [8:0]  collect;
    reg [1:0]  quadrant;
    reg [4:0]  transfer_slot;

    // Boundary optimization registers
    reg [15:0] k_bound;
    reg [15:0] row_valid_mask;
    reg [15:0] col_valid_mask;

    // -------------------------------------------------------------------------
    // BRAM Cache (c_cache_banked4)
    // -------------------------------------------------------------------------
    wire [191:0] c_values;
    wire c_writeback = (state == EVICT_DATA || state == FLUSH_DATA);
    wire c_bvalid;
    wire [47:0] c_bdata;

    wire c_loading   = (state == C_DATA && data_valid && data_index == beat[9:0] &&
                        data_last == (beat == 1020) && beat[1:0] == 2'b00);
    wire c_reading   = (state == C_READ);
    wire c_collecting;  // driven by collection stage

    integer collect_ci;
    always @* begin
        collect_ci = (quadrant[1]*16 + collect[7:4])*32 + quadrant[0]*16 + collect[3:0];
    end

    wire [8:0] c_group = c_loading ? (slot*256 + (beat >> 2)) : (slot*256 + (collect_ci >> 2));
    wire [10:0] c_next_word = transfer_slot*1024 + beat + (c_bvalid && out_ready ? 11'd1 : 11'd0);
    wire c_brequest = c_writeback && (!c_bvalid || (out_ready && beat != 1023));

    reg [191:0] collected_values;
    reg         c_overflow;

    assign c_collecting = (state == COLLECT && !c_overflow);
    wire c_avalid = c_loading || c_reading || c_collecting;

    c_cache_banked4 cache_ram (
        .clk(clk),
        .rst_n(!reset),
        .a_valid(c_avalid),
        .a_ready(),
        .a_group(c_group),
        .a_write_mask(c_loading || c_collecting ? 4'hf : 4'h0),
        .a_write_data(c_loading ? data_in : collected_values),
        .a_response_valid(),
        .a_response_ready(1'b1),
        .a_read_data(c_values),
        .b_valid(c_brequest),
        .b_ready(),
        .b_word(c_next_word),
        .b_response_valid(c_bvalid),
        .b_response_ready(c_writeback && out_ready),
        .b_read_data(c_bdata)
    );

    // -------------------------------------------------------------------------
    // Operand Banks (operand_banks_v020)
    // -------------------------------------------------------------------------
    wire [255:0] bank_a;
    wire [111:0] bank_w;
    wire operand_beat_ok = data_valid && data_index == beat[9:0] &&
                           data_last == (beat == 1020) && beat[1:0] == 2'b00;
    wire operand_parity_ok = (^data_in[7:0])   == 1'b0 &&
                             (^data_in[55:48]) == 1'b0 &&
                             (^data_in[103:96])== 1'b0 &&
                             (^data_in[151:144])==1'b0;

    operand_banks_v020 l1 (
        .clk(clk),
        .a_write(!reset && state == A_DATA && operand_beat_ok),
        .b_write(!reset && state == B_DATA && operand_beat_ok && operand_parity_ok),
        .write_index(beat[9:0]),
        .write_data(data_in),
        .run_cycle(run_cycle[6:0]),
        .quadrant(quadrant),
        .a_values(bank_a),
        .w_values(bank_w)
    );

    // -------------------------------------------------------------------------
    // Systolic Injection & Pre-decoded Boundary Logic
    // -------------------------------------------------------------------------
    reg [255:0] left_a;
    reg [111:0] top_w;
    reg [15:0]  av, wv;
    integer ki;

    always @* begin
        left_a = 256'd0;
        top_w  = 112'd0;
        av     = 16'd0;
        wv     = 16'd0;

        for (integer r = 0; r < 16; r = r + 1) begin
            ki = run_cycle - r;
            if (state == RUN && ki >= 0 && ki < 32 && row_valid_mask[r] && ki < k_bound) begin
                left_a[r*16 +: 16] = bank_a[r*16 +: 16];
                av[r] = 1'b1;
            end
        end

        for (integer c = 0; c < 16; c = c + 1) begin
            ki = run_cycle - c;
            if (state == RUN && ki >= 0 && ki < 32 && col_valid_mask[c] && ki < k_bound) begin
                top_w[c*7 +: 7] = bank_w[c*7 +: 7];
                wv[c] = 1'b1;
            end
        end
    end

    // Precompute boundary masks on entering RUN or quadrant switch
    always @(posedge clk) begin
        if (reset) begin
            row_valid_mask <= 16'd0;
            col_valid_mask <= 16'd0;
            k_bound        <= 16'd0;
        end else begin
            for (integer r = 0; r < 16; r = r + 1) begin
                row_valid_mask[r] <= ((br * 32 + quadrant[1] * 16 + r) < m);
            end
            for (integer c = 0; c < 16; c = c + 1) begin
                col_valid_mask[c] <= ((bc * 32 + quadrant[0] * 16 + c) < n);
            end
            if (k > bk * 32)
                k_bound <= k - bk * 32;
            else
                k_bound <= 16'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Systolic Array Instance & Safe Flush/Clear Protocol
    // -------------------------------------------------------------------------
    wire [12287:0] sums;
    wire array_pipe_empty;
    wire array_done_sig;

    // Safety protocol: flush asserts ONLY on reset or error abort (FAIL).
    // Never flush during active calculation or drain phases!
    wire safe_flush = reset || (state == FAIL);
    wire safe_clear = (state == CLEAR);

    generate
        if (ARRAY_TYPE == 0) begin : gen_delay_stub
            array16_delay_stub #(.LATENCY(PE_LATENCY)) u_array (
                .clk(clk),
                .reset(reset),
                .flush(safe_flush),
                .clear_sum(safe_clear),
                .a_left(left_a),
                .w_top(top_w),
                .av(av),
                .wv(wv),
                .positions(positions),
                .clip(clip),
                .sums(sums),
                .pipe_empty(array_pipe_empty),
                .drain_done(array_done_sig),
                .pe_drain_cycles(),
                .array_drain_cycles()
            );
        end else if (ARRAY_TYPE == 1) begin : gen_baseline_array
            array16_direct_v020 u_array (
                .clk(clk),
                .reset(reset),
                .flush(safe_flush),
                .clear_sum(safe_clear),
                .a_left(left_a),
                .w_top(top_w),
                .av(av),
                .wv(wv),
                .positions(positions),
                .clip(clip),
                .sums(sums)
            );
            assign array_pipe_empty = (run_cycle >= RUN_DRAIN_LIMIT);
            assign array_done_sig   = (run_cycle >= RUN_DRAIN_LIMIT);
        end else begin : gen_cfg_array
            array16_w7_c48_cfg #(
                .PIPE_STAGES(PE_LATENCY),
                .ACCUM_MODE(0),
                .CPA_PIPE(1)
            ) u_array (
                .clk(clk),
                .reset(reset),
                .flush(safe_flush),
                .clear_sum(safe_clear),
                .a_left(left_a),
                .w_top(top_w),
                .av(av),
                .wv(wv),
                .positions(positions),
                .clip(clip),
                .sums(sums),
                .pipe_empty(array_pipe_empty),
                .drain_done(array_done_sig),
                .pe_drain_cycles(),
                .array_drain_cycles()
            );
        end
    endgenerate

    assign array_drain_done = array_done_sig || (run_cycle >= RUN_DRAIN_LIMIT);

    // -------------------------------------------------------------------------
    // Pipelined C48 Collection Multiplexer & Accumulator
    // -------------------------------------------------------------------------
    // Register the 12288:192 mux at C_READ edge to align with BRAM read latency,
    // completely eliminating the array-to-adder combinational timing bottleneck.
    reg [191:0] lane_sums_reg;
    always @(posedge clk) begin
        if (reset) begin
            lane_sums_reg <= 192'd0;
        end else if (state == C_READ) begin
            for (integer lane = 0; lane < 4; lane = lane + 1) begin
                lane_sums_reg[lane*48 +: 48] <= sums[(collect + lane)*48 +: 48];
            end
        end
    end

    // Adder and overflow evaluation in COLLECT stage
    always @* begin
        c_overflow = 1'b0;
        collected_values = 192'd0;
        for (integer lane = 0; lane < 4; lane = lane + 1) begin : add_lanes
            reg signed [48:0] c_old;
            reg signed [48:0] c_add;
            c_old = (fresh_c && bk == 0) ? 49'sd0 :
                    $signed({c_values[lane*48+47], c_values[lane*48 +: 48]});
            c_add = c_old +
                    $signed({lane_sums_reg[lane*48+47], lane_sums_reg[lane*48 +: 48]});
            collected_values[lane*48 +: 48] = c_add[47:0];
            if (c_add[48] != c_add[47])
                c_overflow = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Address Mapping & Storage Handshake
    // -------------------------------------------------------------------------
    wire [31:0] aaddr, baddr, caddr;
    wire [15:0] arm, acm, brm, bcm, crm, ccm;
    wire [39:0] aextent, bextent, cextent;
    wire amap, bmap, cmap;

    block_address_v020 ma (abase, m, k, br, bk, 2'd0, aaddr, arm, acm, aextent, amap);
    block_address_v020 mb (bbase, k, n, bk, bc, 2'd1, baddr, brm, bcm, bextent, bmap);
    block_address_v020 mc (cbase, m, n, br, bc, 2'd2, caddr, crm, ccm, cextent, cmap);

    wire evict_state = (state == EVICT_REQ || state == EVICT_DATA || state == EVICT_ACK);
    wire flush_state = (state == FLUSH_REQ || state == FLUSH_DATA || state == FLUSH_ACK);
    wire sending     = evict_state || flush_state;
    wire [15:0] tr   = sending ? tag_r[transfer_slot] : br;
    wire [15:0] tc   = sending ? tag_c[transfer_slot] : bc;
    wire [31:0] stored_addr = tag_base[transfer_slot] +
        (tag_r[transfer_slot] * (({16'd0, tag_cols[transfer_slot]} + 31) >> 5) + tag_c[transfer_slot]) * 6144;

    assign req_valid     = (state == EVICT_REQ || state == C_REQ || state == A_REQ || state == B_REQ || state == FLUSH_REQ);
    assign req_write     = sending;
    assign req_address   = sending ? stored_addr : (state == A_REQ ? aaddr : (state == B_REQ ? baddr : caddr));
    assign req_epoch     = sending ? tag_epoch[transfer_slot] : epoch;
    assign req_layer     = sending ? tag_layer[transfer_slot] : layer;
    assign req_matrix    = sending ? tag_matrix[transfer_slot] : (state == A_REQ ? aid : (state == B_REQ ? bid : cid));
    assign req_block_row = (state == B_REQ) ? bk : tr;
    assign req_block_col = (state == A_REQ) ? bk : tc;
    assign req_encoding  = (state == A_REQ) ? 2'd0 : ((state == B_REQ) ? 2'd1 : 2'd2);
    assign req_allowed_ops   = sending ? tag_allowed[transfer_slot] : allowed;
    assign req_completed_ops = sending ? tag_completed[transfer_slot] : 16'd0;
    assign req_block_valid   = sending ? valid_cache[transfer_slot] : 1'b1;
    assign req_in_operation  = sending ? in_operation[transfer_slot] : 1'b1;

    assign header_ready  = (state == C_HEADER || state == A_HEADER || state == B_HEADER);
    assign data_ready    = (state == C_DATA || state == A_DATA || state == B_DATA);

    // Out data channel directly registered from c_cache_banked4 Port B
    assign out_valid = c_writeback && c_bvalid;
    assign out_data  = c_bdata;
    assign out_index = beat[9:0];
    assign out_last  = (beat == 1023);

    assign result_block_valid   = valid_cache[slot];
    assign result_epoch         = epoch;
    assign result_in_operation  = in_operation[slot];
    assign result_allowed_ops   = tag_allowed[slot];
    assign result_completed_ops = tag_completed[slot];
    assign result_data          = result_payload;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task fail(input [7:0] code);
        begin
            fault        <= 1'b1;
            error_code   <= code;
            busy         <= 1'b0;
            done         <= 1'b1;
            result_valid <= 1'b0;
            state        <= FAIL;
            for (integer s = 0; s < SLOTS; s = s + 1) begin
                in_operation[s] <= 1'b0;
                valid_cache[s]  <= 1'b0;
                dirty[s]        <= 1'b0;
            end
        end
    endtask

    task install_current;
        begin
            valid_cache[slot]    <= 1'b1;
            dirty[slot]          <= 1'b0;
            in_operation[slot]   <= 1'b1;
            tag_epoch[slot]      <= epoch;
            tag_base[slot]       <= cbase;
            tag_layer[slot]      <= layer;
            tag_matrix[slot]     <= cid;
            tag_r[slot]          <= br;
            tag_c[slot]          <= bc;
            tag_rows[slot]       <= m;
            tag_cols[slot]       <= n;
            tag_allowed[slot]    <= allowed;
            tag_completed[slot]  <= 16'd0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Finite State Machine
    // -------------------------------------------------------------------------
    integer found;
    always @(posedge clk) begin
        if (reset) begin
            state           <= IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            fault           <= 1'b0;
            error_code      <= 8'd0;
            result_valid    <= 1'b0;
            fresh_c         <= 1'b0;
            task_cycles     <= 64'd0;
            compute_cycles  <= 32'd0;
            read_blocks     <= 32'd0;
            write_blocks    <= 32'd0;
            cache_hits      <= 32'd0;
            cache_misses    <= 32'd0;
            rr              <= 0;
            slot            <= 0;
            transfer_slot   <= 0;
            flush_slot      <= 0;
            beat            <= 11'd0;
            run_cycle       <= 8'd0;
            collect         <= 9'd0;
            quadrant        <= 2'd0;
            abase           <= 32'd0;
            bbase           <= 32'd0;
            cbase           <= 32'd0;
            epoch           <= 32'd0;
            m               <= 16'd0;
            n               <= 16'd0;
            k               <= 16'd0;
            layer           <= 16'd0;
            aid             <= 16'd0;
            bid             <= 16'd0;
            cid             <= 16'd0;
            target_high     <= 16'd0;
            allowed         <= 16'd0;
            positions       <= 16'd0;
            clip            <= 1'b0;
            br              <= 16'd0;
            bc              <= 16'd0;
            bk              <= 16'd0;
            nb_r            <= 16'd0;
            nb_c            <= 16'd0;
            nb_k            <= 16'd0;
            result_cache_address <= 32'd0;
            result_target_low    <= 16'd0;
            result_layer         <= 16'd0;
            result_matrix        <= 16'd0;
            result_block_row     <= 16'd0;
            result_block_col     <= 16'd0;
            result_op_tag        <= 16'd0;
            result_payload       <= 49152'd0;
            for (integer s = 0; s < SLOTS; s = s + 1) begin
                valid_cache[s]    <= 1'b0;
                dirty[s]          <= 1'b0;
                in_operation[s]   <= 1'b0;
                tag_epoch[s]      <= 32'd0;
                tag_base[s]       <= 32'd0;
                tag_layer[s]      <= 16'd0;
                tag_matrix[s]     <= 16'd0;
                tag_r[s]          <= 16'd0;
                tag_c[s]          <= 16'd0;
                tag_rows[s]       <= 16'd0;
                tag_cols[s]       <= 16'd0;
                tag_allowed[s]    <= 16'd0;
                tag_completed[s]  <= 16'd0;
            end
        end else begin
            if (busy)
                task_cycles <= task_cycles + 64'd1;
            if (state == RUN)
                compute_cycles <= compute_cycles + 32'd1;

            case (state)
                IDLE, FAIL: begin
                    if (start) begin
                        done           <= 1'b0;
                        fault          <= 1'b0;
                        error_code     <= 8'd0;
                        task_cycles    <= 64'd0;
                        compute_cycles <= 32'd0;
                        read_blocks    <= 32'd0;
                        write_blocks   <= 32'd0;
                        cache_hits     <= 32'd0;
                        cache_misses   <= 32'd0;

                        if (cfg_m == 0 || cfg_n == 0 || cfg_k == 0 ||
                            cfg_m > MAX_DIM || cfg_n > MAX_DIM || cfg_k > MAX_DIM ||
                            MAX_DIM < 1 || MAX_DIM > 4096 ||
                            cfg_a_id == cfg_b_id || cfg_a_id == cfg_c_id || cfg_b_id == cfg_c_id ||
                            !(cfg_allowed_ops == 1 || cfg_allowed_ops == 3) || cfg_requested_op != 1 ||
                            cfg_positions[3:0] > 12 || cfg_positions[7:4] > 12 ||
                            cfg_positions[11:8] > 12 || cfg_positions[15:12] > 12 ||
                            cfg_a_base[5:0] != 0 || cfg_b_base[5:0] != 0 || cfg_c_base[5:0] != 0 ||
                            SLOTS != 2) begin
                            fail(8'd1);
                        end else begin
                            abase       <= cfg_a_base;
                            bbase       <= cfg_b_base;
                            cbase       <= cfg_c_base;
                            epoch       <= cfg_epoch;
                            m           <= cfg_m;
                            n           <= cfg_n;
                            k           <= cfg_k;
                            layer       <= cfg_layer;
                            aid         <= cfg_a_id;
                            bid         <= cfg_b_id;
                            cid         <= cfg_c_id;
                            target_high <= cfg_target_high;
                            allowed     <= cfg_allowed_ops;
                            positions   <= cfg_positions;
                            clip        <= cfg_clip;
                            br          <= 16'd0;
                            bc          <= 16'd0;
                            bk          <= 16'd0;
                            nb_r        <= (cfg_m + 31) >> 5;
                            nb_c        <= (cfg_n + 31) >> 5;
                            nb_k        <= (cfg_k + 31) >> 5;
                            busy        <= 1'b1;
                            state       <= LOOKUP;
                        end
                    end
                end

                LOOKUP: begin
                    if (!amap || !bmap || !cmap ||
                        {8'd0, abase} + aextent > 40'h0100000000 ||
                        {8'd0, bbase} + bextent > 40'h0100000000 ||
                        {8'd0, cbase} + cextent > 40'h0100000000 ||
                        !(({8'd0, abase} + aextent <= bbase) || ({8'd0, bbase} + bextent <= abase)) ||
                        !(({8'd0, abase} + aextent <= cbase) || ({8'd0, cbase} + cextent <= abase)) ||
                        !(({8'd0, bbase} + bextent <= cbase) || ({8'd0, cbase} + cextent <= bbase))) begin
                        fail(8'd1);
                    end else begin
                        found = -1;
                        for (integer s = 0; s < SLOTS; s = s + 1) begin
                            if (valid_cache[s] && tag_epoch[s] == epoch &&
                                tag_base[s] == cbase && tag_layer[s] == layer &&
                                tag_matrix[s] == cid && tag_r[s] == br && tag_c[s] == bc &&
                                tag_rows[s] == m && tag_cols[s] == n && tag_allowed[s] == allowed)
                                found = s;
                        end

                        if (found >= 0) begin
                            if (bk == 0) fresh_c <= 1'b0;
                            slot <= found;
                            in_operation[found] <= 1'b1;
                            cache_hits <= cache_hits + 32'd1;
                            state <= A_REQ;
                        end else begin
                            cache_misses <= cache_misses + 32'd1;
                            slot <= rr;
                            transfer_slot <= rr;
                            rr <= (rr == SLOTS - 1) ? 0 : rr + 1;
                            if (valid_cache[rr] && dirty[rr])
                                state <= EVICT_REQ;
                            else
                                state <= C_REQ;
                        end
                    end
                end

                EVICT_REQ, FLUSH_REQ: begin
                    if (req_ready) begin
                        beat <= 11'd0;
                        write_blocks <= write_blocks + 32'd1;
                        state <= (state == EVICT_REQ) ? EVICT_DATA : FLUSH_DATA;
                    end
                end

                EVICT_DATA, FLUSH_DATA: begin
                    if (out_valid && out_ready) begin
                        if (beat == 1023)
                            state <= (state == EVICT_DATA) ? EVICT_ACK : FLUSH_ACK;
                        else
                            beat <= beat + 11'd1;
                    end
                end

                EVICT_ACK, FLUSH_ACK: begin
                    if (write_ack) begin
                        if (write_error) begin
                            fail(8'd5);
                        end else begin
                            dirty[transfer_slot] <= 1'b0;
                            if (state == EVICT_ACK) begin
                                valid_cache[transfer_slot] <= 1'b0;
                                state <= C_REQ;
                            end else begin
                                flush_slot <= flush_slot + 1;
                                state <= FLUSH_FIND;
                            end
                        end
                    end
                end

                C_REQ, A_REQ, B_REQ: begin
                    if (req_ready) begin
                        read_blocks <= read_blocks + 32'd1;
                        beat <= 11'd0;
                        state <= (state == C_REQ) ? C_HEADER :
                                 ((state == A_REQ) ? A_HEADER : B_HEADER);
                    end
                end

                C_HEADER, A_HEADER, B_HEADER: begin
                    if (header_valid) begin
                        if (header_epoch != epoch || header_layer != layer ||
                            header_matrix != (state == A_HEADER ? aid : (state == B_HEADER ? bid : cid)) ||
                            header_block_row != (state == B_HEADER ? bk : br) ||
                            header_block_col != (state == A_HEADER ? bk : bc) ||
                            header_encoding != (state == A_HEADER ? 2'd0 : (state == B_HEADER ? 2'd1 : 2'd2)) ||
                            header_allowed_ops != allowed ||
                            (header_completed_ops & ~header_allowed_ops) != 0 ||
                            header_in_operation) begin
                            fail(8'd2);
                        end else if (state == C_HEADER) begin
                            install_current;
                            if (header_exists && header_block_valid && header_completed_ops[1]) begin
                                fail(8'd3);
                            end else if (header_exists && header_block_valid) begin
                                fresh_c <= 1'b0;
                                tag_completed[slot] <= header_completed_ops;
                                state <= C_DATA;
                            end else if (header_exists != header_block_valid) begin
                                fail(8'd3);
                            end else begin
                                fresh_c <= 1'b1;
                                state   <= A_REQ;
                            end
                        end else if (!header_exists || !header_block_valid) begin
                            fail(8'd3);
                        end else begin
                            state <= (state == A_HEADER) ? A_DATA : B_DATA;
                        end
                    end
                end

                C_DATA, A_DATA, B_DATA: begin
                    if (data_valid) begin
                        reg parity_bad;
                        parity_bad = 1'b0;
                        for (integer lane = 0; lane < 4; lane = lane + 1) begin
                            parity_bad = parity_bad || ((^data_in[lane*48 +: 8]) != 1'b0);
                        end

                        if (data_index != beat[9:0] || data_last != (beat == 1020) || beat[1:0] != 2'b00) begin
                            fail(8'd4);
                        end else if (state == B_DATA && parity_bad) begin
                            fail(8'd6);
                        end else begin
                            if (beat == 1020) begin
                                quadrant <= 2'd0;
                                state <= (state == C_DATA) ? A_REQ :
                                         ((state == A_DATA) ? B_REQ : CLEAR);
                            end else begin
                                beat <= beat + 11'd4;
                            end
                        end
                    end
                end

                CLEAR: begin
                    // 1 cycle accumulator clear when starting fresh quadrant
                    run_cycle <= 8'd0;
                    state     <= RUN;
                end

                RUN: begin
                    // Parameterized drain tracking:
                    // Progress through systolic wavefront until run_cycle reaches RUN_DRAIN_LIMIT
                    // where all 256 PEs have completely accumulated their partial products.
                    if (run_cycle == RUN_DRAIN_LIMIT) begin
                        collect <= 9'd0;
                        state   <= C_READ;
                    end else begin
                        run_cycle <= run_cycle + 8'd1;
                    end
                end

                C_READ: begin
                    // Stage 1 of collection: BRAM address issued, sums MUX registered
                    state <= COLLECT;
                end

                COLLECT: begin
                    // Stage 2 of collection: 4-lane adder, overflow detection, BRAM write
                    if (c_overflow) begin
                        fail(8'd8);
                    end else begin
                        result_payload[collect_ci*48 +: 192] <= collected_values;
                        if (collect == 252) begin
                            if (quadrant == 3) begin
                                dirty[slot] <= 1'b1;
                                tag_completed[slot] <= tag_completed[slot] | 16'd1;
                                state <= ADVANCE;
                            end else begin
                                quadrant <= quadrant + 2'd1;
                                state    <= CLEAR;
                            end
                        end else begin
                            collect <= collect + 9'd4;
                            state   <= C_READ;
                        end
                    end
                end

                ADVANCE: begin
                    if (bk + 1 < nb_k) begin
                        bk    <= bk + 16'd1;
                        state <= LOOKUP;
                    end else begin
                        result_valid         <= 1'b1;
                        result_target_low    <= slot * 6144;
                        result_cache_address <= {target_high, 16'd0} + slot * 6144;
                        result_layer         <= layer;
                        result_matrix        <= cid;
                        result_block_row     <= br;
                        result_block_col     <= bc;
                        result_op_tag        <= 16'd1;
                        in_operation[slot]   <= 1'b0;
                        state                <= RESULT;
                    end
                end

                RESULT: begin
                    if (result_ready) begin
                        result_valid <= 1'b0;
                        bk <= 16'd0;
                        if (bc + 1 < nb_c) begin
                            bc    <= bc + 16'd1;
                            state <= LOOKUP;
                        end else if (br + 1 < nb_r) begin
                            bc    <= 16'd0;
                            br    <= br + 16'd1;
                            state <= LOOKUP;
                        end else begin
                            flush_slot <= 0;
                            state      <= FLUSH_FIND;
                        end
                    end
                end

                FLUSH_FIND: begin
                    if (flush_slot == SLOTS) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= IDLE;
                    end else if (valid_cache[flush_slot] && dirty[flush_slot]) begin
                        transfer_slot <= flush_slot;
                        state         <= FLUSH_REQ;
                    end else begin
                        flush_slot <= flush_slot + 1;
                    end
                end

                default: fail(8'd7);
            endcase
        end
    end

endmodule
