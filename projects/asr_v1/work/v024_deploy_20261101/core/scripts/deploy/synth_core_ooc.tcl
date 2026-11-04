# Real V0.24 core OOC synthesis; no board pins, no hardware operations.
# User confirmed AXU15EGB; target matches the existing board engineering files.
set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
set part xczu15eg-ffvb1156-2-i
set out [file join $root build]
file mkdir $out
file mkdir [file join $root reports]
set_param general.maxThreads 4
create_project -force v024_core [file join $out project] -part $part
set_property target_language Verilog [current_project]
set fh [open [file join $root filelist.f] r]
set sources [split [read $fh] \n]
close $fh
foreach source $sources {
 set source [string trim $source]
 if {$source ne "" && ![string match {//*} $source]} {read_verilog -sv [file join $root $source]}
}
# Exact repository FMA recipe: nonblocking valid-only interface, single precision,
# single-rounding FMA a*b+c, active-low synchronous reset, fixed 12-cycle latency.
create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name asr_fma_ip
set_property -dict [list CONFIG.Operation_Type {FMA} CONFIG.Add_Sub_Value {Add} \
 CONFIG.A_Precision_Type {Single} CONFIG.Result_Precision_Type {Single} \
 CONFIG.C_Mult_Usage {Full_Usage} CONFIG.Flow_Control {NonBlocking} \
 CONFIG.Has_ARESETn {true} CONFIG.Maximum_Latency {false} CONFIG.C_Latency {12}] [get_ips asr_fma_ip]
report_property [get_ips asr_fma_ip] -file [file join $root reports fma_ip_properties.txt]
generate_target all [get_ips asr_fma_ip]
export_ip_user_files -of_objects [get_ips asr_fma_ip] -no_script -sync
synth_ip [get_ips asr_fma_ip]
set_property top v024_unified_top [current_fileset]
read_xdc [file join $root scripts deploy core_ooc.xdc]
update_compile_order -fileset sources_1
synth_design -top v024_unified_top -part $part -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $out v024_core_synth.dcp]
report_utilization -file [file join $root reports core_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $root reports core_utilization_hier.rpt]
report_timing_summary -report_unconstrained -file [file join $root reports core_timing_synth.rpt]
report_drc -file [file join $root reports core_drc_synth.rpt]
check_timing -verbose -file [file join $root reports core_check_timing.rpt]
set bbs [get_cells -hier -filter {IS_BLACKBOX == 1}]
set fh [open [file join $root reports core_status.txt] w]
puts $fh "TARGET_PART=$part"
puts $fh "TARGET_BOARD_CONFIRMATION=USER_CONFIRMED_AXU15EGB"
puts $fh "TOP=[get_property TOP [current_fileset]]"
puts $fh "CELLS=[llength [get_cells -hier]]"
puts $fh "BLACKBOX_COUNT=[llength $bbs]"
puts $fh "BLACKBOXES=$bbs"
puts $fh "BOUNDARY=CORE_OOC_SYNTHESIS_ONLY_NO_BOARD_OR_TIMING_CLOSURE_CLAIM"
close $fh
if {[llength $bbs] != 0} {error "Unexpected synthesis black boxes: $bbs"}
puts "V024_CORE_OOC_SYNTH_PASS"

