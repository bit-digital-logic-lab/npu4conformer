"""Mechanical real-AXI bench wiring for layout engine; no numerical substitutes."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];target=ROOT/'tests/tb_layout_axi.sv'
if target.exists():raise RuntimeError('Fresh bench')
wrap=(ROOT/'rtl/ddr_layout_axi.sv').read_text();ports=re.sub(r'\(\*.*?\*\)','',wrap.split('module ddr_layout_axi(',1)[1].split(');',1)[0],flags=re.S)
s='''`timescale 1ns/1ps
module tb_layout_axi;
 integer mode=0,nbytes,cycle=0;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;reg [1023:0] descriptor=0;reg [31:0] param_end=32'h20000000;
'''
direction=width=None
for piece in ports.replace('\n',' ').split(','):
    piece=piece.strip();m=re.fullmatch(r'(input|output)\s+wire\s*(\[[^]]+\])?\s*(\w+)',piece)
    if m:direction,width,name=m.groups();width=width or ''
    else:name=piece
    if name not in ('clk','rst_n','start','descriptor','param_end'):s+=f' wire {width} {name};\n'
s+=' ddr_layout_axi dut(.*);\n'
for suffix,width in [('araddr',40),('arlen',8),('arsize',3),('arburst',2),('arvalid',1),('arready',1),('rdata',128),('rresp',2),('rlast',1),('rvalid',1),('rready',1),('awaddr',40),('awlen',8),('awsize',3),('awburst',2),('awvalid',1),('awready',1),('wdata',128),('wstrb',16),('wlast',1),('wvalid',1),('wready',1),('bresp',2),('bvalid',1),('bready',1)]:
    s+=f' wire [{2*width-1}:0] {suffix};\n'
    for i,side in enumerate(['read','write']):
        name=side+'_m_axi_'+suffix;field=f'{suffix}[{i*width}+:{width}]'
        d=re.search(r'(input|output)\s+wire\s*(?:\[[^]]+\])?\s*'+name+r'\b',ports)[1]
        s+=f' assign {field if d=="output" else name}={name if d=="output" else field};\n'
s+=''' wire inject_read_error=mode==7,inject_write_error=mode==8;
 wire [31:0] read_requests,write_requests,read_beats,write_beats;
 axi128_memory_bfm ddr(.read_bursts(read_requests),.write_bursts(write_requests),.*);
 reg [7:0] gold[0:262143];reg [31:0] desc_words[0:31];reg [4095:0] folder;
 always @(posedge clk)if(rst_n)begin cycle<=cycle+1;if(cycle>5000000)$fatal(1,"Layout watchdog state=%d",dut.arithmetic.state);end
 initial begin
  if(!$value$plusargs("folder=%s",folder)||!$value$plusargs("nbytes=%d",nbytes))$fatal(1,"Arguments");
  if($value$plusargs("mode=%d",mode))begin end
  $readmemh({folder,"/memory.hex"},ddr.memory);$readmemh({folder,"/gold.hex"},gold,0,nbytes-1);
  $readmemh({folder,"/descriptor.hex"},desc_words);
  for(integer j=0;j<32;j=j+1)descriptor[j*32+:32]=desc_words[j];
  case(mode)
   1:descriptor[127:96]=32'h10000000;
   2:descriptor[95:64]=32'h02000000;
   3:descriptor[159:128]=32'hffffffff;
   4:descriptor[127:96]=descriptor[95:64];
   5:descriptor[1023]=1;
   6:descriptor[63:32]=9;
   10:descriptor[191:160]=3;
   11:descriptor[95:64]=32'h04000001;
   12:begin descriptor[63:32]=1;descriptor[223:192]=3;descriptor[255:224]=4;descriptor[287:256]=2;end
  endcase
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  if(mode==9)begin repeat(20)@(negedge clk);start=1;@(negedge clk);start=0;end
  wait(done);@(negedge clk);
  if(ddr.ra[0]||ddr.ra[1]||ddr.wa[0]||ddr.wa[1]||ddr.bp[0]||ddr.bp[1])$fatal(1,"Layout DONE before drain");
  if(mode!=0&&mode!=9)begin
   if(!fault)$fatal(1,"Expected layout error mode=%d",mode);
   if(mode!=7&&mode!=8&&(read_requests||write_requests))$fatal(1,"Layout ACL side effects");
  end else begin
   if(fault||processed_elements!=desc_words[4])$fatal(1,"Layout fault=%h processed=%d",error_code,processed_elements);
   for(integer j=0;j<nbytes;j=j+1)if(ddr.memory[65536+j]!==gold[j])$fatal(1,"Layout mismatch byte=%d got=%h expected=%h",j,ddr.memory[65536+j],gold[j]);
   for(integer j=nbytes;j<nbytes+32;j=j+1)if(ddr.memory[65536+j]!==8'ha5)$fatal(1,"Layout tail overwritten");
   if(mode==9&&rejected_starts!=1)$fatal(1,"Layout replayed START");
  end
  $display("V022_LAYOUT_AXI_PASS mode=%d cycles=%d processed=%d cache_hits=%d cache_misses=%d read_requests=%d write_requests=%d",mode,cycles,processed_elements,cache_hits,cache_misses,read_requests,write_requests);$finish;
 end
endmodule
'''
target.write_text(s,encoding='utf-8');print('V022_LAYOUT_BENCH_CREATED')
