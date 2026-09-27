# Read-only checkpoint audit; modified constraints exist only in memory.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build rx_audit]
file mkdir $out
set_param general.maxThreads 2
open_checkpoint [file join $root build board_002 asr_v4_route.dcp]
set rx [get_ports {phy_rxd[*] phy_rx_ctl}]
set_input_delay -clock phy_rx_clk -max 3.000 $rx
set_input_delay -clock phy_rx_clk -min 1.000 $rx
set_input_delay -clock phy_rx_clk -clock_fall -add_delay -max 3.000 $rx
set_input_delay -clock phy_rx_clk -clock_fall -add_delay -min 1.000 $rx
report_timing -from $rx -delay_type min_max -max_paths 20 -nworst 4 -file [file join $out rx_positive_cycle.rpt]
report_timing -to [get_ports {phy_txd[*] phy_tx_ctl}] -delay_type min_max -max_paths 20 -nworst 4 -file [file join $out tx_original.rpt]
report_cdc -details -file [file join $out cdc_original.rpt]
puts "READ_ONLY_RGMII_AUDIT_DONE"
