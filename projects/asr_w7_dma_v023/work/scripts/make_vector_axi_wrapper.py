"""Mechanical interface wiring. Numerical/source modules are never rewritten."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def ports(s):
    result=[];direction=width=None
    for piece in s.replace('\n',' ').split(','):
        piece=piece.strip();m=re.fullmatch(r'(input|output)\s+(?:wire|reg)\s*(\[[^]]+\])?\s*(\w+)',piece)
        if m:direction,width,name=m.groups();width=width or ''
        else:
            m=re.fullmatch(r'(\w+)',piece)
            if not m or direction is None:raise RuntimeError('Port parse '+piece)
            name=m[1]
        result.append((direction,width,name))
    return result
dma=(ROOT/'rtl/axi_dma_v019.sv').read_text();p=ports(dma.split('module axi_dma_v019(',1)[1].split(');',1)[0])
v=(ROOT/'rtl/ddr_vector_engine.sv').read_text();vp=ports(v.split(')(input wire ',1)[1].split(');',1)[0].join(['input wire ','']))
common=[x for x in vp if not x[2].startswith(('rd_','wr_'))]
decl=[f' {d} wire {w} {n}' for d,w,n in common]
decl += [' output wire [31:0] read_bytes,write_bytes,read_bursts,write_bursts']
for side in ('read','write'):
    for d,w,n in p:
        if n.startswith('m_axi_'):
            attr=f'(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 {side}_axi {n[6:].upper()}"'
            if n=='m_axi_araddr':attr+=', X_INTERFACE_PARAMETER="PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 40, FREQ_HZ 125000000, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1"'
            decl.append(f' {attr} *) {d} wire {w} {side}_{n}')
s='`timescale 1ns/1ps\nmodule ddr_vector_axi(\n'+',\n'.join(decl)+'\n);\n'
for d,w,n in vp:
    if n.startswith(('rd_','wr_')):s+=f' wire {w} {n};\n'
s+=' ddr_vector_engine arithmetic(\n'+',\n'.join(f' .{n}({n})' for _,_,n in vp)+'\n );\n'
for side,abbr in [('read','rd'),('write','wr')]:
    maps=dict(request_valid=abbr+'_request_valid',request_ready=abbr+'_request_ready',request_write="1'b"+('0' if side=='read' else '1'),request_address=abbr+'_address',request_beats=abbr+'_beats',done=abbr+'_done',error=abbr+'_error')
    if side=='read':maps.update(read_valid='rd_valid',read_ready='rd_ready',read_data='rd_data',read_index='rd_index',write_valid="1'b0",write_ready='',write_data="128'd0",write_strobe="16'd0",write_index='',read_bytes='read_bytes',write_bytes='',read_bursts='read_bursts',write_bursts='')
    else:maps.update(read_valid='',read_ready="1'b1",read_data='',read_index='',write_valid='wr_valid',write_ready='wr_ready',write_data='wr_data',write_strobe='wr_strobe',write_index='',read_bytes='',write_bytes='write_bytes',read_bursts='',write_bursts='write_bursts')
    maps.update(clk='clk',rst_n='rst_n')
    s+=f' axi_dma_v019 {side}_dma(\n'+',\n'.join(f' .{n}({side+"_"+n if n.startswith("m_axi_") else maps[n]})' for _,_,n in p)+'\n );\n'
s+='endmodule\n';target=ROOT/'rtl/ddr_vector_axi.sv'
if target.exists():raise RuntimeError('Fresh wrapper required')
target.write_text(s,encoding='utf-8');print('V022_VECTOR_AXI_WRAPPER_CREATED')
