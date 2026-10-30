"""Separate runtime; reuse sealed outside-DAG arithmetic and control-only async."""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';ASYNC=ROOT.parent/'model_a_v0_21_1_board_20261013_001/async002'
m=json.loads((ROOT/'assets/parameters002/manifest.json').read_text())
def emit(p,s):
    if p.exists():raise ValueError('Fresh runtime '+str(p))
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
for name in ('backend_v021.py','base_v021.py','layout.py','parameters.py','fusion_backend.py'):
    s=(ASYNC/'host'/name).read_text()
    s=s.replace('0xa51a2116','0xa51a2202').replace('0x2111a501','0x2201a501')
    if name=='fusion_backend.py':
        s=s.replace("name='V0.21.1 board CONV/FFN DRAM programs + PL numerical cores'","name='V0.22 phase1 PL plans, direct DDR CONV/FFN and layout'")
        # Same original program IDs/boundaries, but the PS implementation starts
        # one immutable plan. Host polls once per closed program, not per matrix.
        s=s.replace('from vm_metrics import delta_vm','from plan_metrics import delta_plan')
        s=s.replace('vm_counter_delta=delta_vm(self.initial_vm_status,final)','plan_counter_delta=delta_plan(self.initial_vm_status,final)')
        s=s.replace("conv_ffn_numeric_location='PL, PS bit-copy/indices/queue control only'","conv_ffn_numeric_location='PL plan + direct DDR, PS start/completion/error only'")
        s=s.replace('self.initial_vm_status=list(status)',"if status[30]!=2201:raise RuntimeError('V022 plan ABI required')\n        self.initial_vm_status=list(status)")
    emit(ROOT/'host'/name,s)
for name in ('gateway_main_async.c','async_dispatch.inc.c','gateway_async.c','vm211.h'):
    s=(ASYNC/'ps'/name).read_text().replace('0xa51a2116','0xa51a2202').replace('0x2111a501','0x2201a501')
    if name=='gateway_async.c':
        needle='if(base==0xe400)return vm211_dispatch(io,req,n,reply,received);'
        assert s.count(needle)==1
        s=s.replace(needle,needle+'\n if((*(volatile uint32_t *)(uintptr_t)0xa9000004u)&1u)return V10_BUSY; /* no mutation while an accepted PL plan drains */')
    emit(ROOT/'ps'/name,s)
entries=[]
for key,p in m['v022_programs'].items():
    original=m['v211_programs'][key]
    queues=sum(op[0]<=2 for op in original['ops'])
    vals=[p['original_program_address'],p['plan_address'],p['plan_count'],p['matrix_tasks'],queues,len(original['ops']),original['values'][original['output_id']]['words'][3],1 if p['kind']=='CONV' else 2]
    entries.append(' {'+','.join(f'0x{v:08x}u' for v in vals)+'}')
header='#ifndef V022_PLAN_INDEX_H\n#define V022_PLAN_INDEX_H\n'
for key,value in [('IMAGE_BYTES',m['image_bytes']),('IMAGE_CRC',m['image_crc32']),('MODEL_LO',m['model_tag_lo']),('MODEL_HI',m['model_tag_hi'])]:header+=f'#define V022_{key} 0x{value:08x}u\n'
header+='struct plan_entry {uint32_t program,plan,count,matrix_tasks,matrix_queues,ops,output_elements,kind;};\nstatic const struct plan_entry plan_index[]={\n'+',\n'.join(entries)+'\n};\n#endif\n'
emit(ROOT/'ps/plan_index.h',header)
build=(ASYNC/'scripts/build.ps1').read_text().replace('gateway_async002','gateway_v022').replace('vm211_async.c','vm_pl.c')
build=build.replace("$env:TEMP=Join-Path (Split-Path -Parent $taskRoot) 'tmp'","$env:TEMP=Join-Path $taskRoot 'tmp'")
emit(ROOT/'scripts/build_gateway.ps1',build)
print('V022_RUNTIME_DERIVED; immutable68-entry index bound to newimage CRC/model; outside arithmetic unchanged')
