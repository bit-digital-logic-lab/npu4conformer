`timescale 1ns/1ps
// V1 framing plus BRAM-resident commands. RAM is deliberately uninitialized.
// All arithmetic instances use the immutable, board-verified V1 modules.
module asr_command_engine_v2 #(
    parameter integer MAX_PAYLOAD=1024,
    parameter integer RX_TIMEOUT_CYCLES=50000000
)(input wire clk, input wire rst_n,
  input wire rx_valid, input wire [7:0] rx_data, input wire rx_error,
  output wire tx_valid, input wire tx_ready, output reg [7:0] tx_data,
  output wire busy);
    localparam [5:0] SYNC0=0,SYNC1=1,HEADER=2,PAYLOAD=3,CRC0=4,CRC1=5,
        VALIDATE=6,READ_ARGS=7,EXECUTE=8,MAC_CLEAR=9,MAC_SEND=10,MAC_WAIT=11,
        REQ_SEND=12,REQ_WAIT=13,FP_SEND=14,FP_WAIT=15,REPLY=16,
        RES_SETUP=17,RES_CHECK=18,WR_LOAD=19,WR_COMMIT=20,
        RD_FETCH=21,RD_CAPTURE=22,RD_BYTES=23,
        V_READ_A=24,V_READ_B=25,V_CAPTURE_B=26,V_STORE=27,
        R_FIRST_READ=28,R_FIRST_CAPTURE=29,R_READ=30,R_CAPTURE=31,R_STORE=32,
        M_BEGIN=33,M_READ_C0=34,M_READ_C1=35,M_CAPTURE_C1=36,
        M_READ_A=37,M_READ_B=38,M_CAPTURE_B=39,M_STORE_LO=40,M_STORE_HI=41,
        RES_FINISH=42;
    reg [5:0] state;
    (* ram_style="distributed" *) reg [7:0] request_mem[0:MAX_PAYLOAD-1];
    (* ram_style="block" *) reg [31:0] resident_memory[0:32767];
    reg [14:0] memory_address;
    reg memory_enable,memory_write;
    reg [31:0] memory_write_data,memory_read_data;
    // No reset on RAM or read register: this is a native synchronous BRAM port.
    always @(posedge clk) begin
        if(memory_enable) begin
            if(memory_write) resident_memory[memory_address]<=memory_write_data;
            memory_read_data<=resident_memory[memory_address];
        end
    end
    reg [15:0] seq,request_length,request_crc,reply_crc;
    reg [7:0] opcode,request_flags,received_crc_low,status;
    reg [2:0] header_index;
    reg [15:0] write_index,read_index;
    reg [4:0] arg_index,arg_count;
    reg [135:0] args;
    reg [31:0] timeout_count;
    reg [95:0] reply_value;
    reg [7:0] reply_aux;
    reg [15:0] reply_length,reply_index;
    reg reply_buffer;
    reg signed [47:0] last_sum;
    reg last_overflow;
    reg [15:0] base_a,base_b,base_d,element_count,element_index;
    reg [15:0] dimension_m,dimension_n,dimension_k,mm_accumulate;
    reg [15:0] row_index,column_index,k_index,row_a,row_b,c_address;
    reg [32:0] length_a,length_b,length_d;
    reg [7:0] resident_op,resident_mode,resident_flags;
    reg [31:0] resident_result,word_buffer,execution_cycles;
    reg execution_active;
    reg [1:0] byte_index;
    reg signed [47:0] mm_initial;
    wire mac_clear_ready,mac_in_ready,mac_out_valid,mac_overflow;
    wire signed [47:0] mac_sum;
    wire req_in_ready,req_out_valid;
    wire signed [15:0] req_value;
    wire fp_in_ready,fp_out_valid;
    wire [31:0] fp_result;
    wire [7:0] fp_flags;
    wire receiving=(state>=HEADER && state<=CRC1);
    wire [31:0] product_mk=args[63:48]*args[95:80];
    wire [31:0] product_nk=args[79:64]*args[95:80];
    wire [31:0] product_mn=args[63:48]*args[79:64];
    assign busy=(state!=SYNC0 && state!=SYNC1);
    assign tx_valid=(state==REPLY);
    function automatic [15:0] crc_byte(input [15:0] crc,input [7:0] value);
        reg [15:0] c; integer i;
        begin
            c=crc^{value,8'h00};
            for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction
    function automatic valid_range(input [15:0] base,input [32:0] size);
        begin valid_range=(size!=0 && ({18'd0,base}+{1'b0,size})<=34'd32768); end
    endfunction
    function automatic overlaps(input [15:0] a,input [32:0] na,
                                 input [15:0] b,input [32:0] nb);
        begin overlaps=({18'd0,a}<({18'd0,b}+{1'b0,nb})) &&
                       ({18'd0,b}<({18'd0,a}+{1'b0,na})); end
    endfunction
    asr_i16_mac mac(.clk(clk),.rst_n(rst_n),
        .clear_valid(state==MAC_CLEAR),.clear_ready(mac_clear_ready),
        .clear_value(opcode==8'h45 ? mm_initial : opcode==8'h05 ? 48'sd0 : $signed(args[47:0])),
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
        .in_valid(state==FP_SEND),.in_ready(fp_in_ready),
        .op((opcode==8'h43 || opcode==8'h44)?resident_op:opcode-8'h20),
        .a(args[31:0]),.b(args[63:32]),.out_valid(fp_out_valid),
        .out_ready(state==FP_WAIT),.result(fp_result),.flags(fp_flags));
    always @* begin
        memory_enable=0;memory_write=0;memory_address=0;memory_write_data=0;
        case(state)
            WR_COMMIT:begin memory_enable=1;memory_write=1;
                memory_address=base_a+element_index;memory_write_data=word_buffer;end
            RD_FETCH:begin memory_enable=1;memory_address=base_a+element_index;end
            V_READ_A:begin memory_enable=1;
                memory_address=base_a+(resident_mode[0]?16'd0:element_index);end
            V_READ_B:begin memory_enable=1;
                memory_address=base_b+(resident_mode[1]?16'd0:element_index);end
            V_STORE:begin memory_enable=1;memory_write=1;
                memory_address=base_d+element_index;memory_write_data=resident_result;end
            R_FIRST_READ:begin memory_enable=1;memory_address=base_a;end
            R_READ:begin memory_enable=1;memory_address=base_a+element_index;end
            R_STORE:begin memory_enable=1;memory_write=1;
                memory_address=base_d;memory_write_data=resident_result;end
            M_READ_C0:begin memory_enable=1;memory_address=c_address;end
            M_READ_C1:begin memory_enable=1;memory_address=c_address+16'd1;end
            M_READ_A:begin memory_enable=1;memory_address=row_a+k_index;end
            M_READ_B:begin memory_enable=1;memory_address=row_b+k_index;end
            M_STORE_LO:begin memory_enable=1;memory_write=1;
                memory_address=c_address;memory_write_data=last_sum[31:0];end
            M_STORE_HI:begin memory_enable=1;memory_write=1;
                memory_address=c_address+16'd1;memory_write_data={{16{last_sum[47]}},last_sum[47:32]};end
        endcase
    end
    always @* begin
        tx_data=0;
        case(reply_index)
            0:tx_data=8'h5a;
            1:tx_data=8'ha5;
            2:tx_data=seq[7:0];
            3:tx_data=seq[15:8];
            4:tx_data=opcode;
            5:tx_data=status;
            6:tx_data=reply_length[7:0];
            7:tx_data=reply_length[15:8];
            default:begin
                if(reply_index<8+reply_length) begin
                    if(reply_buffer) tx_data=request_mem[reply_index-8];
                    else if(reply_index==12 && opcode>=8'h20 && opcode<=8'h2f) tx_data=reply_aux;
                    else tx_data=reply_value >> ((reply_index-8)*8);
                end else if(reply_index==8+reply_length) tx_data=reply_crc[7:0];
                else tx_data=reply_crc[15:8];
            end
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=SYNC0;seq<=0;request_length<=0;request_crc<=16'hffff;
            reply_crc<=16'hffff;opcode<=0;request_flags<=0;received_crc_low<=0;
            status<=0;header_index<=0;write_index<=0;read_index<=0;
            arg_index<=0;arg_count<=0;args<=0;timeout_count<=0;
            reply_value<=0;reply_aux<=0;reply_length<=0;reply_index<=0;reply_buffer<=0;
            last_sum<=0;last_overflow<=0;base_a<=0;base_b<=0;base_d<=0;
            element_count<=0;element_index<=0;dimension_m<=0;dimension_n<=0;
            dimension_k<=0;mm_accumulate<=0;row_index<=0;column_index<=0;
            k_index<=0;row_a<=0;row_b<=0;c_address<=0;
            length_a<=0;length_b<=0;length_d<=0;resident_op<=0;resident_mode<=0;
            resident_flags<=0;resident_result<=0;word_buffer<=0;
            execution_cycles<=0;execution_active<=0;byte_index<=0;mm_initial<=0;
        end else begin
            if(execution_active) execution_cycles<=execution_cycles+1;
            if(receiving && !rx_valid) timeout_count<=timeout_count+1;
            else timeout_count<=0;
            if((receiving && timeout_count>=RX_TIMEOUT_CYCLES-1) ||
               (rx_error && (receiving || state==SYNC1))) begin
                state<=SYNC0;timeout_count<=0;
            end else case(state)
                SYNC0:if(rx_valid && rx_data==8'ha5) state<=SYNC1;
                SYNC1:if(rx_valid) begin
                    if(rx_data==8'h5a) begin
                        state<=HEADER;header_index<=0;request_crc<=16'hffff;
                        status<=0;reply_length<=0;reply_value<=0;reply_aux<=0;
                        reply_index<=0;reply_crc<=16'hffff;reply_buffer<=0;
                    end else if(rx_data!=8'ha5) state<=SYNC0;
                end
                HEADER:if(rx_valid) begin
                    request_crc<=crc_byte(request_crc,rx_data);
                    case(header_index)
                        0:seq[7:0]<=rx_data;
                        1:seq[15:8]<=rx_data;
                        2:opcode<=rx_data;
                        3:request_flags<=rx_data;
                        4:request_length[7:0]<=rx_data;
                        5:begin
                            request_length[15:8]<=rx_data;write_index<=0;
                            if({rx_data,request_length[7:0]}>MAX_PAYLOAD) begin status<=2;state<=REPLY;end
                            else if({rx_data,request_length[7:0]}==0) state<=CRC0;
                            else state<=PAYLOAD;
                        end
                    endcase
                    header_index<=header_index+1;
                end
                PAYLOAD:if(rx_valid) begin
                    request_mem[write_index]<=rx_data;
                    request_crc<=crc_byte(request_crc,rx_data);write_index<=write_index+1;
                    if(write_index+1==request_length) state<=CRC0;
                end
                CRC0:if(rx_valid) begin received_crc_low<=rx_data;state<=CRC1;end
                CRC1:if(rx_valid) begin
                    if({rx_data,received_crc_low}!=request_crc) begin status<=1;state<=REPLY;end
                    else state<=VALIDATE;
                end
                VALIDATE:begin
                    args<=0;arg_index<=0;read_index<=0;
                    if((opcode!=5 && request_flags!=0)||(opcode==5 && request_flags[7:1]!=0)) begin status<=3;state<=REPLY;end
                    else case(opcode)
                        0:if(request_length!=0) begin status<=2;state<=REPLY;end
                          else begin reply_value<=96'h000000000000000131525341;reply_length<=8;state<=REPLY;end
                        1:if(request_length!=6) begin status<=2;state<=REPLY;end
                          else begin arg_count<=6;state<=READ_ARGS;end
                        2:if(request_length!=4) begin status<=2;state<=REPLY;end
                          else begin arg_count<=4;state<=READ_ARGS;end
                        3:if(request_length!=0) begin status<=2;state<=REPLY;end
                          else begin reply_value<={48'd0,last_sum};reply_length<=6;status<=last_overflow?4:0;state<=REPLY;end
                        4:if(request_length!=17) begin status<=2;state<=REPLY;end
                          else begin arg_count<=17;state<=READ_ARGS;end
                        5:if(request_length==0 || request_length[1:0]!=0) begin status<=2;state<=REPLY;end
                          else begin arg_count<=4;state<=request_flags[0]?MAC_CLEAR:READ_ARGS;end
                        8'h40:if(request_length!=0) begin status<=2;state<=REPLY;end
                          else begin reply_value<=96'h000080000000000232525341;reply_length<=12;state<=REPLY;end
                        8'h41:if(request_length<8 || request_length[1:0]!=0) begin status<=2;state<=REPLY;end
                          else begin arg_count<=4;state<=READ_ARGS;end
                        8'h42:if(request_length!=4) begin status<=2;state<=REPLY;end
                          else begin arg_count<=4;state<=READ_ARGS;end
                        8'h43:if(request_length!=10) begin status<=2;state<=REPLY;end
                          else begin arg_count<=10;state<=READ_ARGS;end
                        8'h44:if(request_length!=8) begin status<=2;state<=REPLY;end
                          else begin arg_count<=8;state<=READ_ARGS;end
                        8'h45:if(request_length!=14) begin status<=2;state<=REPLY;end
                          else begin arg_count<=14;state<=READ_ARGS;end
                        default:if(opcode>=8'h20 && opcode<=8'h2f) begin
                            if(request_length!=8) begin status<=2;state<=REPLY;end
                            else begin arg_count<=8;state<=READ_ARGS;end
                        end else begin status<=3;state<=REPLY;end
                    endcase
                end
                READ_ARGS:begin
                    args[arg_index*8 +: 8]<=request_mem[read_index];read_index<=read_index+1;
                    if(arg_index+1==arg_count) state<=EXECUTE;
                    else arg_index<=arg_index+1;
                end
                EXECUTE:begin
                    if(opcode>=8'h41 && opcode<=8'h45) state<=RES_SETUP;
                    else if(opcode==1) state<=MAC_CLEAR;
                    else if(opcode==2 || opcode==5) state<=MAC_SEND;
                    else if(opcode==4) begin
                        if(args[87]) begin status<=3;state<=REPLY;end
                        else state<=REQ_SEND;
                    end else state<=FP_SEND;
                end
                MAC_CLEAR:if(mac_clear_ready) begin
                    last_sum<=opcode==8'h45 ? mm_initial : opcode==5 ? 48'd0 : args[47:0];last_overflow<=0;
                    if(opcode==8'h45) state<=M_READ_A;
                    else if(opcode==5) state<=READ_ARGS;
                    else begin reply_value<={48'd0,args[47:0]};reply_length<=6;state<=REPLY;end
                end
                MAC_SEND:if(mac_in_ready) state<=MAC_WAIT;
                MAC_WAIT:if(mac_out_valid) begin
                    last_sum<=mac_sum;last_overflow<=mac_overflow;
                    if(opcode==8'h45) begin
                        if(mac_overflow) begin resident_flags<=resident_flags|8'h04;status<=4;state<=RES_FINISH;end
                        else if(k_index+1<dimension_k) begin k_index<=k_index+1;state<=M_READ_A;end
                        else state<=M_STORE_LO;
                    end else if(opcode==5 && read_index<request_length && !mac_overflow) begin
                        args<=0;arg_index<=0;state<=READ_ARGS;
                    end else begin
                        reply_value<={48'd0,mac_sum};reply_length<=6;status<=mac_overflow?4:0;state<=REPLY;
                    end
                end
                REQ_SEND:if(req_in_ready) state<=REQ_WAIT;
                REQ_WAIT:if(req_out_valid) begin reply_value<={80'd0,req_value};reply_length<=2;state<=REPLY;end
                FP_SEND:if(fp_in_ready) state<=FP_WAIT;
                FP_WAIT:if(fp_out_valid) begin
                    if(opcode==8'h43 || opcode==8'h44) begin
                        resident_result<=fp_result;resident_flags<=resident_flags|fp_flags;
                        if(|fp_flags[2:0]) begin status<=4;state<=RES_FINISH;end
                        else if(opcode==8'h43) state<=V_STORE;
                        else if(element_index+1<element_count) begin element_index<=element_index+1;state<=R_READ;end
                        else state<=R_STORE;
                    end else begin
                        reply_value<={64'd0,fp_result};reply_aux<=fp_flags;reply_length<=5;
                        status<=|fp_flags[2:0]?4:0;state<=REPLY;
                    end
                end
                RES_SETUP:begin
                    element_index<=0;resident_flags<=0;execution_cycles<=0;
                    if(opcode==8'h41 || opcode==8'h42) begin
                        base_a<=args[15:0];element_count<=args[31:16];length_a<={17'd0,args[31:16]};
                    end else if(opcode==8'h43) begin
                        resident_op<=args[7:0];resident_mode<=args[15:8];base_a<=args[31:16];
                        base_b<=args[47:32];base_d<=args[63:48];element_count<=args[79:64];
                        length_a<=args[8]?33'd1:{17'd0,args[79:64]};
                        length_b<=args[9]?33'd1:{17'd0,args[79:64]};length_d<={17'd0,args[79:64]};
                    end else if(opcode==8'h44) begin
                        resident_op<=args[7:0];resident_mode<=args[15:8];base_a<=args[31:16];
                        base_d<=args[47:32];element_count<=args[63:48];length_a<={17'd0,args[63:48]};length_d<=1;
                    end else begin
                        base_a<=args[15:0];base_b<=args[31:16];base_d<=args[47:32];
                        dimension_m<=args[63:48];dimension_n<=args[79:64];dimension_k<=args[95:80];
                        mm_accumulate<=args[111:96];length_a<={1'b0,product_mk};
                        length_b<={1'b0,product_nk};length_d<={product_mn,1'b0};
                        row_a<=args[15:0];row_b<=args[31:16];c_address<=args[47:32];
                        row_index<=0;column_index<=0;k_index<=0;
                    end
                    state<=RES_CHECK;
                end
                RES_CHECK:begin
                    if(opcode==8'h41 || opcode==8'h42) begin
                        if(!valid_range(base_a,length_a) || element_count>(opcode==8'h41 ? 16'd255 : 16'd256) ||
                           (opcode==8'h41 && ({16'd0,element_count}*32'd4+32'd4)!={16'd0,request_length})) begin status<=2;state<=REPLY;end
                        else if(opcode==8'h41) begin read_index<=4;byte_index<=0;word_buffer<=0;state<=WR_LOAD;end
                        else begin write_index<=0;state<=RD_FETCH;end
                    end else if(opcode==8'h43) begin
                        if(resident_op>15 || resident_mode[7:2]!=0) begin status<=3;state<=REPLY;end
                        else if(!valid_range(base_a,length_a)||!valid_range(base_b,length_b)||!valid_range(base_d,length_d)||
                            (overlaps(base_d,length_d,base_a,length_a) && !(base_d==base_a && !resident_mode[0])) ||
                            (overlaps(base_d,length_d,base_b,length_b) && !(base_d==base_b && !resident_mode[1]))) begin status<=2;state<=REPLY;end
                        else begin execution_active<=1;state<=V_READ_A;end
                    end else if(opcode==8'h44) begin
                        if((resident_op!=0 && resident_op!=9)||resident_mode!=0) begin status<=3;state<=REPLY;end
                        else if(!valid_range(base_a,length_a)||!valid_range(base_d,length_d)) begin status<=2;state<=REPLY;end
                        else begin execution_active<=1;state<=R_FIRST_READ;end
                    end else begin
                        if(mm_accumulate>1) begin status<=3;state<=REPLY;end
                        else if(dimension_m==0||dimension_n==0||dimension_k==0||
                            !valid_range(base_a,length_a)||!valid_range(base_b,length_b)||!valid_range(base_d,length_d)||
                            overlaps(base_d,length_d,base_a,length_a)||overlaps(base_d,length_d,base_b,length_b)) begin status<=2;state<=REPLY;end
                        else begin execution_active<=1;state<=M_BEGIN;end
                    end
                end
                WR_LOAD:begin
                    word_buffer[byte_index*8 +: 8]<=request_mem[read_index];read_index<=read_index+1;
                    if(byte_index==3) state<=WR_COMMIT;
                    else byte_index<=byte_index+1;
                end
                WR_COMMIT:begin
                    if(element_index+1==element_count) state<=REPLY;
                    else begin element_index<=element_index+1;byte_index<=0;state<=WR_LOAD;end
                end
                RD_FETCH:state<=RD_CAPTURE;
                RD_CAPTURE:begin word_buffer<=memory_read_data;byte_index<=0;state<=RD_BYTES;end
                RD_BYTES:begin
                    request_mem[write_index]<=word_buffer >> (byte_index*8);write_index<=write_index+1;
                    if(byte_index==3) begin
                        if(element_index+1==element_count) begin reply_length<=element_count<<2;reply_buffer<=1;state<=REPLY;end
                        else begin element_index<=element_index+1;state<=RD_FETCH;end
                    end else byte_index<=byte_index+1;
                end
                V_READ_A:state<=V_READ_B;
                V_READ_B:begin args[31:0]<=memory_read_data;state<=V_CAPTURE_B;end
                V_CAPTURE_B:begin args[63:32]<=memory_read_data;state<=FP_SEND;end
                V_STORE:begin
                    if(element_index+1==element_count) state<=RES_FINISH;
                    else begin element_index<=element_index+1;state<=V_READ_A;end
                end
                R_FIRST_READ:state<=R_FIRST_CAPTURE;
                R_FIRST_CAPTURE:begin
                    resident_result<=memory_read_data;
                    if(element_count==1) state<=R_STORE;
                    else begin element_index<=1;state<=R_READ;end
                end
                R_READ:state<=R_CAPTURE;
                R_CAPTURE:begin args[31:0]<=resident_result;args[63:32]<=memory_read_data;state<=FP_SEND;end
                R_STORE:state<=RES_FINISH;
                M_BEGIN:begin
                    k_index<=0;
                    if(mm_accumulate!=0) state<=M_READ_C0;
                    else begin mm_initial<=0;state<=MAC_CLEAR;end
                end
                M_READ_C0:state<=M_READ_C1;
                M_READ_C1:begin mm_initial[31:0]<=memory_read_data;state<=M_CAPTURE_C1;end
                M_CAPTURE_C1:begin mm_initial[47:32]<=memory_read_data[15:0];state<=MAC_CLEAR;end
                M_READ_A:state<=M_READ_B;
                M_READ_B:begin args[15:0]<=memory_read_data[15:0];state<=M_CAPTURE_B;end
                M_CAPTURE_B:begin args[31:16]<=memory_read_data[15:0];state<=MAC_SEND;end
                M_STORE_LO:state<=M_STORE_HI;
                M_STORE_HI:begin
                    c_address<=c_address+2;
                    if(column_index+1<dimension_n) begin column_index<=column_index+1;row_b<=row_b+dimension_k;state<=M_BEGIN;end
                    else if(row_index+1<dimension_m) begin
                        row_index<=row_index+1;column_index<=0;row_a<=row_a+dimension_k;row_b<=base_b;state<=M_BEGIN;
                    end else state<=RES_FINISH;
                end
                RES_FINISH:begin
                    execution_active<=0;reply_value<={56'd0,execution_cycles,resident_flags};reply_length<=5;state<=REPLY;
                end
                REPLY:if(tx_ready) begin
                    if(reply_index>=2 && reply_index<8+reply_length) reply_crc<=crc_byte(reply_crc,tx_data);
                    if(reply_index==9+reply_length) state<=SYNC0;
                    else reply_index<=reply_index+1;
                end
                default:state<=SYNC0;
            endcase
        end
    end
endmodule
