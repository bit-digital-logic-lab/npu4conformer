# Non-project, out-of-context synthesis. Does not alter adder_16.xpr or program a board.
# vivado -mode batch -source scripts/synth.tcl -tclargs <output-dir> [part]
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build synth]
if {[llength $argv] > 0} {set out [file normalize [lindex $argv 0]]}
set part xc7a35tfgg484-2
if {[llength $argv] > 1} {set part [lindex $argv 1]}
file mkdir $out
set_param general.maxThreads 4
foreach name {asr_i16_mac asr_requant asr_fp32_alu asr_command_engine asr_uart_rx asr_uart_tx asr_uart_top} {
    read_verilog -sv [file join $root rtl ${name}.sv]
}
read_xdc [file join $root constraints clock_ooc.xdc]
synth_design -top asr_uart_top -part $part -mode out_of_context
# Explicit OOC reference clock-buffer location, not a guessed board pin.
# Board integration must replace this assumption with its actual clock tree.
set asr_clock_sites [get_sites -filter {SITE_TYPE == BUFGCTRL}]
if {[llength $asr_clock_sites] == 0} {error "No BUFGCTRL site available for OOC clock reference"}
set_property HD.CLK_SRC [lindex $asr_clock_sites 0] [get_ports clk]
report_utilization -file [file join $out utilization_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -file [file join $out timing_synth.rpt]
report_drc -file [file join $out drc_synth.rpt]
write_checkpoint -force [file join $out asr_uart_top_synth.dcp]
# OOC placement/routing estimates fabric timing, not timing to unknown board pins.
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out utilization_route.rpt]
report_timing_summary -delay_type min_max -max_paths 10 -file [file join $out timing_route.rpt]
report_drc -file [file join $out drc_route.rpt]
write_checkpoint -force [file join $out asr_uart_top_route.dcp]
set asr_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set asr_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "ASR OOC timing: setup slack=$asr_setup ns, hold slack=$asr_hold ns"
if {$asr_setup eq "" || $asr_hold eq "" || $asr_setup < 0 || $asr_hold < 0} {
    error "ASR OOC timing FAILED; reports/checkpoint saved for diagnosis. No 50 MHz acceptance claim."
}
puts "ASR OOC reports: $out (no bitstream, no board programming)"
