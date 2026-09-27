# 中文说明：构建全部算子在 FPGA 执行的 Conformer 单头。
source [file join [file dirname [info script]] create_project.tcl]
set jobs 4
if {[info exists ::env(GEMM_JOBS)]} { set jobs $::env(GEMM_JOBS) }
if {[get_property NEEDS_REFRESH [get_runs synth_1]]} { reset_run synth_1 }
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
if {[get_property NEEDS_REFRESH [get_runs impl_1]]} { reset_run impl_1 }
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
}
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
set out_dir [file join $project_root artifacts]
file mkdir $out_dir
report_utilization -file [file join $out_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out_dir timing_summary.rpt]
report_drc -file [file join $out_dir drc.rpt]
report_methodology -file [file join $out_dir methodology.rpt]
foreach delay {max min} {
    set worst_path [get_timing_paths -quiet -delay_type $delay -max_paths 1]
    if {[llength $worst_path] == 0} { error "No $delay timing paths found." }
    if {[get_property SLACK $worst_path] < 0} { error "$delay timing failed; see timing_summary.rpt" }
}
set bit_file [file join [get_property DIRECTORY [get_runs impl_1]] ax7035_top.bit]
file copy -force $bit_file [file join $out_dir ax7035_top.bit]
puts "BUILD_PASS: [file join $out_dir ax7035_top.bit]"
