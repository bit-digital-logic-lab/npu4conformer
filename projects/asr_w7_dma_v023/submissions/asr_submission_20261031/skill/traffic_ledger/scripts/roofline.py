"""Compute a cycle-normalized Roofline from a fixed operation/traffic/window contract."""
import argparse
import json
from pathlib import Path


def calculate(spec):
    for key in ('scope', 'memory_boundary', 'peak_source', 'bandwidth_source'):
        if not spec.get(key):
            raise ValueError('missing evidence contract: ' + key)
    if spec.get('bandwidth_basis') not in ('interface_contract', 'independent_benchmark'):
        raise ValueError('roof bandwidth must be independent of workload Q/T')
    if spec.get('clock_relation') != 'same_cycle_domain':
        raise ValueError('normalize clocks before cycle Roofline')
    if spec.get('traffic_basis') not in ('bus_bytes', 'valid_bytes_equal_bus_bytes'):
        raise ValueError('declare bus bytes or prove valid bytes equal bus bytes')
    peak, bandwidth = spec['peak_ops_per_cycle'], spec['bandwidth_bytes_per_cycle']
    if peak <= 0 or bandwidth <= 0:
        raise ValueError('nonpositive roof')
    results = []
    for case in spec['cases']:
        m, n, k = (case[x] for x in ('M', 'N', 'K'))
        read, write, cycles = (case[x] for x in ('read_bytes', 'write_bytes', 'cycles'))
        if min(m, n, k, cycles) <= 0 or min(read, write) < 0 or read + write <= 0:
            raise ValueError('invalid shape/traffic/window')
        if not case.get('source'):
            raise ValueError('missing case source')
        ops, total = 2*m*n*k, read + write
        intensity, throughput = ops/total, ops/cycles
        roof = min(peak, bandwidth*intensity)
        if throughput > roof*(1+1e-9):
            raise ValueError('measured point exceeds roof; inspect scope/clock/traffic')
        results.append(dict(case, useful_ops=ops, total_bytes=total,
                            intensity_ops_per_byte=intensity, throughput_ops_per_cycle=throughput,
                            roof_ops_per_cycle=roof, roof_fraction=throughput/roof,
                            peak_fraction=throughput/peak, effective_bytes_per_cycle=total/cycles))
    return dict(spec, operation_convention='1 MAC = 2 integer OP; useful GEMM only',
                ridge_ops_per_byte=peak/bandwidth, cases=results)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('spec',type=Path);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();result=calculate(json.loads(a.spec.read_text()));a.out.parent.mkdir(parents=True,exist_ok=True)
    a.out.write_text(json.dumps(result,indent=2,ensure_ascii=False))
