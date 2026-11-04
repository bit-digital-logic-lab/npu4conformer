set out [file normalize [file dirname [info script]]]
set partition_root {C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/recovery_20261102/partitioned_shared16}
set source_root {C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/recovery_20261102/retained_coeff_physical/regression}
set core [file join $source_root core]

set scratch {C:/Academic_Work/CIM_learning/_resident_ddr_parent}
file mkdir $scratch
cd $scratch
set part xczu15eg-ffvb1156-2-i
set_param general.maxThreads 2
create_project -force candidate [file join $scratch project] -part $part
set_property target_language Verilog [current_project]
set fh [open [file join $core filelist.f] r]
foreach source [split [read $fh] \n] {
 set source [string trim $source]
 if {$source eq "rtl/matrix/array16_w7_c48_cfg.sv"} {read_verilog -sv [file join $partition_root rtl array16_blackbox.sv]} elseif {$source eq "rtl/graph/v024_unified_top.sv"} {read_verilog -sv [file join $out rtl v024_unified_top.sv]} elseif {$source ne ""} {read_verilog -sv [file join $core $source]}
}
close $fh
read_ip [file join $source_root ip asr_fma_ip asr_fma_ip.xci]
set fma [get_ips asr_fma_ip]
if {[llength $fma] != 1 || [get_property CONFIG.C_Latency $fma] ne "12"} {error "Wrong FMA or latency"}
# Reuse the verified official IP OOC checkpoint in this fresh process.
if {[get_property IS_LOCKED $fma]} {error "FMA IP is locked"}
set ip_dcp [file join $source_root ip asr_fma_ip generated asr_fma_ip.dcp]
if {![file exists $ip_dcp]} {error "Expected FMA OOC checkpoint missing"}
report_ip_status -file [file join $out reports retry2_ip_status.rpt]
puts "REUSE_VERIFIED_FMA_CHECKPOINT $ip_dcp"
set_property top v024_unified_top [current_fileset]
read_xdc [file join $core scripts deploy core_ooc.xdc]
update_compile_order -fileset sources_1
synth_design -top v024_unified_top -part $part -mode out_of_context -flatten_hierarchy rebuilt -generic MAX_NODES=128
write_checkpoint -force [file join $out build parent_unlinked.dcp]
# Save the synthesized parent before any checkpoint linking.
set partition [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
set expected [get_cells -quiet matrix/shared_array]
if {[llength $partition] != 1 || [llength $expected] != 1 || [lindex $partition 0] ne [lindex $expected 0]} {error "Expected exactly matrix/shared_array as the parent blackbox: $partition"}
set fma_cells [get_cells -quiet graph/vec/arithmetic/fused]
if {[llength $fma_cells] != 1 || [get_property IS_BLACKBOX $fma_cells]} {error "FMA not linked in parent"}
puts "PARENT_DCP_WRITTEN matrix/shared_array BB=1 FMA_LINKED=1"
report_utilization -file [file join $out reports parent_utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out reports parent_timing.rpt]
set f [open [file join $out reports parent_pass.txt] w]; puts $f "PARENT_SYNTH_PASS BB=1 FMA_LINKED=1 MAX_NODES=128 PARAM_END=0x20000000"; close $f
puts PARENT_SYNTH_PASS


