`timescale 1ns/1ps
module tb_plan_csr;
 reg clk=0;always #4 clk=~clk;reg rst_n=0;
 reg [23:0] s_axi_awaddr=0,s_axi_araddr=0;
 reg s_axi_awvalid=0,s_axi_wvalid=0,s_axi_bready=0,s_axi_arvalid=0,s_axi_rready=0;
 reg [31:0] s_axi_wdata=0;reg [3:0] s_axi_wstrb=15;
 wire s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid;
 wire [1:0] s_axi_bresp,s_axi_rresp;wire [31:0] s_axi_rdata;
 wire start,irq;wire [31:0] plan_base,plan_count;
 reg parameter_ready=1,busy=0,done=0,fault=0,matrix_done=0,vector_done=0,layout_done=0;
 reg [7:0] error_code=0,vector_numeric_flags=0,vector_error_code=0,layout_error_code=0;
 reg [31:0] generation=7,param_end=32'h1a5aa400,completed=4,index=3,rejected_starts=0,last_ticket=4;
 reg [63:0] cycles=64'h123456789,fetch_cycles=100,operator_cycles=200;
 reg [63:0] matrix_cycles=1234,matrix_pe_cycles=264,vector_cycles=55,layout_cycles=22,vector_read_compute_overlap=7,vector_write_compute_overlap=5;
 reg [31:0] vector_read_bytes=10,vector_write_bytes=20,layout_read_bytes=30,layout_write_bytes=40,vector_completed_elements=1001,layout_processed_elements=1001,layout_cache_hits=50,layout_cache_misses=4;
 plan_submit_csr dut(.*);
 integer starts=0;
 always @(posedge clk)if(rst_n&&start)starts<=starts+1;
 task aw(input [23:0] address);
  begin @(negedge clk);s_axi_awaddr=address;s_axi_awvalid=1;do @(posedge clk);while(!s_axi_awready);@(negedge clk);s_axi_awvalid=0;end
 endtask
 task wd(input [31:0] value);
  begin @(negedge clk);s_axi_wdata=value;s_axi_wvalid=1;do @(posedge clk);while(!s_axi_wready);@(negedge clk);s_axi_wvalid=0;end
 endtask
 task write_word(input [23:0] address,input [31:0] value,input integer reverse,input [1:0] response);
  begin
   if(reverse)begin wd(value);repeat(3)@(negedge clk);aw(address);end
   else begin aw(address);repeat(3)@(negedge clk);wd(value);end
   wait(s_axi_bvalid);repeat(3)@(negedge clk);
   if(!s_axi_bvalid||s_axi_bresp!=response)$fatal(1,"CSR write response address=%h",address);
   s_axi_bready=1;@(negedge clk);s_axi_bready=0;
  end
 endtask
 task read_word(input [23:0] address,input [31:0] value);
  begin
   @(negedge clk);s_axi_araddr=address;s_axi_arvalid=1;do @(posedge clk);while(!s_axi_arready);@(negedge clk);s_axi_arvalid=0;
   wait(s_axi_rvalid);repeat(3)@(negedge clk);
   if(!s_axi_rvalid||s_axi_rresp!=0||s_axi_rdata!==value)$fatal(1,"CSR read address=%h got=%h expected=%h",address,s_axi_rdata,value);
   s_axi_rready=1;@(negedge clk);s_axi_rready=0;
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  read_word(0,32'ha51a22d0);write_word(8,32'h10001000,0,0);write_word(12,4,1,0);
  read_word(8,32'h10001000);read_word(12,4);
  parameter_ready=0;write_word(16,1,0,2);if(starts)$fatal(1,"Unready START side effect");parameter_ready=1;
  write_word(16,1,1,0);if(starts!=1)$fatal(1,"Missing START pulse");busy=1;
  write_word(8,32'h10002000,1,2);read_word(8,32'h10001000);
  write_word(16,1,0,2);if(starts!=1)$fatal(1,"Busy START replay");
  @(negedge clk);matrix_done=1;vector_done=1;layout_done=1;vector_read_bytes=100;vector_write_bytes=200;layout_read_bytes=300;layout_write_bytes=400;
  @(negedge clk);vector_done=0;layout_done=0;repeat(100)@(negedge clk);busy=0;done=1;
  @(negedge clk);done=0;repeat(100)@(negedge clk);
  if(!irq)$fatal(1,"Completion IRQ not sticky");read_word(4,2);
  read_word(32,32'h23456789);read_word(36,1);read_word(64,55);read_word(72,22);
  read_word(80,90);read_word(84,180);read_word(88,270);read_word(92,360);
  read_word(160,1234);read_word(164,0);read_word(168,264);read_word(172,0);
  write_word(16,1,0,0);if(irq||starts!=2)$fatal(1,"Fresh start did not clear sticky DONE");
  read_word(160,0);read_word(168,0);read_word(64,0);read_word(72,0);
  s_axi_wstrb=3;write_word(8,0,0,2);s_axi_wstrb=15;
  write_word(24'h100008,0,0,2);write_word(9,0,0,2);
  $display("V022_PLAN_CSR_PASS starts=%d stickyDONE reverseAW/W stalledreplies readonlyACL counteredge",starts);$finish;
 end
 initial begin #1000000;$fatal(1,"CSR watchdog");end
endmodule
