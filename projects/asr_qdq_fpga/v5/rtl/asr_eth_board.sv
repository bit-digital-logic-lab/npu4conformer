`timescale 1ns/1ps
`default_nettype none
// AX7035 (original KSZ9031RNX revision), not AX7035B.
// The application and UDP stack run at the original 50 MHz. The MAC frame
// FIFOs cross to the independent PHY RX clock and MMCM 125 MHz TX clock.
module asr_eth_board #(
    parameter [47:0] LOCAL_MAC = 48'h020000003504,
    parameter [31:0] LOCAL_IP = 32'ha9fe2304,
    // arp.v compares destinations with gateway_ip when deciding same-subnet.
    // Default to our own subnet for a direct cable with no external router.
    parameter [31:0] GATEWAY_IP = LOCAL_IP,
    parameter [31:0] SUBNET_MASK = 32'hffff0000
)(
    input wire clk, input wire rst_n,
    input wire phy_rx_clk, input wire [3:0] phy_rxd, input wire phy_rx_ctl,
    output wire phy_tx_clk, output wire [3:0] phy_txd, output wire phy_tx_ctl,
    output wire phy_reset_n, output wire phy_mdc, inout wire phy_mdio,
    output wire core_clk, output wire core_rst,
    output wire rx_delay_ready,
    output wire [1:0] link_speed,
    output wire [31:0] phy_id,
    output wire phy_config_done, output wire phy_config_error,
    output wire [15:0] phy_basic_status,
    output wire rx_bad_frame, output wire rx_bad_fcs, output wire rx_overflow,
    output wire tx_underflow, output wire ip_arp_failed,

    // Names follow the application BRIDGE perspective: s=RX and m=TX.
    output wire s_hdr_valid, input wire s_hdr_ready,
    output wire [31:0] s_src_ip,
    output wire [15:0] s_src_port, output wire [15:0] s_dst_port,
    output wire [15:0] s_udp_length,
    output wire [7:0] s_axis_tdata,
    output wire s_axis_tvalid, input wire s_axis_tready,
    output wire s_axis_tlast, output wire s_axis_tuser,

    input wire m_hdr_valid, output wire m_hdr_ready,
    input wire [31:0] m_dst_ip,
    input wire [15:0] m_src_port, input wire [15:0] m_dst_port,
    input wire [15:0] m_udp_length,
    input wire [7:0] m_axis_tdata,
    input wire m_axis_tvalid, output wire m_axis_tready,
    input wire m_axis_tlast, input wire m_axis_tuser
);
    wire clk_in, clk125_raw, clk125_90_raw, clk50_raw, clk200_raw;
    wire clk125, clk125_90, clk200, clkfb, mmcm_locked, rst200;
    IBUF clk_ibuf (.I(clk), .O(clk_in));
    // 50 * 20 / 1 = 1000 MHz VCO; /8 = 125 MHz, /20 = 50 MHz.
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(20.0),
        .CLKFBOUT_MULT_F(20.0), .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(8.0), .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(8), .CLKOUT1_PHASE(90.0),
        .CLKOUT2_DIVIDE(20), .CLKOUT2_PHASE(0.0),
        .CLKOUT3_DIVIDE(5), .CLKOUT3_PHASE(0.0),
        .STARTUP_WAIT("FALSE")
    ) clk_mmcm (
        .CLKIN1(clk_in), .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(clk125_raw), .CLKOUT1(clk125_90_raw), .CLKOUT2(clk50_raw),
        .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3(clk200_raw), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB(),
        .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(!rst_n)
    );
    BUFG bufg125 (.I(clk125_raw), .O(clk125));
    BUFG bufg125_90 (.I(clk125_90_raw), .O(clk125_90));
    BUFG bufg50 (.I(clk50_raw), .O(core_clk));
    BUFG bufg200 (.I(clk200_raw), .O(clk200));
    sync_reset #(.N(4)) reset50 (.clk(core_clk), .rst(!rst_n || !mmcm_locked), .out(core_rst));
    // IDELAYCTRL requires at least 50 ns reset assertion; 16*5 ns = 80 ns.
    sync_reset #(.N(16)) reset200 (.clk(clk200), .rst(!rst_n || !mmcm_locked), .out(rst200));

    // board_002 routed evidence: direct RX data is ~1.33 ns but BUFIO clock
    // reaches IDDR at ~3.31 ns. Add calibrated data delay, not a PHY skew change.
    wire idelay_ready200;
    (* IODELAY_GROUP = "ASR_RGMII_RX" *)
    IDELAYCTRL rx_idelayctrl (.REFCLK(clk200), .RST(rst200), .RDY(idelay_ready200));
    (* ASYNC_REG = "TRUE" *) reg [1:0] idelay_ready_sync = 0;
    always @(posedge core_clk or posedge core_rst) begin
        if (core_rst) idelay_ready_sync<=0;
        else idelay_ready_sync<={idelay_ready_sync[0],idelay_ready200};
    end
    assign rx_delay_ready=idelay_ready_sync[1];
    wire [4:0] rx_delayed;
    wire [4:0] rx_raw={phy_rx_ctl,phy_rxd};
    genvar rx_bit;
    generate for(rx_bit=0;rx_bit<5;rx_bit=rx_bit+1) begin: rx_delays
        (* IODELAY_GROUP = "ASR_RGMII_RX" *)
        IDELAYE2 #(
            .DELAY_SRC("IDATAIN"), .IDELAY_TYPE("FIXED"), .IDELAY_VALUE(10),
            .HIGH_PERFORMANCE_MODE("TRUE"), .REFCLK_FREQUENCY(200.0),
            .SIGNAL_PATTERN("DATA"), .CINVCTRL_SEL("FALSE"), .PIPE_SEL("FALSE")
        ) delay_inst (
            .IDATAIN(rx_raw[rx_bit]), .DATAOUT(rx_delayed[rx_bit]), .DATAIN(1'b0),
            .C(1'b0), .CE(1'b0), .INC(1'b0), .CINVCTRL(1'b0), .CNTVALUEIN(5'd0),
            .CNTVALUEOUT(), .LD(1'b0), .LDPIPEEN(1'b0), .REGRST(1'b0)
        );
    end endgenerate

    asr_ksz9031_init phy_init (
        .clk(core_clk), .rst(core_rst), .phy_reset_n(phy_reset_n),
        .mdc(phy_mdc), .mdio(phy_mdio), .phy_id(phy_id),
        .config_done(phy_config_done), .config_error(phy_config_error),
        .basic_status(phy_basic_status)
    );
    // Single registered reset source, asynchronous assertion even if MMCM stops.
    reg network_rst = 1;
    always @(posedge core_clk or posedge core_rst) begin
        if (core_rst) network_rst<=1;
        else network_rst<=!phy_config_done || !rx_delay_ready;
    end
    wire network_rst125;
    sync_reset #(.N(4)) reset_mac125 (.clk(clk125), .rst(network_rst), .out(network_rst125));

    wire [7:0] mac_rx_data, mac_tx_data;
    wire mac_rx_valid, mac_rx_ready, mac_rx_last, mac_rx_user;
    wire mac_tx_valid, mac_tx_ready, mac_tx_last, mac_tx_user;
    eth_mac_1g_rgmii_fifo #(
        .TARGET("XILINX"), .IODDR_STYLE("IODDR"), .CLOCK_INPUT_STYLE("BUFR"),
        .USE_CLK90("TRUE"), .AXIS_DATA_WIDTH(8), .AXIS_KEEP_ENABLE(0),
        .TX_FIFO_DEPTH(4096), .RX_FIFO_DEPTH(4096),
        .TX_FRAME_FIFO(1), .RX_FRAME_FIFO(1), .RX_DROP_BAD_FRAME(1),
        .RX_DROP_WHEN_FULL(1)
    ) mac (
        .gtx_clk(clk125), .gtx_clk90(clk125_90), .gtx_rst(network_rst125),
        .logic_clk(core_clk), .logic_rst(network_rst),
        .tx_axis_tdata(mac_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(mac_tx_valid), .tx_axis_tready(mac_tx_ready),
        .tx_axis_tlast(mac_tx_last), .tx_axis_tuser(mac_tx_user),
        .rx_axis_tdata(mac_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(mac_rx_valid), .rx_axis_tready(mac_rx_ready),
        .rx_axis_tlast(mac_rx_last), .rx_axis_tuser(mac_rx_user),
        .rgmii_rx_clk(phy_rx_clk), .rgmii_rxd(rx_delayed[3:0]), .rgmii_rx_ctl(rx_delayed[4]),
        .rgmii_tx_clk(phy_tx_clk), .rgmii_txd(phy_txd), .rgmii_tx_ctl(phy_tx_ctl),
        .tx_error_underflow(tx_underflow), .tx_fifo_overflow(),
        .tx_fifo_bad_frame(), .tx_fifo_good_frame(),
        .rx_error_bad_frame(rx_bad_frame), .rx_error_bad_fcs(rx_bad_fcs),
        .rx_fifo_overflow(rx_overflow), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(link_speed), .cfg_ifg(8'd12),
        .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );
    wire rx_eth_hdr_valid, rx_eth_hdr_ready, tx_eth_hdr_valid, tx_eth_hdr_ready;
    wire [47:0] rx_eth_dest_mac, rx_eth_src_mac, tx_eth_dest_mac, tx_eth_src_mac;
    wire [15:0] rx_eth_type, tx_eth_type;
    wire [7:0] rx_eth_data, tx_eth_data;
    wire rx_eth_valid, rx_eth_ready, rx_eth_last, rx_eth_user;
    wire tx_eth_valid, tx_eth_ready, tx_eth_last, tx_eth_user;
    eth_axis_rx eth_rx (
        .clk(core_clk), .rst(network_rst),
        .s_axis_tdata(mac_rx_data), .s_axis_tkeep(1'b1),
        .s_axis_tvalid(mac_rx_valid), .s_axis_tready(mac_rx_ready),
        .s_axis_tlast(mac_rx_last), .s_axis_tuser(mac_rx_user),
        .m_eth_hdr_valid(rx_eth_hdr_valid), .m_eth_hdr_ready(rx_eth_hdr_ready),
        .m_eth_dest_mac(rx_eth_dest_mac), .m_eth_src_mac(rx_eth_src_mac), .m_eth_type(rx_eth_type),
        .m_eth_payload_axis_tdata(rx_eth_data), .m_eth_payload_axis_tkeep(),
        .m_eth_payload_axis_tvalid(rx_eth_valid), .m_eth_payload_axis_tready(rx_eth_ready),
        .m_eth_payload_axis_tlast(rx_eth_last), .m_eth_payload_axis_tuser(rx_eth_user),
        .busy(), .error_header_early_termination()
    );
    eth_axis_tx eth_tx (
        .clk(core_clk), .rst(network_rst),
        .s_eth_hdr_valid(tx_eth_hdr_valid), .s_eth_hdr_ready(tx_eth_hdr_ready),
        .s_eth_dest_mac(tx_eth_dest_mac), .s_eth_src_mac(tx_eth_src_mac), .s_eth_type(tx_eth_type),
        .s_eth_payload_axis_tdata(tx_eth_data), .s_eth_payload_axis_tkeep(1'b1),
        .s_eth_payload_axis_tvalid(tx_eth_valid), .s_eth_payload_axis_tready(tx_eth_ready),
        .s_eth_payload_axis_tlast(tx_eth_last), .s_eth_payload_axis_tuser(tx_eth_user),
        .m_axis_tdata(mac_tx_data), .m_axis_tkeep(),
        .m_axis_tvalid(mac_tx_valid), .m_axis_tready(mac_tx_ready),
        .m_axis_tlast(mac_tx_last), .m_axis_tuser(mac_tx_user), .busy()
    );
    wire udp_rx_hdr_valid, udp_rx_hdr_ready;
    wire [47:0] udp_rx_dest_mac;
    wire [31:0] udp_rx_dest_ip;
    wire [2:0] udp_rx_ip_flags;
    wire [12:0] udp_rx_fragment_offset;
    wire [7:0] udp_rx_ttl, udp_rx_data;
    wire [15:0] udp_rx_ip_length;
    wire udp_rx_valid, udp_rx_ready, udp_rx_last, udp_rx_user;
    asr_udp_rx_guard #(.LOCAL_MAC(LOCAL_MAC), .LOCAL_IP(LOCAL_IP)) rx_guard (
        .clk(core_clk), .rst(network_rst),
        .s_hdr_valid(udp_rx_hdr_valid), .s_hdr_ready(udp_rx_hdr_ready),
        .s_dest_mac(udp_rx_dest_mac), .s_dest_ip(udp_rx_dest_ip),
        .s_ip_flags(udp_rx_ip_flags), .s_fragment_offset(udp_rx_fragment_offset),
        .s_ttl(udp_rx_ttl), .s_ip_length(udp_rx_ip_length), .s_udp_length(s_udp_length),
        .s_axis_tdata(udp_rx_data), .s_axis_tvalid(udp_rx_valid), .s_axis_tready(udp_rx_ready),
        .s_axis_tlast(udp_rx_last), .s_axis_tuser(udp_rx_user),
        .m_hdr_valid(s_hdr_valid), .m_hdr_ready(s_hdr_ready),
        .m_axis_tdata(s_axis_tdata), .m_axis_tvalid(s_axis_tvalid), .m_axis_tready(s_axis_tready),
        .m_axis_tlast(s_axis_tlast), .m_axis_tuser(s_axis_tuser)
    );
    udp_complete #(
        .ARP_CACHE_ADDR_WIDTH(2), .ARP_REQUEST_RETRY_COUNT(4),
        .ARP_REQUEST_RETRY_INTERVAL(50000000), .ARP_REQUEST_TIMEOUT(250000000),
        .UDP_CHECKSUM_GEN_ENABLE(1), .UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH(2048),
        .UDP_CHECKSUM_HEADER_FIFO_DEPTH(8)
    ) udp (
        .clk(core_clk), .rst(network_rst),
        .s_eth_hdr_valid(rx_eth_hdr_valid), .s_eth_hdr_ready(rx_eth_hdr_ready),
        .s_eth_dest_mac(rx_eth_dest_mac), .s_eth_src_mac(rx_eth_src_mac), .s_eth_type(rx_eth_type),
        .s_eth_payload_axis_tdata(rx_eth_data), .s_eth_payload_axis_tvalid(rx_eth_valid),
        .s_eth_payload_axis_tready(rx_eth_ready), .s_eth_payload_axis_tlast(rx_eth_last),
        .s_eth_payload_axis_tuser(rx_eth_user),
        .m_eth_hdr_valid(tx_eth_hdr_valid), .m_eth_hdr_ready(tx_eth_hdr_ready),
        .m_eth_dest_mac(tx_eth_dest_mac), .m_eth_src_mac(tx_eth_src_mac), .m_eth_type(tx_eth_type),
        .m_eth_payload_axis_tdata(tx_eth_data), .m_eth_payload_axis_tvalid(tx_eth_valid),
        .m_eth_payload_axis_tready(tx_eth_ready), .m_eth_payload_axis_tlast(tx_eth_last),
        .m_eth_payload_axis_tuser(tx_eth_user),
        .s_ip_hdr_valid(1'b0), .s_ip_hdr_ready(), .s_ip_dscp(6'd0), .s_ip_ecn(2'd0),
        .s_ip_length(16'd0), .s_ip_ttl(8'd0), .s_ip_protocol(8'd0),
        .s_ip_source_ip(32'd0), .s_ip_dest_ip(32'd0),
        .s_ip_payload_axis_tdata(8'd0), .s_ip_payload_axis_tvalid(1'b0),
        .s_ip_payload_axis_tready(), .s_ip_payload_axis_tlast(1'b0), .s_ip_payload_axis_tuser(1'b0),
        .m_ip_hdr_ready(1'b1), .m_ip_payload_axis_tready(1'b1),
        .s_udp_hdr_valid(m_hdr_valid), .s_udp_hdr_ready(m_hdr_ready),
        .s_udp_ip_dscp(6'd0), .s_udp_ip_ecn(2'd0), .s_udp_ip_ttl(8'd64),
        .s_udp_ip_source_ip(LOCAL_IP), .s_udp_ip_dest_ip(m_dst_ip),
        .s_udp_source_port(m_src_port), .s_udp_dest_port(m_dst_port),
        .s_udp_length(m_udp_length), .s_udp_checksum(16'd0),
        .s_udp_payload_axis_tdata(m_axis_tdata),
        .s_udp_payload_axis_tvalid(m_axis_tvalid),
        .s_udp_payload_axis_tready(m_axis_tready),
        .s_udp_payload_axis_tlast(m_axis_tlast),
        .s_udp_payload_axis_tuser(m_axis_tuser),
        .m_udp_hdr_valid(udp_rx_hdr_valid), .m_udp_hdr_ready(udp_rx_hdr_ready),
        .m_udp_eth_dest_mac(udp_rx_dest_mac),
        .m_udp_ip_source_ip(s_src_ip), .m_udp_ip_dest_ip(udp_rx_dest_ip),
        .m_udp_ip_flags(udp_rx_ip_flags), .m_udp_ip_fragment_offset(udp_rx_fragment_offset),
        .m_udp_ip_ttl(udp_rx_ttl), .m_udp_ip_length(udp_rx_ip_length),
        .m_udp_source_port(s_src_port), .m_udp_dest_port(s_dst_port),
        .m_udp_length(s_udp_length),
        .m_udp_payload_axis_tdata(udp_rx_data),
        .m_udp_payload_axis_tvalid(udp_rx_valid),
        .m_udp_payload_axis_tready(udp_rx_ready),
        .m_udp_payload_axis_tlast(udp_rx_last),
        .m_udp_payload_axis_tuser(udp_rx_user),
        .ip_tx_error_arp_failed(ip_arp_failed),
        .local_mac(LOCAL_MAC), .local_ip(LOCAL_IP),
        .gateway_ip(GATEWAY_IP), .subnet_mask(SUBNET_MASK), .clear_arp_cache(1'b0)
    );
endmodule
`default_nettype wire
