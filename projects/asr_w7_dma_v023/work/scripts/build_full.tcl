# Reuse sealed non-matrix PL/network and the actual tested V020 banked core.
# Build only: no hardware access, PS initialization or boot-media writes.
set newroot [file normalize [file join [file dirname [info script]] ..]]
set legacy [file normalize [file join $newroot .. model_a_lowbit_v13]]
set matrix20 $newroot
set f [open [file join $legacy soc_full build.tcl] r];set script [read $f];close $f
proc replace_once {old new} {
 global script
 set at [string first $old $script]
 if {$at<0||[string first $old $script [expr {$at+[string length $old]}]]>=0} {error "Ambiguous inherited build patch: $old"}
 set script [string replace $script $at [expr {$at+[string length $old]-1}] $new]
}
proc phase {name} {
 global newroot argv
 set out [file join $newroot soc_full build [lindex $argv 0]]
 set f [open [file join $out phases.txt] a]
 set s "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $name"
 puts $f $s;close $f;puts "V022_FULL_PHASE $s"
}
replace_once {set root [file normalize [file join [file dirname [info script]] ..]]} {set root $legacy}
replace_once {set out [file join $root soc_full build $tag]} {set out [file join $newroot soc_full build $tag]}
replace_once {set_param general.maxThreads 4} {phase BEGIN
set_param general.maxThreads 2}
replace_once {foreach name {u4_mul coefficient_product_lowbits special_mac_array_lowbits asr_i16_mac asr_requant asr_fp32_alu asr_command_engine_parallel interleaved_fma_gemm lowbit_cached_engine v9_command_router asr_udp_command_bridge asr_udp_rx_guard asr_eth_board_zu15} {read_verilog -sv [file join $root rtl ${name}.sv]}} {
foreach name {u4_mul coefficient_product_lowbits special_mac_array_lowbits asr_i16_mac asr_requant asr_fp32_alu asr_command_engine_parallel interleaved_fma_gemm lowbit_cached_engine v9_command_router asr_udp_command_bridge asr_udp_rx_guard asr_eth_board_zu15} {
 if {$name in {lowbit_cached_engine asr_eth_board_zu15}} {read_verilog -sv [file join $newroot rtl ${name}.sv]} else {read_verilog -sv [file join $root rtl ${name}.sv]}
}
}
replace_once {set clk [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]} {set clk [create_bd_port -dir I -type clk -freq_hz 125000000 aclk]}
replace_once {create_bd_design ps_gateway} {
set_property verilog_define {V020_WIDE4 V020_CBANK} [current_fileset]
foreach name {task_queue.sv block_storage_dma_prefetch.sv axi_dma_v019.sv pe_direct_v020.sv array16_direct_v020.sv block_address_v020.sv block_engine_l1bank_v020.sv c_cache_banked4.sv operand_banks_v020.sv} {read_verilog -sv [file join $matrix20 rtl $name]}
foreach name {queued_v020_monitored.sv queue_submit_csr_board.sv queued_v020_board.sv v020_axi_wrapper.sv} {read_verilog -sv [file join $matrix20 rtl $name]}
set_property file_type Verilog [get_files */v020_axi_wrapper.sv]
foreach name {ddr_vector_engine.sv ddr_vector_axi.sv ddr_layout_engine.sv ddr_layout_axi.sv u16_divmod.sv pl_execution_plan_v022.sv ddr_execution_cluster_v022.sv plan_submit_csr.sv plan_board_v022.sv} {read_verilog -sv [file join $newroot rtl $name]}
set_property file_type Verilog [get_files */plan_board_v022.sv]
create_bd_design ps_gateway
}
replace_once {CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL} {CONFIG.PSU__USE__S_AXI_GP2 {1} CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
 CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL}
