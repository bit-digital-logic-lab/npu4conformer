"""One PL start: DDR copy -> real FP32 -> I16 -> DDR copy, five AXI DMAs."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
tag=sys.argv[1] if len(sys.argv)>1 else 'layout_cluster001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
cluster=(ROOT/'rtl/ddr_execution_cluster_v022.sv').read_text()
# Mechanical port/AXI harness generation from the already tested three-port bench.
original=(ROOT/'tests/tb_plan_cluster.sv').read_text()
prefix=original[:original.index(' reg [7:0] gold_float')]
prefix=prefix.replace('module tb_plan_cluster;','module tb_layout_cluster;').replace('plan_count=2','plan_count=4')
prefix=prefix.replace('ddr_execution_cluster dut(.*);','ddr_execution_cluster_v022 dut(.*);')
prefix=prefix.replace('wire [119:0]','wire [199:0]').replace('wire [23:0] arlen','wire [39:0] arlen').replace('wire [8:0] arsize','wire [14:0] arsize').replace('wire [5:0] arburst','wire [9:0] arburst').replace('wire [383:0]','wire [639:0]').replace('wire [5:0] rresp','wire [9:0] rresp').replace('wire [23:0] awlen','wire [39:0] awlen').replace('wire [8:0] awsize','wire [14:0] awsize').replace('wire [5:0] awburst','wire [9:0] awburst').replace('wire [47:0]','wire [79:0]').replace('wire [5:0] bresp','wire [9:0] bresp')
for signal in ('arvalid','arready','rlast','rvalid','rready','awvalid','awready','wlast','wvalid','wready','bvalid','bready'):
    prefix=prefix.replace('wire [2:0] '+signal+';','wire [4:0] '+signal+';')
ports=cluster.split('module ddr_execution_cluster_v022(',1)[1].split(');',1)[0]
import re
decl=[]
for piece in re.sub(r'\(\*.*?\*\)','',ports,flags=re.S).split(','):
    match=re.fullmatch(r'\s*(input|output)\s+wire\s*(\[[^]]+\])?\s*(\w+)\s*',piece)
    if not match:raise ValueError(piece)
    direction,width,name=match.groups()
    if name.startswith('layout_'):decl.append(f' wire {width or ""} {name};')
prefix=prefix.replace(' ddr_execution_cluster_v022 dut(.*);','\n'.join(decl)+'\n ddr_execution_cluster_v022 dut(.*);')
widths=dict(araddr=40,arlen=8,arsize=3,arburst=2,arvalid=1,arready=1,rdata=128,rresp=2,rlast=1,rvalid=1,rready=1,awaddr=40,awlen=8,awsize=3,awburst=2,awvalid=1,awready=1,wdata=128,wstrb=16,wlast=1,wvalid=1,wready=1,bresp=2,bvalid=1,bready=1)
assign=[]
for port,side in ((3,'read'),(4,'write')):
    for name,width in widths.items():
        target=f'layout_{side}_m_axi_{name}';bus=f'{name}[{port*width}+:{width}]'
        output=name not in ('arready','rdata','rresp','rlast','rvalid','awready','wready','bresp','bvalid')
        assign.append(f' assign {bus if output else target}={target if output else bus};')
prefix=prefix.replace(' axi128_memory_bfm #(.PORTS(3))','\n'.join(assign)+'\n axi128_memory_bfm #(.PORTS(5))')
prefix=prefix.replace('mode==4,inject_write_error=1\'b0','mode==4,inject_write_error=mode==5')
suffix=r'''
 reg [7:0] gold_float[0:4003],gold_q[0:2001],parameters_before[0:16383];
 reg [4095:0] folder;
 task put32(input integer at,input [31:0] value);
  begin for(integer j=0;j<4;j=j+1)ddr.memory[at+j]=value[j*8+:8];end
 endtask
 task instruction(input integer i,input [31:0] kind,input [31:0] pointer,input [31:0] bytes);
  begin
   for(integer j=0;j<16;j=j+1)put32(196608+i*64+j*4,0);
   put32(196608+i*64,32'h22504c4e);put32(196608+i*64+4,kind);
   put32(196608+i*64+8,i+1);put32(196608+i*64+12,i==0?32'hffffffff:i-1);
   put32(196608+i*64+16,pointer);put32(196608+i*64+20,bytes);
  end
 endtask
 task copy_descriptor(input integer at,input [31:0] a,input [31:0] d);
  begin
   for(integer j=0;j<32;j=j+1)put32(at+j*4,0);
   put32(at,32'h224c4159);put32(at+8,a);put32(at+12,d);
   put32(at+16,1001);put32(at+20,2);
  end
 endtask
 always @(posedge clk)if(rst_n)begin
  cycle<=cycle+1;
  if(matrix_valid)$fatal(1,"Unexpected matrix dispatch");
  if(cycle>120000)$fatal(1,"Plan watchdog state=%d",dut.planner.state);
 end
 initial begin
  if(!$value$plusargs("folder=%s",folder))$fatal(1,"Arguments");
  if($value$plusargs("mode=%d",mode))begin end
  $readmemh({folder,"/memory.hex"},ddr.memory);
  $readmemh({folder,"/gold_float.hex"},gold_float);$readmemh({folder,"/gold_q.hex"},gold_q);
  instruction(0,3,32'h10001200,128);instruction(1,2,32'h10001000,64);
  instruction(2,2,32'h10001100,64);instruction(3,3,32'h10001280,128);
  // Copy input as bytes, not as I16 values, then Add and quantize through PL.
  copy_descriptor(196608+4608,32'h04000000,32'h04004000);
  put32(196608+4608+16,2002);
  copy_descriptor(196608+4736,32'h04020000,32'h04028000);
  put32(196608+4096+8,32'h04004000);
  case(mode)
   1:put32(196608+4608,0);
   2:put32(196608+64+12,7);
   7:put32(196608+4608+12,32'h10002000);
  endcase
  for(integer j=0;j<16384;j=j+1)parameters_before[j]=ddr.memory[196608+j];
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  if(mode==3)begin wait(layout_busy);repeat(30)@(negedge clk);generation=8;end
  if(mode==6)begin repeat(20)@(negedge clk);start=1;@(negedge clk);start=0;end
  wait(done);@(negedge clk);
  if(busy||vector_busy||layout_busy)$fatal(1,"Plan done before operator drain");
  for(integer j=0;j<5;j=j+1)if(ddr.ra[j]||ddr.wa[j])$fatal(1,"Plan done before AXI drain");
  for(integer j=0;j<16384;j=j+1)if(parameters_before[j]!==ddr.memory[196608+j])$fatal(1,"Readonly parameters modified");
  if(mode==0||mode==6)begin
   if(fault||completed!=4||last_ticket!=4)$fatal(1,"Plan error=%h complete=%d",error_code,completed);
   for(integer j=0;j<4004;j=j+1)if(ddr.memory[65536+j]!==gold_float[j])$fatal(1,"FP output mismatch %d",j);
   for(integer j=0;j<2002;j=j+1)if(ddr.memory[163840+j]!==gold_q[j])$fatal(1,"Copied Q output mismatch %d",j);
   if(mode==6&&rejected_starts!=1)$fatal(1,"START replay");
  end else if(!fault)$fatal(1,"Fault missing mode=%d",mode);
  if(mode==2&&completed!=1)$fatal(1,"Completed prefix lost");
  $display("V022_LAYOUT_CLUSTER_PASS mode=%d cycles=%d completed=%d error=%h",mode,cycles,completed,error_code);$finish;
 end
endmodule
'''
tb=out/'tb_layout_cluster.sv';tb.write_text(prefix+suffix,encoding='utf-8')
src=[tb,ROOT/'tests/axi128_memory_bfm.sv',ROOT/'tests/fma_forbidden_stub.sv',*[ROOT/'rtl'/x for x in ('ddr_execution_cluster_v022.sv','pl_execution_plan_v022.sv','ddr_vector_axi.sv','ddr_vector_engine.sv','asr_fp32_alu.sv','ddr_layout_axi.sv','ddr_layout_engine.sv','u16_divmod.sv','axi_dma_v019.sv')]]
exe=out/'cluster.vvp';cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_layout_cluster','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode();rows=[]
for mode in range(8):
    cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),'+folder='+str(ROOT/'tests/plan_fixture').replace('\\','/'),f'+mode={mode}'],cwd=out,capture_output=True,text=True,timeout=90)
    (out/f'mode{mode}.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');print(cp.stdout,flush=True)
    passed=cp.returncode==0 and 'V022_LAYOUT_CLUSTER_PASS' in cp.stdout;rows.append(dict(mode=mode,passed=passed))
    if not passed:raise RuntimeError('Layout cluster failed mode'+str(mode))
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='One START and five actual AXI DMAs: PL layout copy, FP32 Add, I16 cast, layout copy. Parameters read-only and intermediates DDR-resident. Matrix arithmetic not exercised; separate FMA vendor test.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n',encoding='utf-8')
print('V022_LAYOUT_CLUSTER_ALL_PASS',len(rows))
