set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
open_project [file join $root core_hls]
set_top conformer_head
add_files [file join $root src_hls conformer_head.cpp]
add_files -tb [file join $root src_hls testbench.cpp]
add_files -tb [file join $root fixtures input.bin]
open_solution "solution" -flow_target vivado
set_part xc7a35tfgg484-1
create_clock -period 20
config_compile -pipeline_loops 0
config_rtl -reset all -reset_level low
csim_design -clean
file mkdir [file join $root artifacts]
file copy -force [file join $root core_hls solution csim build csim_output.bin] [file join $root artifacts csim_output.bin]
csynth_design
file copy -force [file join $root core_hls solution syn report conformer_head_csynth.rpt] [file join $root artifacts hls_synthesis.rpt]
file mkdir [file join $root rtl generated]
set manifest [open [file join $root rtl generated sources.txt] w]
foreach f [lsort [glob -nocomplain [file join $root core_hls solution syn verilog *.v] [file join $root core_hls solution syn verilog *.dat]]] {
 puts $manifest [file tail $f]
 file copy -force $f [file join $root rtl generated [file tail $f]]
}
close $manifest
exit
