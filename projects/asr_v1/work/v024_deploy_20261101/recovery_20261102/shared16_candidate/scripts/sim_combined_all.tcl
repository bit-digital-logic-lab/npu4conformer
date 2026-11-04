# Fourteen tests: original eleven plus 128/129-node and out-of-window dependency guards.
set root {C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/recovery_20261102/shared16_candidate/core}
set out {C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/recovery_20261102/shared16_candidate}
cd $out
set_param general.maxThreads 1
create_project -force v024_combinedsim [file join $out build combinedsim] -part xczu15eg-ffvb1156-2-i
set_property target_language Verilog [current_project]
set fh [open [file join $root filelist.f] r]
foreach source [split [read $fh] \n] {
 set source [string trim $source]
 if {$source ne ""} {read_verilog -sv [file join $root $source]}
}
close $fh
read_ip [file join $out ip asr_fma_ip asr_fma_ip.xci]
generate_target all [get_ips asr_fma_ip]
foreach tb {tb_v024_unified.sv wc_safety_bfm.sv tb_safety_integrated.sv tb_v024_epilogue.sv} {
 add_files -fileset sim_1 [file join $root sim tb $tb]
}
add_files -fileset sim_1 [file join $root analysis tb_v024_iterhash.sv]
set_property xsim.elaborate.debug_level off [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set cases {
 {v024_fused tb_v024_iterhash mem_v024_fused.hex {watchdog=100000 mode=0}}
 {v024_fallback tb_v024_iterhash mem_v024_fallback.hex {watchdog=100000 mode=1}}
 {v024_multicons tb_v024_iterhash mem_v024_multicons.hex {watchdog=100000 mode=4}}
 {v024_badflag tb_v024_iterhash mem_v024_badflag.hex {watchdog=40000 mode=3 expect_error=4}}
 {v024_hold tb_v024_iterhash mem_v024_fused.hex {watchdog=80000 mode=2 hold_b_lo=04004000 hold_b_hi=04005000}}
 {v024_badcrc_stored tb_v024_iterhash ../../analysis/mem_v024_badcrc_stored.hex {watchdog=100000 mode=3 expect_error=4}}
 {v024_badcrc_header tb_v024_iterhash ../../analysis/mem_v024_badcrc_header.hex {watchdog=100000 mode=3 expect_error=4}}
 {v024_badcrc_node tb_v024_iterhash ../../analysis/mem_v024_badcrc_node.hex {watchdog=100000 mode=3 expect_error=4}}
 {v024_bound128 tb_v024_iterhash mem_v024_bound128.hex {watchdog=100000 mode=1 expect_error=0}}
 {v024_over129 tb_v024_iterhash mem_v024_over129.hex {watchdog=40000 mode=3 expect_error=4}}
 {v024_baddep128 tb_v024_iterhash mem_v024_baddep128.hex {watchdog=40000 mode=3 expect_error=4}}
 {base_normal tb_safety_integrated mem_normal.hex {watchdog=120000 mode=0}}
 {base_multitask tb_safety_integrated mem_multitask.hex {watchdog=120000 mode=5}}
 {base_bad_queue_magic tb_safety_integrated mem_bad_queue_magic.hex {watchdog=60000 allow_fault=1 expect_error=3}}
 {base_bad_vec_op tb_safety_integrated mem_bad_vec_op.hex {watchdog=60000 allow_fault=1 expect_error=7}}
 {base_hold_b_c tb_safety_integrated mem_normal.hex {watchdog=60000 allow_fault=1 expect_error=14 expect_iso=1 expect_requires_reset=1 hold_b_lo=04002000 hold_b_hi=04003000}}
 {v024_lane tb_v024_epilogue none {}}
}
set previous_top none
foreach spec $cases {
 lassign $spec name top mem extra
 set options [list -testplusarg "outfile=../../../../../../logs/${name}_out.hex"]
 if {$mem ne "none"} {lappend options -testplusarg "memfile=../../../../../../core/sim/fixtures/$mem"}
 foreach arg $extra {lappend options -testplusarg $arg}
 if {$name eq "v024_lane"} {
  lappend options -testplusarg "vecfile=../../../../../../core/sim/fixtures/lane_vectors.hex" -testplusarg "goldfile=../../../../../../core/sim/fixtures/lane_gold.hex" -testplusarg "twofile=../../../../../../core/sim/fixtures/lane_muladd.hex"
 }
 set_property top $top [get_filesets sim_1]
 set_property -dict [list xsim.simulate.xsim.more_options [join $options " "]] [get_filesets sim_1]
 update_compile_order -fileset sim_1
 puts "V024_RUN_BEGIN $name TOP=$top MAX_NODES=128 REAL_FMA_IP=1 HASH=ITERATIVE_SELECTED VECTOR_MEMORY=PARITY_SINGLE_WRITE"
 if {$top eq $previous_top} {launch_simulation -simset sim_1 -mode behavioral -step simulate} else {launch_simulation -simset sim_1 -mode behavioral}
 close_sim
 file copy -force [file join $out build combinedsim v024_combinedsim.sim sim_1 behav xsim simulate.log] [file join $out logs ${name}.log]
 set previous_top $top
 puts "V024_RUN_COMMAND_COMPLETED $name"
}
puts "V024_XSIM_REGRESSION_COMMANDS_COMPLETED_CHECK_RESULTS_SEPARATELY"



