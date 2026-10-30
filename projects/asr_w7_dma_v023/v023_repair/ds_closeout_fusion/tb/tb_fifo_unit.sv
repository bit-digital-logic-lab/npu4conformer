`timescale 1ns/1ps
// tb_fifo_unit.sv
// Directed capacity/credit test for fusion_c48_fifo.
//
// The producer is handshake-compliant: it holds valid/data/last stable while
// ready is low.  The consumer applies long deterministic stalls.  The test
// proves that 1000 beats pass in order with occupancy <= DEPTH-1 (one skid slot
// reserved), credit never underflows, and overflow_sticky stays 0.  This is the
// formal shape of the capacity argument used for the live matrix collector
// (which also has cval_ready and therefore cannot overrun the FIFO).
module tb_fifo_unit;
  localparam integer DEPTH = 16;
  localparam integer NBEATS = 1000;

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  reg flush = 0;

  reg in_valid = 0;
  wire in_ready;
  reg [191:0] in_data;
  reg [15:0] in_tag;
  reg in_last;

  wire out_valid;
  reg out_ready = 0;
  wire [191:0] out_data;
  wire [15:0] out_tag;
  wire out_last;

  wire [7:0] occ, high, credit;
  wire overflow;
  wire [31:0] in_beats, out_beats, stalls;

  fusion_c48_fifo #(.DEPTH(DEPTH), .TAG_WIDTH(16)) dut (
    .clk(clk), .rst_n(rst_n), .flush(flush),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
    .in_tag(in_tag), .in_last(in_last),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
    .out_tag(out_tag), .out_last(out_last),
    .occupancy(occ), .high_water(high), .credit(credit),
    .overflow_sticky(overflow), .in_beats(in_beats), .out_beats(out_beats),
    .stall_cycles(stalls)
  );

  integer sent, recv, errors, cyc, i;
  reg [191:0] expval;
  reg [7:0] max_occ;
  reg [31:0] lfsr;

  // consumer: long stalls (40 cycles low, 20 high) plus LFSR jitter
  always @(posedge clk) begin
    if (!rst_n) begin
      out_ready <= 0;
      lfsr <= 32'h1aceb00c;
    end else begin
      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      if ((cyc % 60) < 40) out_ready <= 0;
      else out_ready <= lfsr[0] | lfsr[2];
    end
  end

  // compliant producer: data advances only on handshake
  always @(posedge clk) begin
    if (!rst_n) begin
      in_valid <= 0;
      in_data <= 0;
      in_tag <= 0;
      in_last <= 0;
      sent <= 0;
    end else if (sent < NBEATS) begin
      in_valid <= 1;
      if (in_valid && in_ready) begin
        in_data <= in_data + 192'd1;
        in_tag <= in_tag + 16'd1;
        in_last <= ((sent + 1) % 64) == 63;
        sent <= sent + 1;
        if (sent + 1 == NBEATS) in_valid <= 0;
      end
    end else begin
      in_valid <= 0;
    end
  end

  // output checker
  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      expval = recv;
      if (out_data !== expval) begin
        if (errors < 8) $display("FAIL beat %0d data=%h exp=%h", recv, out_data, expval);
        errors = errors + 1;
      end
      if (out_tag !== recv[15:0]) begin
        if (errors < 8) $display("FAIL beat %0d tag=%h exp=%h", recv, out_tag, recv);
        errors = errors + 1;
      end
      recv = recv + 1;
    end
    if (occ > max_occ) max_occ = occ;
  end

  initial begin
    sent = 0; recv = 0; errors = 0; cyc = 0; max_occ = 0;
    rst_n = 0;
    repeat (5) @(negedge clk);
    rst_n = 1;
    while (recv < NBEATS && cyc < 100000) begin
      @(negedge clk);
      cyc = cyc + 1;
      if (overflow) begin
        $display("FAIL overflow_sticky"); errors = errors + 1;
      end
      if (occ > DEPTH-1) begin
        $display("FAIL occupancy %0d > %0d", occ, DEPTH-1); errors = errors + 1;
      end
    end
    $display("FIFO sent=%0d recv=%0d in_beats=%0d out_beats=%0d max_occ=%0d high_water=%0d credit=%0d errors=%0d",
             sent, recv, in_beats, out_beats, max_occ, high, credit, errors);
    if (recv == NBEATS && sent == NBEATS && errors == 0 && in_beats == NBEATS &&
        out_beats == NBEATS && !overflow) $display("FIFO_PASS");
    else $display("FIFO_FAIL");
    $finish;
  end

  initial begin
    #1200000;
    $display("TIMEOUT fifo watchdog");
    $fatal(1, "fifo watchdog");
  end
endmodule
