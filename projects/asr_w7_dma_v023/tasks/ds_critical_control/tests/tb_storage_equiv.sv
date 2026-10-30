`timescale 1ns/1ps
// Protocol-level equivalence harness for block_storage_dma_wide4.
// Same stimulus + same DMA BFM for original and candidate.  The log contains
// transaction outcomes only (header fields, data hash, DMA address/beats/data
// hash, ACK/error, abort/reset), not cycle counts, so added validation
// latency does not create a false mismatch.
module tb_storage_equiv;
 localparam B_IDLE=0,B_RD=1,B_WR=2;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,abort_scalar=0;
 reg [31:0] param_end=32'h20000000;
 reg [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch;
 reg [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,cfg_allowed,cfg_c_completed;
 reg cfg_c_valid;
 reg req_valid=0,req_write=0;
 wire req_ready;
 reg [31:0] req_address=0,req_epoch=0;
 reg [15:0] req_layer=0,req_matrix=0,req_block_row=0,req_block_col=0,req_allowed_ops=0,req_completed_ops=0;
 reg [1:0] req_encoding=0;reg req_block_valid=0,req_in_operation=0;
 wire header_valid;reg header_ready=0;
 wire header_exists,header_block_valid,header_in_operation;
 wire [31:0] header_epoch;
 wire [15:0] header_layer,header_matrix,header_block_row,header_block_col,header_allowed_ops,header_completed_ops;
 wire [1:0] header_encoding;
 wire data_valid;reg data_ready=0;wire [191:0] data_in;wire [9:0] data_index;wire data_last;
 reg out_valid=0;wire out_ready;reg [47:0] out_data=0;reg [9:0] out_index=0;reg out_last=0;
 wire write_ack,write_error;
 wire dma_request_valid;reg dma_request_ready=0;wire dma_request_write;
 wire [31:0] dma_address;wire [15:0] dma_beats;
 reg dma_read_valid=0;wire dma_read_ready;reg [127:0] dma_read_data=0;reg [15:0] dma_read_index=0;
 wire dma_write_valid;reg dma_write_ready=0;wire [127:0] dma_write_data;wire [15:0] dma_write_strobe;
 reg [15:0] dma_write_index=0;
 reg dma_done=0,dma_error=0;
 wire idle;
 wire [31:0] transactions,read_blocks,write_blocks,error_transactions;
 wire [63:0] read_wait_cycles,write_wait_cycles,scalar_cycles;

 block_storage_dma_wide4 dut(
  .clk(clk),.rst_n(rst_n),.abort_scalar(abort_scalar),.param_end(param_end),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),
  .cfg_a_id(cfg_a_id),.cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_allowed(cfg_allowed),
  .cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),
  .req_address(req_address),.req_epoch(req_epoch),
  .req_layer(req_layer),.req_matrix(req_matrix),.req_block_row(req_block_row),.req_block_col(req_block_col),
  .req_allowed_ops(req_allowed_ops),.req_completed_ops(req_completed_ops),
  .req_encoding(req_encoding),.req_block_valid(req_block_valid),.req_in_operation(req_in_operation),
  .header_valid(header_valid),.header_ready(header_ready),.header_exists(header_exists),
  .header_block_valid(header_block_valid),.header_in_operation(header_in_operation),
  .header_epoch(header_epoch),.header_layer(header_layer),.header_matrix(header_matrix),
  .header_block_row(header_block_row),.header_block_col(header_block_col),
  .header_allowed_ops(header_allowed_ops),.header_completed_ops(header_completed_ops),
  .header_encoding(header_encoding),
  .data_valid(data_valid),.data_ready(data_ready),.data_in(data_in),.data_index(data_index),.data_last(data_last),
  .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),.out_index(out_index),.out_last(out_last),
  .write_ack(write_ack),.write_error(write_error),
  .dma_request_valid(dma_request_valid),.dma_request_ready(dma_request_ready),.dma_request_write(dma_request_write),
  .dma_address(dma_address),.dma_beats(dma_beats),
  .dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),.dma_read_data(dma_read_data),.dma_read_index(dma_read_index),
  .dma_write_valid(dma_write_valid),.dma_write_ready(dma_write_ready),.dma_write_data(dma_write_data),
  .dma_write_strobe(dma_write_strobe),.dma_write_index(dma_write_index),
  .dma_done(dma_done),.dma_error(dma_error),
  .idle(idle),.transactions(transactions),.read_blocks(read_blocks),.write_blocks(write_blocks),
  .error_transactions(error_transactions),.read_wait_cycles(read_wait_cycles),
  .write_wait_cycles(write_wait_cycles),.scalar_cycles(scalar_cycles));

 always @* header_ready=header_valid;

 function [31:0] prand(input [31:0] s,input [31:0] i);
  reg [31:0] x;begin
   x=s^(i*32'h9e3779b9);x=x^(x>>16);x=x*32'h7feb352d;x=x^(x>>15);x=x*32'h846ca68b;x=x^(x>>16);prand=x;
  end
 endfunction
 function [127:0] dpat(input [31:0] a,input [15:0] i,input [31:0] s);
  begin dpat={a^(s*32'h9e3779b9),{16'd0,i},16'ha5a5,a[15:0]^{16'd0,i},32'h5a5a5a5a};end
 endfunction
 function [47:0] opat(input [15:0] i,input [31:0] s);
  begin opat={s[15:0]^i,i,i[15:0]^s[31:16]};end
 endfunction
 function [63:0] mix(input [63:0] h,input [63:0] v);
  begin mix=h*64'd33+v;end
 endfunction

 // Stimulus fields (declared before the BFM that reads g_flags).
 reg [31:0] g_write,g_enc,g_req_addr,g_req_epoch,g_req_layer,g_req_matrix,g_req_row,g_req_col;
 reg [31:0] g_req_allowed,g_req_completed,g_block_valid,g_in_op;
 reg [31:0] g_a_base,g_b_base,g_c_base,g_cfg_epoch,g_m,g_n,g_k,g_cfg_layer,g_a_id,g_b_id,g_c_id,g_cfg_allowed;
 reg [31:0] g_c_valid,g_c_completed,g_param_end,g_flags,g_seed,g_reserved;
 reg [1:0] bstate;
 reg [31:0] b_addr,b_seed,bfm_cnt;reg [15:0] b_beats,b_idx,wr_count;
 reg b_write;
 reg [63:0] rd_hash,wr_hash;
 reg [31:0] dma_req_count;
 reg [63:0] dma_addr_hash,dma_beats_hash;
 always @(negedge clk)begin
  if(!rst_n)begin
   bstate<=B_IDLE;dma_request_ready<=1;dma_read_valid<=0;dma_write_ready<=0;dma_done<=0;dma_error<=0;
   b_idx<=0;wr_count<=0;rd_hash<=0;wr_hash<=0;dma_req_count<=0;dma_addr_hash<=0;dma_beats_hash<=0;
   dma_read_data<=0;dma_read_index<=0;dma_write_index<=0;bfm_cnt<=0;
  end else begin
   dma_done<=0;bfm_cnt<=bfm_cnt+1;
   case(bstate)
    B_IDLE:begin
     dma_request_ready<=1;dma_read_valid<=0;dma_write_ready<=0;
     if(dma_request_valid&&dma_request_ready)begin
      b_addr<=dma_address;b_seed<=g_seed;b_beats<=dma_beats;b_write<=dma_request_write;b_idx<=0;wr_count<=0;
      dma_req_count<=dma_req_count+1;
      dma_addr_hash<=mix(dma_addr_hash,{32'd0,dma_address});
      dma_beats_hash<=mix(dma_beats_hash,{48'd0,dma_beats});
      rd_hash<=0;wr_hash<=0;
      bstate<=dma_request_write?B_WR:B_RD;
     end
    end
    B_RD:begin
     dma_request_ready<=0;
     if(!dma_read_valid)begin
      dma_read_data<=dpat(b_addr,b_idx,b_seed);
      dma_read_index<=(g_flags[1]&&b_idx==16'd3)?(b_idx+16'd1):b_idx;
      dma_read_valid<=1;
      if(g_flags[0]&&b_idx==16'd2)dma_error<=1;
     end else if(dma_read_ready)begin
      rd_hash<=mix(rd_hash,{64'd0,dma_read_data[63:0]})^mix(rd_hash,dma_read_data[127:64]);
      b_idx<=b_idx+1;
      if(b_idx+1==b_beats)begin
       dma_read_valid<=0;dma_done<=1;dma_error<=g_flags[0]?1'b1:1'b0;bstate<=B_IDLE;
      end else begin
       dma_read_data<=dpat(b_addr,b_idx+1,b_seed);
       dma_read_index<=(g_flags[1]&&(b_idx+1)==16'd3)?(b_idx+16'd2):(b_idx+1);
      end
     end
    end
    B_WR:begin
     dma_request_ready<=0;
     dma_write_ready<=(!g_flags[11])||((prand(b_seed,bfm_cnt)&32'd1)!=0);
     if(dma_write_valid&&dma_write_ready)begin
      dma_write_index<=dma_write_index+1;
      wr_hash<=mix(wr_hash,{64'd0,dma_write_data[63:0]})^mix(wr_hash,dma_write_data[127:64]);
      wr_count<=wr_count+1;
      if(g_flags[6]&&wr_count==(b_beats>>1))begin
       dma_done<=1;dma_error<=1;bstate<=B_IDLE;
      end else if(wr_count+1==b_beats)begin
       dma_done<=1;dma_error<=0;bstate<=B_IDLE;
      end
     end
    end
   endcase
  end
 end

 integer fd,lg,case_no,nscan;
 reg [1023:0] stim_path,log_path;

 task automatic drive_defaults;
  begin
   cfg_a_base=g_a_base;cfg_b_base=g_b_base;cfg_c_base=g_c_base;cfg_epoch=g_cfg_epoch;
   cfg_m=g_m[15:0];cfg_n=g_n[15:0];cfg_k=g_k[15:0];cfg_layer=g_cfg_layer[15:0];
   cfg_a_id=g_a_id[15:0];cfg_b_id=g_b_id[15:0];cfg_c_id=g_c_id[15:0];cfg_allowed=g_cfg_allowed[15:0];
   cfg_c_valid=g_c_valid[0];cfg_c_completed=g_c_completed[15:0];param_end=g_param_end;
   req_write=g_write[0];req_encoding=g_enc[1:0];req_address=g_req_addr;req_epoch=g_req_epoch;
   req_layer=g_req_layer[15:0];req_matrix=g_req_matrix[15:0];req_block_row=g_req_row[15:0];
   req_block_col=g_req_col[15:0];req_allowed_ops=g_req_allowed[15:0];req_completed_ops=g_req_completed[15:0];
   req_block_valid=g_block_valid[0];req_in_operation=g_in_op[0];
  end
 endtask

 task automatic do_reset;
  begin
   rst_n=0;abort_scalar=0;req_valid=0;data_ready=0;out_valid=0;
   repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  end
 endtask

 integer dcount,acount,widx,errdelta,hdr_seen,aborted,reset_mid,stall_cnt;
 reg [63:0] dat_hash;reg [15:0] dat_beats;
 reg hdr_exists_r,hdr_bvalid_r,hdr_bad_r,hdr_enc_r;
 reg [31:0] hdr_epoch_r;reg [15:0] hdr_layer_r,hdr_matrix_r,hdr_row_r,hdr_col_r,hdr_allowed_r,hdr_completed_r;
 reg ack_seen,ack_err_r;

 task automatic run_case;
  begin
   case_no=case_no+1;
   do_reset();drive_defaults();
   if(g_flags[7])begin
    repeat(3)@(negedge clk);   // delayed request, no premature acceptance
   end
   @(negedge clk);req_valid=1;
   while(!req_ready)@(negedge clk);
   @(posedge clk);#1;       // request accepted here
   @(negedge clk);req_valid=0;
   hdr_seen=0;dat_hash=0;dat_beats=0;ack_seen=0;ack_err_r=0;errdelta=0;aborted=0;reset_mid=0;
   hdr_exists_r=0;hdr_bvalid_r=0;hdr_bad_r=0;hdr_enc_r=0;hdr_epoch_r=0;hdr_layer_r=0;hdr_matrix_r=0;
   hdr_row_r=0;hdr_col_r=0;hdr_allowed_r=0;hdr_completed_r=0;
   if(g_write[0])begin : wr_case
    widx=0;out_valid<=0;
    while(widx<1024)begin
     @(negedge clk);
     if(out_ready)begin
      out_valid<=1;out_data<=opat(widx[15:0],g_seed);
      out_index<=(g_flags[2]&&widx==100)?10'd101:widx[9:0];
      out_last<=(g_flags[3]&&widx==1023)?1'b0:(widx==1023);
      widx=widx+1;
      if(g_flags[9]&&widx==100)begin rst_n<=0;reset_mid=1;disable wr_case;end
     end
    end
    @(negedge clk);out_valid<=0;
    while(!write_ack)@(negedge clk);
    ack_seen=1;ack_err_r=write_error;
    while(!idle)@(negedge clk);
   end else begin : rd_case
    while(!header_valid)@(negedge clk);
    hdr_seen=1;hdr_exists_r=header_exists;hdr_bvalid_r=header_block_valid;hdr_bad_r=header_in_operation;
    hdr_epoch_r=header_epoch;hdr_layer_r=header_layer;hdr_matrix_r=header_matrix;
    hdr_row_r=header_block_row;hdr_col_r=header_block_col;hdr_allowed_r=header_allowed_ops;
    hdr_completed_r=header_completed_ops;hdr_enc_r=header_encoding[0];
    if(g_flags[4])begin
     abort_scalar<=1;aborted=1;@(posedge clk);@(negedge clk);abort_scalar<=0;
     while(!idle)@(negedge clk);
     disable rd_case;
    end
    @(posedge clk); // header handshake
    if(!hdr_bad_r&&hdr_exists_r)begin : data_loop
     dcount=0;stall_cnt=0;
     while(dcount<256)begin
      stall_cnt=stall_cnt+1;
      data_ready=(!g_flags[10])||((prand(g_seed,stall_cnt)&32'd1)!=0);
      @(posedge clk);
      if(data_valid&&data_ready)begin
       dat_hash<=mix(dat_hash,{16'd0,data_in[63:0]})^mix(dat_hash,{16'd0,data_in[127:64]})^mix(dat_hash,{16'd0,data_in[191:128]});
       dat_beats<=dat_beats+1;dcount=dcount+1;
       if(g_flags[5]&&dcount==5)begin abort_scalar=1;aborted=1;end
       if(g_flags[8]&&dcount==8)begin rst_n=0;reset_mid=1;end
      end
      @(negedge clk);
      if(aborted||reset_mid)begin abort_scalar=0;disable data_loop;end
     end
     data_ready<=0;
    end
    while(!idle)@(negedge clk);
   end
   while(!idle)@(negedge clk);
   errdelta=error_transactions;
   $fwrite(lg,"CASE %0d write=%0d enc=%0d addr=%08h hdr=%0d exists=%0d bvalid=%0d bad=%0d henc=%0d hep=%08h hlay=%04h hmat=%04h hrow=%04h hcol=%04h hall=%04h hcmp=%04h data_beats=%0d data_hash=%016h ack=%0d ackerr=%0d abort=%0d reset=%0d dma_req=%0d dma_addr=%016h dma_beats=%016h rd_hash=%016h wr_hash=%016h wr_count=%04h errcnt=%0d idle=%0d\n",
      case_no,g_write[0],g_enc[1:0],g_req_addr,hdr_seen,hdr_exists_r,hdr_bvalid_r,hdr_bad_r,hdr_enc_r,
      hdr_epoch_r,hdr_layer_r,hdr_matrix_r,hdr_row_r,hdr_col_r,hdr_allowed_r,hdr_completed_r,
      dat_beats,dat_hash,ack_seen,ack_err_r,aborted,reset_mid,dma_req_count,dma_addr_hash,dma_beats_hash,
      rd_hash,wr_hash,wr_count,errdelta,idle);
  end
 endtask

 initial begin
  if(!$value$plusargs("stim=%s",stim_path))$fatal(1,"stim");
  if(!$value$plusargs("log=%s",log_path))$fatal(1,"log");
  fd=$fopen(stim_path,"r");lg=$fopen(log_path,"w");
  if(fd==0||lg==0)$fatal(1,"files");
  case_no=0;rst_n=0;
  while(!$feof(fd))begin
   nscan=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
    g_write,g_enc,g_req_addr,g_req_epoch,g_req_layer,g_req_matrix,g_req_row,g_req_col,
    g_req_allowed,g_req_completed,g_block_valid,g_in_op,g_a_base,g_b_base,g_c_base,g_cfg_epoch,
    g_m,g_n,g_k,g_cfg_layer,g_a_id,g_b_id,g_c_id,g_cfg_allowed,g_c_valid,g_c_completed,g_param_end,
    g_flags,g_seed,g_reserved);
   if(nscan==30)run_case();
  end
  $fclose(lg);$fclose(fd);$display("STORAGE_EQUIV_DONE cases=%0d",case_no);$finish;
 end
endmodule
