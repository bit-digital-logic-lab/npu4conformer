"""Wire PL plan fetch DMA and actual DDR vector engine; no numerical rewrites."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def parse(s):
    result=[];direction=width=None
    for piece in re.sub(r'\(\*.*?\*\)','',s,flags=re.S).replace('\n',' ').split(','):
        piece=piece.strip();m=re.fullmatch(r'(input|output)\s+(?:wire|reg)\s*(\[[^]]+\])?\s*(\w+)',piece)
        if m:direction,width,name=m.groups();width=width or ''
        else:
            if not re.fullmatch(r'\w+',piece):raise RuntimeError('Port '+piece)
            name=piece
        result.append((direction,width,name))
    return result
plan=(ROOT/'rtl/pl_execution_plan.sv').read_text();pp=parse('input wire '+plan.split(')(input wire ',1)[1].split(');',1)[0])
vec=(ROOT/'rtl/ddr_vector_axi.sv').read_text();vp=parse(vec.split('module ddr_vector_axi(',1)[1].split(');',1)[0])
dma=(ROOT/'rtl/axi_dma_v019.sv').read_text();dp=parse(dma.split('module axi_dma_v019(',1)[1].split(');',1)[0])
target=ROOT/'rtl/ddr_execution_cluster.sv'
if target.exists():raise RuntimeError('Fresh cluster')
decl=[];known=set()
for d,w,n in pp:
    if n.startswith(('dma_','vector_')):continue
    decl.append(f' {d} wire {w} {n}');known.add(n)
for d,w,n in vp:
    if n in ('clk','rst_n','param_end','descriptor','start','ready'):continue
    if n.startswith(('read_m_axi_','write_m_axi_')):
        side=n.split('_',1)[0];suffix=n.split('m_axi_',1)[1]
        attr=f'(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 {side}_axi {suffix.upper()}"'
        if suffix=='araddr':attr+=', X_INTERFACE_PARAMETER="PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 40, FREQ_HZ 125000000, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1"'
        decl.append(f' {attr} *) {d} wire {w} {n}')
    else:decl.append(f' {d} wire {w} vector_{n}')
for d,w,n in dp:
    if n.startswith('m_axi_'):
        attr=f'(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 fetch_axi {n[6:].upper()}"'
        if n=='m_axi_araddr':attr+=', X_INTERFACE_PARAMETER="PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 40, FREQ_HZ 125000000, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1"'
        decl.append(f' {attr} *) {d} wire {w} fetch_{n}')
decl=[x.replace('input wire  clk','(* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF fetch_axi:read_axi:write_axi, ASSOCIATED_RESET rst_n, FREQ_HZ 125000000" *) input wire clk').replace('input wire  rst_n','(* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 rst_n RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input wire rst_n') for x in decl]
s='`timescale 1ns/1ps\n// Actual PL plan + DDR numeric pipeline. Matrix queue is connected externally.\nmodule ddr_execution_cluster(\n'+',\n'.join(decl)+'\n);\n'
for _,w,n in pp:
    if n.startswith('dma_'):s+=f' wire {w} {n};\n'
    if n in ('vector_valid','vector_ready','vector_descriptor'):s+=f' wire {w} {n};\n'
s+=' pl_execution_plan planner(\n'+',\n'.join(f' .{n}({n})' for _,_,n in pp)+'\n );\n'
connections=[]
for _,_,n in vp:
    if n=='start':value='vector_valid&&vector_ready'
    elif n=='descriptor':value='vector_descriptor'
    elif n=='ready':value='vector_ready'
    elif n in ('clk','rst_n','param_end') or n.startswith(('read_m_axi_','write_m_axi_')):value=n
    else:value='vector_'+n
    connections.append(f' .{n}({value})')
s+=' ddr_vector_axi vectors(\n'+',\n'.join(connections)+'\n );\n'
maps=dict(clk='clk',rst_n='rst_n',request_valid='dma_request_valid',request_ready='dma_request_ready',request_write="1'b0",request_address='dma_address',request_beats='dma_beats',read_valid='dma_read_valid',read_ready='dma_read_ready',read_data='dma_read_data',read_index='dma_read_index',write_valid="1'b0",write_ready='',write_data="128'd0",write_strobe="16'd0",write_index='',done='dma_done',error='dma_error',read_bytes='',write_bytes='',read_bursts='',write_bursts='')
s+=' axi_dma_v019 plan_dma(\n'+',\n'.join(f' .{n}({"fetch_"+n if n.startswith("m_axi_") else maps[n]})' for _,_,n in dp)+'\n );\nendmodule\n'
target.write_text(s,encoding='utf-8');print('V022_EXECUTION_CLUSTER_CREATED')
