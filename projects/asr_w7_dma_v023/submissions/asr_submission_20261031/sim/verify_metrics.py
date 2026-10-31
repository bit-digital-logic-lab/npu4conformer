import json, math
from pathlib import Path
r=Path(__file__).resolve().parents[1]
x=json.load(open(r/'data/roofline_recomputed.json'))
assert x['peak_ops_per_cycle']==512 and x['bandwidth_bytes_per_cycle']==16
c=x['cases'][0]
assert c['useful_ops']==393216 and c['total_bytes']==43008 and c['cycles']==8711
assert math.isclose(c['throughput_ops_per_cycle'],393216/8711)
for z in x['cases']:assert z['throughput_ops_per_cycle']<=z['roof_ops_per_cycle']
a=json.load(open(r/'sim/ledger_fixed/summary.json'))
for z in a['resources']:
 if z['resource'] in ['matrix','vector','layout']:assert 'busy' in z['states'] and 'compute' not in z['states']
print('METRICS_AND_BUSY_SEMANTICS_PASS')
