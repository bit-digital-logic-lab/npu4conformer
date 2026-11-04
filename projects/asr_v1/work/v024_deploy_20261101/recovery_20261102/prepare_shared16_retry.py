"""Prepare a build-flow-only retry; preserve all frozen RTL and failed artifacts."""
import datetime
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
out = root / 'shared16_candidate'
scratch = Path('C:/Academic_Work/CIM_learning/_s16_retry2')
scratch.mkdir(exist_ok=True)
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

ip = out / 'ip/asr_fma_ip'
expected = {
    'ip/asr_fma_ip/asr_fma_ip.xci': '6d4e66d8c69c8d1ca6e687d65d304ed9d84f0563d8fdea342d2ca61b85902333',
    'ip/asr_fma_ip/generated/asr_fma_ip.dcp': '3398344c3a787c46194e63ef81cd5968daa2bbcbd13176d1c2205819d8d6f10d',
}
for rel, digest in expected.items():
    if sha(out / rel) != digest:
        raise RuntimeError('Unexpected FMA input: ' + rel)

script = (out / 'synth.tcl').read_text(encoding='utf-8')
script = script.replace('cd $out', 'set scratch {' + scratch.as_posix() + '}\nfile mkdir $scratch\ncd $scratch')
script = script.replace('create_project -force candidate [file join $out build project] -part $part',
                        'create_project -force candidate [file join $scratch project] -part $part')
script = script.replace('generate_target all $fma\nsynth_ip $fma', '''# Reuse the verified official IP OOC checkpoint in this fresh process.
if {[get_property IS_LOCKED $fma]} {error "FMA IP is locked"}
set ip_dcp [file join $out ip asr_fma_ip generated asr_fma_ip.dcp]
if {![file exists $ip_dcp]} {error "Expected FMA OOC checkpoint missing"}
report_ip_status -file [file join $out reports retry2_ip_status.rpt]
puts "REUSE_VERIFIED_FMA_CHECKPOINT $ip_dcp"''')
script = script.replace('write_checkpoint -force [file join $out build candidate_synth.dcp]', '''set fma_cells [get_cells -quiet graph/vec/arithmetic/fused]
if {[llength $fma_cells] != 1 || [get_property IS_BLACKBOX $fma_cells]} {error "FMA not fully linked"}
set core_clock [get_clocks -quiet core_clk]
if {[llength $core_clock] != 1 || abs([get_property PERIOD $core_clock] - 20.0) > 0.001} {error "Wrong core clock"}
set arrays [get_cells -quiet -hier -filter {REF_NAME =~ array16_w7_c48_cfg*}]
set pes [get_cells -quiet -hier -filter {REF_NAME =~ pe_w7_c48_cfg*}]
set shape_file [open [file join $out reports synthesized_array_shape.txt] w]
puts $shape_file "ARRAY_COUNT=[llength $arrays] PE_COUNT=[llength $pes]"
foreach a $arrays {puts $shape_file "ARRAY=$a REF=[get_property REF_NAME $a]"}
close $shape_file
if {[llength $arrays] != 1 || [llength $pes] != 256} {error "Unexpected physical array or PE count"}
write_checkpoint -force [file join $out build candidate_synth.dcp]''')
(out / 'synth_reuse_ip.tcl').write_text(script, encoding='utf-8')

launcher = (root / 'run_shared16_stage.py').read_text(encoding='utf-8')
launcher = launcher.replace("choices=['synth', 'implement']", "choices=['synth']")
launcher = launcher.replace("script = out / (options.stage + '.tcl')", "script = out / 'synth_reuse_ip.tcl'")
launcher = launcher.replace("stamp = datetime.datetime.now().strftime", """retry_gate = json.loads((out / 'reports/SYNTH_RETRY2_PLAN.json').read_text(encoding='utf-8'))
if digest(script) != retry_gate['script_sha256']:
    raise RuntimeError('Retry script changed since preparation')
for rel, sha in retry_gate['verified_ip_inputs'].items():
    if digest(out / rel) != sha:
        raise RuntimeError('Verified FMA IP changed: ' + rel)
stamp = datetime.datetime.now().strftime""")
launcher = launcher.replace("runid = options.stage + '_' + stamp", "runid = 'synth_reuse_ip_' + stamp")
(root / 'run_shared16_retry.py').write_text(launcher, encoding='utf-8')

plan = {
    'status': 'PREPARED_NOT_RUN',
    'created': datetime.datetime.now().astimezone().isoformat(),
    'changes': ['Fresh short scratch and project directory', 'Reuse hash-verified official FMA OOC DCP; no repeated IP synthesis in core process'],
    'unchanged': ['All frozen RTL and IP configuration', '20 ns pre-synthesis constraint', 'MAX_NODES=128', 'Single-thread rebuilt out-of-context synthesis'],
    'scratch_directory': str(scratch),
    'script_sha256': sha(out / 'synth_reuse_ip.tcl'),
    'verified_ip_inputs': expected,
    'failure_evidence': 'logs/synth_20261102_123634.log',
    'prior_failure': 'Designutils 20-411 temporary directory cleanup; actual locking process/root cause not established',
    'acceptance_requires': ['Actual expected DCP import at graph/vec/arithmetic/fused in current log', 'Correct IP status and 12-cycle config', 'Zero blackboxes', 'One original 16x16 array and 256 original PE instances', '20ns core_clk', 'Actual resources and written core checkpoint'],
}
(out / 'reports/SYNTH_RETRY2_PLAN.json').write_text(json.dumps(plan, indent=2) + '\n', encoding='utf-8')
status_path = root.parent / 'deployment_status.json'
status = json.loads(status_path.read_text(encoding='utf-8-sig'))
status['updated_local'] = plan['created']
status['status'] = 'SHARED16_SIMULATION_PASS_SYNTH_RETRY_PREPARED'
status['recovery_20261102'].update(
    main_heavy_job='layout_v12 isolated OOC; root whole synthesis retry prepared, not started',
    root_owned_synth_session=None,
    root_launcher_pid=None,
    shared16_physical_synthesis='Attempt1 exited1 at249.219s: Designutils20-411 temporary directory cleanup. No final netlist. Retry2 prepared.',
)
status_path.write_text(json.dumps(status, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(json.dumps(plan, indent=2))
