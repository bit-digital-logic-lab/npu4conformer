# Validate the AXU15EGB board-local execution path without disturbing the running FPGA.
# Usage: vivado -mode batch -source ps_ddr_shell.tcl -tclargs <new-output-directory>
if {$argc != 1} {error "expected a new project directory"}
set root [file normalize [file dirname [info script]]]
set deploy [file join $root .. v024_deploy_20261101]
set out [file normalize [lindex $argv 0]]
if {[file exists $out]} {error "output directory already exists"}
file mkdir $out
create_project resident [file join $out project] -part xczu15eg-ffvb1156-2-i
set_property target_language Verilog [current_project]
foreach file {platform/v024_unified_stub.sv board_control/v024_board_control.sv} {
    add_files [file join $deploy $file]
}
# Keep the array untouched. Only adapt the platform wrapper for a DDR-sized
# parameter window and the two single-bit USER fields expected by the PS port.
set input [open [file join $deploy platform v024_core_wrapper.sv] r]
set original [read $input]
close $input
set substitutions [list \
    {module v024_core_wrapper (} {module v024_ddr_core_wrapper (
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARUSER" *) output wire [0:0] m_aruser,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWUSER" *) output wire [0:0] m_awuser,} \
    {PROTOCOL AXI4, DATA_WIDTH 128} {PROTOCOL AXI4, ARUSER_WIDTH 1, AWUSER_WIDTH 1, DATA_WIDTH 128} \
    { (* DONT_TOUCH = "yes" *)} { assign m_aruser = 1'b0;
 assign m_awuser = 1'b0;
 (* DONT_TOUCH = "yes" *)} \
    {.MAX_NODES(128), .SEQ_ENABLE(0)} {.MAX_NODES(128), .SEQ_ENABLE(0), .PARAM_END(32'h20000000)}]
foreach {needle replacement} $substitutions {
    if {[string first $needle $original] < 0 || [string first $needle $original] != [string last $needle $original]} {
        error "unexpected input wrapper: $needle"
    }
}
set wrapper [file join $out v024_ddr_core_wrapper.v]
set file [open $wrapper w]
puts -nonewline $file [string map $substitutions $original]
close $file
add_files $wrapper
set_property FILE_TYPE Verilog [get_files -filter {FILE_TYPE == SystemVerilog}]
create_bd_design ps_ddr
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps
source [file join $deploy ps_platform alinx_ps_config_original.tcl]
set_ps_config ps
set ps [get_bd_cells ps]
set cfg [dict create]
foreach prop [list_property $ps] {
    if {[string match CONFIG.PSU__*__PERIPHERAL__ENABLE $prop]} {dict set cfg $prop 0}
}
foreach {prop value} {
    CONFIG.PSU__DDRC__ENABLE 1
    CONFIG.PSU__USE__DDR_INTF_REQUESTED 1
    CONFIG.PSU__USE__M_AXI_GP0 1
    CONFIG.PSU__USE__M_AXI_GP1 0
    CONFIG.PSU__USE__M_AXI_GP2 0
    CONFIG.PSU__USE__S_AXI_GP2 1
    CONFIG.PSU__SAXIGP2__DATA_WIDTH 128
    CONFIG.PSU__FPGA_PL0_ENABLE 1
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 50
} {dict set cfg $prop $value}
set_property -dict $cfg $ps
create_bd_cell -type module -reference v024_ddr_core_wrapper core_wrap
create_bd_cell -type module -reference v024_board_control board_control
foreach {name n} {ctrl 2 ddr 1} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $name
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI $n CONFIG.NUM_CLKS 1] [get_bd_cells $name]
}
foreach {a b} {
    ps/M_AXI_HPM0_FPD ctrl/S00_AXI
    ctrl/M00_AXI core_wrap/S_AXI
    ctrl/M01_AXI board_control/S_AXI
    core_wrap/M_AXI ddr/S00_AXI
    ddr/M00_AXI ps/S_AXI_HP0_FPD
} {connect_bd_intf_net [get_bd_intf_pins $a] [get_bd_intf_pins $b]}
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset50
set_property CONFIG.C_AUX_RESET_HIGH 0 [get_bd_cells reset50]
foreach {cell val} {one 1 zero 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 $cell
    set_property CONFIG.CONST_VAL $val [get_bd_cells $cell]
}
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins reset50/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset50/aux_reset_in] [get_bd_pins reset50/dcm_locked]
connect_bd_net [get_bd_pins zero/dout] [get_bd_pins reset50/mb_debug_sys_rst]
set clk [get_bd_pins ps/pl_clk0]
foreach pin {ps/maxihpm0_fpd_aclk ps/saxihp0_fpd_aclk ctrl/aclk ddr/aclk core_wrap/aclk board_control/aclk reset50/slowest_sync_clk} {
    connect_bd_net $clk [get_bd_pins $pin]
}
connect_bd_net [get_bd_pins reset50/interconnect_aresetn] [get_bd_pins ctrl/aresetn] [get_bd_pins ddr/aresetn]
connect_bd_net [get_bd_pins reset50/peripheral_aresetn] [get_bd_pins board_control/aresetn]
connect_bd_net [get_bd_pins board_control/core_reset_n] [get_bd_pins core_wrap/core_reset_n]
foreach pin {pc_wr_valid pc_wr_addr pc_wr_data pc_wr_ready busy done fault requires_reset port_quiesced b_pending rd_pending wr_pending completed last_node error_code cycles matrix_fused_used fuse_c48_ddr_bytes fuse_a16_bytes} {
    connect_bd_net [get_bd_pins core_wrap/$pin] [get_bd_pins board_control/$pin]
}
set cpu [get_bd_addr_spaces ps/Data]
set pl [get_bd_addr_spaces core_wrap/M_AXI]
assign_bd_address -target_address_space $cpu -offset 0xA0000000 -range 16M [get_bd_addr_segs -of_objects [get_bd_intf_pins core_wrap/S_AXI]]
assign_bd_address -target_address_space $cpu -offset 0xA1000000 -range 64K [get_bd_addr_segs -of_objects [get_bd_intf_pins board_control/S_AXI]]
set low [get_bd_addr_segs -of_objects [get_bd_intf_pins ps/S_AXI_HP0_FPD] -filter {NAME == HP0_DDR_LOW}]
if {[llength $low] != 1} {error "missing verified HP0 low DDR segment: $low"}
assign_bd_address -target_address_space $pl -offset 0x00000000 -range 2G $low
foreach seg [get_bd_addr_segs -of_objects [get_bd_intf_pins ps/S_AXI_HP0_FPD]] {
    if {$seg ne $low} {exclude_bd_addr_seg -target_address_space $pl $seg}
}
validate_bd_design
if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells reset50]] != 0} {error "unexpected PS reset polarity"}
foreach prop {ARUSER_WIDTH AWUSER_WIDTH} {
    foreach pin {core_wrap/M_AXI ddr/M00_AXI ps/S_AXI_HP0_FPD} {
        if {[get_property CONFIG.$prop [get_bd_intf_pins $pin]] != 1} {error "$pin $prop missing"}
    }
}
save_bd_design
write_bd_tcl [file join $out resident_bd.tcl]
set f [open [file join $out connectivity.txt] w]
puts $f "VIVADO_BD_VALIDATED_ONLY\npart=[get_property PART [current_project]]\ncore_port=core_wrap/M_AXI\nboard_memory_port=ps/S_AXI_HP0_FPD\nDDR_port_bits=[get_property CONFIG.PSU__SAXIGP2__DATA_WIDTH $ps]\nDDR_enabled=[get_property CONFIG.PSU__DDRC__ENABLE $ps]\nclock_MHz=[get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $ps]"
puts $f "core_parameter_window=0x10000000..0x1fffffff (256 MiB, requires synthesis with the new PARAM_END generic)"
foreach space [list $cpu $pl] {
    foreach seg [get_bd_addr_segs -of_objects $space] {
        puts $f "$space $seg offset=[get_property OFFSET $seg] range=[get_property RANGE $seg]"
    }
}
puts $f "This is a block design with a core placeholder. No synthesized system, timing, firmware, network interface or board result is claimed."
close $f
close_project
