set root [file normalize [file join [file dirname [info script]] ..]]
set run_name [lindex $argv 0]
if {![regexp {^[A-Za-z0-9_]+$} $run_name]} {error "Use a unique safe build name"}
set out [file join $root build $run_name]
if {[file exists [file join $out asr_v4_ax7035.bit]] || [file exists [file join $out asr_v4_route.dcp]]} {
    error "Existing build is protected; choose a fresh build name"
}
file mkdir $out
set frozen [file join $root .. releases v2_20260922_pre_golden]
set vendor [file join $root vendor verilog-ethernet]
set_param general.maxThreads 4
foreach name {asr_i16_mac asr_requant asr_fp32_alu asr_uart_tx} {
    read_verilog -sv [file join $frozen rtl ${name}.sv]
}
read_ip [file join $root build fma_ip_002 project fma_probe.srcs sources_1 ip asr_fma_ip asr_fma_ip.xci]
generate_target all [get_ips asr_fma_ip]
synth_ip [get_ips asr_fma_ip]
# Explicit 1G RGMII/IPv4/UDP dependency set, based on upstream NexysVideo example.
# Do not parse unrelated 10G/differential SDR examples into this Artix-7 build.
foreach name {iddr oddr ssio_ddr_in ssio_ddr_out rgmii_phy_if
    eth_mac_1g_rgmii_fifo eth_mac_1g_rgmii eth_mac_1g axis_gmii_rx axis_gmii_tx
    lfsr eth_axis_rx eth_axis_tx udp_complete udp_checksum_gen udp udp_ip_rx
    udp_ip_tx ip_complete ip ip_eth_rx ip_eth_tx ip_arb_mux arp arp_cache
    arp_eth_rx arp_eth_tx eth_arb_mux} {
    read_verilog [file join $vendor rtl ${name}.v]
}
foreach name {arbiter priority_encoder axis_fifo axis_async_fifo axis_async_fifo_adapter sync_reset} {
    read_verilog [file join $vendor lib axis rtl ${name}.v]
}
foreach source [glob [file join $root rtl *.sv]] {read_verilog -sv $source}
read_xdc [file join $root constraints synthesis_clock.xdc]
synth_design -top asr_eth_top_v4 -part xc7a35tfgg484-2
# This constraint file contains assertions and hierarchical lookups, so execute
# it as Tcl after synthesis rather than XDC's restricted command parser.
source [file join $root constraints ax7035_eth.xdc]
read_xdc [file join $root constraints diagnostic_uart.xdc]
# Only CDC/reset exceptions supplied by the component author. No broad clock groups.
foreach name {rgmii_phy_if eth_mac_1g_rgmii eth_mac_fifo} {
    source [file join $vendor syn vivado ${name}.tcl]
}
foreach name {axis_async_fifo sync_reset} {
    source [file join $vendor lib axis syn vivado ${name}.tcl]
}
report_utilization -file [file join $out utilization_synth.rpt]
report_clocks -file [file join $out clocks.rpt]
opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0.1 ||
    [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {
    # Optimize placed/routed cells without changing RTL semantics or clock rate.
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
}
report_utilization -file [file join $out utilization_route.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained -file [file join $out timing_route.rpt]
report_drc -file [file join $out drc_route.rpt]
report_cdc -details -file [file join $out cdc_route.rpt]
report_io -file [file join $out io.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
write_checkpoint [file join $out asr_v4_route.dcp]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "ASR_V4_TIMING setup=$setup hold=$hold"
if {$setup eq "" || $hold eq "" || $setup < 0 || $hold < 0} {error "V4 timing failed; no accepted bitstream"}
set errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $errors]} {error "V4 DRC errors: $errors"}
set_property BITSTREAM.CONFIG.USR_ACCESS 0xA5160005 [current_design]
set python [expr {[info exists ::env(ASR_PYTHON)] ? $::env(ASR_PYTHON) : "python"}]
puts [exec $python -I [file join $root scripts capture_build_inputs.py] --run $run_name --verify]
write_bitstream [file join $out asr_v4_ax7035.bit]
puts "ASR_V4_BUILD_PASS_NOT_PROGRAMMED"
