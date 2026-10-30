"""Port-only wrapper: actual five DMA cluster + AXI-Lite sticky completion."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def parse(s):
    ports=[];direction=width=None
    for piece in re.sub(r'\(\*.*?\*\)','',s,flags=re.S).split(','):
        m=re.fullmatch(r'\s*(input|output)\s+(?:wire|reg)\s*(\[[^]]+\])?\s*(\w+)\s*',piece)
        if m:direction,width,name=m.groups()
        else:
            name=piece.strip()
            if not re.fullmatch(r'\w+',name) or direction is None:raise ValueError(piece)
        ports.append((direction,width or '',name))
    return ports
cluster=(ROOT/'rtl/ddr_execution_cluster_v022.sv').read_text();cp=parse(cluster.split('module ddr_execution_cluster_v022(',1)[1].split(');',1)[0])
csr=(ROOT/'rtl/plan_submit_csr.sv').read_text();sp=parse(csr.split('module plan_submit_csr(',1)[1].split(');',1)[0])
external=set(['clk','rst_n','param_end','parameter_ready','generation','irq','busy'])
external.update(n for _,_,n in cp if '_m_axi_' in n or n.startswith('matrix_'))
external.update(n for _,_,n in sp if n.startswith('s_axi_'))
external.update(n for _,_,n in sp if n.startswith('matrix_'))
decl=[];internal={}
for direction,width,name in cp+sp:
    if name in internal:continue
    internal[name]=(direction,width)
    if name not in external:continue
    attr=''
    if '_m_axi_' in name:
        pre,suffix=name.split('_m_axi_',1);attr=f'(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 {pre}_axi {suffix.upper()}"'
        if suffix=='araddr':attr+=', X_INTERFACE_PARAMETER="PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 40, FREQ_HZ 125000000, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1"'
        attr+=' *) '
    elif name.startswith('s_axi_'):
        suffix=name[6:];attr=f'(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi {suffix.upper()}"'
        if suffix=='awaddr':attr+=', X_INTERFACE_PARAMETER="PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 24, FREQ_HZ 125000000"'
        attr+=' *) '
    elif name=='clk':attr='(* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF s_axi:fetch_axi:read_axi:write_axi:layout_read_axi:layout_write_axi, ASSOCIATED_RESET rst_n, FREQ_HZ 125000000" *) '
    elif name=='rst_n':attr='(* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 rst_n RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) '
    decl.append(f' {attr}{direction} wire {width} {name}')
body='`timescale 1ns/1ps\nmodule plan_board_v022(\n'+',\n'.join(decl)+'\n);\n'
for name,(_,width) in internal.items():
    if name not in external:body+=f' wire {width} {name};\n'
# Cluster IRQ is a pulse; exported IRQ comes from the sticky AXI-Lite CSR.
body+=' ddr_execution_cluster_v022 cluster(\n'+',\n'.join(f' .{n}({"" if n=="irq" else n})' for _,_,n in cp)+'\n );\n'
body+=' plan_submit_csr control(\n'+',\n'.join(f' .{n}({n})' for _,_,n in sp)+'\n );\nendmodule\n'
p=ROOT/'rtl/plan_board_v022.sv'
if p.exists() and 'matrix_pe_cycles' in p.read_text():raise ValueError('Wrapper already upgraded')
p.write_text(body,encoding='utf-8');print('V022_PLAN_BOARD_WRAPPER_CREATED')
