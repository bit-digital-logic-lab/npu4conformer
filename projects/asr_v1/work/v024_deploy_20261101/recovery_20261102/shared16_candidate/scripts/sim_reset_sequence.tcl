set out [file normalize [file dirname [file dirname [info script]]]]
cd $out
set_param general.maxThreads 1
open_project [file join $out build combinedsim v024_combinedsim.xpr]
add_files -fileset sim_1 [file join $out fault_tb tb_reset_sequence.sv]
set_property top tb_reset_sequence [get_filesets sim_1]
set_property xsim.elaborate.mt_level off [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg memfile=../../../../../../core/sim/fixtures/mem_v024_fallback.hex"] [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
file copy -force [file join $out build combinedsim v024_combinedsim.sim sim_1 behav xsim simulate.log] [file join $out logs reset_sequence.log]
close_project
