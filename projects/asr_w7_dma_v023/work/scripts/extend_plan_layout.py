"""New explicit plan ABI variant, preserving the tested two-kind prototype."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'rtl/pl_execution_plan.sv';target=ROOT/'rtl/pl_execution_plan_v022.sv'
if target.exists():raise RuntimeError('Fresh layout-capable plan')
s=source.read_text(encoding='utf-8')
def once(old,new):
    global s
    if s.count(old)!=1:raise RuntimeError('Template '+old)
    s=s.replace(old,new)
once('module pl_execution_plan #(','module pl_execution_plan_v022 #(')
once(' input wire vector_done,vector_fault);',' input wire vector_done,vector_fault,\n output wire layout_valid,input wire layout_ready,\n output wire [1023:0] layout_descriptor,input wire layout_done,layout_fault);')
once('reg [511:0] instruction,payload;','reg [511:0] instruction;reg [1023:0] payload;')
once('reg [2:0] received;','reg [3:0] received;')
once('wire [63:0] payload_end={32\'d0,pointer}+64;','wire [63:0] payload_end={32\'d0,pointer}+length;')
once('!(kind==1||kind==2)','!(kind==1||kind==2||kind==3)')
once('(length!=64||pointer[5:0]!=0||pointer<PLAN_BASE||payload_end>param_end)', '((kind==2?length!=64:length!=128)||pointer[5:0]!=0||pointer<PLAN_BASE||payload_end>param_end)')
once('assign dma_beats=4;','assign dma_beats=(state==VREQ||state==VFETCH)&&kind==3?8:4;')
once('assign vector_descriptor=payload;','assign vector_descriptor=payload[511:0];\n assign layout_descriptor=payload;\n assign layout_valid=state==DISPATCH&&kind==3&&parameter_ready&&generation==gen;')
once('if(dma_read_index!=received||dma_read_index>3)', 'if(dma_read_index!=received||dma_read_index>=dma_beats)')
once('received!=4','received!=dma_beats')
once('else if(kind==2)state<=VREQ','else if(kind==2||kind==3)state<=VREQ')
once('(kind==1&&matrix_ready)||(kind==2&&vector_ready)', '(kind==1&&matrix_ready)||(kind==2&&vector_ready)||(kind==3&&layout_ready)')
old='(kind==1&&matrix_done)||(kind==2&&vector_done)';assert s.count(old)==2
s=s.replace(old,old+'||(kind==3&&layout_done)')
once('(kind==1&&matrix_fault)||(kind==2&&vector_fault)', '(kind==1&&matrix_fault)||(kind==2&&vector_fault)||(kind==3&&layout_fault)')
target.write_text(s,encoding='utf-8');print('V022_LAYOUT_PLAN_ABI_CREATED')
