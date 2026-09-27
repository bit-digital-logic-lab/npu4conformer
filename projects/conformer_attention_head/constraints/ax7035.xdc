# 中文说明：50MHz 时钟 Y18，复位 F20，UART 接收 G15、发送 G16。
# LED 引脚 F19/E21/D20/C20，LVCMOS33；异步入口仅对第一级同步器设置例外。
# ALINX AX7035 and AX7035B common clock/UART/reset/LED connections.
# Sources: AX7035 Chinese UG pp. 9-10,25-26,37-39;
#          AX7035B Chinese UG pp. 9,22-23,31-33.
# The English AX7035 manual contains an inconsistent V10 clock-table entry;
# both Chinese manuals and the English body identify Y18. Use Y18 here.
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
# FPGA RX is connected to CP210x TXD; FPGA TX is connected to CP210x RXD.
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports uart_txd]
# LED1..4, active low. Inversion is in ax7035_top.sv.
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN E21 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[3]}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
# Scope exceptions to asynchronous external inputs; internal release stays timed.
set_false_path -from [get_ports uart_rxd] -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ *rx_meta_reg}] -filter {REF_PIN_NAME == D}]
set_false_path -from [get_ports sys_rst_n] -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ *rst_sync_reg*}] -filter {REF_PIN_NAME == CLR}]
# These outputs have no external synchronous receiver clock.
set_false_path -to [get_ports {led[*] uart_txd}]
