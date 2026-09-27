set root [file normalize [file join [file dirname [info script]] ..]]
set frozen [file join $root .. releases v1_20260922_board_verified]
set baud [lindex $argv 0]
if {$baud ni {115200 460800 921600}} {error "Unsupported tested-baud candidate"}
set out [file join $root build board_build_$baud]
file mkdir $out
set_param general.maxThreads 4
foreach name {asr_i16_mac asr_requant asr_fp32_alu asr_uart_rx asr_uart_tx} {
    read_verilog -sv [file join $frozen rtl ${name}.sv]
}
foreach path [glob [file join $root rtl *.sv]] {read_verilog -sv $path}
read_xdc [file join $frozen constraints ax7035.xdc]
synth_design -top asr_uart_top_v2 -part xc7a35tfgg484-2 -generic BAUD=$baud
report_utilization -file [file join $out utilization_synth.rpt]
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out utilization_route.rpt]
report_timing_summary -delay_type min_max -max_paths 10 -report_unconstrained -file [file join $out timing_route.rpt]
report_drc -file [file join $out drc_route.rpt]
report_io -file [file join $out io.rpt]
write_checkpoint -force [file join $out asr_v2_route.dcp]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "ASR_V2_TIMING setup=$setup hold=$hold baud=$baud"
if {$setup eq "" || $hold eq "" || $setup < 0 || $hold < 0} {error "V2 board timing failed; no bitstream accepted"}
set errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $errors]} {error "V2 DRC errors: $errors"}
set_property BITSTREAM.CONFIG.USR_ACCESS 0xA5160002 [current_design]
write_bitstream -force [file join $out asr_v2_ax7035.bit]
puts "ASR_V2_BUILD_PASS (not programmed)"
