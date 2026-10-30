import json
from pathlib import Path
useful=3461011968
padded=3991404544
traffic=929293344
rows=[]
for f in [125,150,300,600]:
 rows.append(dict(compute_MHz=f,MACs_per_cycle=256,useful_compute_lb_s=useful/(256*f*1e6),padded_compute_lb_s=padded/(256*f*1e6)))
mem=[dict(AXI_MHz=f,bytes_per_cycle=16,ideal_GB_s=16*f/1000,serialized_shared_data_scenario_s=traffic/(16*f*1e6)) for f in [125,200,250,300,333]]
r=dict(scope='68 closed plans only; not whole model; traffic is existing measured 68plan traffic, not mathematically minimum',useful_MAC=useful,padded_MAC=padded,traffic_bytes=traffic,compute=rows,memory=mem,DDR_config_800MHz_64bit_peak_GB_s=12.8,notes=['DDR 800MHz clock implies1600MT/s only if active configured clock is honored; project config not board measurement','One HP128 interface limits effective bandwidth independently of physical DDR peak','Cannot sum arbitrary read/write port peaks or use600MHz atPS interface','DAG-dependent stages require segmented schedule, not blanket max(compute,memory)','Memory sum R+W / single bandwidth is an assumed shared serialized channel scenario; separate AXI R/W and DDR read-write arbitration must be modeled before calling it universal lower bound','Vector/layout, transfer overhead, host outside graph not included in MAC lower bound'])
Path(__file__).with_name('LOWER_BOUNDS.json').write_text(json.dumps(r,indent=2))
print(json.dumps(r,indent=2))
