`timescale 1ns/1ps
// Test the actual vendored ARP implementation, not a replacement routing model.
module tb_arp_direct_link;
    localparam [31:0] BOARD_IP=32'ha9fe2304, PC_IP=32'ha9fe9342;
    localparam [47:0] BOARD_MAC=48'h020000003504, PC_MAC=48'h102030405060;
    reg clk=0;always #10 clk=~clk;
    reg rst=1;
    reg s_eth_hdr_valid=0;wire s_eth_hdr_ready;
    reg [47:0] s_eth_dest_mac=BOARD_MAC,s_eth_src_mac=PC_MAC;
    reg [15:0] s_eth_type=16'h0806;
    reg [7:0] s_eth_payload_axis_tdata=0;
    wire s_eth_payload_axis_tkeep=1'b1;
    reg s_eth_payload_axis_tvalid=0;wire s_eth_payload_axis_tready;
    reg s_eth_payload_axis_tlast=0,s_eth_payload_axis_tuser=0;
    wire m_eth_hdr_valid;reg m_eth_hdr_ready=0;
    wire [47:0] m_eth_dest_mac,m_eth_src_mac;
    wire [15:0] m_eth_type;
    wire [7:0] m_eth_payload_axis_tdata;
    wire m_eth_payload_axis_tkeep,m_eth_payload_axis_tvalid;
    reg m_eth_payload_axis_tready=0;
    wire m_eth_payload_axis_tlast,m_eth_payload_axis_tuser;
    reg arp_request_valid=0;wire arp_request_ready;reg [31:0] arp_request_ip=0;
    wire arp_response_valid,arp_response_error;wire [47:0] arp_response_mac;
    wire arp_response_ready=1'b1;
    wire [47:0] local_mac=BOARD_MAC;
    wire [31:0] local_ip=BOARD_IP,subnet_mask=32'hffff0000;
    reg [31:0] gateway_ip=0;
    wire clear_cache=1'b0;
    arp #(.DATA_WIDTH(8),.KEEP_ENABLE(0),.KEEP_WIDTH(1),.CACHE_ADDR_WIDTH(2),
        .REQUEST_RETRY_COUNT(2),.REQUEST_RETRY_INTERVAL(220),.REQUEST_TIMEOUT(220)) dut(.*);
    reg [7:0] rx_packet[0:27],tx_packet[0:27];
    reg [31:0] frame_target[0:63],frame_source[0:63];
    reg [15:0] frame_op[0:63];
    reg [47:0] frame_dest_mac[0:63],current_dest_mac;
    reg result_error[0:63];reg [47:0] result_mac[0:63];
    integer tx_index=0,frames=0,results=0,failures=0,cycle=0,checks=0,base_frames,base_results;
    reg stalled=0,hdr_stalled=0;reg [7:0] stalled_data;reg stalled_last;
    reg [111:0] stalled_header;
    always @(negedge clk)begin
        cycle=cycle+1;m_eth_hdr_ready=(cycle%5!=0 && cycle%5!=1);
        m_eth_payload_axis_tready=(cycle%7!=0 && cycle%7!=1 && cycle%13!=5);
    end
    always @(posedge clk)begin
        if(rst)begin frames=0;results=0;failures=0;tx_index=0;stalled=0;hdr_stalled=0;end
        else begin
            if(stalled && (!m_eth_payload_axis_tvalid || m_eth_payload_axis_tdata!==stalled_data ||
                m_eth_payload_axis_tlast!==stalled_last))$fatal(1,"ARP TX payload changed under backpressure");
            if(hdr_stalled && (!m_eth_hdr_valid || {m_eth_dest_mac,m_eth_src_mac,m_eth_type}!==stalled_header))
                $fatal(1,"ARP TX header changed under backpressure");
            stalled=m_eth_payload_axis_tvalid&&!m_eth_payload_axis_tready;
            stalled_data=m_eth_payload_axis_tdata;stalled_last=m_eth_payload_axis_tlast;
            hdr_stalled=m_eth_hdr_valid&&!m_eth_hdr_ready;stalled_header={m_eth_dest_mac,m_eth_src_mac,m_eth_type};
            if(m_eth_hdr_valid&&m_eth_hdr_ready)begin
                if(m_eth_src_mac!==BOARD_MAC || m_eth_type!==16'h0806)$fatal(1,"ARP Ethernet header");
                current_dest_mac=m_eth_dest_mac;
            end
            if(m_eth_payload_axis_tvalid&&m_eth_payload_axis_tready)begin
                if(tx_index>=28 || m_eth_payload_axis_tuser)$fatal(1,"ARP TX framing");
                tx_packet[tx_index]=m_eth_payload_axis_tdata;tx_index=tx_index+1;
                if(m_eth_payload_axis_tlast)begin
                    if(tx_index!=28)$fatal(1,"ARP TX payload length");
                    if({tx_packet[0],tx_packet[1],tx_packet[2],tx_packet[3],tx_packet[4],tx_packet[5]}!==48'h000108000604)
                        $fatal(1,"ARP payload type/address widths");
                    if({tx_packet[8],tx_packet[9],tx_packet[10],tx_packet[11],tx_packet[12],tx_packet[13]}!==BOARD_MAC)
                        $fatal(1,"ARP sender MAC");
                    frame_target[frames]={tx_packet[24],tx_packet[25],tx_packet[26],tx_packet[27]};
                    frame_source[frames]={tx_packet[14],tx_packet[15],tx_packet[16],tx_packet[17]};
                    frame_op[frames]={tx_packet[6],tx_packet[7]};frame_dest_mac[frames]=current_dest_mac;
                    if(frame_source[frames]!==BOARD_IP)$fatal(1,"ARP sender IP");
                    frames=frames+1;tx_index=0;
                end
            end
            if(arp_response_valid)begin
                result_error[results]=arp_response_error;result_mac[results]=arp_response_mac;
                if(arp_response_error)failures=failures+1;
                results=results+1;
            end
        end
    end
    task reset_with_gateway(input [31:0] gateway);
        begin
            @(negedge clk);rst=1;gateway_ip=gateway;arp_request_valid=0;
            s_eth_hdr_valid=0;s_eth_payload_axis_tvalid=0;s_eth_payload_axis_tlast=0;s_eth_payload_axis_tuser=0;
            repeat(5)@(negedge clk);rst=0;repeat(12)@(negedge clk);
        end
    endtask
    task query(input [31:0] ip);
        integer watchdog;
        begin
            @(negedge clk);arp_request_ip=ip;arp_request_valid=1;watchdog=0;
            @(posedge clk);while(!arp_request_ready)begin @(posedge clk);watchdog=watchdog+1;
                if(watchdog>2000)$fatal(1,"ARP query handshake timeout");end
            @(negedge clk);arp_request_valid=0;
        end
    endtask
    task wait_frames(input integer count);
        integer watchdog;
        begin watchdog=0;while(frames<count)begin @(negedge clk);watchdog=watchdog+1;
            if(watchdog>2000)$fatal(1,"ARP frame timeout");end end
    endtask
    task wait_result(input integer count,input error,input [47:0] mac);
        integer watchdog;
        begin watchdog=0;while(results<count)begin @(negedge clk);watchdog=watchdog+1;
            if(watchdog>2000)$fatal(1,"ARP result timeout");end
            if(result_error[count-1]!==error || (!error && result_mac[count-1]!==mac))
                $fatal(1,"ARP result got error=%0d mac=%012x expected=%0d/%012x",result_error[count-1],result_mac[count-1],error,mac);
        end
    endtask
    task send_pc_arp(input [15:0] operation,input [31:0] sender_ip,input [31:0] target_ip,input bad_frame);
        integer j;
        begin
            rx_packet[0]=0;rx_packet[1]=1;rx_packet[2]=8;rx_packet[3]=0;
            rx_packet[4]=6;rx_packet[5]=4;rx_packet[6]=operation[15:8];rx_packet[7]=operation[7:0];
            for(j=0;j<6;j=j+1)begin
                rx_packet[8+j]=PC_MAC>>(8*(5-j));
                rx_packet[18+j]=(operation==1?48'd0:BOARD_MAC)>>(8*(5-j));
            end
            for(j=0;j<4;j=j+1)begin rx_packet[14+j]=sender_ip>>(8*(3-j));rx_packet[24+j]=target_ip>>(8*(3-j));end
            @(negedge clk);s_eth_dest_mac=operation==1?48'hffffffffffff:BOARD_MAC;
            s_eth_hdr_valid=1;
            @(posedge clk);while(!s_eth_hdr_ready)@(posedge clk);
            @(negedge clk);s_eth_hdr_valid=0;
            for(j=0;j<28;j=j+1)begin
                s_eth_payload_axis_tdata=rx_packet[j];s_eth_payload_axis_tvalid=1;
                s_eth_payload_axis_tlast=(j==27);s_eth_payload_axis_tuser=bad_frame&&(j==27);
                @(posedge clk);while(!s_eth_payload_axis_tready)@(posedge clk);
                @(negedge clk);s_eth_payload_axis_tvalid=0;s_eth_payload_axis_tlast=0;s_eth_payload_axis_tuser=0;
                if(j%9==0)@(negedge clk);
            end
            repeat(12)@(negedge clk);
        end
    endtask
    task same_subnet_test(input [31:0] peer);
        begin
            reset_with_gateway(BOARD_IP);query(peer);wait_frames(1);
            if(frame_target[0]!==peer || frame_op[0]!==1 || frame_dest_mac[0]!==48'hffffffffffff)
                $fatal(1,"same-subnet ARP target wrong");
            send_pc_arp(2,peer,BOARD_IP,0);wait_result(1,0,PC_MAC);
            if(failures!=0)$fatal(1,"new configuration ARP failure");checks=checks+1;
        end
    endtask
    initial begin
        // Reproduce actual symptom: PC learns FPGA and FPGA learns PC, but the
        // zero gateway makes a later UDP-reply lookup seek 0.0.0.0 anyway.
        reset_with_gateway(0);send_pc_arp(1,PC_IP,BOARD_IP,0);wait_frames(1);
        if(frame_op[0]!==2 || frame_target[0]!==PC_IP || frame_dest_mac[0]!==PC_MAC)$fatal(1,"PC discovery reply");
        query(PC_IP);wait_frames(2);
        if(frame_target[1]!==0 || frame_op[1]!==1)$fatal(1,"old gateway defect not reproduced");
        send_pc_arp(2,PC_IP,BOARD_IP,0);wait_result(1,1,0);
        if(failures!=1 || frames!=3 || frame_target[2]!==0)$fatal(1,"old configuration did not fail bounded retries");
        checks=checks+1;$display("PASS old_gateway_zero reproduces ARP target=00000000 despite learned PC cache");
        same_subnet_test(PC_IP);
        $display("PASS new_gateway_local resolves PC a9fe9342 -> %012x without ARP failure",PC_MAC);
        // A repeated same-peer lookup must hit learned cache, with no new frame.
        base_frames=frames;query(PC_IP);wait_result(2,0,PC_MAC);repeat(30)@(negedge clk);
        if(frames!=base_frames || failures!=0)$fatal(1,"cache hit emitted request");checks=checks+1;
        same_subnet_test(32'ha9fe0001);same_subnet_test(32'ha9fefffe);
        // The vendor block treats a /16 network address as a unicast lookup.
        same_subnet_test(32'ha9fe0000);
        reset_with_gateway(BOARD_IP);query(32'ha9feffff);wait_result(1,0,48'hffffffffffff);
        repeat(30)@(negedge clk);if(frames!=0)$fatal(1,"subnet broadcast emitted ARP");checks=checks+1;
        query(32'hffffffff);wait_result(2,0,48'hffffffffffff);
        repeat(30)@(negedge clk);if(frames!=0)$fatal(1,"limited broadcast emitted ARP");checks=checks+1;
        // This is direct-link mode, not a router: off-subnet lookup seeks the
        // local anchor and times out if no gateway responds. No false success.
        reset_with_gateway(BOARD_IP);query(32'ha9ff9342);wait_frames(1);
        if(frame_target[0]!==BOARD_IP)$fatal(1,"off-subnet gateway target");
        wait_result(1,1,0);checks=checks+1;
        reset_with_gateway(BOARD_IP);query(32'ha9fd9342);wait_frames(1);
        if(frame_target[0]!==BOARD_IP)$fatal(1,"lower off-subnet gateway target");
        wait_result(1,1,0);checks=checks+1;
        // A MAC/FCS error annotation must not seed the ARP cache.
        reset_with_gateway(BOARD_IP);send_pc_arp(2,PC_IP,BOARD_IP,1);
        query(PC_IP);wait_frames(1);if(frame_target[0]!==PC_IP)$fatal(1,"bad frame polluted cache");
        send_pc_arp(2,PC_IP,BOARD_IP,0);wait_result(1,0,PC_MAC);checks=checks+1;
        $display("PASS tb_arp_direct_link checks=%0d actual_vendor_arp cache rx tx old_failure new_success subnet_edges broadcast backpressure",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"ARP direct-link global timeout");end
endmodule
