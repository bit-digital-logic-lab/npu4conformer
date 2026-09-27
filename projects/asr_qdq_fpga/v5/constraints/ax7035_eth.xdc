# ORIGINAL ALINX AX7035, KSZ9031RNX (not AX7035B/JL2121).
# Cross-checked ALINX AX7035_UG pp16-17 and AX7035_User_Manual pp18-19.
# Non-DDR banks are 3.3 V: original manual p9 / English manual p11.
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports rst_n]
create_clock -name sys_clk -period 20.000 [get_ports clk]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports phy_rx_clk]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {phy_rxd[0]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {phy_rxd[1]}]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {phy_rxd[2]}]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports {phy_rxd[3]}]
set_property -dict {PACKAGE_PIN M21 IOSTANDARD LVCMOS33} [get_ports phy_rx_ctl]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports phy_tx_clk]
set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {phy_txd[0]}]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {phy_txd[1]}]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {phy_txd[2]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports {phy_txd[3]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 16} [get_ports phy_tx_ctl]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports phy_reset_n]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports phy_mdc]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8 PULLUP TRUE} [get_ports phy_mdio]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]

# RGMII receive clock is independent of the local MMCM.
create_clock -name phy_rx_clk -period 8.000 [get_ports phy_rx_clk]
# PHY integrated-delay timing: DS00002117K Table 7-1 setup/hold >=1.2 ns.
# Reserve 0.2 ns board mismatch. Use transitions [+1,+3] after each RXC edge;
# the following DDR capture edge samples that symbol. A [-3,-1] representation
# without shifted capture relationships incorrectly asks hold on the same edge.
# These are assumptions for board flight-time mismatch, not measured PCB values.
set_input_delay -clock phy_rx_clk -max 3.000 [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -min 1.000 [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -clock_fall -add_delay -max 3.000 [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -clock_fall -add_delay -min 1.000 [get_ports {phy_rxd[*] phy_rx_ctl}]

# Source is the actual 90-degree ODDR C pin, NOT the unshifted data clock.
# Read this XDC after synth_design, then vendor scoped CDC tcl constraints.
set asr_txc_source [get_pins -hier -filter {REF_PIN_NAME == C && NAME =~ *clk_oddr_inst*}]
if {[llength $asr_txc_source] != 1} { error "Expected exactly one RGMII forwarded-clock ODDR" }
create_generated_clock -name phy_tx_clk -source $asr_txc_source -divide_by 1 [get_ports phy_tx_clk]
# PHY receiver requires setup/hold >=1 ns, with 0.2 ns board skew budget.
set_output_delay -clock phy_tx_clk -max 1.200 [get_ports {phy_txd[*] phy_tx_ctl}]
set_output_delay -clock phy_tx_clk -min -1.200 [get_ports {phy_txd[*] phy_tx_ctl}]
set_output_delay -clock phy_tx_clk -clock_fall -add_delay -max 1.200 [get_ports {phy_txd[*] phy_tx_ctl}]
set_output_delay -clock phy_tx_clk -clock_fall -add_delay -min -1.200 [get_ports {phy_txd[*] phy_tx_ctl}]

# MDIO is an explicitly synchronized slow management bus; RGMII is NOT excepted.
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports phy_mdio] -to [get_pins -hier -filter {NAME =~ *mdio_sync1_reg/D}]
# IDELAYCTRL RDY is a single-bit status crossing into a two-stage synchronizer.
set asr_idelay_ready_first [get_pins -hier -regexp {.*/idelay_ready_sync_reg\[0\]/D}]
if {[llength $asr_idelay_ready_first] != 1} { error "Expected one IDELAY RDY first synchronizer stage" }
set_false_path -to $asr_idelay_ready_first
set_false_path -to [get_ports {phy_reset_n phy_mdc phy_mdio}]
# Optional read-only UART diagnostic pin, same proven old-board mapping.
if {[llength [get_ports -quiet uart_tx]]} {
    set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports uart_tx]
    set_false_path -to [get_ports uart_tx]
}
