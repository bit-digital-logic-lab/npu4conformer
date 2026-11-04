set out [file normalize [file dirname [info script]]]
set b [file join $out build]
set r [file join $out reports]
cd $out
set passfile [file join $out reports READY_FOR_IMPLEMENTATION.json]
if {![file isfile $passfile]} {error "Missing reviewed synthesis and functional gate"}
set_param general.maxThreads 4
open_checkpoint [file join $b platform_synth_copy.dcp]
write_xdc -force -type timing [file join $b platform_timing.xdc]
report_clocks -file [file join $r platform_clocks_before.rpt]
report_exceptions -summary -file [file join $r platform_exceptions_before.rpt]
set cells [get_cells -hier -filter {IS_BLACKBOX == 1 && NAME =~ */core_i}]
if {[llength $cells] != 1} {error "Expected one core black box $cells"}
read_checkpoint -strict -cell [lindex $cells 0] [file join $b candidate_synth.dcp]
set bb [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $bb]} {error "Unresolved blackboxes $bb"}
reset_timing -invalid
read_xdc [file join $b platform_timing.xdc]
write_xdc -force -type timing [file join $b restored_timing.xdc]
proc normalized_timing {path} {
 set f [open $path r]; set data [read $f]; close $f
 set lines [list]
 foreach line [split $data \n] {set line [string trim $line]; if {$line ne "" && ![string match "#*" $line]} {lappend lines $line}}
 return [lsort $lines]
}
set original [normalized_timing [file join $b platform_timing.xdc]]
set restored [normalized_timing [file join $b restored_timing.xdc]]
if {$original ne $restored} {error "Restored timing constraints differ from original platform; inspect both XDC files"}
report_exceptions -summary -file [file join $r linked_exceptions_after.rpt]
if {[llength [get_clocks -quiet -filter {NAME =~ *core_clk}]]} {error "OOC core clock remains"}
report_clocks -file [file join $r linked_clocks.rpt]
set input [get_clocks -quiet sys_clk_p]
set derived [get_clocks -quiet -filter {NAME =~ clk_out1*}]
if {[llength $input] != 1 || [get_property PERIOD $input] != 5.0 || [llength $derived] != 1 || [get_property PERIOD $derived] != 20.0} {error "Platform clock reconstruction mismatch"}
check_timing -verbose -file [file join $r linked_check_timing.rpt]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.USR_ACCESS 0xA51A2491 [current_design]
if {[expr {[get_property BITSTREAM.CONFIG.USR_ACCESS [current_design]] != 0xA51A2491}]} {error "Incorrect configured USR_ACCESS"}
write_checkpoint -force [file join $b linked.dcp]
report_utilization -hierarchical -file [file join $r linked_utilization.rpt]
opt_design
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
    error "Shared16 route failed: $route_error"
}
write_checkpoint -force [file join $b routed.dcp]
report_route_status -file [file join $r route.rpt]
report_utilization -hierarchical -file [file join $r utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -file [file join $r timing_routed.rpt]
report_drc -file [file join $r drc_routed.rpt]
check_timing -verbose -file [file join $r check_timing_routed.rpt]
report_clock_interaction -file [file join $r clock_interaction.rpt]
report_bus_skew -file [file join $r bus_skew.rpt]
report_io -file [file join $r io.rpt]
set bb [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $bb]} {error "Unresolved blackboxes $bb"}
set bad [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]
if {[llength $bad]} {error "Blocking DRC $bad"}
foreach delay {max min} {set paths [get_timing_paths -delay_type $delay -max_paths 1]; if {![llength $paths] || [get_property SLACK [lindex $paths 0]] < 0} {error "$delay timing failed"}}
set f [open [file join $r check_timing_routed.rpt] r]; set txt [read $f]; close $f
foreach kind {no_clock unconstrained_internal_endpoints no_input_delay no_output_delay multiple_clock generated_clocks loops latch_loops} {set pattern [format {checking %s \(([0-9]+)\)} $kind]; if {![regexp $pattern $txt -> count] || $count != 0} {error "Timing coverage failed $kind"}}
set f [open [file join $r timing_routed.rpt] r]; set txt [read $f]; close $f
if {![string match {*All user specified timing constraints are met.*} $txt]} {error "Timing summary failed"}
set f [open [file join $r route.rpt] r]; set txt [read $f]; close $f
if {![regexp {# of nets with routing errors\.+\s*:\s*0} $txt] || ![regexp {# of routable nets\.+\s*:\s*([0-9]+)} $txt -> total] || ![regexp {# of fully routed nets\.+\s*:\s*([0-9]+)} $txt -> routed] || $total != $routed || $total == 0} {error "Routing incomplete"}
set ports [get_ports *]
if {[llength $ports] != 2} {error "Unexpected top ports: $ports"}
foreach {name pin} {sys_clk_p AL8 sys_clk_n AL7} {set p [get_ports $name]; if {[get_property PACKAGE_PIN $p] ne $pin || [get_property IOSTANDARD $p] ne "DIFF_SSTL12"} {error "Incorrect port $name"}}
set f [open [file join $r bus_skew.rpt] r]; set skew [read $f]; close $f
set skew_count 0
foreach line [split $skew \n] {if {[regexp {^\s*(Slow|Fast)\s+[0-9.]+\s+[0-9.]+\s+(-?[0-9.]+)} $line -> corner slack]} {incr skew_count; if {$slack < 0} {error "Negative bus skew $slack"}}}
if {$skew_count < 1} {error "No bus skew results found"}
write_debug_probes -force [file join $b candidate_A51A2491.ltx]
if {[expr {[get_property BITSTREAM.CONFIG.USR_ACCESS [current_design]] != 0xA51A2491}]} {error "USR_ACCESS changed during implementation"}
write_bitstream -force [file join $b candidate_A51A2491.bit]
set f [open [file join $r implementation_pass.txt] w]; puts $f "PASS STATIC ONLY USR_ACCESS=0xA51A2491 NO_HARDWARE_TEST"; close $f




exit
