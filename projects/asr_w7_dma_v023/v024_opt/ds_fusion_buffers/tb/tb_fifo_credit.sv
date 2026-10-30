`timescale 1ns/1ps
// tb_fifo_credit.sv
// Credit-gated non-pausable-source proof for fusion_c48_fifo.
//
// A future C-cache readout may not have a cval_ready handshake.  The required
// contract is then: issue a beat only when credit>0, reserve one slot for the
// one-cycle BRAM read latency, and never retract an asserted valid.  This TB
// models that source (including a deliberately stale registered credit) and
// checks that a whole 256-beat tile, including its tail/last frame, is
// delivered exactly once, in order, with occupancy <= DEPTH-1 and no overflow.
module tb_fifo_credit;
  localparam integer DEPTH   = 16;
  localparam integer NBEATS  = 512;
  localparam integer LONG_AT = 180;
  localparam integer LONG_LEN= 320;
  localparam integer MAX_CYC = 200000;

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;

  wire in_valid, in_ready, in_last, out_valid, out_ready, out_last;
  wire [191:0] in_data, out_data;
  wire [15:0] in_tag, out_tag;
  wire [7:0] occ, high, credit;
  wire overflow;
  wire [31:0] in_beats, out_beats, stalls;

  reg [15:0] sent;
  reg [15:0] recv;
  reg [31:0] lfsr;
  reg [31:0] cyc;
  reg        credit_q;
  integer    max_occ;
  integer    errs;
  integer    last_seen;

  wire credit_ok = credit_q;           // deliberately one cycle stale
  wire pvalid = (sent < NBEATS) && credit_ok;
  assign in_valid = pvalid;
  assign in_data  = pat(sent);
  assign in_tag   = sent;
  assign in_last  = (sent == NBEATS-1);
  wire long_window = (cyc >= LONG_AT) && (cyc < (LONG_AT + LONG_LEN));
  assign out_ready = !long_window && (lfsr[3:0] < 4'd9);

  function [191:0] pat(input [15:0] i);
    begin
      pat = {i, 16'h5aa5, i ^ 16'hffff, i + 16'd1, i + 16'd2, i + 16'd3,
             i + 16'd4, i + 16'd5, i + 16'd6, i + 16'd7, i + 16'd8, i + 16'd9};
    end
  endfunction

  fusion_c48_fifo #(.DEPTH(DEPTH), .TAG_WIDTH(16)) dut (
    .clk(clk), .rst_n(rst_n), .flush(1'b0),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
    .in_tag(in_tag), .in_last(in_last),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
    .out_tag(out_tag), .out_last(out_last),
    .occupancy(occ), .high_water(high), .credit(credit),
    .overflow_sticky(overflow), .in_beats(in_beats), .out_beats(out_beats),
    .stall_cycles(stalls)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      sent <= 0; recv <= 0; lfsr <= 32'h1acebeef; cyc <= 0;
      credit_q <= 0; max_occ <= 0; errs <= 0; last_seen <= 0;
    end else begin
      cyc <= cyc + 1;
      lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
      credit_q <= (credit != 0);
      if (occ > max_occ) max_occ <= occ;
      if (occ > DEPTH-1) begin
        $display("CREDIT_FAIL occupancy %0d > %0d", occ, DEPTH-1); errs <= errs + 1;
      end
      if (credit !== (DEPTH-1-occ)) begin
        $display("CREDIT_FAIL credit %0d != %0d", credit, DEPTH-1-occ); errs <= errs + 1;
      end
      if (overflow) begin
        $display("CREDIT_FAIL overflow sticky"); errs <= errs + 1;
      end
      if (in_valid && in_ready) sent <= sent + 1;
      if (out_valid && out_ready) begin
        if (out_data !== pat(recv)) begin
          $display("CREDIT_FAIL data idx=%0d got=%h exp=%h", recv, out_data, pat(recv)); errs <= errs + 1;
        end
        if (out_tag !== recv) begin
          $display("CREDIT_FAIL tag idx=%0d got=%0d", recv, out_tag); errs <= errs + 1;
        end
        if (out_last !== (recv == NBEATS-1)) begin
          $display("CREDIT_FAIL last idx=%0d got=%b", recv, out_last); errs <= errs + 1;
        end
        if (out_last) last_seen <= 1;
        recv <= recv + 1;
      end
    end
  end

  initial begin
    repeat (5) @(negedge clk);
    rst_n = 1;
    wait (recv == NBEATS);
    repeat (10) @(negedge clk);
    $display("CREDIT sent=%0d recv=%0d max_occ=%0d credit=%0d overflow=%b last_seen=%0d errs=%0d",
             sent, recv, max_occ, credit, overflow, last_seen, errs);
    if ((recv == NBEATS) && (sent == NBEATS) && (max_occ == DEPTH-1) &&
        (last_seen == 1) && (errs == 0) && !overflow) begin
      $display("CREDIT_PASS");
      $finish;
    end
    $display("CREDIT_FAIL final");
    $finish;
  end

  initial begin
    #(MAX_CYC*10);
    $display("CREDIT_FAIL watchdog recv=%0d sent=%0d occ=%0d", recv, sent, occ);
    $fatal(1, "fifo credit watchdog timeout");
  end
endmodule
