"""Mechanical existing numerical fixture bench -> real dual AXI DMA bench."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];target=ROOT/'tests/tb_vector_axi.sv'
if target.exists():raise RuntimeError('Fresh bench')
wrap=(ROOT/'rtl/ddr_vector_axi.sv').read_text()
ports=re.sub(r'\(\*.*?\*\)','',wrap.split('module ddr_vector_axi(',1)[1].split(');',1)[0],flags=re.S)
names=[];decls=[];direction=width=None
for piece in ports.replace('\n',' ').split(','):
    piece=piece.strip();m=re.fullmatch(r'(input|output)\s+wire\s*(\[[^]]+\])?\s*(\w+)',piece)
    if m:direction,width,name=m.groups();width=width or ''
    else:name=piece
    names.append(name)
    if name in ('clk','rst_n','start','descriptor','param_end'):continue
    decls.append(f' wire {width} {name};')
s='`timescale 1ns/1ps\nmodule tb_vector_axi;\n integer mode=0,nbytes,cycle=0;\n reg clk=0;always #4 clk=~clk;\n reg rst_n=0,start=0;reg [511:0] descriptor=0;reg [31:0] param_end=32\'h20000000;\n'
s+='\n'.join(decls)+'\n ddr_vector_axi dut(.*);\n'
for suffix,width in [('araddr',40),('arlen',8),('arsize',3),('arburst',2),('arvalid',1),('arready',1),('rdata',128),('rresp',2),('rlast',1),('rvalid',1),('rready',1),('awaddr',40),('awlen',8),('awsize',3),('awburst',2),('awvalid',1),('awready',1),('wdata',128),('wstrb',16),('wlast',1),('wvalid',1),('wready',1),('bresp',2),('bvalid',1),('bready',1)]:
    s+=f' wire [{2*width-1}:0] {suffix};\n'
    for i,side in enumerate(['read','write']):
        name=side+'_m_axi_'+suffix;field=f'{suffix}[{i*width}+:{width}]'
        d=re.search(r'(input|output)\s+wire\s*(?:\[[^]]+\])?\s*'+name+r'\b',ports)[1]
        s+=f' assign {field if d=="output" else name}={name if d=="output" else field};\n'
s+=' wire inject_read_error=mode==7,inject_write_error=mode==8;\n wire [31:0] read_requests,write_requests,read_beats,write_beats;\n'
s+=' axi128_memory_bfm ddr(.read_bursts(read_requests),.write_bursts(write_requests),.*);\n'
s+=' reg [7:0] gold[0:4095];reg [31:0] desc_words[0:15];\n always @(posedge clk)if(rst_n)begin cycle<=cycle+1;if(cycle>300000)$fatal(1,"AXI vector watchdog");end\n'
old=(ROOT/'tests/tb_vector.sv').read_text();initial=old.split(' reg [4095:0] folder;',1)[1]
initial=initial.replace('memory','ddr.memory').replace('if(ractive||wactive||rp||wp)','if(ddr.ra[0]||ddr.ra[1]||ddr.wa[0]||ddr.wa[1]||ddr.bp[0]||ddr.bp[1])').replace('V022_VECTOR_PASS','V022_VECTOR_AXI_PASS')
initial=initial.replace('ddr.memory.hex','memory.hex')
s+=' reg [4095:0] folder;'+initial
target.write_text(s,encoding='utf-8');print('V022_REAL_DUAL_AXI_TEST_CREATED')
