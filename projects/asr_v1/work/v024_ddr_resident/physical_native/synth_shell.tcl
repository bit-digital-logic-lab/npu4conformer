set out [file normalize [file dirname [info script]]]
set argv [list [file join $out shell_run]]
set argc 1
set_param general.maxThreads 1
source {C:/Academic_Work/CIM_learning/work/v024_ddr_resident/ps_ddr_shell.tcl}
set out [file normalize [file dirname [info script]]]
open_project [file join $out shell_run project resident.xpr]
set bd [get_files -quiet */ps_ddr.bd]
if {[llength $bd] != 1} {error "expected one PS+DDR BD: $bd"}
generate_target all $bd
set wrappers [make_wrapper -files $bd -top]
if {[llength $wrappers] != 1} {error "unexpected BD wrapper $wrappers"}
add_files -norecurse $wrappers
set_property top ps_ddr_wrapper [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set status [get_property STATUS [get_runs synth_1]]
puts "SHELL_SYNTH_STATUS=$status"
if {![string match {*synth_design Complete*} $status]} {error "shell synth failed: $status"}
open_run synth_1
set bb [get_cells -hier -filter {IS_BLACKBOX==1}]
puts "SHELL_BLACKBOXES=$bb"
if {[llength $bb] != 1 || ![string match */core_i [lindex $bb 0]]} {error "unexpected blackboxes: $bb"}
write_checkpoint -force [file join $out build shell_synth.dcp]
report_utilization -hierarchical -file [file join $out reports shell_utilization.rpt]
report_clocks -file [file join $out reports shell_clocks.rpt]
write_xdc -force -type timing [file join $out build shell_timing.xdc]
puts "SHELL_SYNTH_PASS ONE_CORE_BB NO_ETH NO_BOARD"
close_project
exit

