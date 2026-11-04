set dst [file normalize [file dirname [info script]]]
set root [file normalize [file join $dst .. .. .. ..]]
set projects [file join $root v0.24 npu4conformer-main npu4conformer-main projects]
set v5 [file join $projects asr_qdq_fpga v5]
set vendor [file join $v5 vendor verilog-ethernet]
set part xczu15eg-ffvb1156-2-i
set_param general.maxThreads 8
create_project -in_memory -part $part
foreach src [lsort [concat [glob $vendor/rtl/*.v] [glob $vendor/lib/axis/rtl/*.v]]] {
    if {[file tail $src] ni {iddr.v oddr.v}} { read_verilog $src }
}
read_verilog -sv [file join $dst zu15_rgmii_io.sv]
read_verilog -sv [file join $v5 rtl asr_udp_rx_guard.sv]
read_verilog -sv [file join $projects asr_w7_dma_v023 work rtl asr_eth_board_zu15.sv]
read_xdc [file join $dst network_ooc.xdc]
synth_design -top asr_eth_board_zu15 -part $part -mode out_of_context
proc inspect {} {
    if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "unresolved Ethernet instance"}
    foreach {type count} {IDELAYCTRL 1 IDELAYE3 5 IDDRE1 5 OSERDESE3 6} {
        set found [get_cells -quiet -hier -filter "REF_NAME == $type"]
        if {[llength $found] != $count} {error "expected $count $type, found [llength $found]"}
    }
    foreach pin {clk200_p clk200_n phy_rx_clk phy_tx_clk phy_rx_ctl phy_tx_ctl s_hdr_valid s_hdr_ready m_hdr_valid m_hdr_ready s_axis_tvalid m_axis_tvalid s_axis_tready m_axis_tready s_axis_tlast m_axis_tlast core_clk core_rst} {
        if {[llength [get_ports -quiet $pin]] != 1} {error "missing Ethernet top port $pin"}
    }
}
inspect
report_utilization -file [file join $dst network_synth_utilization.rpt]
write_checkpoint -force [file join $dst network_ooc.dcp]
close_project
open_checkpoint [file join $dst network_ooc.dcp]
inspect
puts "NETWORK_OOC_SYNTH_PASS BB=0 RX_IDELAY=5 IDDRE1=5 TX_OSERDES=6 THREAD_LIMIT=[get_param general.maxThreads]"
