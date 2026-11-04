create_clock -name refclk200 -period 5.0 [get_ports clk200_p]
create_clock -name rgmii_rxc -period 8.0 [get_ports phy_rx_clk]
