# Recover the existing standalone Ethernet hierarchy without rebuilding the old ASR core.
set dst [file normalize [file dirname [info script]]]
set_param general.maxThreads 8
puts "NETWORK_THREADS_LIMIT=[get_param general.maxThreads]"
open_checkpoint [file join $dst original_v022_top.dcp]
set eth [get_cells -quiet board]
if {[llength $eth] != 1 || [get_property REF_NAME $eth] ne "asr_eth_board_zu15"} {error "unexpected original network hierarchy"}
set bb [get_cells -quiet -hier -filter {IS_BLACKBOX==1 && NAME =~ board/*}]
if {[llength $bb]} {error "unresolved cells in original network subtree: $bb"}
# The recovered Ethernet block terminates in UDP streams; it does not include the old ASR datapath.
set rxdelay [get_cells -quiet -hier -filter {NAME =~ board/* && REF_NAME =~ rgmii_rx_delay*}]
if {[llength $rxdelay] != 1} {error "missing RGMII delay block"}
set pins [get_pins -quiet -of_objects $eth]
set f [open [file join $dst interface.txt] w]
foreach pin $pins {puts $f "[get_property DIRECTION $pin] [get_property REF_PIN_NAME $pin]"}
close $f
foreach pin {clk200_p clk200_n phy_rx_clk phy_rx_ctl phy_tx_clk phy_tx_ctl core_clk core_rst s_hdr_valid s_hdr_ready s_axis_tvalid s_axis_tready s_axis_tlast m_hdr_valid m_hdr_ready m_axis_tvalid m_axis_tready m_axis_tlast} {
    if {![llength [get_pins -quiet board/$pin]]} {error "network boundary missing $pin"}
}
report_utilization -cells $eth -file [file join $dst network_synth_utilization.rpt]
write_checkpoint -force -cell $eth [file join $dst network_ooc.dcp]
close_project
open_checkpoint [file join $dst network_ooc.dcp]
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX==1}]]} {error "exported network checkpoint has black boxes"}
foreach pin {phy_rx_clk phy_tx_clk phy_rx_ctl phy_tx_ctl s_hdr_valid m_hdr_valid s_axis_tvalid m_axis_tvalid} {
    if {[llength [get_ports -quiet $pin]] != 1} {error "exported network port missing: $pin"}
}
puts "NETWORK_RECOVERED_SYNTH_PASS TOP=[current_design] NO_NEW_NETWORK_BOARD_TEST"
close_project
