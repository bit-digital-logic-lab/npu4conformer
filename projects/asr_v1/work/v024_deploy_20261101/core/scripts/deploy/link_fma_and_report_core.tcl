# Run only if completed core DCP retains the one known official FMA OOC cell.
# This links checkpoints and regenerates reports; it does not resynthesize RTL.
set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
set core [file join $root build v024_core128_iterhash_synth.dcp]
set ip_dcp [file join $root build project v024_core.gen sources_1 ip asr_fma_ip asr_fma_ip.dcp]
open_checkpoint $core
set bbs [get_cells -hier -filter {IS_BLACKBOX == 1}]
if {[llength $bbs] == 1} {
 set bb [lindex $bbs 0]
 set reference [get_property REF_NAME $bb]
 if {![string match asr_fma_ip* $reference]} {error "Refusing unknown black box: $bb ($reference)"}
 file copy -force $core [file join $root build v024_core128_iterhash_before_fma_link.dcp]
 read_checkpoint -cell $bb -strict $ip_dcp
} elseif {[llength $bbs] != 0} {
 error "Refusing multiple/unknown black boxes: $bbs"
}
set bbs [get_cells -hier -filter {IS_BLACKBOX == 1}]
if {[llength $bbs] != 0} {error "Unresolved black boxes after FMA insertion: $bbs"}
write_checkpoint -force $core
report_utilization -file [file join $root reports core128_iterhash_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $root reports core128_iterhash_utilization_hier.rpt]
report_timing_summary -report_unconstrained -file [file join $root reports core128_iterhash_timing_synth.rpt]
report_drc -file [file join $root reports core128_iterhash_drc_synth.rpt]
check_timing -verbose -file [file join $root reports core128_iterhash_check_timing.rpt]
set fh [open [file join $root reports core128_iterhash_status.txt] w]
puts $fh "TARGET_PART=[get_property PART [current_project]]"
puts $fh "BOARD=USER_CONFIRMED_AXU15EGB"
puts $fh "TOP=v024_unified_top"
puts $fh "MAX_NODES=128"
puts $fh "CONTROLLER_SOURCE=analysis/wc_graph_ctrl_iterhash.sv"
puts $fh "CELLS=[llength [get_cells -hier]]"
puts $fh "BLACKBOX_COUNT=0"
puts $fh "CLOCKS=[get_clocks]"
foreach clk [get_clocks] {puts $fh "CLOCK $clk PERIOD=[get_property PERIOD $clk]"}
puts $fh "ACCEPTANCE=NETLIST_INTEGRITY_ONLY_AREA_AND_TIMING_REVIEW_REQUIRED"
puts $fh "BOUNDARY=CORE_OOC_NO_FULL_MODEL_OR_BOARD_CLAIM"
close $fh
puts "CORE_ITERHASH_FMA_LINK_ZERO_BLACKBOX_PASS"
