`timescale 1ns/1ps
// tb_epilogue_contract.sv
// Directed numeric-contract test for the primary epilogue lane.
//
// Each vector is (C48, scale, bias, fma_expected_i16, muladd_expected_i16).
// The DUT is required to match the single-rounding FMA gold.  It is NOT
// required to match the two-rounding mul+add baseline; the test only reports
// how many cases separate the two contracts.
module tb_epilogue_contract;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;

  reg [143:0] cases [0:15];
  reg [1023:0] vecfile;
  integer    NCASES;

  reg [1:0]  cfg_fma_mode;
  reg        cfg_relu_en;
  reg [31:0] cfg_scale, cfg_bias;
  reg        in_valid;
  wire       in_ready;
  reg  [47:0] in_c48;
  reg  [15:0] in_tag;
  reg        in_last;
  wire       out_valid;
  reg        out_ready;
  wire [15:0] out_a16;
  wire [15:0] out_tag;
  wire       out_last;
  wire       fp32_valid;
  wire [31:0] fp32_data;

  epilogue_lane #(.TAG_WIDTH(16)) dut (
    .clk(clk), .rst_n(rst_n), .flush(1'b0),
    .cfg_fma_mode(cfg_fma_mode), .cfg_relu_en(cfg_relu_en),
    .cfg_scale(cfg_scale), .cfg_bias(cfg_bias),
    .in_valid(in_valid), .in_ready(in_ready), .in_c48(in_c48),
    .in_tag(in_tag), .in_last(in_last),
    .out_valid(out_valid), .out_ready(out_ready), .out_a16(out_a16),
    .out_tag(out_tag), .out_last(out_last),
    .fp32_valid(fp32_valid), .fp32_data(fp32_data)
  );

  reg [15:0] lfsr = 16'hace1;
  always @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  always @* out_ready = lfsr[0] | lfsr[3];   // ~75% ready, deterministic stalls

  integer i, f_bad, m_diff, got, guard;
  reg [47:0] x;
  reg [31:0] sc, bi;
  reg [15:0] fexp, mexp;

  initial begin
    f_bad = 0; m_diff = 0; got = 0;
    cfg_fma_mode = 2'd1; cfg_relu_en = 1'b0;
    in_valid = 0; in_c48 = 0; in_tag = 0; in_last = 0;
    if (!$value$plusargs("vec=%s", vecfile)) begin
      $display("FAIL no +vec=");
      $finish;
    end
    NCASES = 0;
    begin : read_cases
      integer fd;
      fd = $fopen(vecfile, "r");
      if (fd == 0) begin
        $display("FAIL cannot open contract vector file %0s", vecfile);
        $fatal(1, "contract vector file missing");
      end
      while (!$feof(fd) && (NCASES < 16)) begin
        if ($fscanf(fd, "%h\n", cases[NCASES]) == 1) NCASES = NCASES + 1;
        else NCASES = 16;
      end
      $fclose(fd);
      if (NCASES == 0) begin
        $display("FAIL contract vector file produced 0 cases");
        $fatal(1, "contract vector file empty");
      end
    end

    rst_n = 0;
    repeat (6) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);

    for (i = 0; i < NCASES; i = i + 1) begin
      x    = cases[i][143:96];
      sc   = cases[i][95:64];
      bi   = cases[i][63:32];
      fexp = cases[i][31:16];
      mexp = cases[i][15:0];
      cfg_scale = sc;
      cfg_bias  = bi;
      // wait for input room
      guard = 0;
      while (!in_ready && guard < 1000) begin @(negedge clk); guard = guard + 1; end
      @(negedge clk);
      in_valid = 1; in_c48 = x; in_tag = i; in_last = 1;
      @(negedge clk);
      in_valid = 0;
      // wait for the lane output
      guard = 0;
      while (!out_valid && guard < 1000) begin @(negedge clk); guard = guard + 1; end
      while (!(out_valid && out_ready) && guard < 2000) begin @(negedge clk); guard = guard + 1; end
      if (out_a16 !== fexp) begin
        $display("FAIL case %0d a16=%04h fma_gold=%04h muladd=%04h", i, out_a16, fexp, mexp);
        f_bad = f_bad + 1;
      end
      if (fexp !== mexp) m_diff = m_diff + 1;
      got = got + 1;
      repeat (2) @(negedge clk);
    end

    $display("CONTRACT cases=%0d fma_mismatch=%0d fma_vs_muladd_diff=%0d", got, f_bad, m_diff);
    if (f_bad == 0 && got == NCASES) $display("CONTRACT_PASS");
    else $display("CONTRACT_FAIL");
    $finish;
  end

  initial begin
    #2000000;
    $display("TIMEOUT contract watchdog");
    $fatal(1, "contract watchdog");
  end
endmodule
