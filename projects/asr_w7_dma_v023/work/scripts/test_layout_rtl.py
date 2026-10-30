"""Actual bit-layout hardware with both real AXI DMAs and stalled AXI memory."""
import hashlib,json,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1] if len(sys.argv)>1 else 'layout_rtl001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
src=[ROOT/'tests/tb_layout_axi.sv',ROOT/'tests/axi128_memory_bfm.sv',*[ROOT/'rtl'/x for x in ('ddr_layout_axi.sv','ddr_layout_engine.sv','u16_divmod.sv','axi_dma_v019.sv')]]
exe=out/'layout.vvp';cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-s','tb_layout_axi','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode();rows=[]
for case in json.loads((ROOT/'tests/layout_fixtures/meta.json').read_text()):
    for mode in (range(13) if case['name']=='copy_i16' else [0]):
        t=time.perf_counter();f=ROOT/'tests/layout_fixtures'/case['name']
        cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),f'+folder={f.as_posix()}',f'+nbytes={case["output_bytes"]}',f'+mode={mode}'],cwd=out,capture_output=True,text=True,timeout=180)
        (out/f'{case["name"]}_{mode}.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');print(case['name'],cp.stdout,flush=True)
        passed=cp.returncode==0 and 'V022_LAYOUT_AXI_PASS' in cp.stdout;rows.append(dict(fixture=case['name'],mode=mode,passed=passed,host_simulation_seconds=time.perf_counter()-t))
        if not passed:raise RuntimeError('Layout failed '+case['name']+'/'+str(mode))
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual integer-index/layout RTL +2actual AXI DMAs; alloutputbytes against independent logicalmatrix/conv oracle. Includes CASE0000conv0 shape, padding/depthwise31/tiledC48 compact,NCHW edges, ACL and drain. No neural CPU fallback, but this is RTL/BFM not FPGA or full ASR.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n',encoding='utf-8');print('V022_LAYOUT_REAL_AXI_PASS',len(rows))
