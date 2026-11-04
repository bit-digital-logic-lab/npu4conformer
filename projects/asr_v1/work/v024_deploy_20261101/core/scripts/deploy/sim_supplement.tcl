set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root
open_project [file join $root build sim_project128 v024_sim128.xpr]
foreach tb {tb_v024_reference1024.sv tb_vendor_fma.sv} {add_files -fileset sim_1 [file join $root sim tb $tb]}
set_property top tb_vendor_fma [get_filesets sim_1]
set options "-testplusarg vecfile=$root/sim/fixtures/vendor_fma_vectors.hex -testplusarg goldfile=$root/sim/fixtures/lane_gold.hex"
set_property -dict [list xsim.simulate.runtime all xsim.simulate.xsim.more_options $options] [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
file copy -force [file join $root build sim_project128 v024_sim128.sim sim_1 behav xsim simulate.log] [file join $root logs vendor_fma.log]
set_property top tb_v024_reference1024 [get_filesets sim_1]
set options "-testplusarg outfile=$root/logs/v024_reference1024_out.hex -testplusarg memfile=$root/sim/fixtures/mem_v024_fused.hex -testplusarg watchdog=100000 -testplusarg mode=0"
set_property -dict [list xsim.simulate.xsim.more_options $options] [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
file copy -force [file join $root build sim_project128 v024_sim128.sim sim_1 behav xsim simulate.log] [file join $root logs v024_reference1024.log]
puts "SUPPLEMENTARY_SIMULATIONS_COMPLETED_CHECK_RESULTS_SEPARATELY"
