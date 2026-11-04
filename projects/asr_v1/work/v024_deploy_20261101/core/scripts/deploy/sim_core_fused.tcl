set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
create_project -force v024_sim [file join $root build sim_project] -part xczu15eg-ffvb1156-2-i
set_property target_language Verilog [current_project]
set fh [open [file join $root filelist.f] r]
foreach source [split [read $fh] \n] {
 set source [string trim $source]
 if {$source ne ""} {read_verilog -sv [file join $root $source]}
}
close $fh
read_ip [file join $root build project v024_core.srcs sources_1 ip asr_fma_ip asr_fma_ip.xci]
add_files -fileset sim_1 [list [file join $root sim tb tb_v024_unified.sv] [file join $root sim tb wc_safety_bfm.sv]]
set_property top tb_v024_unified [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.xsim.more_options "-testplusarg memfile=$root/sim/fixtures/mem_v024_fused.hex -testplusarg outfile=$root/logs/v024_fused_out.hex -testplusarg watchdog=100000 -testplusarg mode=0" [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
puts "V024_XSIM_COMMAND_COMPLETED_CHECK_OUTPUT_SEPARATELY"
