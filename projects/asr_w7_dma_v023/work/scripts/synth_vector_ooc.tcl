# Real FPGA-part OOC implementation, NOT wholeboard/IO signoff or a bitstream.
set root [file normalize [file join [file dirname [info script]] ..]]
set tag [lindex $argv 0]
if {![regexp {^[a-zA-Z0-9_]+$} $tag]} {error "Safe fresh tag"}
set out [file join $root reports $tag]
if {[file exists $out]} {error "Refuse overwrite"};file mkdir $out
set_param general.maxThreads 2
create_project vector [file join $out project] -part xczu15eg-ffvb1156-2-i
set legacy [file normalize [file join $root .. model_a_lowbit_v13]]
import_ip -files [file join $legacy ip asr_fma_ip.xci]
generate_target all [get_ips asr_fma_ip]
create_ip_run [get_files asr_fma_ip.xci]
launch_runs asr_fma_ip_synth_1 -jobs 2;wait_on_run asr_fma_ip_synth_1
if {[get_property PROGRESS [get_runs asr_fma_ip_synth_1]] ne "100%"} {error "FMA synthesis incomplete"}
foreach name {ddr_vector_engine.sv ddr_vector_axi.sv asr_fp32_alu.sv axi_dma_v019.sv} {read_verilog -sv [file join $root rtl $name]}
synth_design -top ddr_vector_axi -part xczu15eg-ffvb1156-2-i -mode out_of_context
create_clock -name clk125 -period 8.000 [get_ports clk]
opt_design;place_design -directive Explore;phys_opt_design -directive Explore;route_design -directive Explore
report_utilization -file [file join $out utilization.txt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.txt]
report_drc -file [file join $out drc.txt]
write_checkpoint [file join $out routed_ooc.dcp]
set setup [get_property SLACK [lindex [get_timing_paths -delay_type max -max_paths 1] 0]]
set hold [get_property SLACK [lindex [get_timing_paths -delay_type min -max_paths 1] 0]]
set f [open [file join $out result.txt] w];puts $f "V022_VECTOR_OOC\nCORE_MHZ=125\nSETUP=$setup\nHOLD=$hold\nNot fullboard IO/STA signoff; no bitstream generated or programmed.";close $f
puts "V022_VECTOR_OOC_RESULT setup=$setup hold=$hold"
close_project
exit
