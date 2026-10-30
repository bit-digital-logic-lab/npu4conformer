`timescale 1ns/1ps

module tb_pe_baseline;
  reg clk;
  reg reset;
  reg flush;
  reg clear_sum;
  reg [15:0] a_in;
  reg [6:0] w_in;
  reg av_in;
  reg wv_in;
  reg [15:0] positions;
  reg clip;

  wire [15:0] a_out;
  wire [6:0] w_out;
  wire av_out;
  wire wv_out;
  wire signed [47:0] sum;

  pe_direct_v020 dut (
    .clk(clk),
    .reset(reset),
    .flush(flush),
    .clear_sum(clear_sum),
    .a_in(a_in),
    .w_in(w_in),
    .av_in(av_in),
    .wv_in(wv_in),
    .positions(positions),
    .clip(clip),
    .a_out(a_out),
    .w_out(w_out),
    .av_out(av_out),
    .wv_out(wv_out),
    .sum(sum)
  );

  always #5 clk = ~clk;

  integer fd_in, fd_out;
  integer r;
  reg [15:0] v_a;
  reg [6:0] v_w;
  reg [15:0] v_pos;
  reg v_clip;
  reg v_av, v_wv, v_flush, v_clr;
  integer sample_count;

  initial begin
    clk = 0;
    reset = 1;
    flush = 0;
    clear_sum = 0;
    a_in = 0;
    w_in = 0;
    av_in = 0;
    wv_in = 0;
    positions = 0;
    clip = 0;
    sample_count = 0;

    #20;
    reset = 0;
    #10;

    fd_in = $fopen("bench/test_vectors_pe.txt", "r");
    if (fd_in == 0) begin
      $display("ERROR: could not open test_vectors_pe.txt");
      $finish;
    end
    fd_out = $fopen("bench/sim_output_pe.txt", "w");

    // File format per line:
    // a_in(hex) w_in(hex) pos(hex) clip(bin) av(bin) wv(bin) clr(bin) flush(bin)
    while (!$feof(fd_in)) begin
      r = $fscanf(fd_in, "%h %h %h %b %b %b %b %b\n", v_a, v_w, v_pos, v_clip, v_av, v_wv, v_clr, v_flush);
      if (r == 8) begin
        @(posedge clk);
        #1;
        a_in = v_a;
        w_in = v_w;
        positions = v_pos;
        clip = v_clip;
        av_in = v_av;
        wv_in = v_wv;
        clear_sum = v_clr;
        flush = v_flush;

        // Log the current sum at negedge clk
        #3;
        $fdisplay(fd_out, "%012h", sum[47:0]);
        sample_count = sample_count + 1;
      end
    end

    // Extra clock cycles to drain pipeline
    repeat (10) begin
      @(posedge clk);
      #1;
      a_in = 0; w_in = 0; av_in = 0; wv_in = 0; clear_sum = 0; flush = 0;
      #3;
      $fdisplay(fd_out, "%012h", sum[47:0]);
    end

    $fclose(fd_in);
    $fclose(fd_out);
    $display("Simulation complete. Sample count: %0d", sample_count);
    $finish;
  end

endmodule
