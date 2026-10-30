`timescale 1ns/1ps
// Integration check: real block_engine_banked_v020 + block_storage_dma_wide4
// (original or candidate selected at compile time) + a deterministic DDR BFM.
// The C region hash and engine status are logged; the two builds must match.
module tb_block_integration;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;
 reg [31:0] param_end=32'h20000000;
 reg [31:0] cfg_a_base=32'h03000000,cfg_b_base=32'h03010000,cfg_c_base=32'h03020000,cfg_epoch=32'h12345678;
 reg [15:0] cfg_m=32,cfg_n=32,cfg_k=32,cfg_layer=7,cfg_a_id=1,cfg_b_id=2,cfg_c_id=3;
 reg [15:0] cfg_allowed=1,cfg_requested_op=1,cfg_positions=16'h0000,cfg_target_high=32'h04000000;
 reg cfg_clip=0,cfg_c_valid=0;reg [15:0] cfg_c_completed=0;
 wire busy,done,fault;wire [7:0] error_code;wire [63:0] task_cycles;wire [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses;
 wire req_valid;wire req_ready;wire req_write;wire [31:0] req_address,req_epoch;
 wire [15:0] req_layer,req_matrix,req_block_row,req_block_col,req_allowed_ops,req_completed_ops;
 wire [1:0] req_encoding;wire req_block_valid,req_in_operation;
 wire header_valid,header_ready,header_exists,header_block_valid,header_in_operation;
 wire [31:0] header_epoch;wire [15:0] header_layer,header_matrix,header_block_row,header_block_col,header_allowed_ops,header_completed_ops;
 wire [1:0] header_encoding;
 wire data_valid,data_ready;wire [191:0] data_in;wire [9:0] data_index;wire data_last;
 wire out_valid,out_ready;wire [47:0] out_data;wire [9:0] out_index;wire out_last;
 wire write_ack,write_error;
 wire dma_request_valid;reg dma_request_ready;wire dma_request_write;wire [31:0] dma_address;wire [15:0] dma_beats;
 reg dma_read_valid;wire dma_read_ready;reg [127:0] dma_read_data;reg [15:0] dma_read_index;
 wire dma_write_valid;reg dma_write_ready;wire [127:0] dma_write_data;wire [15:0] dma_write_strobe;reg [15:0] dma_write_index;
 reg dma_done,dma_error;wire storage_idle;
 wire [31:0] st_transactions,st_reads,st_writes,st_errors;wire [63:0] st_rwait,st_wwait,st_scalar;
 wire result_valid;wire [31:0] result_cache_address,result_epoch;
 wire [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag;
 wire [49151:0] result_data;wire result_block_valid,result_in_operation;
 wire [15:0] result_allowed_ops,result_completed_ops;
 integer result_count=0;

 block_engine_banked_v020 #(.SLOTS(2)) core(
  .clk(clk),.reset(!rst_n),.start(start),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),.cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),
  .cfg_target_high(cfg_target_high),.cfg_allowed_ops(cfg_allowed),.cfg_requested_op(cfg_requested_op),
  .cfg_positions(cfg_positions),.cfg_clip(cfg_clip),.busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .task_cycles(task_cycles),.compute_cycles(compute_cycles),.read_blocks(read_blocks),.write_blocks(write_blocks),
  .cache_hits(cache_hits),.cache_misses(cache_misses),
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
  .result_valid(result_valid),.result_ready(1'b1),.result_cache_address(result_cache_address),.result_epoch(result_epoch),
  .result_target_low(result_target_low),.result_layer(result_layer),.result_matrix(result_matrix),
  .result_block_row(result_block_row),.result_block_col(result_block_col),.result_op_tag(result_op_tag),
  .result_data(result_data),.result_block_valid(result_block_valid),.result_in_operation(result_in_operation),
  .result_allowed_ops(result_allowed_ops),.result_completed_ops(result_completed_ops));

 block_storage_dma_wide4 dut(
  .clk(clk),.rst_n(rst_n),.abort_scalar(done&&fault),.param_end(param_end),
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
  .dma_address(dma_address),.dma_beats(dma_beats),
  .dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),.dma_read_data(dma_read_data),.dma_read_index(dma_read_index),
  .dma_write_valid(dma_write_valid),.dma_write_ready(dma_write_ready),.dma_write_data(dma_write_data),
  .dma_write_strobe(dma_write_strobe),.dma_write_index(dma_write_index),
  .dma_done(dma_done),.dma_error(dma_error),.idle(storage_idle),.transactions(st_transactions),
  .read_blocks(st_reads),.write_blocks(st_writes),.error_transactions(st_errors),
  .read_wait_cycles(st_rwait),.write_wait_cycles(st_wwait),.scalar_cycles(st_scalar));

 // ---------------- deterministic 1 MiB DDR window ------------------------
 localparam DDR_BASE=32'h03000000;
 reg [127:0] mem[0:65535];
 reg [1:0] bstate;
 reg [31:0] b_addr;reg [15:0] b_beats,b_idx,wr_cnt;reg b_write;
 reg [31:0] b_seed;reg [63:0] c_hash;reg [31:0] c_base_bytes;
 function [7:0] pbyte(input [31:0] a);begin pbyte=a[7:0]^a[15:8]^a[23:16]^32'h5a;end endfunction
 function [7:0] peven(input [31:0] a);reg [7:0] b;begin b=pbyte(a);b[7]=^b[6:0];peven=b;end endfunction
 function [127:0] pat128(input [31:0] a);
  begin pat128={pbyte(a*16+15),pbyte(a*16+14),pbyte(a*16+13),pbyte(a*16+12),
                pbyte(a*16+11),pbyte(a*16+10),pbyte(a*16+9),pbyte(a*16+8),
                pbyte(a*16+7),pbyte(a*16+6),pbyte(a*16+5),pbyte(a*16+4),
                pbyte(a*16+3),pbyte(a*16+2),pbyte(a*16+1),pbyte(a*16)};end
 endfunction
 function [127:0] pat128_even(input [31:0] a);
  begin pat128_even={peven(a*16+15),peven(a*16+14),peven(a*16+13),peven(a*16+12),
                peven(a*16+11),peven(a*16+10),peven(a*16+9),peven(a*16+8),
                peven(a*16+7),peven(a*16+6),peven(a*16+5),peven(a*16+4),
                peven(a*16+3),peven(a*16+2),peven(a*16+1),peven(a*16)};end
 endfunction
 function [63:0] mix(input [63:0] h,input [63:0] v);begin mix=h*64'd33+v;end endfunction
 function [31:0] ddr_index(input [31:0] a);begin ddr_index=(a-DDR_BASE)>>4;end endfunction
 integer i;
 initial begin
  for(i=0;i<65536;i=i+1)mem[i]=128'h0;
  // A: 16-bit pattern, B: 8-bit pattern, C: zero (whole-word writes).
  for(i=0;i<512;i=i+1)mem[i]=pat128(i);
  for(i=0;i<256;i=i+1)mem[4096+i]=pat128_even(i+100000);
 end
 always @(negedge clk)begin
  if(!rst_n)begin
   bstate<=0;dma_request_ready<=1;dma_read_valid<=0;dma_write_ready<=0;dma_done<=0;dma_error<=0;
   b_idx<=0;wr_cnt<=0;dma_read_data<=0;dma_read_index<=0;dma_write_index<=0;c_hash<=0;
  end else begin
   dma_done<=0;
   case(bstate)
    0:begin
     dma_request_ready<=1;dma_read_valid<=0;dma_write_ready<=0;
     if(dma_request_valid&&dma_request_ready)begin
      b_addr<=dma_address;b_beats<=dma_beats;b_write<=dma_request_write;b_idx<=0;wr_cnt<=0;
      bstate<=dma_request_write?2:1;
     end
    end
    1:begin
     dma_request_ready<=0;
     if(!dma_read_valid)begin
      dma_read_data<=mem[ddr_index(b_addr)+b_idx];
      dma_read_index<=b_idx;dma_read_valid<=1;
     end else if(dma_read_ready)begin
      b_idx<=b_idx+1;
      if(b_idx+1==b_beats)begin dma_read_valid<=0;dma_done<=1;bstate<=0;end
      else begin dma_read_data<=mem[ddr_index(b_addr)+b_idx+1];dma_read_index<=b_idx+1;end
     end
    end
    2:begin
     dma_request_ready<=0;
     dma_write_ready<=1;
     if(dma_write_valid&&dma_write_ready)begin
      mem[ddr_index(b_addr)+dma_write_index]=dma_write_data;
      wr_cnt<=wr_cnt+1;dma_write_index<=dma_write_index+1;
      if(wr_cnt+1==b_beats)begin dma_done<=1;bstate<=0;end
     end
    end
   endcase
  end
 end

 // C result hash: sample the C region after completion.
 reg [1023:0] log_path;
 integer lg;
 always @(posedge clk)if(result_valid)result_count<=result_count+1;
 initial begin
  if(!$value$plusargs("log=%s",log_path))$fatal(1,"log");
  if($value$plusargs("m=%d",cfg_m))begin end
  if($value$plusargs("n=%d",cfg_n))begin end
  if($value$plusargs("k=%d",cfg_k))begin end
  lg=$fopen(log_path,"w");
  rst_n=0;repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  start=1;@(negedge clk);start=0;
  wait(done||fault);repeat(4)@(negedge clk);
  c_base_bytes=(cfg_c_base-DDR_BASE);
  c_hash=0;
  for(i=0;i<(((cfg_m+31)/32)*((cfg_n+31)/32)*6144)/16;i=i+1)
   c_hash=mix(c_hash,mem[(c_base_bytes>>4)+i]);
  $fwrite(lg,"BLOCK m=%0d n=%0d k=%0d done=%0d fault=%0d err=%02h result_count=%0d read=%0d write=%0d hit=%0d miss=%0d st_err=%0d c_hash=%016h\n",
   cfg_m,cfg_n,cfg_k,done,fault,error_code,result_count,read_blocks,write_blocks,cache_hits,cache_misses,st_errors,c_hash);
  $fclose(lg);$display("BLOCK_DONE m=%0d n=%0d k=%0d fault=%0d err=%02h c_hash=%016h",cfg_m,cfg_n,cfg_k,fault,error_code,c_hash);$finish;
 end
endmodule
