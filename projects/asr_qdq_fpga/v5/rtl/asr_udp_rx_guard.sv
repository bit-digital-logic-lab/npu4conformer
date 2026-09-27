`timescale 1ns/1ps
`default_nettype none
// The upstream UDP parser forwards destination/fragment fields but does not
// filter them. Admit only unicast, unfragmented local ASR datagrams; drain the
// complete payload of all other datagrams without exposing a header to ASR.
module asr_udp_rx_guard #(
    parameter [47:0] LOCAL_MAC = 48'h020000003504,
    parameter [31:0] LOCAL_IP = 32'ha9fe2304
)(
    input wire clk, input wire rst,
    input wire s_hdr_valid, output wire s_hdr_ready,
    input wire [47:0] s_dest_mac, input wire [31:0] s_dest_ip,
    input wire [2:0] s_ip_flags, input wire [12:0] s_fragment_offset,
    input wire [7:0] s_ttl,
    input wire [15:0] s_ip_length, input wire [15:0] s_udp_length,
    input wire [7:0] s_axis_tdata, input wire s_axis_tvalid,
    output wire s_axis_tready, input wire s_axis_tlast, input wire s_axis_tuser,
    output wire m_hdr_valid, input wire m_hdr_ready,
    output wire [7:0] m_axis_tdata, output wire m_axis_tvalid,
    input wire m_axis_tready, output wire m_axis_tlast, output wire m_axis_tuser
);
    reg active=0, accept_payload=0;
    wire eligible = s_dest_mac == LOCAL_MAC && s_dest_ip == LOCAL_IP &&
                    !s_ip_flags[2] && !s_ip_flags[0] && s_fragment_offset == 0 &&
                    s_ttl != 0 && s_udp_length >= 26 && s_udp_length <= 1408 &&
                    {1'b0,s_ip_length} == {1'b0,s_udp_length}+17'd20;
    assign s_hdr_ready = !active && (!eligible || m_hdr_ready);
    assign m_hdr_valid = !active && eligible && s_hdr_valid;
    assign s_axis_tready = active && (!accept_payload || m_axis_tready);
    assign m_axis_tvalid = active && accept_payload && s_axis_tvalid;
    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tlast = s_axis_tlast;
    assign m_axis_tuser = s_axis_tuser;
    always @(posedge clk) begin
        if (rst) begin active<=0; accept_payload<=0; end
        else begin
            if (s_hdr_valid && s_hdr_ready) begin
                active<=1; accept_payload<=eligible;
            end
            if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                active<=0; accept_payload<=0;
            end
        end
    end
endmodule
`default_nettype wire
