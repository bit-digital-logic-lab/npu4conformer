"""Freeze current V2 and the completed failed short run; NOT a pass certificate."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

ASR = Path(__file__).resolve().parents[2]
OUT = ASR / 'releases/v2_20260922_pre_golden'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    if OUT.exists():
        raise RuntimeError('Frozen release already exists; refusing overwrite')
    prior = ASR / 'v2/reports/full_micro7x1_20260922'
    result = json.loads((prior / 'result.json').read_text(encoding='utf-8'))
    if not (result.get('completed') and result.get('physical_fpga_executed')):
        raise RuntimeError('Previous physical run has not completed')
    acceptance = json.loads((ASR / 'v2/reports/board_acceptance.json').read_text(encoding='utf-8'))
    # Prove current V2 RTL and bitstream still match the board-acceptance record.
    for relative in ('v2/rtl/asr_command_engine_v2.sv', 'v2/rtl/asr_uart_top_v2.sv',
                     'v2/build/board_build_921600/asr_v2_ax7035.bit'):
        if digest(ASR / relative) != acceptance['sha256'][relative]:
            raise RuntimeError(f'Accepted hardware artifact changed: {relative}')
    changed_since_board_record = [name for name, expected in acceptance['sha256'].items()
                                  if (ASR / name).is_file() and digest(ASR / name) != expected]
    selected = {}
    for folder in ('rtl', 'host', 'constraints', 'scripts', 'sim', 'tests',
                   'v2/rtl', 'v2/host', 'v2/scripts', 'v2/tests', 'v2/sim'):
        base = ASR / folder
        if base.exists():
            for path in base.rglob('*'):
                if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
                    selected[path.relative_to(ASR).as_posix()] = path
    for folder in ('reports', 'v2/reports'):
        for path in (ASR / folder).glob('*'):
            if path.is_file():
                selected[path.relative_to(ASR).as_posix()] = path
    for path in prior.glob('*'):
        if path.is_file():
            selected[path.relative_to(ASR).as_posix()] = path
    for relative in ('README.md', 'PROTOCOL.md', 'requirements.txt', 'v2/README.md', 'v2/PROTOCOL_V2.md'):
        if (ASR / relative).is_file():
            selected[relative] = ASR / relative
    for name in ('asr_v2_ax7035.bit', 'asr_v2_route.dcp', 'timing_route.rpt',
                 'utilization_route.rpt', 'drc_route.rpt', 'io.rpt', 'vivado.log'):
        relative = 'v2/build/board_build_921600/' + name
        selected[relative] = ASR / relative
    vector_tools = Path(r'D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors_bundle')
    for name in ('vector_io.py', 'model_a_fpga_vectors.py'):
        selected['golden_tools/' + name] = vector_tools / name
    selected['freeze_procedure.py'] = Path(__file__).resolve()
    before = {name: digest(path) for name, path in selected.items()}
    OUT.mkdir(parents=True, exist_ok=False)
    for relative, source in sorted(selected.items()):
        destination = OUT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        if digest(destination) != before[relative] or digest(source) != before[relative]:
            raise RuntimeError(f'Snapshot changed during copy: {relative}')
    manifest = dict(release=OUT.name, frozen_utc=datetime.now(timezone.utc).isoformat(),
                    purpose='Reproducible V2 baseline BEFORE original golden acceptance, not a numerical pass',
                    device='xc7a35tfgg484-2', clock_hz=50000000, uart_baud=921600,
                    expected_user_access='A5160002', previous_run_completed=True,
                    previous_run_frames=7, previous_run_tokens=1,
                    previous_run_numerical_pass=result['numerical_pass_atol_1e_3_rtol_1e_3'],
                    previous_run_comparison=result['software_reference_comparison'],
                    original_golden_hardware_acceptance=False,
                    differences_since_board_acceptance_record=changed_since_board_record,
                    policy='Do not edit this release. Golden harness and V3 live outside it.',
                    source_root=str(ASR), sha256=before,
                    sources={name: str(path) for name, path in selected.items()})
    (OUT / 'FREEZE_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(frozen=str(OUT), files=len(before), original_golden_pass=False,
                         previous_short_run_pass=manifest['previous_run_numerical_pass'],
                         differences_since_board_record=changed_since_board_record), indent=2))


if __name__ == '__main__':
    main()