replace_once {CONFIG.NUM_MI {2}} {CONFIG.NUM_MI {4}}
replace_once {create_bd_cell -type module -reference v13_ps_mailbox mailbox} {
create_bd_cell -type module -reference v13_ps_mailbox mailbox
create_bd_cell -type module -reference v020_axi_wrapper accelerator
set dsc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* ddr_connect]
set_property -dict [list CONFIG.NUM_SI {6} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] $dsc
create_bd_cell -type module -reference plan_board_v022 plans
}
replace_once {connect_bd_intf_net [get_bd_intf_pins control_connect/M01_AXI] [get_bd_intf_pins mailbox/s_axi]} {
connect_bd_intf_net [get_bd_intf_pins control_connect/M01_AXI] [get_bd_intf_pins mailbox/s_axi]
connect_bd_net $clk [get_bd_pins ps/saxihp0_fpd_aclk] [get_bd_pins accelerator/clk] [get_bd_pins ddr_connect/aclk]
connect_bd_net $rst [get_bd_pins accelerator/rst_n] [get_bd_pins ddr_connect/aresetn]
connect_bd_intf_net [get_bd_intf_pins control_connect/M02_AXI] [get_bd_intf_pins accelerator/s_axi]
connect_bd_intf_net [get_bd_intf_pins accelerator/m_axi] [get_bd_intf_pins ddr_connect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ddr_connect/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]
connect_bd_net $clk [get_bd_pins plans/clk]
connect_bd_net $rst [get_bd_pins plans/rst_n]
connect_bd_intf_net [get_bd_intf_pins control_connect/M03_AXI] [get_bd_intf_pins plans/s_axi]
set si 1
foreach name {read_axi write_axi fetch_axi layout_read_axi layout_write_axi} {
 connect_bd_intf_net [get_bd_intf_pins plans/$name] [get_bd_intf_pins ddr_connect/[format {S%02d_AXI} $si]]
 incr si
}
foreach row {{busy plan_lock} {matrix_valid plan_matrix_valid} {matrix_queue_base plan_matrix_base} {matrix_queue_count plan_matrix_count} {matrix_ready plan_matrix_ready} {matrix_done plan_matrix_done} {matrix_fault plan_matrix_fault} {matrix_cycles plan_matrix_cycles} {matrix_pe_cycles plan_matrix_pe_cycles} {parameter_ready parameter_ready} {generation parameter_generation} {param_end parameter_end}} {
 lassign $row a b;connect_bd_net [get_bd_pins plans/$a] [get_bd_pins accelerator/$b]
}
}
replace_once {foreach row {{mailbox 0xA4000000} {resident 0xA0000000}}} {foreach row {{plans 0xA9000000} {accelerator 0xA8000000} {mailbox 0xA4000000} {resident 0xA0000000}}}
replace_once {generate_target all [get_files */ps_gateway.bd]} {generate_target all [get_files */ps_gateway.bd]
phase IP_GENERATED}
replace_once {launch_runs synth_1 -jobs 4} {launch_runs synth_1 -jobs 2
phase SYNTH_LAUNCHED}
replace_once {open_run synth_1} {open_run synth_1
phase SYNTH_COMPLETE
if {[llength [get_cells -quiet -hier -filter {NAME =~ *accelerator*core*array* && REF_NAME =~ DSP*}]]} {error "Unexpected V021 PE DSP"}}
replace_once "\nopt_design\n" "\nopt_design\nphase OPT_COMPLETE\n"
replace_once {place_design -directive Explore} {place_design -directive Explore
phase PLACE_COMPLETE}
replace_once {phys_opt_design -directive AggressiveExplore} {phys_opt_design -directive AggressiveExplore
phase PHYS_OPT_COMPLETE}
replace_once {route_design -directive Explore} {route_design -directive Explore
phase ROUTE_COMPLETE}
replace_once {set_property BITSTREAM.CONFIG.USR_ACCESS 0xA51A1310} {set_property BITSTREAM.CONFIG.USR_ACCESS 0xA51A2201}
replace_once {v13_full.bit} {v022_full.bit}
replace_once {v13_full_no_bit.xsa} {v022_full_no_bit.xsa}
replace_once {puts "V13_FULL_BUILD_PASS setup=$setup hold=$hold NOT_YET_GOLDEN"} {set f [open [file join $out result.txt] w]
puts $f "V022_FULL_BUILD_PASS\nCORE_MHZ=125\nWORST_SETUP=$setup\nWORST_HOLD=$hold\nUSR_ACCESS=A51A2201\nNot yet hardware tested."
close $f
phase BIT_COMPLETE
puts "V022_FULL_BUILD_PASS setup=$setup hold=$hold NOT_YET_GOLDEN"}
replace_once {close_project} {close_project
phase END}
# RGMII clocks/pins, all 201 RX placement locks, no-clock checks and signoff gates unchanged.
eval $script
