"""Actual16x16 W7/A16/C48 engine and DMA with static-queue epoch bias."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1'
tag=sys.argv[1] if len(sys.argv)>1 else 'matrix_epoch001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
tb=(BASE/'tests/tb_queue.sv').read_text().replace('queue_submit_csr_board csr(',"queue_submit_csr_board csr(.plan_lock(1'b0),.parameter_ready_out(),.param_generation_out(),")
tb=tb.replace('queued_v020_monitored dut(',"reg [31:0] epoch_bias=0;\n queued_v020_monitored dut(.epoch_bias(epoch_bias),")
tb=tb.replace('completion_cookie!=100+retired','completion_cookie!=100+retired+epoch_bias')
tb=tb.replace('if(!$value$plusargs("mode=%d",mode))mode=0;','if(!$value$plusargs("mode=%d",mode))mode=0;\n if($value$plusargs("bias=%d",epoch_bias))begin end')
path=out/'tb_matrix.sv';path.write_text(tb)
names=['task_queue.sv','axi_dma_v019.sv','pe_direct_v020.sv','array16_direct_v020.sv','block_address_v020.sv','block_engine_l1bank_v020.sv','block_storage_dma_prefetch.sv','c_cache_banked4.sv','operand_banks_v020.sv','queued_v020_monitored.sv','queue_submit_csr_board.sv']
src=[path,*[ROOT/'rtl'/name for name in names]];exe=out/'matrix.vvp'
cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\iverilog.exe','-g2012','-DV020_WIDE4','-DV020_CBANK','-DV020_CSR','-s','tb_queued_v020','-o',str(exe),*map(str,src)],cwd=out,capture_output=True,text=True,timeout=90)
(out/'compile.log').write_text(cp.stdout+cp.stderr);cp.check_returncode();rows=[]
for name in ('l1bankcsr001','l1bankmulti001'):
    folder=BASE/'tests/vectors'/name;meta=json.loads((folder/'meta.json').read_text())
    for bias in (0,1000):
        for mode in (range(7) if bias==0 and name=='l1bankcsr001' else [0]):
            cp=subprocess.run([r'D:\app\iverilog\iverilog\bin\vvp.exe','-i',str(exe),f'+input={folder.as_posix()}/input.hex',f'+gold={folder.as_posix()}/gold.hex',f'+mode={mode}',f'+bias={bias}',*[f'+{k}={v}' for k,v in meta.items()]],cwd=out,capture_output=True,text=True,timeout=180)
            (out/f'{name}_{bias}_{mode}.log').write_text(cp.stdout+cp.stderr);print(cp.stdout,flush=True)
            passed=cp.returncode==0 and 'QUEUED_V020_PASS' in cp.stdout;rows.append(dict(fixture=name,bias=bias,mode=mode,passed=passed))
            if not passed:raise RuntimeError('Matrix epoch failed')
(out/'result.json').write_text(json.dumps(dict(passed=True,hardware_accessed=False,scope='Actual16x16 W7/A16/C48 RTL and realAXIDMA, static epochs offset0/1000, split accumulation/edges/parity/bus errors. External board CSR ownership not exercised by this test.',tests=rows,source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}),indent=2)+'\n')
print('V022_MATRIX_EPOCH_ALL_PASS',len(rows))
