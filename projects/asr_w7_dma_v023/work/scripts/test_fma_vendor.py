"""Use official frozen vendor functional netlist, never an arithmetic stub."""
import hashlib,json,os,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1'
tag=sys.argv[1] if len(sys.argv)>1 else 'vendor_fma001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
viv=Path(r'D:\fpga\new2025\vitis\2025.2\Vivado');vendor=BASE/'soc_full/build/full001/project/full.gen/sources_1/ip/asr_fma_ip/asr_fma_ip_sim_netlist.v'
src=[ROOT/'tests/tb_vector_axi.sv',ROOT/'tests/axi128_memory_bfm.sv',*[ROOT/'rtl'/x for x in ('ddr_vector_axi.sv','ddr_vector_engine.sv','asr_fp32_alu.sv','axi_dma_v019.sv')],vendor,viv/'data/verilog/src/glbl.v']
env=os.environ.copy();env['TEMP']=str(ROOT/'tmp');env['TMP']=env['TEMP'];env['XILINX_LOCAL_USER_DATA']='NO'
options=out/'simulation_options.txt'
options.write_text('-runall\n-testplusarg "folder='+str(ROOT/'tests/fma_fixture').replace('\\','/')+'"\n-testplusarg "nbytes=4004"\n-testplusarg "mode=0"\n',encoding='utf-8')
commands=[([str(viv/'bin/xvlog.bat'),'-sv',*map(str,src)],'compile.log'),
 ([str(viv/'bin/xelab.bat'),'tb_vector_axi','glbl','-L','unisims_ver','-L','unimacro_ver','--relax','--debug','typical','-s','v022_fma'],'elaborate.log'),
 ([str(viv/'bin/xsim.bat'),'v022_fma','-f',str(options)],'simulation.log')]
for cmd,name in commands:
    t=time.perf_counter();cp=subprocess.run(cmd,cwd=out,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
    (out/name).write_text(cp.stdout+cp.stderr,encoding='utf-8');print(name,cp.returncode,time.perf_counter()-t,flush=True);print(cp.stdout[-2500:],flush=True)
    cp.check_returncode()
assert 'V022_VECTOR_AXI_PASS' in cp.stdout and 'FATAL' not in cp.stdout
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual AXI DMA/vector RTL + official frozen vendorFMA functionalnetlist inXsim.1001outputs, cancellation case and tail/stalls. Not FPGA or boardDDR performance.',source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n',encoding='utf-8');print('V022_OFFICIAL_VENDOR_FMA_PASS')
