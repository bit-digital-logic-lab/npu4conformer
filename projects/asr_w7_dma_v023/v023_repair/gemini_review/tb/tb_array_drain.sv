`timescale 1ns/1ps
module tb_array_drain;

  parameter integer PIPE_STAGES = 5;
  parameter integer ACCUM_MODE  = 0;
  parameter integer CPA_PIPE    = 1;

  reg clk;
  reg reset;
  reg flush;
  reg clear_sum;
  reg [255:0] a_left;
  reg [111:0] w_top;
  reg [15:0]  av;
  reg [15:0]  wv;
  reg [15:0]  positions;
  reg         clip;
  wire [12287:0] sums;
  wire        pipe_empty;
  wire        drain_done;
  wire [7:0]  pe_drain_cycles;
  wire [7:0]  array_drain_cycles;

  array16_w7_c48_cfg #(
    .PIPE_STAGES(PIPE_STAGES),
    .ACCUM_MODE(ACCUM_MODE),
    .CPA_PIPE(CPA_PIPE)
  ) dut (
    .clk(clk),
    .reset(reset),
    .flush(flush),
    .clear_sum(clear_sum),
    .a_left(a_left),
    .w_top(w_top),
    .av(av),
    .wv(wv),
    .positions(positions),
    .clip(clip),
    .sums(sums),
    .pipe_empty(pipe_empty),
    .drain_done(drain_done),
    .pe_drain_cycles(pe_drain_cycles),
    .array_drain_cycles(array_drain_cycles)
  );

  always #5 clk = ~clk;

  integer cycle;
  integer k;
  reg [47:0] expected_pe15_15;

  initial begin
    clk = 0;
    reset = 1;
    flush = 0;
    clear_sum = 0;
    a_left = 0;
    w_top = 0;
    av = 0;
    wv = 0;
    positions = 16'h0000; // all shifts = 0
    clip = 0;
    expected_pe15_15 = 0;

    #20;
    @(posedge clk);
    reset = 0;
    clear_sum = 1;
    @(posedge clk);
    clear_sum = 0;

    $display("=== TB_ARRAY_DRAIN: Testing PIPE_STAGES=%0d ACCUM_MODE=%0d ===", PIPE_STAGES, ACCUM_MODE);
    $display("PE Drain Cycles: %0d, Array Drain Cycles: %0d", pe_drain_cycles, array_drain_cycles);

    // Feed a wavefront: K=1 single pulse entering at (0,0) at cycle 0,
    // so row 15 receives A at cycle 15, col 15 receives W at cycle 15.
    // They meet at PE(15,15) at cycle 15 + 15 = 30.
    for (cycle = 0; cycle < 16; cycle = cycle + 1) begin
      @(posedge clk);
      a_left = 0;
      w_top = 0;
      av = 0;
      wv = 0;

      // Enter row 'cycle'
      a_left[cycle*16 +: 16] = 16'd10; // A = 10
      av[cycle] = 1'b1;

      // Enter col 'cycle'
      // W = {S=0, J=0, M=3} -> 7'b000_0011 -> 3
      w_top[cycle*7 +: 7] = 7'b000_0011;
      wv[cycle] = 1'b1;
    end

    // After cycle 15, inputs stop
    @(posedge clk);
    a_left = 0;
    w_top = 0;
    av = 0;
    wv = 0;

    // Expected product at PE(15,15): 10 * 3 = 30
    expected_pe15_15 = 48'd30;

    // Wait until drain_done asserts
    while (!drain_done) begin
      @(posedge clk);
    end

    $display("Drain asserted at time %0t. Inspecting PE(15,15) accumulator...", $time);

    // PE(15,15) is at index (15*16 + 15) = 255. Each sum is 48 bits.
    if (sums[255*48 +: 48] == expected_pe15_15) begin
      $display("PASS: PE(15,15) accumulator is EXACTLY %0d", sums[255*48 +: 48]);
    end else begin
      $display("FAIL: PE(15,15) expected %0d, got %0d", expected_pe15_15, sums[255*48 +: 48]);
      $fatal(1);
    end

    #50;
    $finish;
  end

endmodule
