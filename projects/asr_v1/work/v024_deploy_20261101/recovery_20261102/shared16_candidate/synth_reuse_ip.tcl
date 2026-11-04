set out [file normalize [file dirname [info script]]]
set core [file join $out core]

set scratch {C:/Academic_Work/CIM_learning/_s16_retry2}
file mkdir $scratch
cd $scratch
set part xczu15eg-ffvb1156-2-i
set_param general.maxThreads 1
create_project -force candidate [file join $scratch project] -part $part
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
# Reuse the verified official IP OOC checkpoint in this fresh process.
if {[get_property IS_LOCKED $fma]} {error "FMA IP is locked"}
set ip_dcp [file join $out ip asr_fma_ip generated asr_fma_ip.dcp]
if {![file exists $ip_dcp]} {error "Expected FMA OOC checkpoint missing"}
report_ip_status -file [file join $out reports retry2_ip_status.rpt]
puts "REUSE_VERIFIED_FMA_CHECKPOINT $ip_dcp"
set_property top v024_unified_top [current_fileset]
read_xdc [file join $core scripts deploy core_ooc.xdc]
update_compile_order -fileset sources_1
synth_design -top v024_unified_top -part $part -mode out_of_context -flatten_hierarchy rebuilt -generic MAX_NODES=128
set fma_cells [get_cells -quiet graph/vec/arithmetic/fused]
if {[llength $fma_cells] != 1 || [get_property IS_BLACKBOX $fma_cells]} {error "FMA not fully linked"}
set core_clock [get_clocks -quiet core_clk]
if {[llength $core_clock] != 1 || abs([get_property PERIOD $core_clock] - 20.0) > 0.001} {error "Wrong core clock"}
set arrays [get_cells -quiet -hier -filter {REF_NAME =~ array16_w7_c48_cfg*}]
set pes [get_cells -quiet -hier -filter {REF_NAME =~ pe_w7_c48_cfg*}]
set shape_file [open [file join $out reports synthesized_array_shape.txt] w]
puts $shape_file "ARRAY_COUNT=[llength $arrays] PE_COUNT=[llength $pes]"
foreach a $arrays {puts $shape_file "ARRAY=$a REF=[get_property REF_NAME $a]"}
close $shape_file
if {[llength $arrays] != 1 || [llength $pes] != 256} {error "Unexpected physical array or PE count"}
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

