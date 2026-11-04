set out [file normalize [file dirname [info script]]]
set core [file join $out core]

cd $out
set part xczu15eg-ffvb1156-2-i
set_param general.maxThreads 1
create_project -force candidate [file join $out build project] -part $part
set_property target_language Verilog [current_project]
set fh [open [file join $core filelist.f] r]
foreach source [split [read $fh] \n] {
 set source [string trim $source]
 if {$source ne ""} {read_verilog -sv [file join $core $source]}
}
close $fh
read_ip [file join $out ip asr_fma_ip asr_fma_ip.xci]
set fma [get_ips asr_fma_ip]
if {[llength $fma] != 1 || [get_property CONFIG.C_Latency $fma] ne "12"} {error "Wrong FMA or latency"}
generate_target all $fma
synth_ip $fma
set_property top v024_unified_top [current_fileset]
read_xdc [file join $core scripts deploy core_ooc.xdc]
update_compile_order -fileset sources_1
synth_design -top v024_unified_top -part $part -mode out_of_context -flatten_hierarchy rebuilt -generic MAX_NODES=128
write_checkpoint -force [file join $out build candidate_synth.dcp]
report_utilization -file [file join $out reports utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out reports utilization_hier.rpt]
report_timing_summary -report_unconstrained -file [file join $out reports timing.rpt]
report_drc -file [file join $out reports drc.rpt]
check_timing -verbose -file [file join $out reports check_timing.rpt]
set bb [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $bb]} {error "Unexpected blackboxes $bb"}
set f [open [file join $out reports synth_pass.txt] w]; puts $f "SYNTH_PASS BLACKBOX=0 MAX_NODES=128 FMA_LATENCY=12"; close $f
puts CANDIDATE_SYNTH_PASS

