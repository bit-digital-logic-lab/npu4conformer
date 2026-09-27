# 中文说明：通过 JTAG 将原生 INT16 位流下载到 FPGA SRAM；不写板载 Flash。
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root artifacts ax7035_top.bit]
if {![file exists $bit]} {error "Build bitstream first: $bit"}
open_hw_manager
connect_hw_server -allow_non_jtag
set targets [get_hw_targets -quiet *]
if {[llength $targets] != 1} {error "Expected exactly one JTAG target; found: $targets"}
open_hw_target [lindex $targets 0]
set devices [get_hw_devices -quiet xc7a35t*]
if {[llength $devices] != 1} {error "Expected one xc7a35t device: $devices"}
set dev [lindex $devices 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAM_PASS: $dev $bit"
close_hw_manager
