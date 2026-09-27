# AX7035 older board, identified from user's photograph (2026-09-22).
# ALINX Chinese AX7035_UG: 50 MHz Y18, reset F20; UART G15/G16.
# Official PDF direct download returns HTML; pin tables checked via search index
# and independently against the existing local AX7035 project constraints.
create_clock -name sys_clk -period 20.000 [get_ports clk]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports rst_n]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports uart_tx]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
# Only genuinely asynchronous external interfaces are excepted.
# UART RX synchronizer stage 2, reset release and all arithmetic remain timed.
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports uart_rx] -to [get_pins -hier -filter {NAME =~ */sync1_reg/D}]
set_false_path -to [get_ports uart_tx]
