# Resume real V024 OOC with explicitly bounded 128-node graph window.
set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
set part xczu15eg-ffvb1156-2-i
set_param general.maxThreads 2
create_project -force v024_core128_iterhash [file join $root build project128_iterhash] -part $part
set_property target_language Verilog [current_project]
set fh [open [file join $root filelist.f] r]
foreach source [split [read $fh] \n] {
 set source [string trim $source]
 if {$source eq "rtl/graph/wc_graph_ctrl.sv"} {read_verilog -sv [file join $root analysis wc_graph_ctrl_iterhash.sv]} elseif {$source ne ""} {read_verilog -sv [file join $root $source]}
}
close $fh
read_ip [file join $root build project v024_core.srcs sources_1 ip asr_fma_ip asr_fma_ip.xci]
set_property top v024_unified_top [current_fileset]
read_xdc [file join $root scripts deploy core_ooc.xdc]
update_compile_order -fileset sources_1
synth_design -top v024_unified_top -part $part -mode out_of_context -flatten_hierarchy rebuilt -generic MAX_NODES=128
write_checkpoint -force [file join $root build v024_core128_iterhash_synth.dcp]
report_utilization -file [file join $root reports core128_iterhash_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $root reports core128_iterhash_utilization_hier.rpt]
report_timing_summary -report_unconstrained -file [file join $root reports core128_iterhash_timing_synth.rpt]
report_drc -file [file join $root reports core128_iterhash_drc_synth.rpt]
check_timing -verbose -file [file join $root reports core128_iterhash_check_timing.rpt]
set bbs [get_cells -hier -filter {IS_BLACKBOX == 1}]
set fh [open [file join $root reports core128_iterhash_status.txt] w]
puts $fh "TARGET_PART=$part"
puts $fh "BOARD=USER_CONFIRMED_AXU15EGB"
puts $fh "MAX_NODES=128"
puts $fh "CONTROLLER_SOURCE=analysis/wc_graph_ctrl_iterhash.sv"
puts $fh "TOP=[get_property TOP [current_fileset]]"
puts $fh "CELLS=[llength [get_cells -hier]]"
puts $fh "BLACKBOX_COUNT=[llength $bbs]"
puts $fh "BLACKBOXES=$bbs"
puts $fh "BOUNDARY=128_NODE_CORE_OOC_ONLY_NO_FULL_MODEL_OR_BOARD_OR_TIMING_CLOSURE_CLAIM"
close $fh
if {[llength $bbs] != 0} {error "Unexpected synthesis black boxes: $bbs"}
puts "V024_CORE128_ITERHASH_OOC_SYNTH_PASS"

