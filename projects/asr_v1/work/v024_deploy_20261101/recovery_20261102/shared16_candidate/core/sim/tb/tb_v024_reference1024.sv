`timescale 1ns/1ps
// Same complete V024 testbench, changed only node-storage capacity for comparison.
module tb_v024_reference1024;
 tb_v024_unified body();
 defparam body.dut.MAX_NODES = 1024;
endmodule
