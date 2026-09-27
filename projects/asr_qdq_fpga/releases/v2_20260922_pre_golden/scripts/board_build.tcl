# Full board implementation; never programs hardware or writes Flash.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build board_build]
file mkdir $out
set_param general.maxThreads 4
foreach name {asr_i16_mac asr_requant asr_fp32_alu asr_command_engine asr_uart_rx asr_uart_tx asr_uart_top} {
    read_verilog -sv [file join $root rtl ${name}.sv]
}
read_xdc [file join $root constraints ax7035.xdc]
synth_design -top asr_uart_top -part xc7a35tfgg484-2
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out utilization_route.rpt]
report_timing_summary -delay_type min_max -max_paths 10 -report_unconstrained -file [file join $out timing_route.rpt]
report_drc -file [file join $out drc_route.rpt]
report_io -file [file join $out io.rpt]
write_checkpoint -force [file join $out asr_uart_top_route.dcp]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "ASR_BOARD_TIMING setup=$setup hold=$hold"
if {$setup eq "" || $hold eq "" || $setup < 0 || $hold < 0} {error "Board timing failed; do not generate/program a bitstream"}
set errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $errors]} {error "Board DRC errors: $errors"}
set_property BITSTREAM.CONFIG.USR_ACCESS 0xA5160001 [current_design]
write_bitstream -force [file join $out asr_v1_ax7035.bit]
puts "ASR_BOARD_BUILD_PASS (not programmed)"
