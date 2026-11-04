"""Offline evidence checks. Python 3.10+, standard library, no board access."""
import argparse,hashlib,json,math,struct,sys
from pathlib import Path

def compare(reference,actual,kind,count,atol=0.0,rtol=0.0):
    if count<=0 or not all(math.isfinite(v) and v>=0 for v in (atol,rtol)):
        raise ValueError('positive count and finite nonnegative tolerances required')
    fmt={'f32':'<f','f64':'<d','i32':'<i','i64':'<q'}[kind];item=struct.calcsize(fmt)
    a=Path(reference).read_bytes();b=Path(actual).read_bytes()
    if len(a)!=count*item or len(b)!=count*item:raise ValueError('length does not match declared element count')
    maximum=0
    for index,((expected,),(observed,)) in enumerate(zip(struct.iter_unpack(fmt,a),struct.iter_unpack(fmt,b),strict=True)):
        if not math.isfinite(expected) or not math.isfinite(observed):raise ValueError(f'nonfinite value at {index}')
        error=abs(expected-observed);maximum=max(maximum,error)
        # Use the declared reference as the scale, with no broadcasting or NaN equality.
        if error>atol+rtol*abs(expected):raise ValueError(f'mismatch at {index}: expected {expected}, observed {observed}')
    return dict(passed=True,count=count,dtype=kind,max_absolute_error=maximum,
                reference_sha256=hashlib.sha256(a).hexdigest(),actual_sha256=hashlib.sha256(b).hexdigest())

def partition(path):
    data=json.loads(Path(path).read_text(encoding='utf8'));total=data['total_seconds'];parts=data['disjoint_parts']
    if not isinstance(total,(int,float)) or not math.isfinite(total) or total<=0:raise ValueError('invalid total seconds')
    if not parts:raise ValueError('missing partitions')
    names=[p['name'] for p in parts]
    if len(set(names))!=len(names):raise ValueError('duplicate partition name')
    values=[p['seconds'] for p in parts]
    if not all(isinstance(v,(int,float)) and math.isfinite(v) and v>=0 for v in values):raise ValueError('invalid partition seconds')
    delta=math.fsum(values)-total
    if abs(delta)>max(1e-9,total*1e-9):raise ValueError(f'partition sum differs by {delta} seconds')
    return dict(passed=True,total_seconds=total,delta_seconds=delta,
                parts=[dict(p,percent=p['seconds']*100/total) for p in parts],
                excluded_overlaps=data.get('excluded_overlaps',[]),
                boundary='Sum consistency only. Disjointness must be established by instrumentation design.')

def main():
    ap=argparse.ArgumentParser(description=__doc__);sub=ap.add_subparsers(dest='mode',required=True)
    c=sub.add_parser('compare');c.add_argument('reference');c.add_argument('actual')
    c.add_argument('--dtype',choices=['f32','f64','i32','i64'],required=True);c.add_argument('--count',type=int,required=True)
    c.add_argument('--atol',type=float,default=0);c.add_argument('--rtol',type=float,default=0)
    s=sub.add_parser('partition');s.add_argument('input')
    a=ap.parse_args()
    try:
        result=compare(a.reference,a.actual,a.dtype,a.count,a.atol,a.rtol) if a.mode=='compare' else partition(a.input)
        print(json.dumps(result,ensure_ascii=False,allow_nan=False));return 0
    except (ValueError,KeyError,TypeError,OverflowError,OSError,struct.error) as error:
        print(json.dumps(dict(passed=False,error=str(error)),ensure_ascii=False));return 1
if __name__=='__main__':sys.exit(main())
