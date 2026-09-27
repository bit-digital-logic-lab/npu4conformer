`timescale 1ns/1ps
// Stop-and-wait byte framing. The only operand RAM is a bounded UART packet;
// there is no model memory, DDR dependency, or host-side arithmetic fallback.
module asr_command_engine #(
    parameter integer MAX_PAYLOAD = 1024,
    parameter integer RX_TIMEOUT_CYCLES = 50000000
)(input wire clk, input wire rst_n,
  input wire rx_valid, input wire [7:0] rx_data, input wire rx_error,
  output wire tx_valid, input wire tx_ready, output reg [7:0] tx_data,
  output wire busy);
    localparam [4:0] SYNC0=0,SYNC1=1,HEADER=2,PAYLOAD=3,CRC0=4,CRC1=5,
        VALIDATE=6,READ_ARGS=7,EXECUTE=8,MAC_CLEAR=9,MAC_SEND=10,MAC_WAIT=11,
        REQ_SEND=12,REQ_WAIT=13,FP_SEND=14,FP_WAIT=15,REPLY=16;
    reg [4:0] state;
    (* ram_style = "distributed" *) reg [7:0] request_mem [0:MAX_PAYLOAD-1];
    reg [15:0] seq, request_length, request_crc, reply_crc;
    reg [7:0] opcode, request_flags, received_crc_low, status;
    reg [2:0] header_index;
    reg [15:0] write_index, read_index;
    reg [4:0] arg_index, arg_count;
    reg [135:0] args;
    reg [31:0] timeout_count;
    reg [63:0] reply_value;
    reg [7:0] reply_aux;
    reg [3:0] reply_length;
    reg [4:0] reply_index;
    reg signed [47:0] last_sum;
    reg last_overflow;
    wire mac_clear_ready, mac_in_ready, mac_out_valid, mac_overflow;
    wire signed [47:0] mac_sum;
    wire req_in_ready, req_out_valid;
    wire signed [15:0] req_value;
    wire fp_in_ready, fp_out_valid;
    wire [31:0] fp_result;
    wire [7:0] fp_flags;
    wire receiving=(state>=HEADER && state<=CRC1);
    assign busy=(state!=SYNC0 && state!=SYNC1);
    assign tx_valid=(state==REPLY);

    function automatic [15:0] crc_byte(input [15:0] crc, input [7:0] value);
        reg [15:0] c; integer i;
        begin
            c=crc^{value,8'h00};
            for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction

    asr_i16_mac mac(.clk(clk),.rst_n(rst_n),
        .clear_valid(state==MAC_CLEAR),.clear_ready(mac_clear_ready),
        .clear_value(opcode==8'h05 ? 48'sd0 : $signed(args[47:0])),
        .in_valid(state==MAC_SEND),.in_ready(mac_in_ready),
        .in_a($signed(args[15:0])),.in_b($signed(args[31:16])),
        .out_valid(mac_out_valid),.out_ready(state==MAC_WAIT),
        .out_sum(mac_sum),.overflow(mac_overflow));
    asr_requant requant(.clk(clk),.rst_n(rst_n),
        .in_valid(state==REQ_SEND),.in_ready(req_in_ready),
        .in_acc($signed(args[47:0])),.in_multiplier($signed(args[79:48])),
        .in_shift(args[86:80]),.in_bias($signed(args[135:88])),
        .out_valid(req_out_valid),.out_ready(state==REQ_WAIT),.out_value(req_value));
    asr_fp32_alu scalar(.clk(clk),.rst_n(rst_n),
        .in_valid(state==FP_SEND),.in_ready(fp_in_ready),.op(opcode-8'h20),
        .a(args[31:0]),.b(args[63:32]),.out_valid(fp_out_valid),
        .out_ready(state==FP_WAIT),.result(fp_result),.flags(fp_flags));

    always @* begin
        tx_data=0;
        case(reply_index)
            0:tx_data=8'h5a;
            1:tx_data=8'ha5;
            2:tx_data=seq[7:0];
            3:tx_data=seq[15:8];
            4:tx_data=opcode;
            5:tx_data=status;
            6:tx_data={4'b0,reply_length};
            7:tx_data=0;
            default: begin
                if(reply_index<8+reply_length) begin
                    if(reply_index==12 && opcode>=8'h20) tx_data=reply_aux;
                    else tx_data=reply_value >> ((reply_index-8)*8);
                end else if(reply_index==8+reply_length) tx_data=reply_crc[7:0];
                else tx_data=reply_crc[15:8];
            end
        endcase
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=SYNC0; seq<=0; request_length<=0; request_crc<=16'hffff;
            reply_crc<=16'hffff; opcode<=0; request_flags<=0;
            received_crc_low<=0; status<=0; header_index<=0;
            write_index<=0; read_index<=0; arg_index<=0; arg_count<=0;
            args<=0; timeout_count<=0; reply_value<=0; reply_aux<=0;
            reply_length<=0; reply_index<=0; last_sum<=0; last_overflow<=0;
        end else begin
            if(receiving && !rx_valid) timeout_count<=timeout_count+1;
            else timeout_count<=0;
            if((receiving && timeout_count>=RX_TIMEOUT_CYCLES-1) ||
                (rx_error && (receiving || state==SYNC1))) begin
                // A truncated or framing-corrupt packet cannot execute.
                state<=SYNC0; timeout_count<=0;
            end else case(state)
                SYNC0: if(rx_valid && rx_data==8'ha5) state<=SYNC1;
                SYNC1: if(rx_valid) begin
                    if(rx_data==8'h5a) begin
                        state<=HEADER; header_index<=0; request_crc<=16'hffff;
                        status<=0; reply_length<=0; reply_value<=0; reply_aux<=0;
                        reply_index<=0; reply_crc<=16'hffff;
                    end else if(rx_data!=8'ha5) state<=SYNC0;
                end
                HEADER: if(rx_valid) begin
                    request_crc<=crc_byte(request_crc,rx_data);
                    case(header_index)
                        0:seq[7:0]<=rx_data;
                        1:seq[15:8]<=rx_data;
                        2:opcode<=rx_data;
                        3:request_flags<=rx_data;
                        4:request_length[7:0]<=rx_data;
                        5:begin
                            request_length[15:8]<=rx_data;
                            write_index<=0;
                            if({rx_data,request_length[7:0]}>MAX_PAYLOAD) begin
                                // Reject the header and resynchronize; no arithmetic changed.
                                status<=2; state<=REPLY;
                            end else if({rx_data,request_length[7:0]}==0) state<=CRC0;
                            else state<=PAYLOAD;
                        end
                    endcase
                    header_index<=header_index+1;
                end
                PAYLOAD: if(rx_valid) begin
                    request_mem[write_index]<=rx_data;
                    request_crc<=crc_byte(request_crc,rx_data);
                    write_index<=write_index+1;
                    if(write_index+1==request_length) state<=CRC0;
                end
                CRC0: if(rx_valid) begin received_crc_low<=rx_data; state<=CRC1; end
                CRC1: if(rx_valid) begin
                    if({rx_data,received_crc_low}!=request_crc) begin status<=1; state<=REPLY; end
                    else state<=VALIDATE;
                end
                VALIDATE: begin
                    args<=0; arg_index<=0; read_index<=0;
                    if((opcode!=5 && request_flags!=0) ||
                       (opcode==5 && request_flags[7:1]!=0)) begin status<=3; state<=REPLY; end
                    else case(opcode)
                        0:if(request_length!=0) begin status<=2; state<=REPLY; end
                          else begin reply_value<=64'h0000000131525341; reply_length<=8; state<=REPLY; end
                        1:if(request_length!=6) begin status<=2; state<=REPLY; end
                          else begin arg_count<=6; state<=READ_ARGS; end
                        2:if(request_length!=4) begin status<=2; state<=REPLY; end
                          else begin arg_count<=4; state<=READ_ARGS; end
                        3:if(request_length!=0) begin status<=2; state<=REPLY; end
                          else begin reply_value<={16'd0,last_sum}; reply_length<=6;
                              status<=last_overflow?4:0; state<=REPLY; end
                        4:if(request_length!=17) begin status<=2; state<=REPLY; end
                          else begin arg_count<=17; state<=READ_ARGS; end
                        5:if(request_length==0 || request_length[1:0]!=0) begin status<=2; state<=REPLY; end
                          else begin arg_count<=4; state<=request_flags[0]?MAC_CLEAR:READ_ARGS; end
                        default:if(opcode>=8'h20 && opcode<=8'h2f) begin
                            if(request_length!=8) begin status<=2; state<=REPLY; end
                            else begin arg_count<=8; state<=READ_ARGS; end
                        end else begin status<=3; state<=REPLY; end
                    endcase
                end
                READ_ARGS: begin
                    args[arg_index*8 +: 8]<=request_mem[read_index];
                    read_index<=read_index+1;
                    if(arg_index+1==arg_count) state<=EXECUTE;
                    else arg_index<=arg_index+1;
                end
                EXECUTE: begin
                    if(opcode==1) state<=MAC_CLEAR;
                    else if(opcode==2 || opcode==5) state<=MAC_SEND;
                    else if(opcode==4) begin
                        if(args[87]) begin status<=3; state<=REPLY; end
                        else state<=REQ_SEND;
                    end else state<=FP_SEND;
                end
                MAC_CLEAR: if(mac_clear_ready) begin
                    last_sum<=opcode==5?48'd0:args[47:0]; last_overflow<=0;
                    if(opcode==5) state<=READ_ARGS;
                    else begin reply_value<={16'd0,args[47:0]}; reply_length<=6; state<=REPLY; end
                end
                MAC_SEND: if(mac_in_ready) state<=MAC_WAIT;
                MAC_WAIT: if(mac_out_valid) begin
                    last_sum<=mac_sum; last_overflow<=mac_overflow;
                    if(opcode==5 && read_index<request_length && !mac_overflow) begin
                        args<=0; arg_index<=0; state<=READ_ARGS;
                    end else begin
                        reply_value<={16'd0,mac_sum}; reply_length<=6;
                        status<=mac_overflow?4:0; state<=REPLY;
                    end
                end
                REQ_SEND: if(req_in_ready) state<=REQ_WAIT;
                REQ_WAIT: if(req_out_valid) begin
                    reply_value<={48'd0,req_value}; reply_length<=2; state<=REPLY;
                end
                FP_SEND: if(fp_in_ready) state<=FP_WAIT;
                FP_WAIT: if(fp_out_valid) begin
                    reply_value<={32'd0,fp_result}; reply_aux<=fp_flags;
                    reply_length<=5; status<=|fp_flags[2:0]?4:0; state<=REPLY;
                end
                REPLY: if(tx_ready) begin
                    if(reply_index>=2 && reply_index<8+reply_length)
                        reply_crc<=crc_byte(reply_crc,tx_data);
                    if(reply_index==9+reply_length) state<=SYNC0;
                    else reply_index<=reply_index+1;
                end
                default:state<=SYNC0;
            endcase
        end
    end
endmodule
