"""Keep PS DDR/RGMII/IO constraints and strict STA/DRC gates; add PL plan."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1'
s=(BASE/'scripts/build_full.tcl').read_text(encoding='utf-8')
def once(a,b):
    global s
    if s.count(a)!=1:raise ValueError('Build template mismatch '+a)
    s=s.replace(a,b)
once('replace_once {CONFIG.NUM_MI {2}} {CONFIG.NUM_MI {3}}','replace_once {CONFIG.NUM_MI {2}} {CONFIG.NUM_MI {4}}')
once('set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] $dsc','set_property -dict [list CONFIG.NUM_SI {6} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] $dsc\ncreate_bd_cell -type module -reference plan_board_v022 plans')
once('create_bd_design ps_gateway\n}', '''foreach name {ddr_vector_engine.sv ddr_vector_axi.sv ddr_layout_engine.sv ddr_layout_axi.sv u16_divmod.sv pl_execution_plan_v022.sv ddr_execution_cluster_v022.sv plan_submit_csr.sv plan_board_v022.sv} {read_verilog -sv [file join $newroot rtl $name]}
create_bd_design ps_gateway
}''')
once('connect_bd_intf_net [get_bd_intf_pins ddr_connect/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]', '''connect_bd_intf_net [get_bd_intf_pins ddr_connect/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]
connect_bd_net $clk [get_bd_pins plans/clk]
connect_bd_net $rst [get_bd_pins plans/rst_n]
connect_bd_intf_net [get_bd_intf_pins control_connect/M03_AXI] [get_bd_intf_pins plans/s_axi]
set si 1
foreach name {read_axi write_axi fetch_axi layout_read_axi layout_write_axi} {
 connect_bd_intf_net [get_bd_intf_pins plans/$name] [get_bd_intf_pins ddr_connect/[format {S%02d_AXI} $si]]
 incr si
}
foreach row {{busy plan_lock} {matrix_valid plan_matrix_valid} {matrix_queue_base plan_matrix_base} {matrix_queue_count plan_matrix_count} {matrix_ready plan_matrix_ready} {matrix_done plan_matrix_done} {matrix_fault plan_matrix_fault} {parameter_ready parameter_ready} {generation parameter_generation} {param_end parameter_end}} {
 lassign $row a b;connect_bd_net [get_bd_pins plans/$a] [get_bd_pins accelerator/$b]
}''')
once('{{accelerator 0xA8000000} {mailbox 0xA4000000} {resident 0xA0000000}}','{{plans 0xA9000000} {accelerator 0xA8000000} {mailbox 0xA4000000} {resident 0xA0000000}}')
s=s.replace('0xA51A2114','0xA51A2201').replace('USR_ACCESS=A51A2114','USR_ACCESS=A51A2201').replace('v0211_full','v022_full').replace('V0211_FULL','V022_FULL')
for name,data in [('build_full.tcl',s),('launch_build.ps1',(BASE/'scripts/launch_build.ps1').read_text())]:
    p=ROOT/'scripts'/name
    if p.exists():raise ValueError('Fresh build '+name)
    p.write_text(data,encoding='utf-8')
print('V022_FULL_BUILD_DERIVED: unchanged DDR init, same125MHz/201RGMII locks, strict signoff')
