from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
old = root.parent / 'core_peripheral_candidate'
out = root / 'route16_alternate'
for name in ('build', 'reports'):
    (out / name).mkdir(parents=True, exist_ok=True)
checkpoint = old / 'build/physopt.dcp'
original = (old / 'resume_implementation.tcl').read_text(encoding='utf-8-sig')
tail = original.split('write_checkpoint -force [file join $b routed.dcp]', 1)[1]
head = '''# Same frozen 16x16 design and constraints, alternate routing only.
set out [file normalize [file dirname [info script]]]
cd $out
set b [file join $out build]
set r [file join $out reports]
set_param general.maxThreads 4
open_checkpoint {%s}
if {[get_property PART [current_design]] ne "xczu15eg-ffvb1156-2-i"} {error "Unexpected part"}
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "Unresolved blackbox"}
if {[llength [get_clocks -quiet -filter {NAME =~ *core_clk}]]} {error "Residual OOC clock"}
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.USR_ACCESS 0xA51A2482 [current_design]
report_clocks -file [file join $r clocks_input.rpt]
report_exceptions -file [file join $r exceptions_input.rpt]
if {[catch {route_design -directive AlternateCLBRouting} route_error]} {
    puts "RECOVERY_ROUTE_FAILED: $route_error"
    catch {report_route_status -file [file join $r route_failed.rpt]}
    catch {report_design_analysis -congestion -file [file join $r congestion_failed.rpt]}
    catch {write_checkpoint -force [file join $b route_failed.dcp]}
    set f [open [file join $r route_failed.txt] w]
    puts $f $route_error
    close $f
    error "AlternateCLBRouting did not complete; no bitstream generated"
}
write_checkpoint -force [file join $b routed.dcp]
''' % checkpoint.as_posix()
script = out / 'route_alternate.tcl'
script.write_text(head + tail + '\nexit\n', encoding='utf-8')
receipt = {
    'scope': 'same frozen old two-16x16 platform; route-only recovery, not an RTL change',
    'input_checkpoint': str(checkpoint),
    'input_sha256': hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
    'script_sha256': hashlib.sha256(script.read_bytes()).hexdigest(),
    'directive': 'AlternateCLBRouting',
    'hardware_access': False,
    'bitstream_requires_all_original_static_gates': True,
}
(out / 'reports/INPUT.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
