`timescale 1ns/1ps
module tb_udp_rx_guard;
    reg clk=0; always #10 clk=~clk;
    reg rst=1;
    reg s_hdr_valid=0; wire s_hdr_ready;
    reg [47:0] s_dest_mac; reg [31:0] s_dest_ip;
    reg [2:0] s_ip_flags; reg [12:0] s_fragment_offset;
    reg [7:0] s_ttl; reg [15:0] s_ip_length,s_udp_length;
    reg [7:0] s_axis_tdata=0; reg s_axis_tvalid=0;
    wire s_axis_tready; reg s_axis_tlast=0,s_axis_tuser=0;
    wire m_hdr_valid; reg m_hdr_ready=0;
    wire [7:0] m_axis_tdata; wire m_axis_tvalid;
    reg m_axis_tready=0; wire m_axis_tlast,m_axis_tuser;
    asr_udp_rx_guard dut(.*);
    integer tests=0, headers=0, bytes_seen=0;
    always @(posedge clk) if(!rst) begin
        if(m_hdr_valid && m_hdr_ready) headers=headers+1;
        if(m_axis_tvalid && m_axis_tready) bytes_seen=bytes_seen+1;
    end
    task defaults;
        begin
            s_dest_mac=48'h020000003504; s_dest_ip=32'ha9fe2304;
            s_ip_flags=0; s_fragment_offset=0; s_ttl=64;
            s_udp_length=26; s_ip_length=46;
        end
    endtask
    task packet(input integer accept_expected);
        integer before_headers,before_bytes,j;
        begin
            before_headers=headers;before_bytes=bytes_seen;
            @(negedge clk); s_hdr_valid=1; m_hdr_ready=0;
            #1;
            if(accept_expected) begin
                if(s_hdr_ready || !m_hdr_valid) $fatal(1,"good header must honor backpressure");
                repeat(3) @(negedge clk);
                m_hdr_ready=1;
            end else if (!s_hdr_ready || m_hdr_valid) $fatal(1,"bad header must drain independently");
            @(negedge clk); s_hdr_valid=0; m_hdr_ready=1;
            // Header changes after acceptance must not alter the drain decision.
            defaults();
            for(j=0;j<4;j=j+1) begin
                s_axis_tvalid=1;s_axis_tdata=8'h80+j;s_axis_tlast=j==3;s_axis_tuser=j==3;
                m_axis_tready=0; #1;
                if(accept_expected) begin
                    if(s_axis_tready || !m_axis_tvalid || m_axis_tdata!==s_axis_tdata)
                        $fatal(1,"accepted payload backpressure failure");
                    repeat(2) @(negedge clk);
                    if(m_axis_tdata!==s_axis_tdata || m_axis_tlast!==s_axis_tlast || m_axis_tuser!==s_axis_tuser)
                        $fatal(1,"payload metadata mismatch");
                    m_axis_tready=1;
                end else if(!s_axis_tready || m_axis_tvalid) $fatal(1,"bad payload leaked/blocked");
                @(negedge clk);
            end
            s_axis_tvalid=0;s_axis_tlast=0;s_axis_tuser=0;
            if(headers-before_headers!=accept_expected || bytes_seen-before_bytes!=4*accept_expected)
                $fatal(1,"header/data count mismatch");
            tests=tests+1;
        end
    endtask
    initial begin
        defaults(); repeat(5) @(negedge clk);rst=0;
        packet(1);
        defaults();s_ip_flags=2;packet(1); // DF is allowed.
        defaults();s_dest_ip=32'ha9fe2305;packet(0);
        defaults();s_dest_mac=48'hffffffffffff;packet(0);
        defaults();s_fragment_offset=1;packet(0);
        defaults();s_ip_flags=1;packet(0); // More fragments.
        defaults();s_ip_flags=4;packet(0); // Reserved flag.
        defaults();s_ttl=0;packet(0);
        defaults();s_ip_length=47;packet(0);
        defaults();s_udp_length=25;s_ip_length=45;packet(0);
        defaults();s_udp_length=1409;s_ip_length=1429;packet(0);
        defaults();s_udp_length=1408;s_ip_length=1428;packet(1);
        defaults();packet(1); // Recovery after dropped frames.
        $display("UDP_RX_GUARD_TEST_PASS cases=%0d",tests);$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
