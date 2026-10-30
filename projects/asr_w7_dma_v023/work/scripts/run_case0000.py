"""Explicit load/run phases; real FPGA only, no CPU numerical fallback."""
import argparse,hashlib,importlib.util,json,struct,sys,time
from pathlib import Path
from datetime import datetime,timezone
import numpy as np
import onnx
ASYNC=Path(__file__).resolve().parents[1];ROOT=ASYNC;BASE=ROOT.parent/'model_a_v0_21_1';OLD=ROOT.parent/'model_a_v0_21';sys.dont_write_bytecode=True
p=argparse.ArgumentParser();p.add_argument('stage',choices=['verify','status','load','run']);p.add_argument('--out',default='case0000_board001');p.add_argument('--allow-hardware',action='store_true');p.add_argument('--adopt-existing',action='store_true');p.add_argument('--prototype-carrier-v21',action='store_true');p.add_argument('--board-receipt');a=p.parse_args()
host=ASYNC/'host'
sys.path[:0]=[str(host),str(BASE/'host'),str(OLD/'host'),str(ROOT.parent/'model_a_lowbit_v13/host')]
from parameters import ParameterImage,ParameterTransport
def module(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
image=ParameterImage(ROOT/'assets/parameters002')
if a.stage=='verify':print(json.dumps(dict(verified=True,hardware_accessed=False,image_bytes=len(image.data),subgraphs=len(image.meta['v211_programs']),image_sha256=image.meta['image_sha256']),indent=2));raise SystemExit(0)
if not a.allow_hardware:p.error('Explicit --allow-hardware required')
if a.prototype_carrier_v21:p.error('100MHz prototype is NOT released/tested; use production125MHz only')
sys.path.insert(0,str(ROOT/'scripts'))
from seal_runtime import verify
seal=verify('full002')
if not a.board_receipt:p.error('Fresh board/<tag>/started.txt receipt required')
receipt_path=Path(a.board_receipt).resolve()
if ASYNC/'board' not in receipt_path.parents or receipt_path.name!='started.txt' or (receipt_path.parent/'stopped.txt').exists():p.error('Own current running gateway receipt required')
receipt=receipt_path.read_text(encoding='utf-8')
if 'V022_PHASE1_GATEWAY_STARTED' not in receipt or 'USR_ACCESS=A51A2201' not in receipt or 'ELF_SHA256='+sha(ASYNC/'ps/gateway_v022.elf') not in receipt:p.error('Gateway receipt does not match sealed release')
if not a.out.replace('_','').isalnum():p.error('Safe output name required')
if a.adopt_existing and a.stage!='load':p.error('Adopt only belongs to explicit load phase')
from ethernet_transport import open_link
from resident_backend import ResidentBackend
from types import SimpleNamespace
link=open_link('169.254.15.6',49152,local_host='169.254.147.66',timeout=5,retries=0,deadline=time.perf_counter()+14400)
transport=ParameterTransport(link,image)
try:
    if a.stage=='status':
        print(json.dumps(dict(telemetry=list(transport.state()),vm=list(struct.unpack('<64I',link.request(0x42,struct.pack('<HH',0xe400,64))))),indent=2));raise SystemExit(0)
    if a.stage=='load':
        before=transport.state();started=time.perf_counter();last=[0]
        def progress(done,total):
            if time.perf_counter()-last[0]>10:last[0]=time.perf_counter();print('V211_PARAMETER_LOAD',done,total,flush=True)
        after=transport.load(a.adopt_existing,progress)
        print(json.dumps(dict(stage='load',ready=True,generation=after[37],seconds=time.perf_counter()-started,parameter_payload_bytes=(after[38]-before[38])&0xffffffff,readback_verified_bytes=after[45],image_bytes=len(image.data)),indent=2));raise SystemExit(0)
    before=transport.require_ready();out=ROOT/'reports'/a.out;out.mkdir(exist_ok=False)
    from fusion_backend import FusionBoard
    from fusion_executor import FusionExecutor
    from frozen_imports import FROZEN
    common=module('common_run211',ROOT.parent/'model_a_lowbit_v9/scripts/golden_common.py');prep=ROOT.parent/'model_a_lowbit_v9/reports/case_preparation_001';meta=json.loads((prep/'result.json').read_text())
    for name,h in meta['artifact_sha256'].items():
        if sha(prep/name)!=h:raise ValueError('Independent reference changed')
    inputs,original,provenance=common.load_golden(FROZEN,meta['original_provenance']['case_dir'],ROOT.parent/'model_a_int16_runs/run01/int16_qdq_fix01')
    if provenance!=meta['original_provenance']:raise ValueError('CASE0000 provenance')
    package=ROOT.parent/'model_a_7bit_ctc_int16_handoff_v1';loader=module('loader_run211',package/'load_models.py')
    backend=FusionBoard(link,image);actual={};stages={};started=time.perf_counter()
    report=dict(completed=False,hardware_executed=True,cpu_numeric_fallback=False,started_utc=datetime.now(timezone.utc).isoformat(),parameter_generation=before[37],provenance=provenance,
        carrier='V022 phase1 PL plans+DDR arithmetic/layout,125MHz candidate',core_hz=125000000,board_receipt=str(receipt_path),release_bit_sha256=seal['bit_sha256'],elf_sha256=sha(ASYNC/'ps/gateway_v022.elf'),runtime_derivation=str(ROOT/'scripts/derive_runtime_v022.py'),
        scope='CASE0000 128frames/16suppliedtokens; all38CONV+30FFN PL plans includingQDQ directDDR; outside nodes retain host DAG. Phase1: integer matrix storage still serial, not wholegraphPL; not free firsttoken/CTC/WER',parameter_load_included_in_case_time=False,
        image_sha256=image.meta['image_sha256'],runner_sha256=sha(Path(__file__)),vm_source_sha256=sha(ASYNC/'ps/vm_pl.c'),base_numerical_vm_sha256=sha(BASE/'ps/vm211.c'))
    try:
        for part in ('encoder','decoder'):
            model_begin=time.perf_counter();packed=onnx.load(package/'models'/f'{part}.onnx');records=json.loads(next(x.value for x in packed.metadata_props if x.key=='model_a_special_quant_v1'))['tensors'];del packed
            if sha(package/'models'/f'{part}.onnx')!=image.meta['model_hashes'][part]:raise ValueError('Model hash')
            exe=FusionExecutor(loader.restore_packed_model(package/'models'/f'{part}.onnx'),backend,records,image,part);prepared=time.perf_counter()-model_begin;last=[0]
            def progress(i,total,name,op):
                if time.perf_counter()-last[0]>10:last[0]=time.perf_counter();print('V211_BOARD',part,i,total,name,flush=True)
            feed={'feats':inputs['feats']} if part=='encoder' else {'memory':actual['encoder_memory'],'tokens':inputs['tokens']};begin=time.perf_counter();outputs=exe.run(feed,progress=progress)
            stages[part]=dict(seconds=time.perf_counter()-begin,model_prepare_seconds=prepared,execution=exe.last_stats,fused_calls=exe.fused_calls,logical_original_nodes=exe.original_dynamic_count)
            if part=='encoder':actual.update(encoder_memory=outputs['memory'],encoder_memory_lengths=outputs['memory_lengths'])
            else:actual['decoder_log_probs']=outputs['log_probs']
        after=transport.require_ready()
        if after[38]!=before[38] or after[37]!=before[37]:raise ValueError('Parameter reload/generation changed during run')
        np.savez(out/'hardware_outputs.npz',**actual)
        with np.load(prep/'reference7_outputs.npz') as z:report['vs_7bit_onnx']={k:common.compare_golden(v,z[k]) for k,v in actual.items()}
        with np.load(OLD/'reports/case0000_board001/hardware_outputs.npz') as z:report['vs_v21_hardware']={k:common.compare_golden(v,z[k]) for k,v in actual.items()}
        report.update(completed=True,parameter_upload_bytes=0,stages=stages,backend=backend.report(),parameter_before=list(before),parameter_after=list(after),ps_after=ResidentBackend.telemetry(SimpleNamespace(link=link)))
    except BaseException as e:report['error']=repr(e);raise
    finally:
        report['elapsed_seconds']=time.perf_counter()-started;report['native_matrix_tasks']=backend.v21_tasks
        report['fusion_calls']=backend.fusion_calls;report['fusion_stats']=dict(backend.fusion_stats)
        (out/'result.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(completed=True,seconds=report['elapsed_seconds'],encoder=stages['encoder']['seconds'],decoder=stages['decoder']['seconds'],parameter_upload_bytes=0,vs_v21_bit_exact=all(c['bit_exact'] for c in report['vs_v21_hardware'].values()),strict_onnx_pass=all(c['pass_golden'] for c in report['vs_7bit_onnx'].values())),indent=2))
finally:link.close()
