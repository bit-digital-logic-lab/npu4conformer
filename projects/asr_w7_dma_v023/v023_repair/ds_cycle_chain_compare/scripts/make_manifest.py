#!/usr/bin/env python3
"""Hash frozen inputs, reused snapshot source, local harness/source, and raw logs."""
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
SNAP = HERE / 'snapshot' / 'integrated_20261029T2302'

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()

def add(paths, out):
    for p in paths:
        if p.is_file():
            out[str(p.relative_to(HERE))] = sha(p)

def main():
    out = {}
    ext_root = Path('/home/yang/Desktop/项目')
    external = [
        'work/rtl/axi_dma_v019.sv','work/rtl/asr_fp32_alu.sv','work/rtl/u16_divmod.sv',
        'work/rtl/ddr_vector_engine.sv','work/rtl/ddr_vector_axi.sv',
        'work/rtl/ddr_layout_engine.sv','work/rtl/ddr_layout_axi.sv',
        'work/rtl/block_engine_l1bank_v020.sv','work/rtl/block_storage_dma_prefetch.sv',
        'work/rtl/block_address_v020.sv','work/rtl/operand_banks_v020.sv',
        'work/rtl/array16_direct_v020.sv','work/rtl/pe_direct_v020.sv',
        'work/rtl/c_cache_banked4.sv',
        'v023_repair/primary_stream_fix/INTERFACE.md',
        'v023_repair/primary_stream_fix/REPORT.md',
        'v023_repair/primary_stream_fix/result.json',
        'v023_repair/ds_matrix/tests/gen_engine_vectors.py',
        'v023_repair/ds_matrix/tests/tb_engine_baseline.sv',
    ]
    for rel in external:
        ep = (ext_root / rel).resolve()
        if ep.is_file():
            out['external/' + rel] = sha(ep)
    add(sorted((HERE/'inputs').rglob('*')), out)
    add([HERE/'filelist_candidate.f', HERE/'filelist_baseline_full.f',
         HERE/'run_all.sh', HERE/'REPORT.md', HERE/'result.json', HERE/'progress.json'], out)
    add(sorted((HERE/'tb').glob('*.sv')), out)
    add(sorted((HERE/'rtl_harness').rglob('*.sv')), out)
    add(sorted((HERE/'scripts').glob('*.py')), out)
    add(sorted((SNAP/'rtl').glob('*.sv')), out)
    add(sorted((SNAP/'tb').glob('*.sv')), out)
    add(sorted((SNAP/'scripts').glob('*.py')), out)
    add([SNAP/'filelist_integrated.f', SNAP/'filelist_baseline.f'], out)
    add(sorted((SNAP/'fixtures').rglob('*')), out)
    add(sorted((HERE/'runs').rglob('run.log')), out)
    add(sorted((HERE/'runs').rglob('out.hex')), out)
    add(sorted((HERE/'runs').rglob('stage_c48.hex')), out)
    add(sorted((HERE/'logs').glob('*.log')), out)
    add(sorted((HERE/'logs').glob('*.txt')), out)
    add(sorted((HERE/'logs').glob('*.diff')), out)
    add(sorted((HERE/'build').glob('*.vvp')), out)
    (HERE/'SOURCE_SHA256.json').write_text(json.dumps(out, indent=2, sort_keys=True) + '\n')
    print(f'{len(out)} files hashed -> SOURCE_SHA256.json')

if __name__ == '__main__':
    main()
