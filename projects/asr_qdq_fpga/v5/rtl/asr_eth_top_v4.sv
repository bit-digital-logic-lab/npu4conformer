`timescale 1ns/1ps
`default_nettype none
module asr_eth_top_v4 (
    input wire clk, input wire rst_n,
    input wire phy_rx_clk, input wire [3:0] phy_rxd, input wire phy_rx_ctl,
    output wire phy_tx_clk, output wire [3:0] phy_txd, output wire phy_tx_ctl,
    output wire phy_reset_n, output wire phy_mdc, inout wire phy_mdio,
    output wire uart_tx
);
    wire core_clk,core_rst;
    wire [1:0] link_speed;
    wire [31:0] phy_id;
    wire phy_config_done,phy_config_error,rx_delay_ready;
    wire [15:0] phy_basic_status;
    wire rx_bad_frame,rx_bad_fcs,rx_overflow,tx_underflow,ip_arp_failed;
    wire s_hdr_valid,s_hdr_ready,m_hdr_valid,m_hdr_ready;
    wire [31:0] s_src_ip,m_dst_ip;
    wire [15:0] s_src_port,s_dst_port,s_udp_length,m_dst_port,m_src_port,m_udp_length;
    wire [7:0] s_axis_tdata,m_axis_tdata;
    wire s_axis_tvalid,s_axis_tready,s_axis_tlast,s_axis_tuser;
    wire m_axis_tvalid,m_axis_tready,m_axis_tlast,m_axis_tuser;
    wire engine_rx_valid,engine_rx_error,engine_tx_valid,engine_tx_ready,engine_busy;
    wire [7:0] engine_rx_data,engine_tx_data;

    // Upstream arp.v uses gateway_ip, not local_ip, as its subnet anchor.
    // This isolated /16 link has no router; use the local address as anchor.
    // Off-subnet destinations are not supported by this direct-link design.
    asr_eth_board #(.LOCAL_IP(32'ha9fe2304),.SUBNET_MASK(32'hffff0000),
                    .GATEWAY_IP(32'ha9fe2304)) board(.*);
    asr_udp_command_bridge bridge(.clk(core_clk),.rst_n(!core_rst),.*);
    asr_command_engine_v5 engine(
        .clk(core_clk),.rst_n(!core_rst),.rx_valid(engine_rx_valid),
        .rx_data(engine_rx_data),.rx_error(engine_rx_error),
        .tx_valid(engine_tx_valid),.tx_ready(engine_tx_ready),
        .tx_data(engine_tx_data),.busy(engine_busy));

    // UART is read-only diagnostics, NEVER an ASR command input in V4.
    // Binary 32-byte V4DG snapshots, once per second, 921600 8N1.
    reg [25:0] heartbeat=0;
    reg [31:0] received_packets=0,transmitted_packets=0;
    reg [15:0] bad_frames=0,bad_fcs=0,overflows=0,underflows=0,arp_failures=0;
    reg [255:0] telemetry=0;
    reg [5:0] telemetry_index=32;
    wire telemetry_ready;
    wire telemetry_valid=telemetry_index<32;
    wire [7:0] telemetry_data=telemetry[telemetry_index*8+:8];
    asr_uart_tx #(.CLK_HZ(50000000),.BAUD(921600)) diagnostic_uart(
        .clk(core_clk),.rst_n(!core_rst),.valid(telemetry_valid),
        .ready(telemetry_ready),.data(telemetry_data),.tx(uart_tx));
    always @(posedge core_clk) begin
        if(core_rst) begin
            heartbeat<=0;received_packets<=0;transmitted_packets<=0;
            bad_frames<=0;bad_fcs<=0;overflows<=0;underflows<=0;arp_failures<=0;
            telemetry<=0;telemetry_index<=32;
        end else begin
            if(s_hdr_valid && s_hdr_ready) received_packets<=received_packets+1;
            if(m_hdr_valid && m_hdr_ready) transmitted_packets<=transmitted_packets+1;
            if(rx_bad_frame) bad_frames<=bad_frames+1;
            if(rx_bad_fcs) bad_fcs<=bad_fcs+1;
            if(rx_overflow) overflows<=overflows+1;
            if(tx_underflow) underflows<=underflows+1;
            if(ip_arp_failed) arp_failures<=arp_failures+1;
            if(telemetry_valid && telemetry_ready) telemetry_index<=telemetry_index+1;
            if(heartbeat==49999999) begin
                heartbeat<=0;
                if(!telemetry_valid) begin
                    telemetry<={16'd0,arp_failures,underflows,overflows,bad_fcs,bad_frames,
                                transmitted_packets,received_packets,phy_basic_status,phy_id,
                                6'd0,link_speed,4'd0,rx_delay_ready,engine_busy,phy_config_error,phy_config_done,
                                32'h47443456};
                    telemetry_index<=0;
                end
            end else heartbeat<=heartbeat+1;
        end
    end
endmodule
`default_nettype wire
