"""New V022 board path, sealed V211 untouched. Epoch-biased static queues.

External PL plan owns the accelerator while busy; PS parameter/queue writes
are rejected until the plan has drained. No per-matrix PS query/copy in a plan.
"""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1'
hashes={}
def emit(name,data):
    p=ROOT/'rtl'/name
    if p.exists():
        if p.read_text(encoding='utf-8')!=data:raise ValueError('Existing derivation differs '+name)
        return
    p.write_text(data,encoding='utf-8')
def once(s,a,b):
    if s.count(a)!=1:raise ValueError('Template mismatch '+a)
    return s.replace(a,b)
for p in (BASE/'rtl').glob('*.sv'):
    if p.name=='axi_dma_v019.sv':continue
    s=p.read_text(encoding='utf-8');hashes[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
    if p.name=='queued_v020_monitored.sv':
        s=once(s,'queue_base,queue_count,param_end,','queue_base,queue_count,param_end,epoch_bias,')
        s=once(s,'wire ev,er;', 'wire [31:0] relative_cookie;\n assign completion_cookie=relative_cookie+epoch_bias;\n wire ev,er;')
        s=once(s,'.completion_cookie(completion_cookie)','.completion_cookie(relative_cookie)')
        s=once(s,'cfg<=ed;','cfg<=ed;cfg[351:320]<=ed[351:320]+epoch_bias;')
        s=once(s,'wire bad_cfg=mdim==0','wire bad_cfg=epoch==0||mdim==0')
    elif p.name=='queue_submit_csr_board.sv':
        s=once(s,'input wire clk,rst_n,','input wire clk,rst_n,plan_lock,\n output wire [31:0] param_generation_out,\n output wire parameter_ready_out,')
        s=once(s,'assign param_end=', 'assign parameter_ready_out=param_ready;assign param_generation_out=param_generation;\n assign param_end=')
        s=once(s,'if(ws!=15||busy||start||','if(ws!=15||busy||start||plan_lock||')
    elif p.name=='queued_v020_board.sv':
        s=once(s,'input wire clk,rst_n,','input wire clk,rst_n,\n input wire plan_lock,plan_matrix_valid,\n input wire [31:0] plan_matrix_base,plan_matrix_count,\n output wire plan_matrix_ready,plan_matrix_done,plan_matrix_fault,\n output wire parameter_ready,output wire [31:0] parameter_generation,parameter_end,')
        s=once(s,'wire start,busy,done,fault,completion_valid,completion_ready;','wire legacy_start,start,busy,done,fault,completion_valid,completion_ready;\n wire [31:0] legacy_base,legacy_count;reg [31:0] epoch_bias;\n assign plan_matrix_ready=plan_lock&&!busy&&!legacy_start;\n assign start=legacy_start||(plan_matrix_valid&&plan_matrix_ready);\n assign queue_base=plan_lock?plan_matrix_base:legacy_base;\n assign queue_count=plan_lock?plan_matrix_count:legacy_count;\n assign plan_matrix_done=done;assign plan_matrix_fault=fault;\n assign parameter_end=param_end;\n always @(posedge clk)if(!rst_n)epoch_bias<=0;else if(start&&!busy)epoch_bias<=plan_lock?control.last_cookie:0;')
        s=once(s,'queue_submit_csr_board control(.*);','queue_submit_csr_board control(.start(legacy_start),.queue_base(legacy_base),.queue_count(legacy_count),.parameter_ready_out(parameter_ready),.param_generation_out(parameter_generation),.*);')
    elif p.name=='v020_axi_wrapper.sv':
        # Wrapper is strict Verilog for Vivado AXI interface inference.
        s=once(s,'module v020_axi_wrapper (','module v020_axi_wrapper (\n input wire plan_lock,plan_matrix_valid,\n input wire [31:0] plan_matrix_base,plan_matrix_count,\n output wire plan_matrix_ready,plan_matrix_done,plan_matrix_fault,\n output wire parameter_ready,output wire [31:0] parameter_generation,parameter_end,')
        s=once(s,'queued_v020_board core (', 'queued_v020_board core (\n .plan_lock(plan_lock),.plan_matrix_valid(plan_matrix_valid),.plan_matrix_base(plan_matrix_base),.plan_matrix_count(plan_matrix_count),.plan_matrix_ready(plan_matrix_ready),.plan_matrix_done(plan_matrix_done),.plan_matrix_fault(plan_matrix_fault),.parameter_ready(parameter_ready),.parameter_generation(parameter_generation),.parameter_end(parameter_end),')
    emit(p.name,s)
(ROOT/'reports/MATRIX_INTEGRATION_BASELINE.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
print('V022_MATRIX_DERIVED; storage still serial; static epoch guard added; sealed source untouched')
