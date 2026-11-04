"""Prepare, but do not run, the isolated fixed-controller/banked-RAM platform."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parent
old = root.parent / 'core_peripheral_candidate'
out = root / 'safe16_candidate'
for name in ('build', 'reports'):
    (out / name).mkdir(parents=True, exist_ok=True)
platform = old / 'build/platform_synth_copy.dcp'
shutil.copy2(platform, out / 'build/platform_synth_copy.dcp')
base = (old / 'implement.tcl').read_text(encoding='utf-8-sig')
base = base.replace('set_param general.maxThreads 2', 'set_param general.maxThreads 4')
base = base.replace('0xA51A2482', '0xA51A2490').replace('candidate_A51A2482', 'candidate_A51A2490')
old_flow = 'opt_design\nplace_design\nphys_opt_design\nroute_design\n'
new_flow = '''opt_design
write_checkpoint -force [file join $b optimized.dcp]
place_design -subdirective {GPlace.ReduceCongestion.high DPlace.ReducePinDensity.high}
write_checkpoint -force [file join $b placed.dcp]
report_timing_summary -file [file join $r timing_placed.rpt]
report_design_analysis -congestion -file [file join $r congestion_placed.rpt]
phys_opt_design
write_checkpoint -force [file join $b physopt.dcp]
if {[catch {route_design -directive AlternateCLBRouting} route_error]} {
    catch {report_route_status -file [file join $r route_failed.rpt]}
    catch {report_design_analysis -congestion -file [file join $r congestion_failed.rpt]}
    catch {write_checkpoint -force [file join $b route_failed.dcp]}
    error "Safe16 route failed: $route_error"
}
'''
assert base.count(old_flow) == 1
base = base.replace(old_flow, new_flow)
# No inference or placement work can start before the complete frozen source
# simulation has been independently reviewed by the parent task.
guard = '''set passfile [file join $out reports READY_FOR_IMPLEMENTATION.json]
if {![file isfile $passfile]} {error "Missing reviewed synthesis and functional gate"}
'''
base = base.replace('cd $out\n', 'cd $out\n' + guard, 1)
script = out / 'implement.tcl'
script.write_text(base + '\nexit\n', encoding='utf-8')
receipt = {
    'status': 'PREPARED_NOT_EXECUTED',
    'usr_access': '0xA51A2490',
    'platform_sha256': hashlib.sha256(platform.read_bytes()).hexdigest(),
    'script_sha256': hashlib.sha256(script.read_bytes()).hexdigest(),
    'source_platform': str(platform),
    'part': 'xczu15eg-ffvb1156-2-i',
    'clock_period_ns': 20,
    'placement': ['GPlace.ReduceCongestion.high', 'DPlace.ReducePinDensity.high'],
    'route': 'AlternateCLBRouting',
    'requires': 'Reviewed exact-source functional regression and core synthesis; no hardware access',
}
(out / 'reports/IMPLEMENTATION_PLAN.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
