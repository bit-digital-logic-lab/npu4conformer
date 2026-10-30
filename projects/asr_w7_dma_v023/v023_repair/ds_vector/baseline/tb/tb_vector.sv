`timescale 1ns/1ps
// Transactional DMA BFM, NOT AXI timing or real DDR performance evidence.
module tb_vector;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;reg [511:0] descriptor=0;reg [31:0] param_end=32'h20000000;
 wire ready,busy,done,fault;wire [7:0] error_code,numeric_flags;
 wire [31:0] completed_elements,rejected_starts;
 wire [63:0] cycles,read_compute_overlap,write_compute_overlap;
 wire rd_request_valid,rd_request_ready,rd_valid,rd_ready,rd_done,rd_error;
 wire [31:0] rd_address;wire [15:0] rd_beats,rd_index;wire [127:0] rd_data;
 wire wr_request_valid,wr_request_ready,wr_valid,wr_ready,wr_done,wr_error;
 wire [31:0] wr_address;wire [15:0] wr_beats,wr_strobe;wire [127:0] wr_data;
 ddr_vector_engine dut(.*);
 reg [7:0] memory[0:262143],gold[0:4095];reg [31:0] desc_words[0:15];
 integer mode=0,nbytes,cycle=0,read_requests=0,write_requests=0;
 reg ractive=0,wactive=0,rcomplete=0,wcomplete=0;
 reg [31:0] raddr,waddr;reg [15:0] ri=0,wi=0,rbeats,wbeats;
 integer rp=0,wp=0;reg error_r=0,error_w=0;
 assign rd_request_ready=!ractive&&rp==0&&!rcomplete;
 assign rd_valid=ractive&&cycle%5!=0;
 assign rd_index=ri;assign rd_done=rcomplete;assign rd_error=error_r;
 assign wr_request_ready=!wactive&&wp==0&&!wcomplete;
 assign wr_ready=wactive&&cycle%7!=0;
 assign wr_done=wcomplete;assign wr_error=error_w;
 function automatic integer offset(input [31:0] a);
  begin if(a<32'h04000000||a>=32'h04040000)$fatal(1,"BFM invalid address %h",a);offset=a-32'h04000000;end
 endfunction
 for(genvar lane=0;lane<16;lane=lane+1)assign rd_data[lane*8+:8]=memory[offset(raddr)+ri*16+lane];
 reg held=0;reg [127:0] held_data;reg [15:0] held_strobe;
 always @(posedge clk)if(rst_n)begin
  cycle<=cycle+1;rcomplete<=0;wcomplete<=0;
  if(held&&(!wr_valid||wr_data!==held_data||wr_strobe!==held_strobe))$fatal(1,"Write changed under backpressure");
  held<=wr_valid&&!wr_ready;held_data<=wr_data;held_strobe<=wr_strobe;
  if(rd_request_valid&&rd_request_ready)begin
   if(rd_address[3:0]||rd_beats==0||rd_beats>96)$fatal(1,"Read framing");
   ractive<=1;ri<=0;raddr<=rd_address;rbeats<=rd_beats;read_requests<=read_requests+1;
   error_r<=mode==7&&read_requests==0;
  end
  if(rd_valid&&rd_ready)begin
   if(ri+1==rbeats)begin ractive<=0;rp<=2;end else ri<=ri+1;
  end
  if(rp>0)begin rp<=rp-1;if(rp==1)rcomplete<=1;end
  if(wr_request_valid&&wr_request_ready)begin
   if(wr_address[3:0]||wr_beats==0||wr_beats>64)$fatal(1,"Write framing");
   wactive<=1;wi<=0;waddr<=wr_address;wbeats<=wr_beats;write_requests<=write_requests+1;
   error_w<=mode==8&&write_requests==0;
  end
  if(wr_valid&&wr_ready)begin
   for(integer lane=0;lane<16;lane=lane+1)if(wr_strobe[lane])memory[offset(waddr)+wi*16+lane]<=wr_data[lane*8+:8];
   if(wi+1==wbeats)begin wactive<=0;wp<=3;end else wi<=wi+1;
  end
  if(wp>0)begin wp<=wp-1;if(wp==1)wcomplete<=1;end
  if(cycle>300000)$fatal(1,"Vector watchdog ls=%d cs=%d ws=%d completed=%d",dut.ls,dut.cs,dut.ws,completed_elements);
 end
 reg [4095:0] folder;
 initial begin
  if(!$value$plusargs("folder=%s",folder)||!$value$plusargs("nbytes=%d",nbytes))$fatal(1,"Arguments");
  if($value$plusargs("mode=%d",mode))begin end
  $readmemh({folder,"/memory.hex"},memory);$readmemh({folder,"/gold.hex"},gold,0,nbytes-1);
  $readmemh({folder,"/descriptor.hex"},desc_words);
  for(integer j=0;j<16;j=j+1)descriptor[j*32+:32]=desc_words[j];
  case(mode)
   1:descriptor[191:160]=32'h10000000;
   2:descriptor[95:64]=32'h02000000;
   3:descriptor[223:192]=32'hffffffff;
   4:descriptor[191:160]=descriptor[95:64];
   5:descriptor[511]=1;
   6:descriptor[39:32]=19;
  endcase
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  if(mode==9)begin repeat(20)@(negedge clk);start=1;@(negedge clk);start=0;end
  wait(done);@(negedge clk);
  if(ractive||wactive||rp||wp)$fatal(1,"DONE before DMA drain");
  if(mode>=1&&mode<=8)begin
   if(!fault)$fatal(1,"Expected failure mode=%d",mode);
   if(mode<=6&&(read_requests||write_requests))$fatal(1,"ACL failure had side effects");
  end else begin
   if(fault||completed_elements!=1001||numeric_flags&7)$fatal(1,"Numerical job failed %d flags=%h",error_code,numeric_flags);
   for(integer j=0;j<nbytes;j=j+1)if(memory[65536+j]!==gold[j])$fatal(1,"Output mismatch byte=%d got=%h expected=%h",j,memory[65536+j],gold[j]);
   for(integer j=nbytes;j<nbytes+32;j=j+1)if(memory[65536+j]!==8'ha5)$fatal(1,"Tail byte overwritten");
   if(read_compute_overlap==0||write_compute_overlap==0)$fatal(1,"No ping-pong overlap");
   if(mode==9&&rejected_starts!=1)$fatal(1,"Busy start overwritten job");
  end
  $display("V022_VECTOR_PASS mode=%d cycles=%d read_compute_overlap=%d write_compute_overlap=%d read_requests=%d write_requests=%d",mode,cycles,read_compute_overlap,write_compute_overlap,read_requests,write_requests);
  $finish;
 end
endmodule
