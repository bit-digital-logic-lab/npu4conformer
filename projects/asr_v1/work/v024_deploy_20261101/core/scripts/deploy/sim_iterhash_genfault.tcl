set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
set_param general.maxThreads 1
open_project [file join $root build hashsim v024_hashsim.xpr]
add_files -fileset sim_1 [file join $root analysis tb_v024_iterhash_genfault.sv]
set_property top tb_v024_iterhash_genfault [get_filesets sim_1]
set_property xsim.elaborate.debug_level off [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
foreach st {10 11} {
 set name v024_genfault_$st
 set options "-testplusarg memfile=$root/sim/fixtures/mem_v024_fused.hex -testplusarg outfile=$root/analysis/iterhash_logs/${name}_out.hex -testplusarg mode=3 -testplusarg expect_error=2 -testplusarg watchdog=100000 -testplusarg inject_state=$st"
 set_property -dict [list xsim.simulate.xsim.more_options $options] [get_filesets sim_1]
 update_compile_order -fileset sim_1
 if {$st==10} {launch_simulation -simset sim_1 -mode behavioral} else {launch_simulation -simset sim_1 -mode behavioral -step simulate}
 close_sim
 file copy -force [file join $root build hashsim v024_hashsim.sim sim_1 behav xsim simulate.log] [file join $root analysis iterhash_logs ${name}.log]
}
puts "ITERHASH_GENERATION_TESTS_COMPLETED_CHECK_SEPARATELY"
