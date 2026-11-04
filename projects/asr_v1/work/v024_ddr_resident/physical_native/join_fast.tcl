# Link the resident-DDR synthesis partitions. The Ethernet fabric is a later platform variant.
set work [file normalize [file dirname [info script]]]
set build [file join $work build]
set old [file normalize [file join $work .. .. v024_deploy_20261101 recovery_20261102 retained_coeff_physical]]
set part xczu15eg-ffvb1156-2-i
set_param general.maxThreads 8
puts "JOIN_THREADS_LIMIT=[get_param general.maxThreads]"
proc require {ok message} {if {!$ok} {error $message}}

# The driver reuses this intermediate only when a prior successful core link
# has a matching input manifest and checkpoint digest.
set output [file join $build core_ddr_synth.dcp]
if {$argc == 0} {
    create_project -in_memory -part $part
    set leaf [file join $old build array16_ooc_clockless.dcp]
    read_checkpoint [file join $build parent_unlinked.dcp]
    read_checkpoint $leaf
    set_property SCOPED_TO_CELLS {matrix/shared_array} [get_files $leaf]
    link_design -top v024_unified_top -part $part -mode out_of_context
    require [expr {![llength [get_cells -quiet -hier -filter {IS_BLACKBOX==1}]]}] "unresolved core black box"
    require [expr {[llength [get_cells -quiet graph/vec/arithmetic/fused]] == 1}] "FMA missing"
    require [expr {[llength [get_cells -quiet -hier -filter {REF_NAME =~ array16_w7_c48_cfg*}]] == 1}] "array count"
    require [expr {[llength [get_cells -quiet -hier -filter {REF_NAME =~ pe_w7_c48_cfg*}]] == 256}] "PE count"
    write_checkpoint -force $output
    puts "RESIDENT_CORE_LINK_PASS BLACKBOX=0 ARRAY=1 PE=256"
    close_project
}

open_checkpoint [file join $build shell_synth.dcp]
set cell [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
require [expr {[llength $cell] == 1 && $cell eq "ps_ddr_i/core_wrap/inst/core_i"}] "wrong PS shell placeholder: $cell"
# read_checkpoint rebuilds the whole design and invalidates old design handles.
read_checkpoint -strict -cell $cell $output
unset cell
require [expr {![llength [get_cells -quiet -hier -filter {IS_BLACKBOX==1}]]}] "unresolved top black box"
reset_timing -invalid
read_xdc [file join $build shell_timing.xdc]
set clocks [get_clocks -quiet *]
require [expr {[llength $clocks] == 1 && $clocks eq "clk_pl_0"}] "unexpected full-system clocks: $clocks"
set period [get_property PERIOD $clocks]
require [expr {abs($period - 20.625) < 0.001}] "shell clock changed: $period"
set clock_pin [get_pins -quiet ps_ddr_i/core_wrap/inst/core_i/clk]
require [expr {[llength $clock_pin] == 1 && [get_clocks -quiet -of_objects $clock_pin] eq $clocks}] "core clock not driven by PS PLCLK"
set pes [get_cells -quiet -hier -filter {REF_NAME =~ pe_w7_c48_cfg*}]
require [expr {[llength $pes] == 256}] "full-system PE count"
write_checkpoint -force [file join $build ps_ddr_synth.dcp]
puts "RESIDENT_SYSTEM_LINK_PASS BLACKBOX=0 PE=[llength $pes] CLOCK_PERIOD_NS=$period"
report_utilization -file [file join $work reports ps_ddr_synth_utilization.rpt]
report_clocks -file [file join $work reports ps_ddr_synth_clocks.rpt]
close_project
