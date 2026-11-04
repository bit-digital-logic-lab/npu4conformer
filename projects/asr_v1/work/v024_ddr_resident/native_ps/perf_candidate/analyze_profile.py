"""Convert the sideband timing counters from a completed real profiling request."""
import json
import struct
import sys
from pathlib import Path


def compute(path):
    cpu=struct.unpack("<8Ii3IQ2I",(path/"mailbox.bin").read_bytes())
    magic,abi,seq,graphs,desc,status,total,pl,*v=struct.unpack("<6I14Q",(path/"profile.raw").read_bytes())
    if (magic,abi,seq,status,total)!=(0x50465231,1,cpu[5],0,cpu[12]) or cpu[2]!=3 or cpu[6]!=2:
        raise ValueError("mailbox/sideband atomic request and duration mismatch")
    keys="linear_total dynamic_w_pack activation_scan activation_pack weight_repack submit_and_wait c48_unpack layernorm swish glu softmax depthwise".split()
    slots=dict(zip(keys,v))
    linear=slots.pop("linear_total")
    linear_parts=sum(slots[k] for k in ("activation_scan","activation_pack","weight_repack","submit_and_wait","c48_unpack"))
    slots["pl_driver_other"]=linear-linear_parts
    slots["encoder_other"]=total-sum(slots.values())
    if min(slots.values())<0 or not (0<graphs<=desc and pl>0):
        raise ValueError("nonphysical timing or completion counters")
    hz=cpu[13]
    return dict(sequence=seq,encoder_frames=cpu[9],pl_high_level_calls=cpu[10],graphs=graphs,
                descriptors=desc,board_ticks=total,tick_frequency=hz,board_seconds=total/hz,
                pl_graph_cycles=pl,pl_seconds_clock_period_20_625ns=pl*20.625e-9,
                pl_seconds_nominal_50MHz=pl/50e6,
                warning="PL graph busy interval overlaps submit_and_wait. Do not add those two values.",
                partition_seconds={k:t/hz for k,t in slots.items()},partition_ticks=slots)


if __name__=="__main__":
    folder=Path(sys.argv[1])
    result=json.dumps(compute(folder),indent=2)
    (folder/"profile.json").write_text(result,encoding="utf-8")
    print(result)
