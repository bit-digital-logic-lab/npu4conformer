"""Actual board smoke: same captured CASE0000 input Q, never upload golden output."""
import argparse,hashlib,json,struct,sys,time
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';OLD=ROOT.parent/'model_a_v0_21';HERE=ROOT.parent/'model_a_v0_21_1_board_20261013_001'
sys.path[:0]=[str(ROOT/'host'),str(BASE/'host'),str(OLD/'host'),str(ROOT.parent/'model_a_lowbit_v13/host')]
from parameters import ParameterImage,ParameterTransport
from fusion_backend import FusionBoard
from lowbit_executor import Tensor
from ethernet_transport import open_link
from seal_runtime import verify
p=argparse.ArgumentParser();p.add_argument('--allow-hardware',action='store_true');p.add_argument('--board-receipt',required=True);p.add_argument('--out',default='first_conv_board001');args=p.parse_args()
if not args.allow_hardware:p.error('Explicit hardware authorization required')
if not args.out.replace('_','').isalnum():p.error('Safe tag')
verify('full002');receipt=Path(args.board_receipt).resolve()
if ROOT/'board' not in receipt.parents or receipt.name!='started.txt' or (receipt.parent/'stopped.txt').exists():p.error('Own live gateway receipt required')
text=receipt.read_text();elf=hashlib.sha256((ROOT/'ps/gateway_v022.elf').read_bytes()).hexdigest()
if 'V022_PHASE1_GATEWAY_STARTED' not in text or 'USR_ACCESS=A51A2201' not in text or 'ELF_SHA256='+elf not in text:p.error('Receipt identity')
proof=json.loads((HERE/'first_conv_verified.json').read_text());image=ParameterImage(ROOT/'assets/parameters002')
for name in ('first_conv_input_q.bin','first_conv_output_f32.bin','first_conv_output_q.bin'):
    if hashlib.sha256((HERE/name).read_bytes()).hexdigest()!=proof['sha256'][name]:raise ValueError('Captured reference changed')
key='encoder|/encoder/embed/conv/conv.0/Conv';program=image.meta['v211_programs'][key];iv=program['values'][program['input_id']]['words'];shape=tuple(iv[6:6+iv[5]])
q=np.fromfile(HERE/'first_conv_input_q.bin','<i2').reshape(shape);scale=np.frombuffer(image.data,'<f4',count=1,offset=iv[2]-0x10000000)[0]
out=ROOT/'reports'/args.out;out.mkdir(exist_ok=False);link=open_link('169.254.15.6',49152,local_host='169.254.147.66',timeout=5,retries=0,deadline=time.perf_counter()+600)
report=dict(completed=False,hardware_executed=True,cpu_numeric_fallback=False,scope='Real firstCONV all1257984 outputs, PL directDDR plan, bitcomparison to prior confirmedV211capture; not wholeCASE or WER',parameter_load_included=False)
try:
    transport=ParameterTransport(link,image);before=transport.require_ready();backend=FusionBoard(link,image)
    # Host data field is a placeholder; only the original Q input is uploaded.
    started=time.perf_counter();actual=backend.fuse_plan(image,key,Tensor(np.zeros(shape,np.float32),q,np.asarray(scale,np.float32)))
    report['wall_seconds']=time.perf_counter()-started;after=transport.require_ready()
    if before[37]!=after[37] or before[38]!=after[38]:raise ValueError('Run changed parameter generation/upload')
    actual.data.astype('<f4').tofile(out/'hardware_output_f32.bin');actual.q.astype('<i2').tofile(out/'hardware_output_q.bin')
    gold=np.fromfile(HERE/'first_conv_output_f32.bin','<f4').reshape(actual.data.shape);goldq=np.fromfile(HERE/'first_conv_output_q.bin','<i2').reshape(actual.q.shape)
    report.update(completed=True,f32_bit_exact=np.array_equal(actual.data.view('<u4'),gold.view('<u4')),q_bit_exact=np.array_equal(actual.q,goldq),max_abs=float(np.max(np.abs(actual.data-gold))),parameter_upload_bytes=0,parameter_generation=after[37],backend=backend.report())
    if not report['f32_bit_exact'] or not report['q_bit_exact']:raise ValueError('FirstCONV differs: stop before wholeCASE')
    print('V022_REAL_FIRST_CONV_PASS',report['wall_seconds'],flush=True)
except BaseException as error:report['error']=repr(error);raise
finally:
    (out/'result.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8');link.close()
