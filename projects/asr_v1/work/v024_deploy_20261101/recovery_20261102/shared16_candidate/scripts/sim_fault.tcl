set out [file normalize [file dirname [file dirname [info script]]]]
cd $out
set_param general.maxThreads 1
open_project [file join $out build combinedsim v024_combinedsim.xpr]
remove_files [get_files *wc_safety_bfm.sv]
foreach tb {tb_v024_acl_body.sv tb_parallel_fault.sv wc_safety_bfm.sv} {add_files -fileset sim_1 [file join $out fault_tb $tb]}
set_property top tb_parallel_fault [get_filesets sim_1]
set_property xsim.elaborate.debug_level off [get_filesets sim_1]
set_property xsim.elaborate.mt_level off [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
foreach spec {{vec 0 7} {fetch 1 3} {lay 0 7}} {
 lassign $spec kind fault err
 set mem ../../../../../../fault_tb/parallel_vec.hex
 if {$kind eq "lay"} {set mem ../../../../../../fault_tb/parallel_lay.hex}
 set options "-testplusarg memfile=$mem -testplusarg outfile=../../../../../../logs/fault_${kind}_out.hex -testplusarg mode=3 -testplusarg expect_error=$err -testplusarg watchdog=100000 -testplusarg fault_payload=$fault"
 set_property -dict [list xsim.simulate.xsim.more_options $options] [get_filesets sim_1]
 update_compile_order -fileset sim_1
 if {$kind eq "vec"} {launch_simulation -simset sim_1 -mode behavioral} else {launch_simulation -simset sim_1 -mode behavioral -step simulate}
 close_sim
 file copy -force [file join $out build combinedsim v024_combinedsim.sim sim_1 behav xsim simulate.log] [file join $out logs fault_${kind}.log]
}
close_project
puts SAFE16_FAULT_RUNS_COMPLETE

