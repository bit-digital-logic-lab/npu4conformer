# Assumed 50 MHz from user; replace only after checking actual board oscillator.
create_clock -name sys_clk -period 20.000 [get_ports clk]
# Reset assertion is asynchronous; deassertion is synchronized in asr_uart_top.
set_false_path -from [get_ports rst_n]
# UART RX is asynchronous. Only cut to the first synchronizer stage.
set_false_path -from [get_ports uart_rx] -to [get_pins -hier -filter {NAME =~ */sync1_reg/D}]
