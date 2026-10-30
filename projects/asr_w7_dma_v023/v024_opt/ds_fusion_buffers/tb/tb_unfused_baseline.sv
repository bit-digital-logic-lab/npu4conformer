`timescale 1ns/1ps
// tb_unfused_cluster.sv
// Same workload as tb_fusion_cluster, but through matrix_stream_unfused_top:
// matrix -> C48 DDR write -> C48 DDR read-back -> epilogue -> A16 DDR write.
// This is the real traffic/cycle baseline; C48 bytes are counted at real AXI
// handshakes, not estimated.
module tb_unfused_baseline;
  parameter [31:0] BASE      = 32'h03000000;
  parameter integer MEM_BYTES= 1048576;
  parameter integer MEM_WORDS= 8192;
  parameter integer MAX_CYC  = 900000;

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;

  reg [31:0] A_BASE, B_BASE, C48_BASE, A16_BASE;
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

  wire busy, done, fault;
  wire [7:0] error_code;
  wire [63:0] matrix_cycles;
  wire [15:0] st_tiles;
  wire [31:0] st_c48w, st_c48r, st_a16b, st_drain;

  wire [39:0] rd_araddr;
  wire [7:0]  rd_arlen;
  wire [2:0]  rd_arsize;
  wire [1:0]  rd_arburst;
  wire        rd_arvalid, rd_arready;
  wire [127:0] rd_rdata;
  wire [1:0]  rd_rresp;
  wire        rd_rlast, rd_rvalid, rd_rready;

  wire [39:0] cw_awaddr;
  wire [7:0]  cw_awlen;
  wire [2:0]  cw_awsize;
  wire [1:0]  cw_awburst;
  wire        cw_awvalid, cw_awready;
  wire [127:0] cw_wdata;
  wire [15:0] cw_wstrb;
  wire        cw_wlast, cw_wvalid, cw_wready;
  wire [1:0]  cw_bresp;
  wire        cw_bvalid, cw_bready;

  wire [39:0] rb_araddr;
  wire [7:0]  rb_arlen;
  wire [2:0]  rb_arsize;
  wire [1:0]  rb_arburst;
  wire        rb_arvalid, rb_arready;
  wire [127:0] rb_rdata;
  wire [1:0]  rb_rresp;
  wire        rb_rlast, rb_rvalid, rb_rready;

  wire [39:0] a16_awaddr;
  wire [7:0]  a16_awlen;
  wire [2:0]  a16_awsize;
  wire [1:0]  a16_awburst;
  wire        a16_awvalid, a16_awready;
  wire [127:0] a16_wdata;
  wire [15:0] a16_wstrb;
  wire        a16_wlast, a16_wvalid, a16_wready;
  wire [1:0]  a16_bresp;
  wire        a16_bvalid, a16_bready;

  matrix_stream_unfused_top #(
    .PIPE_STAGES(4), .MAX_OUT(8), .FIFO_BEATS(128)
  ) dut (
    .clk(clk), .reset(!rst_n), .start(start),
    .cfg_a_base(A_BASE), .cfg_b_base(B_BASE), .cfg_c48_base(C48_BASE),
    .cfg_a16_base(A16_BASE), .cfg_epoch(EPOCH), .cfg_m(M), .cfg_n(N), .cfg_k(K),
    .cfg_layer(LAYER), .cfg_a_id(A_ID), .cfg_b_id(B_ID), .cfg_c_id(C_ID),
    .cfg_target_high(TARGET_HIGH), .cfg_allowed_ops(ALLOWED),
    .cfg_requested_op(REQ_OP), .cfg_positions(POSITIONS), .cfg_clip(CLIP),
    .cfg_c_valid(C_VALID), .cfg_c_completed(C_COMPLETED), .param_end(PARAM_END),
    .cfg_fma_mode(FMA_MODE), .cfg_relu_en(RELU_EN), .cfg_scale(SCALE), .cfg_bias(BIAS),
    .param_wr_valid(1'b0), .param_wr_ready(), .param_wr_addr(8'd0), .param_wr_data(32'd0),
    .busy(busy), .done(done), .fault(fault), .error_code(error_code),
    .matrix_cycles(matrix_cycles), .stat_tiles(st_tiles),
    .stat_c48_written_bytes(st_c48w), .stat_c48_readback_bytes(st_c48r),
    .stat_a16_bytes(st_a16b), .stat_drain_cycles(st_drain),
    .m_rd_araddr(rd_araddr), .m_rd_arlen(rd_arlen), .m_rd_arsize(rd_arsize),
    .m_rd_arburst(rd_arburst), .m_rd_arvalid(rd_arvalid), .m_rd_arready(rd_arready),
    .m_rd_rdata(rd_rdata), .m_rd_rresp(rd_rresp), .m_rd_rlast(rd_rlast),
    .m_rd_rvalid(rd_rvalid), .m_rd_rready(rd_rready),
    .m_wr_awaddr(cw_awaddr), .m_wr_awlen(cw_awlen), .m_wr_awsize(cw_awsize),
    .m_wr_awburst(cw_awburst), .m_wr_awvalid(cw_awvalid), .m_wr_awready(cw_awready),
    .m_wr_wdata(cw_wdata), .m_wr_wstrb(cw_wstrb), .m_wr_wlast(cw_wlast),
    .m_wr_wvalid(cw_wvalid), .m_wr_wready(cw_wready),
    .m_wr_bresp(cw_bresp), .m_wr_bvalid(cw_bvalid), .m_wr_bready(cw_bready),
    .rb_araddr(rb_araddr), .rb_arlen(rb_arlen), .rb_arsize(rb_arsize),
    .rb_arburst(rb_arburst), .rb_arvalid(rb_arvalid), .rb_arready(rb_arready),
    .rb_rdata(rb_rdata), .rb_rresp(rb_rresp), .rb_rlast(rb_rlast),
    .rb_rvalid(rb_rvalid), .rb_rready(rb_rready),
    .a16_awaddr(a16_awaddr), .a16_awlen(a16_awlen), .a16_awsize(a16_awsize),
    .a16_awburst(a16_awburst), .a16_awvalid(a16_awvalid), .a16_awready(a16_awready),
    .a16_wdata(a16_wdata), .a16_wstrb(a16_wstrb), .a16_wlast(a16_wlast),
    .a16_wvalid(a16_wvalid), .a16_wready(a16_wready),
    .a16_bresp(a16_bresp), .a16_bvalid(a16_bvalid), .a16_bready(a16_bready)
  );

  integer dbg_rb, dbg_g, dbg_p;
  reg dbg_en;
  initial begin dbg_rb=0; dbg_g=0; dbg_p=0; dbg_en=$test$plusargs("dbg"); end
  always @(posedge clk) if (rst_n && dbg_en) begin
    if (rb_rvalid && rb_rready && dbg_rb < 4) begin
      $display("DBG_RB %0d %h", dbg_rb, rb_rdata); dbg_rb = dbg_rb + 1;
    end
    if (dut.gb_valid && dut.gb_ready && dbg_g < 4) begin
      $display("DBG_GB %0d %h", dbg_g, dut.gb_data); dbg_g = dbg_g + 1;
    end
    if (dut.ep_packed_valid && dut.ep_packed_ready && dbg_p < 2) begin
      $display("DBG_UPK %0d %h", dbg_p, dut.ep_packed); dbg_p = dbg_p + 1;
    end
  end

  // 4 BFM ports: 0 m_rd, 1 c48 wr, 2 rb_rd, 3 a16 wr
  wire [3:0] arready_b, awready_b, wready_b, rvalid_b, bvalid_b;
  wire [3:0] arvalid_b, awvalid_b, wvalid_b, bready_b, rready_b;
  wire [159:0] araddr_b, awaddr_b;
  wire [31:0]  arlen_b, awlen_b;
  wire [11:0]  arsize_b, awsize_b;
  wire [7:0]   arburst_b, awburst_b;
  wire [511:0] rdata_b, wdata_b;
  wire [7:0]   rresp_b, bresp_b;
  wire [63:0]  wstrb_b;
  wire [3:0]   rlast_b, wlast_b;

  // port map: p0 = matrix A/W read, p1 = unused, p2 = C48 write + readback,
  //           p3 = A16 write
  assign araddr_b  = {40'd0, rb_araddr, 40'd0, rd_araddr};
  assign arlen_b   = {8'd0, rb_arlen, 8'd0, rd_arlen};
  assign arsize_b  = {3'd0, rb_arsize, 3'd0, rd_arsize};
  assign arburst_b = {2'd0, rb_arburst, 2'd0, rd_arburst};
  assign arvalid_b = {1'b0, rb_arvalid, 1'b0, rd_arvalid};
  assign rready_b  = {1'b0, rb_rready, 1'b0, rd_rready};
  assign awaddr_b  = {a16_awaddr, cw_awaddr, 40'd0, 40'd0};
  assign awlen_b   = {a16_awlen, cw_awlen, 8'd0, 8'd0};
  assign awsize_b  = {a16_awsize, cw_awsize, 3'd0, 3'd0};
  assign awburst_b = {a16_awburst, cw_awburst, 2'd0, 2'd0};
  assign awvalid_b = {a16_awvalid, cw_awvalid, 1'b0, 1'b0};
  assign wvalid_b  = {a16_wvalid, cw_wvalid, 1'b0, 1'b0};
  assign wdata_b   = {a16_wdata, cw_wdata, 128'd0, 128'd0};
  assign wstrb_b   = {a16_wstrb, cw_wstrb, 16'd0, 16'd0};
  assign wlast_b   = {a16_wlast, cw_wlast, 1'b0, 1'b0};
  assign bready_b  = {a16_bready, cw_bready, 1'b0, 1'b0};

  assign rd_arready = arready_b[0];
  assign rd_rvalid  = rvalid_b[0];
  assign rd_rdata   = rdata_b[127:0];
  assign rd_rresp   = rresp_b[1:0];
  assign rd_rlast   = rlast_b[0];

  assign cw_awready = awready_b[2];
  assign cw_wready  = wready_b[2];
  assign cw_bvalid  = bvalid_b[2];
  assign cw_bresp   = bresp_b[5:4];

  assign rb_arready = arready_b[2];
  assign rb_rvalid  = rvalid_b[2];
  assign rb_rdata   = rdata_b[383:256];
  assign rb_rresp   = rresp_b[5:4];
  assign rb_rlast   = rlast_b[2];

  assign a16_awready = awready_b[3];
  assign a16_wready  = wready_b[3];
  assign a16_bvalid  = bvalid_b[3];
  assign a16_bresp   = bresp_b[7:6];

  integer LONG_MODE, LONG_PERIOD, LONG_LEN, SEED, LAT_MIN, LAT_MAX, BP_PCT;
  reg [63:0] total_cycles;
  reg [63:0] rd_beats_p0, wr_beats_p1, c48_bytes_p1, rd_beats_p2, c48_bytes_p2;
  reg [63:0] wr_beats_p3, a16_bytes_p3;
  reg [31:0] last_w_p1, last_b_p1, last_w_p3, last_b_p3;
  reg [31:0] b_count_p3;
  integer    cyc, errs, wind_err;
  integer    start_cycle, done_cycle;
  integer    i;
  integer    dbg_aw;

  function [15:0] pop16(input [15:0] v);
    integer q;
    begin
      pop16 = 0;
      for (q = 0; q < 16; q = q + 1) pop16 = pop16 + v[q];
    end
  endfunction

  axi128_ddr_bfm #(
    .PORTS(4), .BASE(BASE), .MEM_BYTES(MEM_BYTES),
    .MAX_RD_OUT(8), .MAX_WR_OUT(8), .DUPLEX(0), .QDEPTH(16)
  ) bfm (
    .clk(clk), .rst_n(rst_n),
    .cfg_lat_min(LAT_MIN), .cfg_lat_max(LAT_MAX),
    .cfg_bp_pct(BP_PCT), .cfg_seed(SEED),
    .cfg_long_mode(LONG_MODE), .cfg_long_period(LONG_PERIOD), .cfg_long_len(LONG_LEN),
    .cfg_b_extra(B_EXTRA),
    .araddr(araddr_b), .arlen(arlen_b), .arsize(arsize_b), .arburst(arburst_b),
    .arvalid(arvalid_b), .arready(arready_b),
    .rdata(rdata_b), .rresp(rresp_b), .rlast(rlast_b), .rvalid(rvalid_b), .rready(rready_b),
    .awaddr(awaddr_b), .awlen(awlen_b), .awsize(awsize_b), .awburst(awburst_b),
    .awvalid(awvalid_b), .awready(awready_b),
    .wdata(wdata_b), .wstrb(wstrb_b), .wlast(wlast_b), .wvalid(wvalid_b), .wready(wready_b),
    .bresp(bresp_b), .bvalid(bvalid_b), .bready(bready_b),
    .inject_read_error(1'b0), .inject_write_error(1'b0),
    .total_cycles(total_cycles), .busy_cycles(), .read_busy_cycles(),
    .write_busy_cycles(), .read_beats(), .write_beats(),
    .read_bursts(), .write_bursts(),
    .read_wait_cycles(), .write_wait_cycles(),
    .ar_full_stalls(), .aw_full_stalls(), .cmd_stalls(),
    .max_rd_outstanding(), .max_wr_outstanding()
  );

  always @(posedge clk) begin
    if (rst_n) begin
      cyc <= cyc + 1;
      if (rd_rvalid && rd_rready) rd_beats_p0 <= rd_beats_p0 + 1;
      if (cw_awvalid && cw_awready)
        if ((cw_awaddr < C48_BASE) || (cw_awaddr >= (C48_BASE + NTILES*16'd6144))) wind_err <= wind_err + 1;
      if (cw_wvalid && cw_wready) begin
        wr_beats_p1 <= wr_beats_p1 + 1;
        c48_bytes_p1 <= c48_bytes_p1 + pop16(cw_wstrb);
        last_w_p1 <= cyc;
      end
      if (cw_bvalid && cw_bready) last_b_p1 <= cyc;
      if (rb_arvalid && rb_arready)
        if ((rb_araddr < C48_BASE) || (rb_araddr >= (C48_BASE + NTILES*16'd6144))) wind_err <= wind_err + 1;
      if (rb_rvalid && rb_rready) begin
        rd_beats_p2 <= rd_beats_p2 + 1;
        c48_bytes_p2 <= c48_bytes_p2 + 16;
      end
      if (a16_awvalid && a16_awready) begin
        if ((a16_awaddr < A16_BASE) || (a16_awaddr >= (A16_BASE + NTILES*16'd2048))) wind_err <= wind_err + 1;
        if (dbg_en && dbg_aw < 2) begin $display("DBG_A16_AW %h len=%0d", a16_awaddr, a16_awlen); dbg_aw = dbg_aw + 1; end
      end
      if (a16_wvalid && a16_wready) begin
        wr_beats_p3 <= wr_beats_p3 + 1;
        a16_bytes_p3 <= a16_bytes_p3 + pop16(a16_wstrb);
        last_w_p3 <= cyc;
      end
      if (a16_bvalid && a16_bready) begin
        last_b_p3 <= cyc;
        b_count_p3 <= b_count_p3 + 1;
      end
    end
  end

  reg [127:0] initmem [0:MEM_WORDS-1];
  reg [1023:0] initfile, outfile;
  integer fd, t, v;
  reg [15:0] cur;

  initial begin
    cyc = 0; errs = 0; wind_err = 0;
    rd_beats_p0 = 0; wr_beats_p1 = 0; c48_bytes_p1 = 0;
    rd_beats_p2 = 0; c48_bytes_p2 = 0; wr_beats_p3 = 0; a16_bytes_p3 = 0; b_count_p3 = 0;
    last_w_p1 = 0; last_b_p1 = 0; last_w_p3 = 0; last_b_p3 = 0;
    start_cycle = 0; done_cycle = 0; dbg_aw = 0;

    if (!$value$plusargs("init=%s", initfile)) initfile = "vectors/main/init.hex";
    if (!$value$plusargs("out=%s", outfile))   outfile  = "logs/unfused_a16.hex";
    if (!$value$plusargs("abase=%h", A_BASE))  A_BASE = 32'h03000000;
    if (!$value$plusargs("bbase=%h", B_BASE))  B_BASE = 32'h03002000;
    if (!$value$plusargs("c48base=%h", C48_BASE)) C48_BASE = 32'h03010000;
    if (!$value$plusargs("a16base=%h", A16_BASE)) A16_BASE = 32'h03020000;
    if (!$value$plusargs("m=%d", M)) M = 16'd32;
    if (!$value$plusargs("n=%d", N)) N = 16'd32;
    if (!$value$plusargs("k=%d", K)) K = 16'd96;
    if (!$value$plusargs("positions=%h", POSITIONS)) POSITIONS = 16'h3210;
    if (!$value$plusargs("clip=%d", CLIP)) CLIP = 1'b1;
    if (!$value$plusargs("cvalid=%d", C_VALID)) C_VALID = 1'b0;
    if (!$value$plusargs("scale=%h", SCALE)) SCALE = 32'h3f000000;
    if (!$value$plusargs("bias=%h", BIAS))   BIAS  = 32'h3f800000;
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
    if (!$value$plusargs("watchdog=%d", WATCHDOG)) WATCHDOG = 900000;

    LAYER = 16'd5; A_ID = 16'd1; B_ID = 16'd2; C_ID = 16'd3;
    TARGET_HIGH = 16'd0; ALLOWED = 16'd1; REQ_OP = 16'd1;
    C_COMPLETED = 16'd0; EPOCH = 32'd3; PARAM_END = 32'h40000000;
    NTILES = ((M + 31) / 32) * ((N + 31) / 32);

    $readmemh(initfile, initmem);
    for (i = 0; i < MEM_WORDS; i = i + 1) bfm.mem[i] = initmem[i];
    for (i = MEM_WORDS; i < MEM_BYTES/16; i = i + 1) bfm.mem[i] = 128'd0;

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

    fd = $fopen(outfile, "w");
    for (t = 0; t < NTILES; t = t + 1) begin
      for (i = 0; i < 1024; i = i + 1) begin
        v = ((A16_BASE - BASE) + t*2048 + i*2);
        cur = {bfm.mem[v/16][((v%16)+1)*8 +: 8], bfm.mem[v/16][(v%16)*8 +: 8]};
        $fwrite(fd, "%04x\n", cur);
      end
    end
    $fclose(fd);

    $display("UNFUSED_DONE done=%b fault=%b code=%02h cycles=%0d matrix_cycles=%0d tiles=%0d",
             done, fault, error_code, done_cycle-start_cycle, matrix_cycles, st_tiles);
    $display("UNFUSED_TRAFFIC rd_aw=%0d c48w_beats=%0d c48w_bytes=%0d c48r_beats=%0d c48r_bytes=%0d a16_beats=%0d a16_bytes=%0d",
             rd_beats_p0, wr_beats_p1, c48_bytes_p1, rd_beats_p2, c48_bytes_p2,
             wr_beats_p3, a16_bytes_p3);
    $display("UNFUSED_DRAIN c48_last_w=%0d c48_last_b=%0d a16_last_w=%0d a16_last_b=%0d a16_b_count=%0d bextra=%0d",
             last_w_p1, last_b_p1, last_w_p3, last_b_p3, b_count_p3, B_EXTRA);
    $display("UNFUSED_WINDOW errors=%0d", wind_err);

    if (fault) begin
      $display("FAIL unfused fault code=%02h", error_code);
      $finish;
    end
    if (wind_err != 0) begin
      $display("FAIL unfused address window error");
      $finish;
    end
    if (b_count_p3 !== ({16'd0, NTILES} * 32'd8)) begin
      $display("FAIL unfused a16 B responses %0d != %0d", b_count_p3, NTILES*8);
      $finish;
    end
    if (done_cycle <= last_b_p3) begin
      $display("FAIL unfused done=%0d before/at last A16 B=%0d", done_cycle, last_b_p3);
      $finish;
    end
    $display("UNFUSED_TB_PASS");
    $finish;
  end

  initial begin
    #(WATCHDOG*10);
    $display("TIMEOUT unfused watchdog cycles=%0d state=%0d", WATCHDOG, dut.state);
    $fatal(1, "unfused watchdog timeout");
  end
endmodule
