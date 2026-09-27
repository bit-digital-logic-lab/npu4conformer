`timescale 1ns/1ps
// V4.0 stop-and-wait UDP transport. Arithmetic and resident memory remain V2.
// No request byte reaches the engine until every inner frame has been checked.
// Three synchronous byte RAMs retain RX, the last request, and the last reply.
module asr_udp_command_bridge #(
    parameter integer UDP_PORT = 49152,
    parameter integer MAX_BODY = 1382,
    parameter integer RX_TIMEOUT_CYCLES = 50000000,
    parameter integer ENGINE_TIMEOUT_CYCLES = 500000000
)(
    input wire clk, input wire rst_n,
    input wire s_hdr_valid, output wire s_hdr_ready,
    input wire [31:0] s_src_ip,
    input wire [15:0] s_src_port, s_dst_port, s_udp_length,
    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid, output wire s_axis_tready,
    input wire s_axis_tlast, s_axis_tuser,
    output wire m_hdr_valid, input wire m_hdr_ready,
    output wire [31:0] m_dst_ip,
    output wire [15:0] m_dst_port, m_src_port, m_udp_length,
    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid, input wire m_axis_tready,
    output wire m_axis_tlast, m_axis_tuser,
    output wire engine_rx_valid, output wire [7:0] engine_rx_data,
    output wire engine_rx_error,
    input wire engine_tx_valid, input wire [7:0] engine_tx_data,
    output wire engine_tx_ready, input wire engine_busy
);
    localparam [4:0] IDLE=0, RX=1, PACKET=2, COMP_GET=3, COMP_USE=4,
        CHECK_GET=5, CHECK_USE=6, COPY_GET=7, COPY_USE=8,
        ENGINE_IDLE=9, SEND_GET=10, SEND_USE=11, RECEIVE=12,
        RESPONSE=13, TX_GET=14, TX_SEND=15;
    reg [4:0] state;
    (* ram_style="block" *) reg [7:0] request_mem [0:2047];
    (* ram_style="block" *) reg [7:0] previous_mem [0:2047];
    (* ram_style="block" *) reg [7:0] response_mem [0:2047];
    reg [10:0] read_address;
    reg [7:0] request_q, previous_q, response_q;
    reg [15:0] receive_index, received_length, udp_payload_length;
    reg [127:0] header;
    reg [15:0] receive_crc;
    reg [7:0] receive_crc_low;
    reg receive_bad;
    reg [31:0] request_ip;
    reg [15:0] request_port;
    wire [31:0] request_session=header[63:32];
    wire [31:0] request_sequence=header[95:64];
    wire [7:0] request_kind=header[103:96];
    wire [15:0] body_length=header[127:112];
    reg session_active, cache_valid, poisoned;
    reg [31:0] active_session, peer_ip, completed_sequence;
    reg [15:0] peer_port, previous_length, cached_length;
    reg [15:0] pointer, body_end, frame_index, frame_length;
    reg [15:0] frame_crc, read_count, worst_reply_length;
    reg [7:0] frame_crc_low, frame_opcode;
    reg [6:0] frame_count;
    reg [15:0] response_length, response_index;
    reg [15:0] reply_index, reply_length, reply_crc;
    reg [7:0] reply_crc_low;
    reg [15:0] inner_sequence;
    reg [7:0] response_status;
    reg response_hello, response_cached;
    reg [31:0] watchdog;
    reg [7:0] tx_data;
    reg [15:0] transmit_crc;
    wire rx_handshake=s_axis_tvalid && s_axis_tready;
    wire capture_reply=(state==RECEIVE && engine_tx_valid && engine_tx_ready);
    wire [15:0] response_address=response_index>=16 ? response_index-16 : 0;

    function automatic [15:0] crc_byte(input [15:0] crc,input [7:0] value);
        reg [15:0] c; integer i;
        begin
            c=crc^{value,8'h00};
            for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction
    function automatic [15:0] reply_bound(input [7:0] op,
                                         input [15:0] length,input [15:0] words);
        begin
            case(op)
                0:reply_bound=18;
                1,2,3,5:reply_bound=16;
                4:reply_bound=12;
                8'h40,8'h4f:reply_bound=22;
                8'h41:reply_bound=10;
                8'h42:reply_bound=(length==4 && words>0 && words<=256) ? 10+(words<<2) : 10;
                8'h43,8'h44,8'h45,8'h46,8'h47,8'h48:reply_bound=15;
                default:reply_bound=(op>=8'h20 && op<=8'h2f) ? 15 : 10;
            endcase
        end
    endfunction
    // Response selection does not modify the cached successful EXEC body.
    task automatic respond(input [7:0] status,input [15:0] length,
                           input hello,input cached);
        begin
            response_status<=status;response_length<=length;
            response_hello<=hello;response_cached<=cached;
            response_index<=0;transmit_crc<=16'hffff;state<=RESPONSE;
        end
    endtask

    assign s_hdr_ready=(state==IDLE);
    assign s_axis_tready=(state==RX);
    assign m_hdr_valid=(state==RESPONSE);
    assign m_dst_ip=request_ip;
    assign m_dst_port=request_port;
    assign m_src_port=UDP_PORT;
    assign m_udp_length=response_length+16'd26;
    assign m_axis_tdata=tx_data;
    assign m_axis_tvalid=(state==TX_SEND);
    assign m_axis_tlast=(response_index==response_length+17);
    assign m_axis_tuser=1'b0;
    assign engine_rx_valid=(state==SEND_USE);
    assign engine_rx_data=request_q;
    assign engine_rx_error=1'b0;
    assign engine_tx_ready=(state==RECEIVE);

    always @* begin
        read_address=pointer[10:0];
        tx_data=0;
        case(response_index)
            0:tx_data="A";1:tx_data="S";2:tx_data="R";3:tx_data="4";
            4:tx_data=request_session[7:0];5:tx_data=request_session[15:8];
            6:tx_data=request_session[23:16];7:tx_data=request_session[31:24];
            8:tx_data=request_sequence[7:0];9:tx_data=request_sequence[15:8];
            10:tx_data=request_sequence[23:16];11:tx_data=request_sequence[31:24];
            12:tx_data=request_kind|8'h80;13:tx_data=response_status;
            14:tx_data=response_length[7:0];15:tx_data=response_length[15:8];
            default:begin
                if(response_index<16+response_length) begin
                    if(response_hello) begin
                        case(response_index-16)
                            0:tx_data="A";1:tx_data="S";2:tx_data="R";3:tx_data="4";
                            4:tx_data=4;9:tx_data=8'h80;
                            12:tx_data=MAX_BODY%256;13:tx_data=MAX_BODY/256;
                            default:tx_data=0;
                        endcase
                    end else if(response_cached) tx_data=response_q;
                end else if(response_index==16+response_length) tx_data=transmit_crc[7:0];
                else tx_data=transmit_crc[15:8];
            end
        endcase
    end
    // Synchronous RAM ports, no RAM resets. Low address widths avoid large muxes.
    always @(posedge clk) begin
        request_q<=request_mem[read_address];
        previous_q<=previous_mem[read_address];
        response_q<=response_mem[response_address[10:0]];
        if(rx_handshake && receive_index<2048) request_mem[receive_index[10:0]]<=s_axis_tdata;
        if(state==COPY_USE) previous_mem[pointer[10:0]]<=request_q;
        if(capture_reply && response_index<MAX_BODY) response_mem[response_index[10:0]]<=engine_tx_data;
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;receive_index<=0;received_length<=0;udp_payload_length<=0;
            header<=0;receive_crc<=16'hffff;receive_crc_low<=0;receive_bad<=0;
            request_ip<=0;request_port<=0;session_active<=0;cache_valid<=0;poisoned<=0;
            active_session<=0;peer_ip<=0;peer_port<=0;completed_sequence<=0;
            previous_length<=0;cached_length<=0;pointer<=0;body_end<=0;frame_index<=0;
            frame_length<=0;frame_crc<=16'hffff;read_count<=0;worst_reply_length<=0;
            frame_crc_low<=0;frame_opcode<=0;frame_count<=0;response_length<=0;
            response_index<=0;reply_index<=0;reply_length<=0;reply_crc<=16'hffff;
            reply_crc_low<=0;inner_sequence<=0;response_status<=0;
            response_hello<=0;response_cached<=0;watchdog<=0;transmit_crc<=16'hffff;
        end else begin
            if(state==RX && !rx_handshake) watchdog<=watchdog+1;
            else if(state==ENGINE_IDLE || state==RECEIVE) watchdog<=watchdog+1;
            else watchdog<=0;
            case(state)
                IDLE:if(s_hdr_valid) begin
                    request_ip<=s_src_ip;request_port<=s_src_port;
                    udp_payload_length<=s_udp_length-8;
                    receive_bad<=(s_dst_port!=UDP_PORT || s_udp_length<26 || s_udp_length>MAX_BODY+26);
                    receive_index<=0;header<=0;receive_crc<=16'hffff;
                    receive_crc_low<=0;state<=RX;
                end
                RX:begin
                    if(rx_handshake) begin
                        if(receive_index<16) header[receive_index*8 +: 8]<=s_axis_tdata;
                        if(receive_index<udp_payload_length-2) receive_crc<=crc_byte(receive_crc,s_axis_tdata);
                        if(receive_index==udp_payload_length-2) receive_crc_low<=s_axis_tdata;
                        receive_bad<=receive_bad|s_axis_tuser;
                        receive_index<=receive_index+1;
                        if(s_axis_tlast) begin
                            received_length<=receive_index+1;
                            receive_bad<=receive_bad|s_axis_tuser|
                                (receive_index+1!=udp_payload_length)|
                                ({s_axis_tdata,receive_crc_low}!=receive_crc);
                            state<=PACKET;
                        end
                    end else if(watchdog>=RX_TIMEOUT_CYCLES-1) state<=IDLE;
                end
                PACKET:begin
                    if(receive_bad || header[31:0]!=32'h34525341) state<=IDLE;
                    else if(header[111:104]!=0 || received_length!=body_length+18 || body_length>MAX_BODY || request_kind>2)
                        respond(1,0,0,0);
                    else if(request_kind==0) begin
                        if(request_session==0 || request_sequence!=0 || body_length!=0) respond(1,0,0,0);
                        else if(session_active && (active_session!=request_session || peer_ip!=request_ip || peer_port!=request_port))
                            respond(2,0,0,0);
                        else if(poisoned) respond(6,0,0,0);
                        else begin
                            if(!session_active) begin
                                session_active<=1;active_session<=request_session;peer_ip<=request_ip;peer_port<=request_port;
                                completed_sequence<=0;cache_valid<=0;
                            end
                            respond(0,16,1,0);
                        end
                    end else if(!session_active || active_session!=request_session || peer_ip!=request_ip || peer_port!=request_port)
                        respond(2,0,0,0);
                    else if(poisoned) respond(6,0,0,0);
                    else if(request_kind==2) begin
                        if(body_length!=0) respond(1,0,0,0);
                        else if(completed_sequence==32'hffffffff || request_sequence!=completed_sequence+1) respond(3,0,0,0);
                        else begin session_active<=0;cache_valid<=0;respond(0,0,0,0);end
                    end else if(cache_valid && request_sequence==completed_sequence) begin
                        if(received_length!=previous_length) respond(5,0,0,0);
                        else begin pointer<=0;state<=COMP_GET;end
                    end else if(completed_sequence==32'hffffffff || request_sequence!=completed_sequence+1) respond(3,0,0,0);
                    else if(body_length<10) respond(4,0,0,0);
                    else begin
                        pointer<=16;body_end<=body_length+16;frame_index<=0;frame_length<=0;
                        frame_crc<=16'hffff;frame_count<=0;worst_reply_length<=0;read_count<=0;
                        state<=CHECK_GET;
                    end
                end
                COMP_GET:state<=COMP_USE;
                COMP_USE:begin
                    if(request_q!=previous_q) respond(5,0,0,0);
                    else if(pointer+1==received_length) respond(0,cached_length,0,1);
                    else begin pointer<=pointer+1;state<=COMP_GET;end
                end
                CHECK_GET:state<=CHECK_USE;
                CHECK_USE:begin
                    if((frame_index==0 && request_q!=8'ha5) || (frame_index==1 && request_q!=8'h5a))
                        respond(4,0,0,0);
                    else if(frame_index==7 && ({request_q,frame_length[7:0]}>1024 ||
                        pointer+3+{request_q,frame_length[7:0]}>body_end)) respond(4,0,0,0);
                    else if(frame_index==frame_length+9 && frame_index>=9) begin
                        if({request_q,frame_crc_low}!=frame_crc || frame_count>=64 ||
                            worst_reply_length+reply_bound(frame_opcode,frame_length,read_count)>MAX_BODY)
                            respond(4,0,0,0);
                        else begin
                            worst_reply_length<=worst_reply_length+reply_bound(frame_opcode,frame_length,read_count);
                            frame_count<=frame_count+1;
                            if(pointer+1==body_end) begin pointer<=0;state<=COPY_GET;end
                            else if(pointer+11>body_end) respond(4,0,0,0);
                            else begin pointer<=pointer+1;frame_index<=0;frame_length<=0;
                                frame_crc<=16'hffff;read_count<=0;state<=CHECK_GET;end
                        end
                    end else begin
                        if(frame_index>=2 && frame_index<frame_length+8) frame_crc<=crc_byte(frame_crc,request_q);
                        if(frame_index==4) frame_opcode<=request_q;
                        if(frame_index==6) frame_length[7:0]<=request_q;
                        if(frame_index==7) frame_length[15:8]<=request_q;
                        if(frame_index==10) read_count[7:0]<=request_q;
                        if(frame_index==11) read_count[15:8]<=request_q;
                        if(frame_index==frame_length+8 && frame_index>=8) frame_crc_low<=request_q;
                        pointer<=pointer+1;frame_index<=frame_index+1;state<=CHECK_GET;
                    end
                end
                COPY_GET:state<=COPY_USE;
                COPY_USE:begin
                    if(pointer+1==received_length) begin
                        previous_length<=received_length;cache_valid<=0;
                        pointer<=16;frame_index<=0;frame_length<=0;response_index<=0;state<=ENGINE_IDLE;
                    end else begin pointer<=pointer+1;state<=COPY_GET;end
                end
                ENGINE_IDLE:begin
                    if(!engine_busy && !engine_tx_valid) state<=SEND_GET;
                    else if(watchdog>=ENGINE_TIMEOUT_CYCLES-1) begin poisoned<=1;respond(6,0,0,0);end
                end
                SEND_GET:state<=SEND_USE;
                SEND_USE:begin
                    if(frame_index==2) inner_sequence[7:0]<=request_q;
                    if(frame_index==3) inner_sequence[15:8]<=request_q;
                    if(frame_index==4) frame_opcode<=request_q;
                    if(frame_index==6) frame_length[7:0]<=request_q;
                    if(frame_index==7) frame_length[15:8]<=request_q;
                    pointer<=pointer+1;frame_index<=frame_index+1;
                    if(frame_index==frame_length+9 && frame_index>=9) begin
                        reply_index<=0;reply_length<=0;reply_crc<=16'hffff;state<=RECEIVE;
                    end else state<=SEND_GET;
                end
                RECEIVE:begin
                    if(capture_reply) begin
                        if(response_index>=MAX_BODY ||
                            (reply_index==0 && engine_tx_data!=8'h5a) ||
                            (reply_index==1 && engine_tx_data!=8'ha5) ||
                            (reply_index==2 && engine_tx_data!=inner_sequence[7:0]) ||
                            (reply_index==3 && engine_tx_data!=inner_sequence[15:8]) ||
                            (reply_index==4 && engine_tx_data!=frame_opcode) ||
                            (reply_index==5 && engine_tx_data!=0) ||
                            (reply_index==7 && ({engine_tx_data,reply_length[7:0]}>1024 ||
                                response_index+3+{engine_tx_data,reply_length[7:0]}>MAX_BODY))) begin
                            poisoned<=1;respond(6,0,0,0);
                        end else begin
                            response_index<=response_index+1;reply_index<=reply_index+1;
                            if(reply_index>=2 && reply_index<reply_length+8) reply_crc<=crc_byte(reply_crc,engine_tx_data);
                            if(reply_index==6) reply_length[7:0]<=engine_tx_data;
                            if(reply_index==7) reply_length[15:8]<=engine_tx_data;
                            if(reply_index==reply_length+8 && reply_index>=8) reply_crc_low<=engine_tx_data;
                            if(reply_index==reply_length+9 && reply_index>=9) begin
                                if({engine_tx_data,reply_crc_low}!=reply_crc) begin poisoned<=1;respond(6,0,0,0);end
                                else if(pointer==body_end) begin
                                    completed_sequence<=request_sequence;cache_valid<=1;cached_length<=response_index+1;
                                    respond(0,response_index+1,0,1);
                                end else begin frame_index<=0;frame_length<=0;state<=ENGINE_IDLE;end
                            end
                        end
                    end else if(watchdog>=ENGINE_TIMEOUT_CYCLES-1) begin poisoned<=1;respond(6,0,0,0);end
                end
                RESPONSE:if(m_hdr_ready) begin response_index<=0;state<=TX_GET;end
                TX_GET:state<=TX_SEND;
                TX_SEND:if(m_axis_tready) begin
                    if(response_index<response_length+16) transmit_crc<=crc_byte(transmit_crc,tx_data);
                    if(response_index==response_length+17) state<=IDLE;
                    else begin response_index<=response_index+1;state<=TX_GET;end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
