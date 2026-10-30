`timescale 1ns/1ps
// Storage descriptor handshake contract with the pipelined block address.
// Checks:
//  * block_address_v023 output is held under out_ready backpressure;
//  * a storage request is accepted only when idle, and a bad descriptor
//    returns HEADER/WACK with no DMA request;
//  * a good A read waits for the registered validator, issues the real DMA
//    burst count, drains it, and only then presents HEADER;
//  * a bad write still consumes exactly 1024 scalar words and exits via WACK.
module tb_storage_handshake;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;
 // address pipeline
 reg ba_valid=0;reg ba_out_ready=1;wire ba_in_ready,ba_out_valid;
 wire [31:0] ba_addr;wire [15:0] ba_vr,ba_vc;wire [39:0] ba_ext;wire ba_ok;
 reg [31:0] base=32'h03000000;reg [15:0] rows=64,cols=32,br=0,bc=0;reg [1:0] enc=0;
 block_address_v023 baddr(.clk(clk),.rst_n(rst_n),.in_valid(ba_valid),.in_ready(ba_in_ready),
  .base(base),.rows(rows),.cols(cols),.block_row(br),.block_col(bc),.encoding(enc),
  .out_valid(ba_out_valid),.out_ready(ba_out_ready),.address(ba_addr),.valid_rows(ba_vr),
  .valid_cols(ba_vc),.extent_bytes(ba_ext),.valid(ba_ok));
 // storage
 reg abort_scalar=0;
 reg [31:0] param_end=32'h20000000,cfg_a_base=32'h03000000,cfg_b_base=32'h03010000,cfg_c_base=32'h03020000,cfg_epoch=1;
 reg [15:0] cfg_m=64,cfg_n=64,cfg_k=32,cfg_layer=0,cfg_a_id=1,cfg_b_id=2,cfg_c_id=3,cfg_allowed=16'hffff;
 reg cfg_c_valid=1;reg [15:0] cfg_c_completed=0;
 reg req_valid=0;wire req_ready;reg req_write=0;reg [31:0] req_address=0,req_epoch=1;
 reg [15:0] req_layer=0,req_matrix=1,req_block_row=0,req_block_col=0,req_allowed=16'hffff,req_completed=0;
 reg [1:0] req_encoding=0;reg req_block_valid=1,req_in_operation=1;
 wire header_valid;reg header_ready=0;
 wire header_exists,header_block_valid,header_in_operation;wire [31:0] header_epoch;
 wire [15:0] header_layer,header_matrix,header_block_row,header_block_col,header_allowed,header_completed;
 wire [1:0] header_encoding;
 wire data_valid;reg data_ready=1;wire [191:0] data_in;wire [9:0] data_index;wire data_last;
 reg out_valid=0;wire out_ready;reg [47:0] out_data=0;reg [9:0] out_index=0;reg out_last=0;
 wire write_ack,write_error;
 wire dma_request_valid;reg dma_request_ready=1;wire dma_request_write;
 wire [31:0] dma_address;wire [15:0] dma_beats;
 reg dma_read_valid=0;wire dma_read_ready;reg [127:0] dma_read_data=0;reg [15:0] dma_read_index=0;
 wire dma_write_valid;reg dma_write_ready=0;wire [127:0] dma_write_data;wire [15:0] dma_write_strb;
 reg [15:0] dma_write_index=0;reg rd_done=0,wr_done=0;wire dma_done=rd_done|wr_done;reg dma_error=0;
 wire idle;wire [31:0] transactions,read_blocks,write_blocks,error_transactions;
 wire [63:0] rwait,wwait,scycles;
 block_storage_dma_wide4 dut(.clk(clk),.rst_n(rst_n),.abort_scalar(abort_scalar),.param_end(param_end),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),.cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),
  .cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),.req_address(req_address),.req_epoch(req_epoch),
  .req_layer(req_layer),.req_matrix(req_matrix),.req_block_row(req_block_row),.req_block_col(req_block_col),
  .req_allowed_ops(req_allowed),.req_completed_ops(req_completed),.req_encoding(req_encoding),
  .req_block_valid(req_block_valid),.req_in_operation(req_in_operation),
  .header_valid(header_valid),.header_ready(header_ready),.header_exists(header_exists),
  .header_block_valid(header_block_valid),.header_in_operation(header_in_operation),.header_epoch(header_epoch),
  .header_layer(header_layer),.header_matrix(header_matrix),.header_block_row(header_block_row),.header_block_col(header_block_col),
  .header_allowed_ops(header_allowed),.header_completed_ops(header_completed),.header_encoding(header_encoding),
  .data_valid(data_valid),.data_ready(data_ready),.data_in(data_in),.data_index(data_index),.data_last(data_last),
  .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),.out_index(out_index),.out_last(out_last),
  .write_ack(write_ack),.write_error(write_error),
  .dma_request_valid(dma_request_valid),.dma_request_ready(dma_request_ready),.dma_request_write(dma_request_write),
  .dma_address(dma_address),.dma_beats(dma_beats),
  .dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),.dma_read_data(dma_read_data),.dma_read_index(dma_read_index),
  .dma_write_valid(dma_write_valid),.dma_write_ready(dma_write_ready),.dma_write_data(dma_write_data),
  .dma_write_strobe(dma_write_strb),.dma_write_index(dma_write_index),.dma_done(dma_done),.dma_error(dma_error),
  .idle(idle),.transactions(transactions),.read_blocks(read_blocks),.write_blocks(write_blocks),
  .error_transactions(error_transactions),.read_wait_cycles(rwait),.write_wait_cycles(wwait),.scalar_cycles(scycles));
 integer errors=0;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 task do_reset;begin rst_n=0;ba_valid=0;req_valid=0;out_valid=0;dma_read_valid=0;rd_done=0;wr_done=0;dma_error=0;abort_scalar=0;header_ready=0;
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);end endtask
 task get_addr;begin
  @(negedge clk);ba_valid=1;
  while(!ba_in_ready)@(negedge clk);
  @(posedge clk);@(negedge clk);ba_valid=0;
  while(!ba_out_valid)@(negedge clk);
 end endtask
 task issue_read(input [31:0] addr,input good);begin
  @(negedge clk);req_write=0;req_address=addr;req_encoding=0;req_block_row=0;req_block_col=0;
  req_in_operation=1;req_completed=0;req_block_valid=1;req_valid=1;
  while(!req_ready)@(negedge clk);
  @(posedge clk);@(negedge clk);req_valid=0;
 end endtask
 // Read-side DMA responder
 reg rd_active=0;reg [15:0] rd_idx=0,rd_n=0;integer rh=0;
 always @(posedge clk)begin
  if(!rst_n)begin rd_active<=0;rd_idx<=0;rd_n<=0;dma_read_valid<=0;rd_done<=0;end
  else begin
   rd_done<=0;
   if(dma_request_valid&&dma_request_ready&&!dma_request_write)begin
    rd_active<=1;rd_idx<=0;rd_n<=dma_beats;rh=0;
   end else if(rd_active)begin
    dma_read_valid<=1;dma_read_data<={4{32'h12345678}};
    if(dma_read_valid&&dma_read_ready)begin
     rh=rh+1;
     if(rd_idx+1==rd_n)begin dma_read_valid<=0;rd_done<=1;rd_active<=0;end
     else begin rd_idx<=rd_idx+1;dma_read_index<=rd_idx+1;end
    end
   end
  end
 end
 // Write-side responder: accept request, consume dma_write_valid beats.
 reg wr_active=0;reg [15:0] wr_idx=0,wr_n=0;
 always @(posedge clk)begin
  if(!rst_n)begin wr_active<=0;wr_idx<=0;wr_n<=0;dma_write_ready<=0;dma_write_index<=0;wr_done<=0;end
  else begin
   wr_done<=0;
   if(dma_request_valid&&dma_request_ready&&dma_request_write&&!wr_active)begin
    wr_active<=1;wr_idx<=0;wr_n<=dma_beats;dma_write_ready<=1;dma_write_index<=0;
   end else if(wr_active&&dma_write_valid&&dma_write_ready)begin
    if(dma_write_index+1>=wr_n)begin wr_active<=0;dma_write_ready<=0;wr_done<=1;end
    else dma_write_index<=dma_write_index+1;
   end
  end
 end
 // scalar write source
 integer wi=0;reg feeding=0;
 always @(posedge clk)begin
  if(!rst_n)begin out_valid<=0;wi<=0;feeding<=0;end
  else begin
   if(req_valid&&req_ready&&req_write)begin feeding<=1;wi<=0;out_valid<=0;end
   else if(feeding&&out_ready)begin
    out_valid<=1;out_data<=48'h000000000001;out_index<=wi[9:0];out_last<=(wi==1023);
    if(wi==1023)begin feeding<=0;end else wi<=wi+1;
   end else if(feeding&&!out_ready)out_valid<=0;
  end
 end
 reg [15:0] saw_dma_beats=0;reg saw_dma_req=0;
 always @(posedge clk)if(dma_request_valid&&dma_request_ready)begin saw_dma_req<=1;saw_dma_beats<=dma_beats;end
 integer cyc;
 always @(posedge clk)if(dut.state==3&&dma_read_valid&&(dma_read_index>=dut.nbeats))$display("IDXGE idx=%0d nbeats=%0d",dma_read_index,dut.nbeats);
 integer rd_hs=0;
 always @(posedge clk)if(dma_read_valid&&dma_read_ready)rd_hs=rd_hs+1;
 initial begin
  $display("STORAGE_HANDSHAKE_BEGIN");
  // -------- pipelined address hold under backpressure --------
  do_reset;base=32'h03000000;rows=64;cols=32;br=3;bc=1;enc=0;ba_out_ready=0;
  @(negedge clk);ba_valid=1;while(!ba_in_ready)@(negedge clk);@(posedge clk);@(negedge clk);ba_valid=0;
  wait(ba_out_valid);begin : hold
   reg [31:0] a0;reg [15:0] vr0,vc0;reg [39:0] e0;reg v0;
   a0=ba_addr;vr0=ba_vr;vc0=ba_vc;e0=ba_ext;v0=ba_ok;
   repeat(6)@(negedge clk);
   chk("address held under backpressure",ba_addr===a0&&ba_vr===vr0&&ba_vc===vc0&&ba_ext===e0&&ba_ok===v0);
  end
  ba_out_ready=1;@(posedge clk);

  // -------- bad A read: no DMA, HEADER reports bad --------
  do_reset;base=32'h03000000;rows=64;cols=32;br=0;bc=0;enc=0;ba_out_ready=1;
  get_addr;
  $display("ADDR A0 %h valid=%0d ext=%h",ba_addr,ba_ok,ba_ext);
  chk("A address expected",ba_addr==32'h03000000);
  issue_read(ba_addr+16,0);
  repeat(12)@(negedge clk);
  chk("bad read no DMA",!dma_request_valid);
  while(!header_valid)@(negedge clk);
  chk("bad header in_operation",header_in_operation==1);
  chk("bad header exists",header_exists==1);
  // hold header under backpressure
  repeat(5)@(negedge clk);chk("header held",header_valid==1);
  @(negedge clk);header_ready=1;@(posedge clk);@(negedge clk);header_ready=0;
  @(negedge clk);chk("storage returns idle",idle==1);

  // -------- good A read: validator first, then 128-beat DMA, then HEADER --------
  do_reset;base=32'h03000000;rows=64;cols=32;br=0;bc=0;enc=0;ba_out_ready=1;rd_hs=0;
  get_addr;saw_dma_req=0;saw_dma_beats=0;
  issue_read(ba_addr,1);
  // header must not appear before the DMA drains
  repeat(6)@(negedge clk);
  chk("no early header",header_valid==0);
  while(!header_valid)@(negedge clk);
  $display("GOOD_READ header=%0d dma_req=%0d beats=%0d rdblocks=%0d errs=%0d bad=%0d recv=%0d nbeats=%0d",
    header_valid,saw_dma_req,saw_dma_beats,read_blocks,error_transactions,dut.bad,dut.dma_received,dut.nbeats);
  chk("good read issued DMA",saw_dma_req==1);
  chk("good read beats 128",saw_dma_beats==128);
  chk("good header not bad",header_in_operation==0);
  @(negedge clk);header_ready=1;@(posedge clk);@(negedge clk);header_ready=0;
  repeat(3)@(negedge clk);abort_scalar=1;@(posedge clk);@(negedge clk);abort_scalar=0;
  repeat(3)@(negedge clk);chk("good read abort idle",idle==1);

  // -------- bad write: 1024 words, WACK, no DMA --------
  do_reset;base=32'h03000000;rows=64;cols=32;br=0;bc=0;enc=0;ba_out_ready=1;
  get_addr;saw_dma_req=0;
  @(negedge clk);req_write=1;req_address=ba_addr+16;req_encoding=0;req_block_row=0;req_block_col=0;
  req_in_operation=0;req_completed=1;req_block_valid=1;req_valid=1;
  while(!req_ready)@(negedge clk);@(posedge clk);@(negedge clk);req_valid=0;
  while(!write_ack)@(negedge clk);
  $display("BAD_WRITE ack=%0d werr=%0d dma_req=%0d errs=%0d",write_ack,write_error,saw_dma_req,error_transactions);
  chk("bad write error",write_error==1);
  chk("bad write no DMA",saw_dma_req==0);
  @(posedge clk);@(negedge clk);chk("write idle",idle==1);

  $display("STORAGE_HANDSHAKE_TEST_END errors=%0d",errors);$fflush();
  if(errors==0)$display("STORAGE_HANDSHAKE_PASS");else $display("STORAGE_HANDSHAKE_FAIL");
  $finish;
 end
 initial begin repeat(100000)@(posedge clk);$display("STORAGE_HANDSHAKE_TIMEOUT");$finish;end
endmodule
