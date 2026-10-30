"""Mechanically adapt the same two-AXI DMA wiring for the bit-layout engine."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'scripts/make_vector_axi_wrapper.py'
s=source.read_text(encoding='utf-8').replace('ddr_vector','ddr_layout')
line=next(q for q in s.splitlines() if q.startswith("v=(ROOT/'rtl/ddr_layout_engine.sv')"))
s=s.replace(line,"v=(ROOT/'rtl/ddr_layout_engine.sv').read_text();vp=ports(v.split('module ddr_layout_engine(',1)[1].split(');',1)[0])")
script=ROOT/'scripts/generated_layout_wrapper.py'
if script.exists():raise RuntimeError('Fresh generated wiring script')
script.write_text(s,encoding='utf-8')
exec(compile(s,str(script),'exec'),{'__file__':str(script),'__name__':'__main__'})
