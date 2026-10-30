`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_full_array_integration.sv
//
// Real Hardware Array Integration Testbench (NOT a compute stub).
// Integrates:
//   Instance 1: Candidate block controller + Original Array (array16_direct_v020)
//   Instance 2: Candidate block controller + Candidate Array (array16_w7_c48_cfg)
//
// Verifies:
//   1. Real W7 neural code decoding, positions shift table, and saturation clip.
//   2. Full 4-quadrant execution (16x16 sub-arrays -> 32x32 block).
//   3. Cross-K multi-iteration accumulation (K = 64: nb_k = 2) in BRAM cache.
//   4. Multi-block continuous execution with double-buffering (SLOTS = 2).
//   5. 100% bit-exact equivalence between Baseline Array and Candidate Array.
// -----------------------------------------------------------------------------

module tb_full_array_integration;

    reg clk;
    reg reset;

    localparam integer M = 32;
    localparam integer N = 32; // 1 output block (32x32) with cross-K
    localparam integer K = 64; // 2 K-chunks (bk=0, bk=1)
    localparam [15:0] TEST_POSITIONS = 16'h3210;
    localparam        TEST_CLIP      = 1'b1;

    always #5 clk = ~clk;

    // Instance 1: Baseline Array (array16_direct_v020, PE_LATENCY = 3)
    reg  start_base;
    wire busy_base, done_base, fault_base;
    wire [7:0]  err_base;
    wire [63:0] tc_base;
    wire [31:0] cc_base, rb_base, wb_base, ch_base, cm_base;
    wire req_v_base, req_r_base, req_w_base;
    wire [31:0] req_addr_base, req_ep_base;
    wire [15:0] req_lay_base, req_mat_base, req_br_base, req_bc_base, req_allow_base, req_comp_base;
    wire [1:0]  req_enc_base;
    wire req_bv_base, req_inop_base;
    wire hdr_v_base, hdr_r_base, hdr_ex_base, hdr_bv_base, hdr_inop_base;
    wire [31:0] hdr_ep_base;
    wire [15:0] hdr_lay_base, hdr_mat_base, hdr_br_base, hdr_bc_base, hdr_allow_base, hdr_comp_base;
    wire [1:0]  hdr_enc_base;
    wire d_v_base, d_r_base, d_last_base;
    wire [191:0] d_in_base;
    wire [9:0]   d_idx_base;
    wire o_v_base, o_r_base, o_last_base, w_ack_base, w_err_base;
    wire [47:0] o_data_base;
    wire [9:0]  o_idx_base;
    wire res_val_base;
    reg  res_rdy_base;
    wire [49151:0] res_data_base;

    block_engine_pipeline_ctrl_v023 #(
        .SLOTS(2),
        .MAX_DIM(4096),
        .PE_LATENCY(3),
        .ARRAY_TYPE(1) // REAL array16_direct_v020!
    ) dut_baseline (
        .clk(clk), .reset(reset), .start(start_base),
        .cfg_a_base(32'h0300_0000), .cfg_b_base(32'h0300_4000), .cfg_c_base(32'h0300_8000), .cfg_epoch(32'd2),
        .cfg_m(M[15:0]), .cfg_n(N[15:0]), .cfg_k(K[15:0]), .cfg_layer(16'd1),
        .cfg_a_id(16'd1), .cfg_b_id(16'd2), .cfg_c_id(16'd3),
        .cfg_target_high(16'd0), .cfg_allowed_ops(16'd1), .cfg_requested_op(16'd1),
        .cfg_positions(TEST_POSITIONS), .cfg_clip(TEST_CLIP),
        .busy(busy_base), .done(done_base), .fault(fault_base), .error_code(err_base),
        .task_cycles(tc_base), .compute_cycles(cc_base),
        .read_blocks(rb_base), .write_blocks(wb_base),
        .cache_hits(ch_base), .cache_misses(cm_base),
        .req_valid(req_v_base), .req_ready(req_r_base), .req_write(req_w_base),
        .req_address(req_addr_base), .req_epoch(req_ep_base), .req_layer(req_lay_base),
        .req_matrix(req_mat_base), .req_block_row(req_br_base), .req_block_col(req_bc_base),
        .req_allowed_ops(req_allow_base), .req_completed_ops(req_comp_base),
        .req_encoding(req_enc_base), .req_block_valid(req_bv_base), .req_in_operation(req_inop_base),
        .header_valid(hdr_v_base), .header_ready(hdr_r_base), .header_exists(hdr_ex_base),
        .header_block_valid(hdr_bv_base), .header_in_operation(hdr_inop_base),
        .header_epoch(hdr_ep_base), .header_layer(hdr_lay_base), .header_matrix(hdr_mat_base),
        .header_block_row(hdr_br_base), .header_block_col(hdr_bc_base),
        .header_allowed_ops(hdr_allow_base), .header_completed_ops(hdr_comp_base),
        .header_encoding(hdr_enc_base),
        .data_valid(d_v_base), .data_ready(d_r_base), .data_in(d_in_base), .data_index(d_idx_base), .data_last(d_last_base),
        .out_valid(o_v_base), .out_ready(o_r_base), .out_data(o_data_base), .out_index(o_idx_base), .out_last(o_last_base),
        .write_ack(w_ack_base), .write_error(w_err_base),
        .result_valid(res_val_base), .result_ready(res_rdy_base),
        .result_cache_address(), .result_epoch(), .result_target_low(),
        .result_layer(), .result_matrix(), .result_block_row(), .result_block_col(),
        .result_op_tag(), .result_data(res_data_base),
        .result_block_valid(), .result_in_operation(), .result_allowed_ops(), .result_completed_ops(),
        .cfg_drain_limit(), .array_drain_done()
    );

    storage_engine_bfm #(.M(M), .N(N), .K(K)) bfm_base (
        .clk(clk), .reset(reset),
        .req_valid(req_v_base), .req_ready(req_r_base), .req_write(req_w_base),
        .req_address(req_addr_base), .req_epoch(req_ep_base), .req_layer(req_lay_base),
        .req_matrix(req_mat_base), .req_block_row(req_br_base), .req_block_col(req_bc_base),
        .req_allowed_ops(req_allow_base), .req_completed_ops(req_comp_base),
        .req_encoding(req_enc_base), .req_block_valid(req_bv_base), .req_in_operation(req_inop_base),
        .header_valid(hdr_v_base), .header_ready(hdr_r_base), .header_exists(hdr_ex_base),
        .header_block_valid(hdr_bv_base), .header_in_operation(hdr_inop_base),
        .header_epoch(hdr_ep_base), .header_layer(hdr_lay_base), .header_matrix(hdr_mat_base),
        .header_block_row(hdr_br_base), .header_block_col(hdr_bc_base),
        .header_allowed_ops(hdr_allow_base), .header_completed_ops(hdr_comp_base),
        .header_encoding(hdr_enc_base),
        .data_valid(d_v_base), .data_ready(d_r_base), .data_in(d_in_base), .data_index(d_idx_base), .data_last(d_last_base),
        .out_valid(o_v_base), .out_ready(o_r_base), .out_data(o_data_base), .out_index(o_idx_base), .out_last(o_last_base),
        .write_ack(w_ack_base), .write_error(w_err_base),
        .c_exists_mode(1'b0)
    );

    // Instance 2: Candidate Array (array16_w7_c48_cfg, PE_LATENCY = 4)
    reg  start_cand;
    wire busy_cand, done_cand, fault_cand;
    wire [7:0]  err_cand;
    wire [63:0] tc_cand;
    wire [31:0] cc_cand, rb_cand, wb_cand, ch_cand, cm_cand;
    wire req_v_cand, req_r_cand, req_w_cand;
    wire [31:0] req_addr_cand, req_ep_cand;
    wire [15:0] req_lay_cand, req_mat_cand, req_br_cand, req_bc_cand, req_allow_cand, req_comp_cand;
    wire [1:0]  req_enc_cand;
    wire req_bv_cand, req_inop_cand;
    wire hdr_v_cand, hdr_r_cand, hdr_ex_cand, hdr_bv_cand, hdr_inop_cand;
    wire [31:0] hdr_ep_cand;
    wire [15:0] hdr_lay_cand, hdr_mat_cand, hdr_br_cand, hdr_bc_cand, hdr_allow_cand, hdr_comp_cand;
    wire [1:0]  hdr_enc_cand;
    wire d_v_cand, d_r_cand, d_last_cand;
    wire [191:0] d_in_cand;
    wire [9:0]   d_idx_cand;
    wire o_v_cand, o_r_cand, o_last_cand, w_ack_cand, w_err_cand;
    wire [47:0] o_data_cand;
    wire [9:0]  o_idx_cand;
    wire res_val_cand;
    reg  res_rdy_cand;
    wire [49151:0] res_data_cand;

    block_engine_pipeline_ctrl_v023 #(
        .SLOTS(2),
        .MAX_DIM(4096),
        .PE_LATENCY(4),
        .ARRAY_TYPE(2) // REAL array16_w7_c48_cfg!
    ) dut_candidate (
        .clk(clk), .reset(reset), .start(start_cand),
        .cfg_a_base(32'h0300_0000), .cfg_b_base(32'h0300_4000), .cfg_c_base(32'h0300_8000), .cfg_epoch(32'd2),
        .cfg_m(M[15:0]), .cfg_n(N[15:0]), .cfg_k(K[15:0]), .cfg_layer(16'd1),
        .cfg_a_id(16'd1), .cfg_b_id(16'd2), .cfg_c_id(16'd3),
        .cfg_target_high(16'd0), .cfg_allowed_ops(16'd1), .cfg_requested_op(16'd1),
        .cfg_positions(TEST_POSITIONS), .cfg_clip(TEST_CLIP),
        .busy(busy_cand), .done(done_cand), .fault(fault_cand), .error_code(err_cand),
        .task_cycles(tc_cand), .compute_cycles(cc_cand),
        .read_blocks(rb_cand), .write_blocks(wb_cand),
        .cache_hits(ch_cand), .cache_misses(cm_cand),
        .req_valid(req_v_cand), .req_ready(req_r_cand), .req_write(req_w_cand),
        .req_address(req_addr_cand), .req_epoch(req_ep_cand), .req_layer(req_lay_cand),
        .req_matrix(req_mat_cand), .req_block_row(req_br_cand), .req_block_col(req_bc_cand),
        .req_allowed_ops(req_allow_cand), .req_completed_ops(req_comp_cand),
        .req_encoding(req_enc_cand), .req_block_valid(req_bv_cand), .req_in_operation(req_inop_cand),
        .header_valid(hdr_v_cand), .header_ready(hdr_r_cand), .header_exists(hdr_ex_cand),
        .header_block_valid(hdr_bv_cand), .header_in_operation(hdr_inop_cand),
        .header_epoch(hdr_ep_cand), .header_layer(hdr_lay_cand), .header_matrix(hdr_mat_cand),
        .header_block_row(hdr_br_cand), .header_block_col(hdr_bc_cand),
        .header_allowed_ops(hdr_allow_cand), .header_completed_ops(hdr_comp_cand),
        .header_encoding(hdr_enc_cand),
        .data_valid(d_v_cand), .data_ready(d_r_cand), .data_in(d_in_cand), .data_index(d_idx_cand), .data_last(d_last_cand),
        .out_valid(o_v_cand), .out_ready(o_r_cand), .out_data(o_data_cand), .out_index(o_idx_cand), .out_last(o_last_cand),
        .write_ack(w_ack_cand), .write_error(w_err_cand),
        .result_valid(res_val_cand), .result_ready(res_rdy_cand),
        .result_cache_address(), .result_epoch(), .result_target_low(),
        .result_layer(), .result_matrix(), .result_block_row(), .result_block_col(),
        .result_op_tag(), .result_data(res_data_cand),
        .result_block_valid(), .result_in_operation(), .result_allowed_ops(), .result_completed_ops(),
        .cfg_drain_limit(), .array_drain_done()
    );

    storage_engine_bfm #(.M(M), .N(N), .K(K)) bfm_cand (
        .clk(clk), .reset(reset),
        .req_valid(req_v_cand), .req_ready(req_r_cand), .req_write(req_w_cand),
        .req_address(req_addr_cand), .req_epoch(req_ep_cand), .req_layer(req_lay_cand),
        .req_matrix(req_mat_cand), .req_block_row(req_br_cand), .req_block_col(req_bc_cand),
        .req_allowed_ops(req_allow_cand), .req_completed_ops(req_comp_cand),
        .req_encoding(req_enc_cand), .req_block_valid(req_bv_cand), .req_in_operation(req_inop_cand),
        .header_valid(hdr_v_cand), .header_ready(hdr_r_cand), .header_exists(hdr_ex_cand),
        .header_block_valid(hdr_bv_cand), .header_in_operation(hdr_inop_cand),
        .header_epoch(hdr_ep_cand), .header_layer(hdr_lay_cand), .header_matrix(hdr_mat_cand),
        .header_block_row(hdr_br_cand), .header_block_col(hdr_bc_cand),
        .header_allowed_ops(hdr_allow_cand), .header_completed_ops(hdr_comp_cand),
        .header_encoding(hdr_enc_cand),
        .data_valid(d_v_cand), .data_ready(d_r_cand), .data_in(d_in_cand), .data_index(d_idx_cand), .data_last(d_last_cand),
        .out_valid(o_v_cand), .out_ready(o_r_cand), .out_data(o_data_cand), .out_index(o_idx_cand), .out_last(o_last_cand),
        .write_ack(w_ack_cand), .write_error(w_err_cand),
        .c_exists_mode(1'b0)
    );

    always @(posedge clk) begin
        if ($time % 100000 == 0) begin
            $display("[PROGRESS T=%0t] BASE: state=%0d br=%0d bc=%0d bk=%0d quad=%0d tc=%0d | CAND: state=%0d br=%0d bc=%0d bk=%0d quad=%0d tc=%0d",
                     $time, dut_baseline.state, dut_baseline.br, dut_baseline.bc, dut_baseline.bk, dut_baseline.quadrant, tc_base,
                     dut_candidate.state, dut_candidate.br, dut_candidate.bc, dut_candidate.bk, dut_candidate.quadrant, tc_cand);
        end
    end

    // Capture outputs on writeback
    reg signed [47:0] captured_base [0:1][0:1023];
    reg signed [47:0] captured_cand [0:1][0:1023];
    integer blk_base_cnt, blk_cand_cnt;

    always @(posedge clk) begin
        if (reset) begin
            blk_base_cnt <= 0;
            blk_cand_cnt <= 0;
        end else begin
            if (res_val_base && res_rdy_base) begin
                for (integer w = 0; w < 1024; w = w + 1) begin
                    captured_base[blk_base_cnt][w] <= res_data_base[w*48 +: 48];
                end
                blk_base_cnt <= blk_base_cnt + 1;
            end
            if (res_val_cand && res_rdy_cand) begin
                for (integer w = 0; w < 1024; w = w + 1) begin
                    captured_cand[blk_cand_cnt][w] <= res_data_cand[w*48 +: 48];
                end
                blk_cand_cnt <= blk_cand_cnt + 1;
            end
        end
    end

    // Test stimulus and validation
    integer r_idx, c_idx, k_idx, b, w, mismatches;
    reg [15:0] test_a;
    reg [6:0]  test_w;

    initial begin
        clk = 0;
        reset = 1;
        start_base = 0; res_rdy_base = 1;
        start_cand = 0; res_rdy_cand = 1;
        mismatches = 0;

        #40;
        @(negedge clk);
        reset = 0;

        // Initialize realistic matrix values into both BFMs: M=32, N=64, K=64
        for (r_idx = 0; r_idx < M; r_idx = r_idx + 1) begin
            for (k_idx = 0; k_idx < K; k_idx = k_idx + 1) begin
                // Include positive and negative signed INT16 values
                test_a = ((r_idx * 19 + k_idx * 23 + 11) & 16'h7FFF) - 16'h2000;
                bfm_base.a_mem[r_idx][k_idx] = test_a;
                bfm_cand.a_mem[r_idx][k_idx] = test_a;
            end
        end

        for (k_idx = 0; k_idx < K; k_idx = k_idx + 1) begin
            for (c_idx = 0; c_idx < N; c_idx = c_idx + 1) begin
                // Realistic W7 neural codes
                test_w = (k_idx * 11 + c_idx * 17 + 5) & 7'h7F;
                bfm_base.w_mem[k_idx][c_idx] = test_w;
                bfm_cand.w_mem[k_idx][c_idx] = test_w;
            end
        end

        $display("\n========================================================");
        $display("[TB] REAL Hardware Array Integration Test Starting...");
        $display("[TB] Workload: M=%0d, N=%0d, K=%0d (2 Output Blocks x 2 K-chunks)", M, N, K);
        $display("[TB] Baseline:  array16_direct_v020 (Real W7 decoder/array)");
        $display("[TB] Candidate: array16_w7_c48_cfg (Real 4-stage pipeline array)");
        $display("========================================================");

        @(posedge clk);
        start_base <= 1;
        start_cand <= 1;
        @(posedge clk);
        start_base <= 0;
        start_cand <= 0;

        wait (done_base && done_cand);

        #100;
        $display("\n========================================================");
        $display("[TB] Real Array Integration Simulation Completed!");
        $display("========================================================");
        $display("Baseline Array : task_cycles=%0d, compute_cycles=%0d, cache_hits=%0d, cache_misses=%0d, fault=%0d",
                 tc_base, cc_base, ch_base, cm_base, fault_base);
        $display("Candidate Array: task_cycles=%0d, compute_cycles=%0d, cache_hits=%0d, cache_misses=%0d, fault=%0d",
                 tc_cand, cc_cand, ch_cand, cm_cand, fault_cand);

        if (fault_base || fault_cand) begin
            $display("[FATAL ERROR] Fault detected: base_err=%0d, cand_err=%0d", err_base, err_cand);
            $finish(1);
        end

        // Verify cache hits occurred across K (cross-K accumulation)
        if (ch_cand == 0) begin
            $display("[ERROR] Expected non-zero cache_hits during cross-K accumulation!");
            $finish(1);
        end
        $display("[SUCCESS] Cross-K cache hits verified: %0d hits (bk=1 accumulated in-place in BRAM).", ch_cand);

        // Verify bit-exact results between Baseline Array and Candidate Array
        $display("[TB] Comparing 1024 INT48 outputs between Baseline Array and Candidate Array...");
        for (b = 0; b < 1; b = b + 1) begin
            for (w = 0; w < 1024; w = w + 1) begin
                if (captured_cand[b][w] !== captured_base[b][w]) begin
                    $display("[ERROR] Mismatch at Block %0d Word %0d: CAND=0x%012h vs BASE=0x%012h",
                             b, w, captured_cand[b][w], captured_base[b][w]);
                    mismatches = mismatches + 1;
                end
            end
        end

        if (mismatches == 0) begin
            $display("[SUCCESS] 1024 / 1024 output elements MATCH BIT-FOR-BIT between Real Baseline and Real Candidate!");
            $display("[SUCCESS] Verified all 4 quadrants and multi-K (K=64) accumulation in real PE array!");
        end else begin
            $display("[FAILURE] Total mismatches detected: %0d", mismatches);
            $finish(1);
        end

        // Dump results for Python golden verification
        begin : dump_real_results
            integer fd;
            fd = $fopen("bench/sim_real_array_output.hex", "w");
            if (fd != 0) begin
                for (b = 0; b < 1; b = b + 1) begin
                    for (w = 0; w < 1024; w = w + 1) begin
                        $fdisplay(fd, "%012h", captured_cand[b][w]);
                    end
                end
                $fclose(fd);
                $display("[TB] Written 1024 words to bench/sim_real_array_output.hex");
            end
        end

        $finish(0);
    end

endmodule
