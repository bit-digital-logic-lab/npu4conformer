"""New cluster variant with a third operator class and five real AXI masters."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];source=ROOT/'scripts/make_cluster_wrapper.py';target=ROOT/'scripts/generated_layout_cluster.py'
if target.exists():raise RuntimeError('Fresh generated cluster')
s=source.read_text(encoding='utf-8').replace("'rtl/pl_execution_plan.sv'","'rtl/pl_execution_plan_v022.sv'").replace("'rtl/ddr_execution_cluster.sv'","'rtl/ddr_execution_cluster_v022.sv'").replace('module ddr_execution_cluster(','module ddr_execution_cluster_v022(').replace('pl_execution_plan planner','pl_execution_plan_v022 planner')
s=s.replace("pp=parse('input wire '+plan.split(')(input wire ',1)[1].split(');',1)[0])","pp=parse('input wire '+plan.split(')(input wire ',1)[1].split(');',1)[0])")
s=s.replace("if n.startswith(('dma_','vector_')):continue","if n.startswith(('dma_','vector_','layout_')):continue")
s=s.replace("for d,w,n in dp:\n    if n.startswith('m_axi_'):","layout=(ROOT/'rtl/ddr_layout_axi.sv').read_text();lp=parse(layout.split('module ddr_layout_axi(',1)[1].split(');',1)[0])\nfor d,w,n in lp:\n    if n in ('clk','rst_n','param_end','descriptor','start','ready'):continue\n    if n.startswith(('read_m_axi_','write_m_axi_')):\n        side=n.split('_',1)[0];suffix=n.split('m_axi_',1)[1]\n        attr=f'(* X_INTERFACE_INFO=\"xilinx.com:interface:aximm:1.0 layout_{side}_axi {suffix.upper()}\"'\n        if suffix=='araddr':attr+=', X_INTERFACE_PARAMETER=\"PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 40, FREQ_HZ 125000000, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1\"'\n        decl.append(f' {attr} *) {d} wire {w} layout_{n}')\n    else:decl.append(f' {d} wire {w} layout_{n}')\nfor d,w,n in dp:\n    if n.startswith('m_axi_'):")
s=s.replace('ASSOCIATED_BUSIF fetch_axi:read_axi:write_axi','ASSOCIATED_BUSIF fetch_axi:read_axi:write_axi:layout_read_axi:layout_write_axi')
s=s.replace("if n in ('vector_valid','vector_ready','vector_descriptor'):","if n in ('vector_valid','vector_ready','vector_descriptor','layout_valid','layout_ready','layout_descriptor'):")
needle="maps=dict(clk='clk',rst_n='rst_n',request_valid='dma_request_valid'"
assert needle in s
addition="""connections=[]
for _,_,n in lp:
    if n=='start':value='layout_valid&&layout_ready'
    elif n=='descriptor':value='layout_descriptor'
    elif n=='ready':value='layout_ready'
    elif n in ('clk','rst_n','param_end'):value=n
    else:value='layout_'+n
    connections.append(f' .{n}({value})')
s+=' ddr_layout_axi layouts(\\n'+',\\n'.join(connections)+'\\n );\\n'
"""
s=s.replace(needle,addition+needle)
target.write_text(s,encoding='utf-8');exec(compile(s,str(target),'exec'),{'__file__':str(target),'__name__':'__main__'})
print('V022_VECTOR_LAYOUT_PLAN_CLUSTER_CREATED')
