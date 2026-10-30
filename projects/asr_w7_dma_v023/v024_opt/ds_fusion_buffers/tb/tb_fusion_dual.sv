`timescale 1ns/1ps
// tb_fusion_cluster.sv
// Directed/backpressure test for matrix_stream_fusion_top (fused on-chip path).
//
// The testbench only preloads A/W (and optional C) once, pulses start, and then
// waits.  Every A/W read, C48 transfer, A16 write and BRESP is issued by the
// DUT's own DMA state machines.  No host-side per-tile reads/writes.
//
// Observability:
//   * per-port AXI beat/byte counters (real handshakes, real WSTRB popcount)
//   * AW address window check: no write outside the A16 tensor
//   * last-W, last-B, dma-done cycles (AXI write response drain boundary)
//   * A16 dump for the independent Python golden
module tb_fusion_dual;
  parameter [31:0] BASE      = 32'h03000000;
  parameter integer MEM_BYTES= 1048576;
  parameter integer MEM_WORDS= 8192;
  parameter integer MAX_CYC  = 400000;

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;

  reg [31:0] A_BASE, B_BASE, A16_BASE;
  reg [15:0] M, N, K, LAYER, A_ID, B_ID, C_ID, TARGET_HIGH, ALLOWED, REQ_OP, POSITIONS;
  reg        CLIP, C_VALID;
  reg [15:0] C_COMPLETED;
  reg [31:0] SCALE, BIAS, EPOCH;
  reg [1:0]  FMA_MODE;
  reg        RELU_EN;
  reg [31:0] PARAM_END;
  reg [15:0] NTILES;
  reg [31:0] B_EXTRA;
  integer    WATCHDOG;

  reg start = 0;

  // DUT
  wire busy, done, fault;
  wire [7:0] error_code;
  wire [63:0] task_cycles;
  wire [31:0] compute_cycles, read_blocks, write_blocks;
  wire [31:0] c_groups, c_cycles, c_raw;
  wire [7:0]  pe_drain, arr_drain;
  wire [31:0] st_c48_beats, st_a16_words, st_a16_bytes, st_fifo_high, st_fifo_stalls;
  wire [31:0] st_c48_ddr, st_drain, st_last_w, st_dma_done;
  wire [15:0] st_tiles;
  wire [31:0] st_overlap, st_bank_stall;
  wire [15:0] st_bank_occ;

  wire [39:0] r_araddr;
  wire [7:0]  r_arlen;
  wire [2:0]  r_arsize;
  wire [1:0]  r_arburst;
  wire        r_arvalid, r_arready;
  wire [127:0] r_rdata;
  wire [1:0]  r_rresp;
  wire        r_rlast, r_rvalid, r_rready;
  wire [39:0] w_awaddr;
  wire [7:0]  w_awlen;
  wire [2:0]  w_awsize;
  wire [1:0]  w_awburst;
  wire        w_awvalid, w_awready;
  wire [127:0] w_wdata;
  wire [15:0] w_wstrb;
  wire        w_wlast, w_wvalid, w_wready;
  wire [1:0]  w_bresp;
  wire        w_bvalid, w_bready;

  wire [31:0] rd_bytes, rd_bursts, wr_bytes, wr_bursts, rd_armax, wr_bmax;

  matrix_stream_fusion_top_dual #(
    .PIPE_STAGES(4), .MAX_OUT(8), .FIFO_BEATS(128), .BRIDGE_FIFO(16)
  ) dut (
    .clk(clk), .reset(!rst_n), .start(start),
    .cfg_a_base(A_BASE), .cfg_b_base(B_BASE), .cfg_a16_base(A16_BASE),
    .cfg_epoch(EPOCH), .cfg_m(M), .cfg_n(N), .cfg_k(K), .cfg_layer(LAYER),
    .cfg_a_id(A_ID), .cfg_b_id(B_ID), .cfg_c_id(C_ID),
    .cfg_target_high(TARGET_HIGH), .cfg_allowed_ops(ALLOWED),
    .cfg_requested_op(REQ_OP), .cfg_positions(POSITIONS), .cfg_clip(CLIP),
    .cfg_c_valid(C_VALID), .cfg_c_completed(C_COMPLETED), .param_end(PARAM_END),
    .cfg_fma_mode(FMA_MODE), .cfg_relu_en(RELU_EN), .cfg_scale(SCALE), .cfg_bias(BIAS),
    .param_wr_valid(1'b0), .param_wr_ready(), .param_wr_addr(8'd0), .param_wr_data(32'd0),
    .busy(busy), .done(done), .fault(fault), .error_code(error_code),
    .task_cycles(task_cycles), .compute_cycles(compute_cycles),
    .read_blocks(read_blocks), .write_blocks(write_blocks),
    .c_collect_groups(c_groups), .c_collect_cycles(c_cycles),
    .c_raw_bypass_cycles(c_raw), .pe_drain_cycles(pe_drain),
    .array_drain_cycles(arr_drain),
    .stat_c48_beats(st_c48_beats), .stat_a16_words(st_a16_words),
    .stat_a16_bytes(st_a16_bytes), .stat_fifo_high(st_fifo_high),
    .stat_fifo_stalls(st_fifo_stalls), .stat_c48_ddr_bytes(st_c48_ddr),
    .stat_drain_cycles(st_drain), .stat_last_w_cycle(st_last_w),
    .stat_dma_done_cycle(st_dma_done), .stat_tiles(st_tiles),
    .stat_overlap_cycles(st_overlap), .stat_bank_stall_cycles(st_bank_stall),
    .stat_bank_occ_max(st_bank_occ),
    .rd_m_axi_araddr(r_araddr), .rd_m_axi_arlen(r_arlen),
    .rd_m_axi_arsize(r_arsize), .rd_m_axi_arburst(r_arburst),
    .rd_m_axi_arvalid(r_arvalid), .rd_m_axi_arready(r_arready),
    .rd_m_axi_rdata(r_rdata), .rd_m_axi_rresp(r_rresp),
    .rd_m_axi_rlast(r_rlast), .rd_m_axi_rvalid(r_rvalid),
    .rd_m_axi_rready(r_rready),
    .wr_m_axi_awaddr(w_awaddr), .wr_m_axi_awlen(w_awlen),
    .wr_m_axi_awsize(w_awsize), .wr_m_axi_awburst(w_awburst),
    .wr_m_axi_awvalid(w_awvalid), .wr_m_axi_awready(w_awready),
    .wr_m_axi_wdata(w_wdata), .wr_m_axi_wstrb(w_wstrb),
    .wr_m_axi_wlast(w_wlast), .wr_m_axi_wvalid(w_wvalid),
    .wr_m_axi_wready(w_wready),
    .wr_m_axi_bresp(w_bresp), .wr_m_axi_bvalid(w_bvalid),
    .wr_m_axi_bready(w_bready),
    .rd_read_bytes(rd_bytes), .rd_read_bursts(rd_bursts),
    .wr_write_bytes(wr_bytes), .wr_write_bursts(wr_bursts),
    .rd_ar_outstanding_max(rd_armax), .wr_b_outstanding_max(wr_bmax)
  );

  // BFM ports: 0 = read master, 1 = write master
  wire [1:0] arready_b, awready_b, wready_b, rvalid_b, bvalid_b;
  wire [1:0] arvalid_b, awvalid_b, wvalid_b, bready_b, rready_b;
  wire [79:0] araddr_b, awaddr_b;
  wire [15:0] arlen_b, awlen_b;
  wire [5:0]  arsize_b, awsize_b;
  wire [3:0]  arburst_b, awburst_b;
  wire [255:0] rdata_b, wdata_b;
  wire [3:0]  rresp_b, bresp_b;
  wire [31:0] wstrb_b;
  wire [1:0]  rlast_b, wlast_b;

  assign araddr_b = {40'd0, r_araddr};
  assign arlen_b  = {8'd0, r_arlen};
  assign arsize_b = {3'd0, r_arsize};
  assign arburst_b= {2'd0, r_arburst};
  assign arvalid_b= {1'b0, r_arvalid};
  assign rready_b = {1'b1, r_rready};
  assign awaddr_b = {w_awaddr, 40'd0};
  assign awlen_b  = {w_awlen, 8'd0};
  assign awsize_b = {w_awsize, 3'd0};
  assign awburst_b= {w_awburst, 2'd0};
  assign awvalid_b= {w_awvalid, 1'b0};
  assign wvalid_b = {w_wvalid, 1'b0};
  assign wdata_b  = {w_wdata, 128'd0};
  assign wstrb_b  = {w_wstrb, 16'd0};
  assign wlast_b  = {w_wlast, 1'b0};
  assign bready_b = {w_bready, 1'b1};

  assign r_arready = arready_b[0];
  assign r_rvalid  = rvalid_b[0];
  assign r_rdata   = rdata_b[127:0];
  assign r_rresp   = rresp_b[1:0];
  assign r_rlast   = rlast_b[0];
  assign w_awready = awready_b[1];
  assign w_wready  = wready_b[1];
  assign w_bvalid  = bvalid_b[1];
  assign w_bresp   = bresp_b[3:2];

  integer LONG_MODE, LONG_PERIOD, LONG_LEN, SEED, LAT_MIN, LAT_MAX, BP_PCT;
  reg [63:0] total_cycles, r_beats_bfm, w_beats_bfm;
  reg [63:0] rd_beats_p0, wr_beats_p1, wr_bytes_p1;
  reg [63:0] ar_cmds_p0, aw_cmds_p1;
  reg [31:0] last_w_cycle, last_b_cycle, first_w_cycle;
  reg [31:0] b_count, aw_count;
  integer    cyc, start_cycle, done_cycle;
  integer    errs;
  integer    aw_out_of_window;
  integer    i;

  function [15:0] pop16(input [15:0] v);
    integer q;
    begin
      pop16 = 0;
      for (q = 0; q < 16; q = q + 1) pop16 = pop16 + v[q];
    end
  endfunction

  axi128_ddr_bfm #(
    .PORTS(2), .BASE(BASE), .MEM_BYTES(MEM_BYTES),
    .MAX_RD_OUT(8), .MAX_WR_OUT(8), .DUPLEX(0), .QDEPTH(16)
  ) bfm (
    .clk(clk), .rst_n(rst_n),
    .cfg_lat_min(LAT_MIN), .cfg_lat_max(LAT_MAX),
    .cfg_bp_pct(BP_PCT), .cfg_seed(SEED),
    .cfg_long_mode(LONG_MODE), .cfg_long_period(LONG_PERIOD),
    .cfg_long_len(LONG_LEN), .cfg_b_extra(B_EXTRA),
    .araddr(araddr_b), .arlen(arlen_b), .arsize(arsize_b), .arburst(arburst_b),
    .arvalid(arvalid_b), .arready(arready_b),
    .rdata(rdata_b), .rresp(rresp_b), .rlast(rlast_b), .rvalid(rvalid_b), .rready(rready_b),
    .awaddr(awaddr_b), .awlen(awlen_b), .awsize(awsize_b), .awburst(awburst_b),
    .awvalid(awvalid_b), .awready(awready_b),
    .wdata(wdata_b), .wstrb(wstrb_b), .wlast(wlast_b), .wvalid(wvalid_b), .wready(wready_b),
    .bresp(bresp_b), .bvalid(bvalid_b), .bready(bready_b),
    .inject_read_error(1'b0), .inject_write_error(1'b0),
    .total_cycles(total_cycles), .busy_cycles(), .read_busy_cycles(),
    .write_busy_cycles(), .read_beats(r_beats_bfm), .write_beats(w_beats_bfm),
    .read_bursts(), .write_bursts(),
    .read_wait_cycles(), .write_wait_cycles(),
    .ar_full_stalls(), .aw_full_stalls(), .cmd_stalls(),
    .max_rd_outstanding(), .max_wr_outstanding()
  );

  integer dbg_cval, dbg_pack;
  reg dbg_en;
  initial begin dbg_cval=0; dbg_pack=0; dbg_en=$test$plusargs("dbg"); end
  always @(posedge clk) if (rst_n && dbg_en) begin
    if (dut.fifo_valid && dut.fifo_ready && dbg_cval < 8) begin
      $display("DBG_CVAL %0d tag=%h data=%h", dbg_cval, dut.fifo_tag, dut.fifo_data);
      dbg_cval = dbg_cval + 1;
    end
    if (dut.ep_packed_valid && dut.ep_packed_ready && dbg_pack < 4) begin
      $display("DBG_PACK %0d tag=%h data=%h last=%b", dbg_pack, dut.ep_packed_tag, dut.ep_packed, dut.ep_packed_last);
      dbg_pack = dbg_pack + 1;
    end
  end

  // structural / protocol assertions
  integer assert_err;
  reg         hold_stalled;
  reg [191:0] hold_data;
  reg         hold_last;
  integer     fifo_peak;
  initial begin assert_err=0; hold_stalled=0; hold_data=0; hold_last=0; fifo_peak=0; end
  always @(posedge clk) if (rst_n) begin
    if (dut.fifo_occ > fifo_peak) fifo_peak = dut.fifo_occ;
    if (dut.fifo_overflow) begin
      $display("ASSERT_FAIL fifo overflow"); assert_err = assert_err + 1;
    end
    if (dut.fifo_occ > 15) begin
      $display("ASSERT_FAIL fifo occupancy %0d > 15", dut.fifo_occ); assert_err = assert_err + 1;
    end
    if (dut.cval_valid && !dut.cval_ready) begin
      hold_stalled = 1; hold_data = dut.cval_data; hold_last = dut.cval_last;
    end else if (hold_stalled) begin
      if (!dut.cval_valid || (dut.cval_data !== hold_data) || (dut.cval_last !== hold_last)) begin
        $display("ASSERT_FAIL cval not held during stall"); assert_err = assert_err + 1;
      end
      hold_stalled = 0;
    end
  end

  // per-port monitoring
  always @(posedge clk) begin
    if (rst_n) begin
      cyc <= cyc + 1;
      if (r_arvalid && r_arready) ar_cmds_p0 <= ar_cmds_p0 + 1;
      if (r_rvalid && r_rready)  rd_beats_p0 <= rd_beats_p0 + 1;
      if (w_awvalid && w_awready) begin
        aw_cmds_p1 <= aw_cmds_p1 + 1;
        aw_count <= aw_count + 1;
        if ((w_awaddr < A16_BASE) || (w_awaddr >= (A16_BASE + (NTILES * 16'd2048)))) begin
          aw_out_of_window <= aw_out_of_window + 1;
          if (errs < 8) $display("FAIL fused write outside A16 window: awaddr=%h base=%h tiles=%0d", w_awaddr, A16_BASE, NTILES);
        end
      end
      if (w_wvalid && w_wready) begin
        wr_beats_p1 <= wr_beats_p1 + 1;
        wr_bytes_p1 <= wr_bytes_p1 + pop16(w_wstrb);
        if (first_w_cycle == 0) first_w_cycle <= cyc;
        last_w_cycle <= cyc;
      end
      if (w_bvalid && w_bready) begin
        last_b_cycle <= cyc;
        b_count <= b_count + 1;
      end
    end
  end

  reg [127:0] initmem [0:MEM_WORDS-1];
  reg [1023:0] initfile, outfile;
  integer fd, t, v;
  reg [15:0] cur;

  initial begin
    cyc = 0; errs = 0; aw_out_of_window = 0; start_cycle = 0; done_cycle = 0;
    rd_beats_p0 = 0; wr_beats_p1 = 0; wr_bytes_p1 = 0;
    ar_cmds_p0 = 0; aw_cmds_p1 = 0; b_count = 0; aw_count = 0;
    last_w_cycle = 0; last_b_cycle = 0; first_w_cycle = 0;

    if (!$value$plusargs("init=%s", initfile)) initfile = "vectors/main/init.hex";
    if (!$value$plusargs("out=%s", outfile))   outfile  = "logs/fused_a16.hex";
    if (!$value$plusargs("abase=%h", A_BASE))  A_BASE = 32'h03000000;
    if (!$value$plusargs("bbase=%h", B_BASE))  B_BASE = 32'h03002000;
    if (!$value$plusargs("a16base=%h", A16_BASE)) A16_BASE = 32'h03010000;
    if (!$value$plusargs("m=%d", M)) M = 16'd32;
    if (!$value$plusargs("n=%d", N)) N = 16'd32;
    if (!$value$plusargs("k=%d", K)) K = 16'd96;
    if (!$value$plusargs("positions=%h", POSITIONS)) POSITIONS = 16'h3210;
    if (!$value$plusargs("clip=%d", CLIP)) CLIP = 1'b1;
    if (!$value$plusargs("cvalid=%d", C_VALID)) C_VALID = 1'b0;
    if (!$value$plusargs("scale=%h", SCALE)) SCALE = 32'h3f000000; // 0.5
    if (!$value$plusargs("bias=%h", BIAS))   BIAS  = 32'h3f800000; // 1.0
    if (!$value$plusargs("fma=%d", FMA_MODE)) FMA_MODE = 2'd1;
    if (!$value$plusargs("relu=%d", RELU_EN)) RELU_EN = 1'b0;
    if (!$value$plusargs("bp=%d", BP_PCT)) BP_PCT = 0;
    if (!$value$plusargs("longmode=%d", LONG_MODE)) LONG_MODE = 0;
    if (!$value$plusargs("longper=%d", LONG_PERIOD)) LONG_PERIOD = 240;
    if (!$value$plusargs("longlen=%d", LONG_LEN)) LONG_LEN = 96;
    if (!$value$plusargs("seed=%d", SEED)) SEED = 7;
    if (!$value$plusargs("latmin=%d", LAT_MIN)) LAT_MIN = 8;
    if (!$value$plusargs("latmax=%d", LAT_MAX)) LAT_MAX = 32;
    if (!$value$plusargs("bextra=%d", B_EXTRA)) B_EXTRA = 32'd0;
    if (!$value$plusargs("watchdog=%d", WATCHDOG)) WATCHDOG = MAX_CYC;

    LAYER = 16'd5; A_ID = 16'd1; B_ID = 16'd2; C_ID = 16'd3;
    TARGET_HIGH = 16'd0; ALLOWED = 16'd1; REQ_OP = 16'd1;
    C_COMPLETED = 16'd0; EPOCH = 32'd3; PARAM_END = 32'h40000000;

    NTILES = ((M + 31) / 32) * ((N + 31) / 32);
    $readmemh(initfile, initmem);
    for (i = 0; i < MEM_WORDS; i = i + 1) bfm.mem[i] = initmem[i];
    for (i = MEM_WORDS; i < MEM_BYTES/16; i = i + 1) bfm.mem[i] = 128'd0;

    // pre-poison the A16 region and a separate C48-shaped probe region
    for (i = 0; i < 8192/16; i = i + 1) bfm.mem[((A16_BASE - BASE) >> 4) + i] = 128'hdead_beef_dead_beef_dead_beef_dead_beef;

    rst_n = 0;
    repeat (8) @(negedge clk);
    rst_n = 1;
    repeat (4) @(negedge clk);
    start_cycle = cyc;
    @(negedge clk); start = 1;
    @(negedge clk); start = 0;

    wait (done || fault);
    repeat (4) @(negedge clk);
    done_cycle = cyc;

    // dump A16, 16-bit little endian values, row-major per tile
    fd = $fopen(outfile, "w");
    for (t = 0; t < NTILES; t = t + 1) begin
      for (i = 0; i < 1024; i = i + 1) begin
        v = ((A16_BASE - BASE) + t*2048 + i*2);
        cur = {bfm.mem[v/16][((v%16)+1)*8 +: 8], bfm.mem[v/16][(v%16)*8 +: 8]};
        $fwrite(fd, "%04x\n", cur);
      end
    end
    $fclose(fd);

    $display("FUSION_DONE done=%b fault=%b code=%02h cycles=%0d task_cycles=%0d busy=%b",
             done, fault, error_code, done_cycle-start_cycle, task_cycles, busy);
    $display("FUSION_STATS c48_beats=%0d a16_words=%0d a16_bytes=%0d fifo_high=%0d fifo_stalls=%0d c48_ddr_bytes=%0d tiles=%0d",
             st_c48_beats, st_a16_words, st_a16_bytes, st_fifo_high, st_fifo_stalls,
             st_c48_ddr, st_tiles);
    $display("FUSION_AXI rd_beats=%0d rd_cmds=%0d rd_bytes=%0d wr_beats=%0d wr_cmds=%0d wr_bytes=%0d wr_bursts=%0d bmax=%0d",
             rd_beats_p0, ar_cmds_p0, rd_bytes, wr_beats_p1, aw_cmds_p1, wr_bytes,
             wr_bursts, wr_bmax);
    $display("FUSION_DRAIN last_w=%0d last_b=%0d dma_done=%0d drain_cycles=%0d",
             last_w_cycle, last_b_cycle, st_dma_done, st_drain);
    $display("FUSION_DUAL overlap=%0d bank_stall=%0d bank_occ_max=%0d b_count=%0d aw_count=%0d bextra=%0d",
             st_overlap, st_bank_stall, st_bank_occ, b_count, aw_count, B_EXTRA);
    $display("FUSION_WINDOW out_of_a16=%0d", aw_out_of_window);
    $display("FUSION_ASSERT fifo_peak=%0d assert_err=%0d", fifo_peak, assert_err);
    if (st_a16_words !== ({16'd0, NTILES} * 32'd128)) begin
      $display("ASSERT_FAIL a16_words %0d != %0d", st_a16_words, NTILES*128); assert_err = assert_err + 1;
    end
    if (st_a16_bytes !== ({16'd0, NTILES} * 32'd2048)) begin
      $display("ASSERT_FAIL a16_bytes %0d != %0d", st_a16_bytes, NTILES*2048); assert_err = assert_err + 1;
    end
    if (st_c48_beats !== ({16'd0, NTILES} * 32'd256)) begin
      $display("ASSERT_FAIL c48_beats %0d != %0d", st_c48_beats, NTILES*256); assert_err = assert_err + 1;
    end
    if (st_c48_ddr !== 32'd0) begin
      $display("ASSERT_FAIL c48_ddr_bytes %0d != 0", st_c48_ddr); assert_err = assert_err + 1;
    end
    if (st_tiles !== NTILES) begin
      $display("ASSERT_FAIL tiles %0d != %0d", st_tiles, NTILES); assert_err = assert_err + 1;
    end
    // Every A16 tile is 128 words = 8 x 16-beat bursts.  Count real AW/B
    // handshakes so the completion boundary cannot hide a missing B response.
    if (aw_count !== ({16'd0, NTILES} * 32'd8)) begin
      $display("ASSERT_FAIL aw_count %0d != %0d", aw_count, NTILES*8); assert_err = assert_err + 1;
    end
    if (b_count !== ({16'd0, NTILES} * 32'd8)) begin
      $display("ASSERT_FAIL b_count %0d != %0d", b_count, NTILES*8); assert_err = assert_err + 1;
    end
    if (last_b_cycle == 0) begin
      $display("ASSERT_FAIL no B response observed"); assert_err = assert_err + 1;
    end
    if (done_cycle <= last_b_cycle) begin
      $display("ASSERT_FAIL done=%0d before/at last_b=%0d", done_cycle, last_b_cycle); assert_err = assert_err + 1;
    end
    if (st_dma_done < last_b_cycle) begin
      $display("ASSERT_FAIL dma_done=%0d before last_b=%0d", st_dma_done, last_b_cycle); assert_err = assert_err + 1;
    end
    if (done_cycle <= st_dma_done) begin
      $display("ASSERT_FAIL done=%0d before/at dma_done=%0d", done_cycle, st_dma_done); assert_err = assert_err + 1;
    end
    if ((B_EXTRA >= 32'd1000) && (NTILES > 1)) begin
      if (st_bank_occ !== 16'd2) begin
        $display("ASSERT_FAIL dual banks did not overlap: occ_max=%0d", st_bank_occ); assert_err = assert_err + 1;
      end
      if (st_overlap == 0) begin
        $display("ASSERT_FAIL no engine/writer overlap"); assert_err = assert_err + 1;
      end
    end

    if (fault) begin
      $display("FAIL fusion fault code=%02h", error_code);
      $finish;
    end
    if (aw_out_of_window != 0) begin
      $display("FAIL fused path issued a write outside the A16 window");
      $finish;
    end
    if (assert_err != 0) begin
      $display("FUSION_TB_FAIL assertions=%0d", assert_err);
      $finish;
    end
    $display("FUSION_TB_PASS");
    $finish;
  end

  initial begin
    #(MAX_CYC*10);
    $display("TIMEOUT watchdog=%0d done=%b fault=%b busy=%b state_dut=%0d", WATCHDOG, done, fault, busy, 0);
    $fatal(1, "fusion watchdog timeout");
  end
endmodule
