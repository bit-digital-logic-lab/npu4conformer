# Original AX7035 G16 UART_TX, verified in the prior physical V2 run.
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports uart_tx]
# Asynchronous serial output, not a synchronous external data interface.
set_false_path -to [get_ports uart_tx]
