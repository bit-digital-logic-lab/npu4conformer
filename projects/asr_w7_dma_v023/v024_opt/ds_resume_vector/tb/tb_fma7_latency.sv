`timescale 1ns/1ps
// Independent latency / II / flush-epoch test for the ds_fma_deep 7-stage
// fp32_fma_pipe as seen through this task's vector_fma_lane wrapper.
//
// This does not import ds_fma_deep's testbench or its runner.  It checks:
//   1. first-result latency is 7 cycles for a continuously accepted stream;
//   2. throughput is II=1 (no gaps while out_ready=1);
//   3. a stream with output backpressure still delivers every tag in order;
//   4. one-cycle flush with in_valid=0 drops all in-flight results and the
//      following epoch is exact, with the same 7-cycle latency.
//
// Failure is printed as FMA7_LATENCY FAIL; the runner treats that as failure.
module tb_fma7_latency;
 // Seven register stages: first accepted input edge to first output edge is
 // 7 clock edges.  The vector engine never uses this number.
 localparam integer EXPECT_LATENCY = 7;
 localparam integer TIMEOUT = 50000;

 reg clk = 0;
 always #4 clk = ~clk;

 reg rst_n = 0;
 reg flush = 0;
 reg in_valid = 0;
 reg [31:0] in_a = 0, in_b = 0, in_c = 0;
 reg [15:0] in_tag = 0;
 reg in_last = 0;
 wire in_ready;
 reg out_ready = 1;
 wire out_valid;
 wire [31:0] out_result;
 wire [15:0] out_tag;
 wire out_last;

 integer cyc = 0;
 integer errors = 0;
 integer accepted = 0, accepted_epoch = 0;
 integer received = 0, received_epoch = 0;
 integer first_in = -1, first_out = -1, latency = -1;
 integer last_out = -1, gap_errors = 0;
 integer stalls = 0;
 integer tag_errors = 0, last_errors = 0, x_errors = 0;
 integer post_flush_arm = 0, post_flush_outputs = 0;
 integer pre_flush_outputs = 0;
 integer flush_seen = 0;
 integer i;
 reg [15:0] expect_tag = 0;
 reg [31:0] lfsr = 32'h1a2b3c4d;

 vector_fma_lane #(.EXTRA_STAGES(0), .TAG_WIDTH(16)) dut (
  .clk(clk), .rst_n(rst_n), .flush(flush),
  .in_valid(in_valid), .in_ready(in_ready),
  .in_a(in_a), .in_b(in_b), .in_c(in_c),
  .in_tag(in_tag), .in_last(in_last),
  .out_valid(out_valid), .out_ready(out_ready),
  .out_result(out_result), .out_tag(out_tag), .out_last(out_last)
 );

 // Monitor and cycle counter run on the posedge.
 always @(posedge clk) begin
  cyc = cyc + 1;
  if (rst_n) begin
   if (flush) flush_seen = flush_seen + 1;
   if (in_valid && in_ready) begin
    if (first_in < 0) first_in = cyc;
    accepted = accepted + 1;
    accepted_epoch = accepted_epoch + 1;
   end else if (in_valid && !in_ready) begin
    stalls = stalls + 1;
   end
   if (out_valid && out_ready) begin
    if (out_tag !== expect_tag) tag_errors = tag_errors + 1;
    if (out_last !== 1'b0) last_errors = last_errors + 1;
    if ((^{out_result, out_tag}) === 1'bx) x_errors = x_errors + 1;
    if (first_out < 0) first_out = cyc;
    if (last_out >= 0 && (cyc - last_out) != 1) gap_errors = gap_errors + 1;
    last_out = cyc;
    received = received + 1;
    received_epoch = received_epoch + 1;
    if (post_flush_arm) post_flush_outputs = post_flush_outputs + 1;
    else if (flush_seen != 0) pre_flush_outputs = pre_flush_outputs + 1;
    expect_tag = expect_tag + 1;
   end
  end
 end

 function [31:0] mix(input [31:0] x);
  begin
   mix = {x[30:0], x[31]^x[21]^x[1]^x[0]} + 32'h9e3779b9;
  end
 endfunction

 task fail(input [1023:0] msg);
  begin
   $display("FMA7_LATENCY FAIL %0s cyc=%0d", msg, cyc);
   errors = errors + 1;
  end
  endtask

 task wait_cycles(input integer n);
  integer j;
  begin
   for (j = 0; j < n; j = j + 1) @(negedge clk);
  end
  endtask

 // Stream n elements.  bp=0 keeps out_ready high every cycle; bp=1 toggles it
 // from an LFSR.  The input payload is held stable while in_ready is low.
 task stream(input integer n, input [15:0] base, input integer bp,
              input integer measure_latency, input [1023:0] name);
  integer edge_delta;
  integer prev_accepted;
  begin
   accepted_epoch = 0;
   received_epoch = 0;
   expect_tag = base;
   first_in = -1;
   first_out = -1;
   last_out = -1;
   gap_errors = 0;
   tag_errors = 0;
   last_errors = 0;
   out_ready = 1;
   in_valid = 0;
   @(negedge clk);
   in_valid = 1;
   in_tag = base;
   in_a = 32'h3f800000;
   in_b = 32'h40000000;
   in_c = 32'h00000000;
   prev_accepted = -1;
   while (received_epoch < n) begin
    @(negedge clk);
    if (bp) begin
     lfsr = mix(lfsr);
     out_ready = lfsr[3] ^ lfsr[7];
    end else out_ready = 1;
    // A posedge acceptance happened iff accepted_epoch changed.  Only then
    // is the beat currently on the bus already consumed; prepare the next.
    if (accepted_epoch != prev_accepted) begin
     prev_accepted = accepted_epoch;
     if (accepted_epoch >= n) in_valid = 0;
     else begin
      in_tag = base + accepted_epoch;
      in_a = mix(in_a + accepted_epoch);
      in_b = 32'h40000000 + (accepted_epoch & 7);
      in_c = mix(in_c ^ accepted_epoch);
     end
    end
    if (cyc > TIMEOUT) begin
     fail("timeout in stream");
     received_epoch = n;
    end
   end
   in_valid = 0;
   if (accepted_epoch != n) fail("accepted count mismatch");
   if (received_epoch != n) fail("received count mismatch");
   if (tag_errors != 0) fail("tag order/stability mismatch");
   if (last_errors != 0) fail("out_last is not zero");
   if (x_errors != 0) fail("X on result/tag");
   if (bp == 0 && gap_errors != 0) fail("II gap with out_ready=1");
   if (measure_latency != 0) begin
    edge_delta = first_out - first_in;
    latency = edge_delta;
    if (latency != EXPECT_LATENCY) fail("first-result latency not 7");
   end
   $display("FMA7_STREAM %0s n=%0d accepted=%0d received=%0d latency=%0d edge_delta=%0d gaps=%0d stalls=%0d",
            name, n, accepted_epoch, received_epoch, latency, edge_delta,
            gap_errors, stalls);
  end
  endtask

 initial begin
  rst_n = 0;
  repeat (10) @(posedge clk);
  rst_n = 1;
  repeat (4) @(posedge clk);

  // 1. continuous stream: exactly 7-cycle latency and II=1
  stream(64, 16'h0000, 0, 1, "ii1");
  if (latency != EXPECT_LATENCY) fail("latency must be 7, see FMA7_STREAM");
  if (accepted != 64) fail("global accepted != 64");
  if (received != 64) fail("global received != 64");

  // 2. output backpressure: every result still appears once, in order
  stream(32, 16'h0100, 1, 0, "backpressure");

  // 3. flush with no upstream transfer in the flush cycle: all in-flight
  // results are dropped, including the deepest pipeline stages.
  accepted_epoch = 0; received_epoch = 0; expect_tag = 16'h0200;
  in_valid = 1; in_tag = 16'h0200;
  in_a = 32'h3f800000; in_b = 32'h40000000; in_c = 32'h00000000;
  @(negedge clk);
  while (accepted_epoch < 5) @(negedge clk);
  in_valid = 0;
  wait_cycles(1);
  @(negedge clk); flush = 1;
  @(negedge clk); flush = 0;
  post_flush_arm = 1; post_flush_outputs = 0;
  wait_cycles(16);
  post_flush_arm = 0;
  if (post_flush_outputs != 0) fail("output appeared after flush");
  $display("FMA7_FLUSH in_flight=5 post_flush_outputs=%0d flush_cycles=%0d",
           post_flush_outputs, flush_seen);

  // 4. new epoch after flush: exact, same 7-cycle latency
  stream(16, 16'h0300, 0, 1, "new_epoch");
  if (latency != EXPECT_LATENCY) fail("new-epoch latency not 7");

  if (cyc >= TIMEOUT) fail("watchdog");
  if (errors == 0) begin
   $display("FMA7_LATENCY PASS latency=%0d ii1=1 bp=1 flush_drop=1 new_epoch=1",
            latency);
   $finish;
  end else begin
   $display("FMA7_LATENCY FAIL errors=%0d", errors);
   $fatal(1, "fma7 latency test failed");
  end
 end

 always @(posedge clk) begin
  if (cyc > TIMEOUT + 1000) begin
   $display("FMA7_LATENCY FAIL watchdog cyc=%0d", cyc);
   $fatal(1, "fma7 latency timeout");
  end
 end
endmodule
