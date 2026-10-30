`timescale 1ns/1ps
module tb_storage_cand_debug;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,abort_scalar=0;reg [31:0] param_end=32'h20000000;
 reg [31:0] cfg_a_base=32'h03000000,cfg_b_base=32'h03010000,cfg_c_base=32'h03020000,cfg_epoch=32'h12345678;
 reg [15:0] cfg_m=64,cfg_n=64,cfg_k=64,cfg_layer=7,cfg_a_id=1,cfg_b_id=2,cfg_c_id=3,cfg_allowed=1,cfg_c_completed=0;
 reg cfg_c_valid=1;reg req_valid=0,req_write=0;wire req_ready;
 reg [31:0] req_address=32'h03000000,req_epoch=32'h12345678;
 reg [15:0] req_layer=7,req_matrix=1,req_block_row=0,req_block_col=0,req_allowed_ops=1,req_completed_ops=0;
 reg [1:0] req_encoding=0;reg req_block_valid=1,req_in_operation=1;
 wire header_valid;wire header_exists,header_block_valid,header_in_operation;
 wire [31:0] header_epoch;wire [15:0] header_layer,header_matrix,header_block_row,header_block_col,header_allowed_ops,header_completed_ops;
 wire [1:0] header_encoding;
 wire data_valid;wire [191:0] data_in;wire [9:0] data_index;wire data_last;
 wire out_valid,out_ready;wire [47:0] out_data;wire [9:0] out_index;wire out_last;
 wire write_ack,write_error;wire dma_request_valid,dma_request_ready,dma_request_write;
 wire [31:0] dma_address;wire [15:0] dma_beats;wire dma_read_valid,dma_read_ready;wire [127:0] dma_read_data;wire [15:0] dma_read_index;
 wire dma_write_valid,dma_write_ready,dma_write_strobe,dma_write_index;wire [127:0] dma_write_data;
 wire dma_done,dma_error;wire idle;wire [31:0] transactions,read_blocks,write_blocks,error_transactions;
 wire [63:0] read_wait_cycles,write_wait_cycles,scalar_cycles;
 reg header_ready=0,data_ready=0;
 block_storage_dma_wide4 dut(.clk(clk),.rst_n(rst_n),.abort_scalar(abort_scalar),.param_end(param_end),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),.cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),
  .cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),.req_address(req_address),.req_epoch(req_epoch),
  .req_layer(req_layer),.req_matrix(req_matrix),.req_block_row(req_block_row),.req_block_col(req_block_col),
  .req_allowed_ops(req_allowed_ops),.req_completed_ops(req_completed_ops),.req_encoding(req_encoding),
  .req_block_valid(req_block_valid),.req_in_operation(req_in_operation),
  .header_valid(header_valid),.header_ready(header_ready),.header_exists(header_exists),.header_block_valid(header_block_valid),
  .header_in_operation(header_in_operation),.header_epoch(header_epoch),.header_layer(header_layer),.header_matrix(header_matrix),
  .header_block_row(header_block_row),.header_block_col(header_block_col),.header_allowed_ops(header_allowed_ops),
  .header_completed_ops(header_completed_ops),.header_encoding(header_encoding),
  .data_valid(data_valid),.data_ready(data_ready),.data_in(data_in),.data_index(data_index),.data_last(data_last),
  .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),.out_index(out_index),.out_last(out_last),
  .write_ack(write_ack),.write_error(write_error),
  .dma_request_valid(dma_request_valid),.dma_request_ready(dma_request_ready),.dma_request_write(dma_request_write),
  .dma_address(dma_address),.dma_beats(dma_beats),.dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),
  .dma_read_data(dma_read_data),.dma_read_index(dma_read_index),.dma_write_valid(dma_write_valid),.dma_write_ready(dma_write_ready),
  .dma_write_data(dma_write_data),.dma_write_strobe(dma_write_strobe),.dma_write_index(dma_write_index),
  .dma_done(dma_done),.dma_error(dma_error),.idle(idle),.transactions(transactions),.read_blocks(read_blocks),
  .write_blocks(write_blocks),.error_transactions(error_transactions),.read_wait_cycles(read_wait_cycles),
  .write_wait_cycles(write_wait_cycles),.scalar_cycles(scalar_cycles));
 initial begin
  rst_n=0;repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  @(negedge clk);req_valid=1;while(!req_ready)@(negedge clk);
  @(posedge clk);@(negedge clk);req_valid=0;
  wait(dut.v_done);#1;
  $display("v_meta=%b v_addr_bad=%b v_bad=%b exp=%h end=%h base=%h bytes=%h ncols=%h nrows=%h",
    dut.v_meta,dut.v_addr_bad,dut.v_bad_final,dut.v_expected,dut.v_expected_end,dut.v_base,dut.v_bytes,dut.v_ncols,dut.v_nrows);
  $display("r_enc=%0d r_row=%0d r_col=%0d r_addr=%h r_write=%b r_inop=%b r_cmp=%0d r_bv=%b",
    dut.r_encoding,dut.r_row,dut.r_col,dut.r_req_address,dut.r_write,dut.r_in_operation,dut.r_completed_req,dut.r_block_valid);
  $display("meta terms enc3=%b ep=%b lay=%b mat=%b alw=%b bv=%b al=%b wr=%b",
    dut.r_encoding==3,dut.r_epoch!=dut.r_cfg_epoch,dut.r_layer!=dut.r_cfg_layer,
    dut.r_matrix!=(dut.r_encoding==0?dut.r_a_id:dut.r_encoding==1?dut.r_b_id:dut.r_c_id),
    dut.r_allowed_req!=dut.r_cfg_allowed,!dut.r_block_valid,dut.r_req_address[5:0]!=0,
    (dut.r_write?(dut.r_encoding!=2||dut.r_in_operation||dut.r_completed_req!=1):(!dut.r_in_operation||dut.r_completed_req!=0)));
  $display("range1=%b range2=%b exp_eq=%b rowbad=%b colbad=%b",
    (dut.v_expected>=32'h03000000)&&(dut.v_expected_end<=32'h08000000),
    (!dut.r_write&&dut.r_encoding==1&&dut.v_expected>=32'h10000000&&dut.v_expected_end<=dut.r_param_end&&dut.r_param_end<=32'h40000000),
    dut.v_expected=={32'd0,dut.r_req_address},dut.r_row>=dut.v_nrows,dut.r_col>=dut.v_ncols);
  $finish;
 end
endmodule
