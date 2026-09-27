set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build numeric_sim_001]
create_project numeric_sim [file join $out project] -part xc7a35tfgg484-2
set frozen [file join $root .. releases v2_20260922_pre_golden]
foreach name {asr_i16_mac asr_requant asr_fp32_alu} {read_verilog -sv [file join $frozen rtl ${name}.sv]}
read_verilog -sv [file join $root rtl asr_command_engine_v5.sv]
read_ip [file join $root build fma_ip_002 project fma_probe.srcs sources_1 ip asr_fma_ip asr_fma_ip.xci]
generate_target simulation [get_ips asr_fma_ip]
add_files -fileset sim_1 [file join $root sim tb_v5_numeric.sv]
set_property top tb_v5_numeric [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.xsim.more_options [format {-testplusarg "INPUT=%s" -testplusarg "OUTPUT=%s"} [file join $out input.hex] [file join $out output.hex]] [get_filesets sim_1]
launch_simulation -mode behavioral
close_sim
puts V5_NUMERIC_SIM_FINISHED
