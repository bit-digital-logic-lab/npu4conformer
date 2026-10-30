"""Wire shared AXI BFM to all three real cluster masters, one PS start."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];target=ROOT/'tests/tb_plan_cluster.sv'
if target.exists():raise RuntimeError('Fresh bench')
wrap=(ROOT/'rtl/ddr_execution_cluster.sv').read_text();ports=re.sub(r'\(\*.*?\*\)','',wrap.split('module ddr_execution_cluster(',1)[1].split(');',1)[0],flags=re.S)
s='''`timescale 1ns/1ps
module tb_plan_cluster;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;reg [31:0] plan_base=32'h10000000,plan_count=2,param_end=32'h10004000,generation=7;
 integer mode=0,cycle=0,matrix_timer=0,matrix_calls=0;reg matrix_active=0,matrix_done=0,matrix_fault=0;
 wire matrix_ready=!matrix_active;
'''
direction=width=None;inputnames={'clk','rst_n','start','parameter_ready','plan_base','plan_count','param_end','generation','matrix_ready','matrix_done','matrix_fault'}
for piece in ports.replace('\n',' ').split(','):
    piece=piece.strip();m=re.fullmatch(r'(input|output)\s+wire\s*(\[[^]]+\])?\s*(\w+)',piece)
    if m:direction,width,name=m.groups();width=width or ''
    else:name=piece
    if name not in inputnames:s+=f' wire {width} {name};\n'
s+=' ddr_execution_cluster dut(.*);\n defparam dut.planner.WATCHDOG=25000;\n'
for suffix,width in [('araddr',40),('arlen',8),('arsize',3),('arburst',2),('arvalid',1),('arready',1),('rdata',128),('rresp',2),('rlast',1),('rvalid',1),('rready',1),('awaddr',40),('awlen',8),('awsize',3),('awburst',2),('awvalid',1),('awready',1),('wdata',128),('wstrb',16),('wlast',1),('wvalid',1),('wready',1),('bresp',2),('bvalid',1),('bready',1)]:
    s+=f' wire [{3*width-1}:0] {suffix};\n'
    for i,side in enumerate(['read','write','fetch']):
        name=side+'_m_axi_'+suffix;field=f'{suffix}[{i*width}+:{width}]'
        d=re.search(r'(input|output)\s+wire\s*(?:\[[^]]+\])?\s*'+name+r'\b',ports)[1]
        s+=f' assign {field if d=="output" else name}={name if d=="output" else field};\n'
s+=''' wire inject_read_error=mode==4,inject_write_error=1'b0;
 wire [31:0] read_bursts,write_bursts,read_beats,write_beats;
 axi128_memory_bfm #(.PORTS(3)) ddr(.*);
 reg [7:0] gold_float[0:4003],gold_q[0:2001],parameters_before[0:16383];
 reg [4095:0] folder;
 task put32(input integer at,input [31:0] value);
  begin for(integer j=0;j<4;j=j+1)ddr.memory[at+j]=value[j*8+:8];end
 endtask
 always @(posedge clk)if(rst_n)begin
  cycle<=cycle+1;matrix_done<=0;
  if(matrix_valid&&matrix_ready)begin
   if(matrix_queue_base!=32'h03000000||matrix_queue_count!=1)$fatal(1,"Matrix queue dispatch");
   matrix_calls<=matrix_calls+1;matrix_active<=1;matrix_timer<=mode==14?30000:6;
  end
  if(matrix_active)begin
   matrix_timer<=matrix_timer-1;
   if(matrix_timer==1)begin matrix_active<=0;matrix_done<=1;matrix_fault<=mode==13;end
  end
  if(cycle>120000)$fatal(1,"Plan watchdog state=%d",dut.planner.state);
 end
 initial begin
  if(!$value$plusargs("folder=%s",folder))$fatal(1,"Arguments");
  if($value$plusargs("mode=%d",mode))begin end
  $readmemh({folder,"/memory.hex"},ddr.memory);
  $readmemh({folder,"/gold_float.hex"},gold_float);$readmemh({folder,"/gold_q.hex"},gold_q);
  case(mode)
   1:put32(196608,0);
   2:put32(196608+64+12,7);
   5:put32(196608+4096+4,19);
   7:put32(196608+16,32'h04000000);
   8:put32(196608+60,1);
   9:plan_count=0;
   10:parameter_ready=0;
   11:put32(196608+4096+20,32'h04000000);
   12,13,14:begin
    put32(196608+4,1);put32(196608+16,32'h03000000);put32(196608+20,1);
    put32(196608+64+16,32'h10001000);
   end
  endcase
  for(integer j=0;j<16384;j=j+1)parameters_before[j]=ddr.memory[196608+j];
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  if(mode==3)begin wait(vector_busy);repeat(30)@(negedge clk);generation=8;end
  if(mode==6)begin repeat(20)@(negedge clk);start=1;@(negedge clk);start=0;end
  wait(done);@(negedge clk);
  if(busy||vector_busy||matrix_active||ddr.ra[0]||ddr.ra[1]||ddr.ra[2]||ddr.wa[0]||ddr.wa[1]||ddr.wa[2])$fatal(1,"Plan done before drain");
  for(integer j=0;j<16384;j=j+1)if(parameters_before[j]!==ddr.memory[196608+j])$fatal(1,"Readonly parameters modified");
  if(mode==0||mode==6||mode==12)begin
   if(fault||completed!=2||last_ticket!=2)$fatal(1,"Plan failed error=%h complete=%d",error_code,completed);
   for(integer j=0;j<4004;j=j+1)if(ddr.memory[65536+j]!==gold_float[j])$fatal(1,"Plan FP output mismatch %d",j);
   if(mode!=12)for(integer j=0;j<2002;j=j+1)if(ddr.memory[131072+j]!==gold_q[j])$fatal(1,"Plan Q output mismatch %d",j);
   if(mode==6&&rejected_starts!=1)$fatal(1,"Plan START replay");
   if(mode==12&&matrix_calls!=1)$fatal(1,"Matrix dispatch missing");
  end else begin
   if(!fault)$fatal(1,"Fault missing mode=%d",mode);
   if(mode==2&&completed!=1)$fatal(1,"Completed prefix lost");
   if(mode==14&&(error_code!=9||cycle<30000))$fatal(1,"Watchdog cancelled active operation");
   if((mode==9||mode==10)&&read_bursts!=0)$fatal(1,"Bad start had side effects");
  end
  $display("V022_PLAN_CLUSTER_PASS mode=%d cycles=%d completed=%d error=%h matrix_calls=%d",mode,cycles,completed,error_code,matrix_calls);$finish;
 end
endmodule
'''
target.write_text(s,encoding='utf-8');print('V022_PLAN_CLUSTER_BENCH_CREATED')
