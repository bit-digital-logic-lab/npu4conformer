"""Physical V5 primitive/compound regression; references generated OFFLINE.
References are comparisons only, never used to execute the model.
"""
from pathlib import Path
import sys,argparse,json,time,hashlib,traceback
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'host'),str(ROOT/'diagnostics')]
from frozen_imports import require_frozen_modules
require_frozen_modules()
from compat_ethernet import CompatEthernetBackend
from ethernet_transport import open_link
from compat_cpu import CompatCpuBackend

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--allow-hardware',action='store_true');ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    if not args.allow_hardware:ap.error('explicit --allow-hardware required')
    if (ROOT/'reports').resolve() not in args.out.resolve().parents:ap.error('report must be under v5/reports')
    args.out.mkdir(exist_ok=False,parents=True);rng=np.random.default_rng(5932);cpu=CompatCpuBackend();tests=[]
    def case(name,method,values,kwargs={},exact=True):tests.append((name,method,values,kwargs,getattr(cpu,method)(*values,**kwargs),exact))
    def rand(shape,scale=1):return (rng.normal(size=shape)*scale).astype(np.float32)
    for shapes in [((31,129),(129,64)),((3,521),(521,3)),((1,15),(15,31)),((1,31),(31,65))]:
        case('matrix '+str(shapes),'matmul_f32',[rand(shapes[0]),rand(shapes[1])])
    case('FMA broadcast','fma',[rand((2,512)),rand((512,)),rand((512,))])
    q=rng.integers(-32767,32768,(31,512),dtype=np.int16);x=q.astype(np.float32)*np.float32(.00031)
    case('LayerNorm extent512','layer_norm',[x,rand((512,)),rand((512,))])
    case('Sigmoid rational','unary',['Sigmoid',rand((8193,),9)])
    case('Softmax SIMD16','softmax',[rand((8,31,31),5)])
    case('Softmax FTZ','softmax',[np.array([[0,-88,-90,-100,-10000]],np.float32)],exact=False)
    case('BatchNorm','batch_norm',[rand((1,512,31)),rand((512,)),rand((512,)),rand((512,)),np.abs(rand((512,)))])
    report=dict(physical_fpga_executed=True,reference='offline random/edge CPU arithmetic (NOT original case acceptance)',tests=[],pass_all=False)
    started=time.perf_counter();link=None
    try:
        link=open_link();backend=CompatEthernetBackend(link)
        for name,method,values,kwargs,expected,exact in tests:
            actual=getattr(backend,method)(*values,**kwargs)
            aa=actual if isinstance(actual,tuple) else (actual,);ee=expected if isinstance(expected,tuple) else (expected,);entries=[]
            for a,e in zip(aa,ee):
                same=np.array_equal(a.view(np.uint32),e.view(np.uint32));maxerr=float(np.max(np.abs(a-e)))
                entries.append(dict(shape=list(a.shape),bit_exact=bool(same),max_abs=maxerr,passed=bool(same or (not exact and maxerr<1e-37))))
            entry=dict(name=name,outputs=entries,passed=all(v['passed'] for v in entries));report['tests'].append(entry);print(json.dumps(entry),flush=True)
            if not entry['passed']:
                np.savez(args.out/f'failed_{len(report["tests"])}.npz',**{f'actual_{i}':v for i,v in enumerate(aa)},**{f'expected_{i}':v for i,v in enumerate(ee)})
        report['backend']=backend.report();report['pass_all']=all(v['passed'] for v in report['tests'])
    except BaseException as e:report['error']=str(e);traceback.print_exc()
    finally:
        if link is not None:
            link.close();report['ethernet_after_close']=link.report();report['pass_all'] &= link.close_confirmed and not link.poisoned
        report['seconds']=time.perf_counter()-started
        (args.out/'result.json').write_text(json.dumps(report,indent=2));print('NUMERIC_SMOKE_PASS',report['pass_all'])
    return 0 if report['pass_all'] else 1
if __name__=='__main__':raise SystemExit(main())
