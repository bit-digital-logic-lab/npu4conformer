"""Create a non-overwriting, hashed V1 release after physical acceptance."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
out = root / 'releases' / 'v1_20260922_board_verified'
if out.exists():
    raise SystemExit('Release already exists: refusing to overwrite frozen V1')
for name, key in [('smoke_hardware_v1.json', 'pass'), ('benchmark_hardware_v1.json', 'passed')]:
    report = json.loads((root/'reports'/name).read_text(encoding='utf-8'))
    if not report.get(key) or not report.get('physical_fpga_executed'):
        raise SystemExit(f'Physical acceptance missing: {name}')
program_log = (root/'build/program_board/vivado.log').read_text(encoding='utf-8')
if 'ASR_PROGRAM_PASS_VOLATILE_ONLY\n' not in program_log:
    raise SystemExit('JTAG acceptance missing')
for folder in ('rtl', 'host', 'constraints', 'scripts', 'sim', 'tests', 'reports'):
    shutil.copytree(root/folder, out/folder, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
for name in ('README.md', 'PROTOCOL.md', 'requirements.txt'):
    shutil.copy2(root/name, out/name)
for folder, files in {
    'board_build': ['asr_v1_ax7035.bit', 'asr_uart_top_route.dcp', 'timing_route.rpt',
                    'utilization_route.rpt', 'drc_route.rpt', 'io.rpt', 'vivado.log'],
    'program_board': ['vivado.log'],
    'tests': ['test_report.json'],
}.items():
    (out/'build'/folder).mkdir(parents=True, exist_ok=True)
    for name in files:
        shutil.copy2(root/'build'/folder/name, out/'build'/folder/name)
files = {}
for path in sorted(out.rglob('*')):
    if path.is_file():
        files[path.relative_to(out).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
manifest = dict(release='v1_20260922_board_verified', frozen_utc=datetime.now(timezone.utc).isoformat(),
                device='xc7a35tfgg484-2', clock_hz=50000000, uart_baud=115200,
                user_access='A5160001', physical_smoke_passed=True,
                full_model_hardware_inference=False, flash_written=False,
                policy='Never edit this release. Develop V2 in a separate directory.', sha256=files)
(out/'FREEZE_MANIFEST.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
print(f'FROZEN {out}: {len(files)} hashed files')
