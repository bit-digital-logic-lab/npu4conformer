# Give synthesis the real oscillator before hierarchical pins exist.
# Board pin/DDR timing constraints are applied after elaboration/synthesis.
create_clock -name sys_clk -period 20.000 [get_ports clk]
