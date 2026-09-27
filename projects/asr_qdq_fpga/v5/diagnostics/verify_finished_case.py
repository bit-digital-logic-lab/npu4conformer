"""Independent final verifier: original golden files, scalar Python criterion.
Does not call the deployment comparator, generate references, or access FPGA.
"""
from pathlib import Path
import argparse,json,hashlib,math
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--run',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    if (ROOT/'reports').resolve() not in args.out.resolve().parents or args.out.exists():ap.error('fresh output under v5/reports required')
    run=json.loads((args.run/'result.json').read_text())
    if not all(run.get(k) is True for k in ['completed','physical_fpga_executed','encoder_hardware_executed','full_chain_tested','end_provenance_verified','decoder_uses_actual_encoder_output']):raise SystemExit('No complete proven physical full-chain run')
    case=Path(run['provenance']['case_dir']);source=case/'expected.npz'
    if sha(source)!='da4e158e5ff4da8b0615e8a0fb70bbf365d7b061524af921bef3565db49c4d99':raise SystemExit('Original case_0000 golden identity mismatch')
    actual_file=args.run/'hardware_outputs.npz';actual=np.load(actual_file,allow_pickle=False);expected=np.load(source,allow_pickle=False)
    keys=['encoder_memory','encoder_memory_lengths','decoder_log_probs'];comparisons={}
    for key in keys:
        a=actual[key];b=expected[key];same=a.shape==b.shape and a.dtype==b.dtype
        failed=0;maximum=0.0
        if same:
            for x,y in zip(a.ravel(),b.ravel()):
                if a.dtype.kind in 'iu':failed+=int(int(x)!=int(y));continue
                x=float(x);y=float(y);error=abs(x-y);maximum=max(maximum,error)
                failed+=int(not(math.isfinite(x) and math.isfinite(y)) or error>0.001+0.001*abs(y))
        comparisons[key]=dict(shape=list(a.shape),dtype=str(a.dtype),shape_dtype_match=same,elements=int(a.size),failed_elements=failed,max_abs=maximum,bit_exact=same and a.tobytes()==b.tobytes(),passed=same and failed==0)
    uart=ROOT.parent/'golden_validation/reports/case_0000_v2_20260922_170622/hardware_outputs.npz'
    old=np.load(uart,allow_pickle=False)['decoder_log_probs'];decoder_same=actual['decoder_log_probs'].tobytes()==old.tobytes()
    clean=run['ethernet_after_close']['close_confirmed'] and not run['ethernet_after_close']['poisoned']
    report=dict(independent_original_golden_check=True,comparator='scalar Python float64 element loop; no imported deployment comparator',pass_all=all(v['passed'] for v in comparisons.values()) and clean,comparisons=comparisons,original_golden_path=str(source),original_golden_sha256=sha(source),hardware_outputs_path=str(actual_file),hardware_outputs_sha256=sha(actual_file),physical_result_sha256=sha(args.run/'result.json'),decoder_bit_exact_prior_uart=bool(decoder_same),prior_uart_scope='Decoder-only with original golden Encoder memory; not old full-chain proof',clean_session=clean)
    with args.out.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    print(json.dumps(report,indent=2));return 0 if report['pass_all'] else 1
if __name__=='__main__':raise SystemExit(main())
