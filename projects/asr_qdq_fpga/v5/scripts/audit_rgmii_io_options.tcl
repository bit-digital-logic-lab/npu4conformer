set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build rx_audit]
set_param general.maxThreads 2
open_checkpoint [file join $root build board_002 asr_v4_route.dcp]
set rx [get_ports {phy_rxd[*] phy_rx_ctl}]
set tx [get_ports {phy_txd[*] phy_tx_ctl}]
set_input_delay -clock phy_rx_clk -max 3.000 $rx
set_input_delay -clock phy_rx_clk -min 1.000 $rx
set_input_delay -clock phy_rx_clk -clock_fall -add_delay -max 3.000 $rx
set_input_delay -clock phy_rx_clk -clock_fall -add_delay -min 1.000 $rx
report_timing -from $rx -delay_type max -max_paths 10 -file [file join $out rx_positive_setup.rpt]
report_timing -to $tx -delay_type max -max_paths 10 -file [file join $out tx_original_setup.rpt]
foreach drive {12 16} {
    set_property DRIVE $drive [get_ports {phy_txd[*] phy_tx_ctl phy_tx_clk}]
    report_timing -to $tx -delay_type min -max_paths 10 -file [file join $out tx_drive${drive}_hold.rpt]
    report_timing -to $tx -delay_type max -max_paths 10 -file [file join $out tx_drive${drive}_setup.rpt]
}
puts "READ_ONLY_RGMII_IO_OPTIONS_DONE"
