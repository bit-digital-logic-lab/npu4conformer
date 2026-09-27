`timescale 1ns/1ps
module tb_asr_command_engine;
    reg clk=0;
    always #5 clk=!clk;
    reg rst_n=0,rx_valid=0,rx_error=0;
    reg [7:0] rx_data=0;
    wire tx_valid,busy;
    wire [7:0] tx_data;
    reg tx_ready=0;
    asr_command_engine #(.MAX_PAYLOAD(1024),.RX_TIMEOUT_CYCLES(32)) dut(.*);
    reg [7:0] payload[0:1023], reply[0:63];
    integer reply_count=0,cycle=0,checked=0,i,j;
    reg [15:0] sequence_id=0,active_seq;
    reg [7:0] active_opcode;
    reg was_stalled=0;
    reg [7:0] stalled_data;
    reg [15:0] request_checksum;
    reg signed [47:0] expected_acc;

    function automatic [15:0] crc16(input [15:0] start,input [7:0] value);
        reg [15:0] value_crc;
        integer bit_no;
        begin
            value_crc=start^(value<<8);
            for(bit_no=0;bit_no<8;bit_no=bit_no+1)
                if(value_crc[15]) value_crc=(value_crc<<1)^16'h1021;
                else value_crc=value_crc<<1;
            crc16=value_crc;
        end
    endfunction

    always @(negedge clk) begin
        cycle=cycle+1;
        // Deliberate stalls on all positions, including CRC bytes.
        tx_ready=(cycle%7!=0)&&(cycle%7!=1)&&(cycle%13!=4);
    end
    always @(posedge clk) begin
        if(!rst_n) begin reply_count=0;was_stalled=0;end
        else begin
            if(was_stalled && (!tx_valid || tx_data!==stalled_data))
                $fatal(1,"reply changed while backpressured");
            was_stalled=tx_valid&&!tx_ready;
            stalled_data=tx_data;
            if(tx_valid&&tx_ready) begin
                if(reply_count>=64) $fatal(1,"oversized reply");
                reply[reply_count]=tx_data;
                reply_count=reply_count+1;
            end
        end
    end
    task byte_in(input [7:0] value);
        begin
            @(negedge clk);rx_data=value;rx_valid=1;
            @(negedge clk);rx_valid=0;
        end
    endtask
    task crc_in(input [7:0] value);
        begin byte_in(value);request_checksum=crc16(request_checksum,value);end
    endtask
    task set_payload(input [135:0] value,input integer length);
        integer n;
        begin for(n=0;n<length;n=n+1) payload[n]=value>>(n*8);end
    endtask
    task start_packet(input [7:0] opcode,input [7:0] flags,input integer length);
        begin
            @(negedge clk);
            if(busy||tx_valid) $fatal(1,"packet started while engine busy");
            reply_count=0;
            active_seq=sequence_id;
            sequence_id=sequence_id+1;
            active_opcode=opcode;
            request_checksum=16'hffff;
            byte_in(8'ha5);byte_in(8'h5a);
            crc_in(active_seq[7:0]);crc_in(active_seq[15:8]);
            crc_in(opcode);crc_in(flags);crc_in(length[7:0]);crc_in(length[15:8]);
        end
    endtask
    task packet(input [7:0] opcode,input [7:0] flags,input integer length,input bad_crc);
        integer n;
        begin
            start_packet(opcode,flags,length);
            for(n=0;n<length;n=n+1) crc_in(payload[n]);
            byte_in(request_checksum[7:0]^(bad_crc?8'h01:8'h00));
            byte_in(request_checksum[15:8]);
        end
    endtask
    task expect_reply(input [7:0] expected_status,input integer length,input [63:0] value);
        integer n,wait_cycles;
        reg [15:0] check_crc;
        begin
            wait_cycles=0;
            while(reply_count<10+length) begin
                @(negedge clk);wait_cycles=wait_cycles+1;
                if(wait_cycles>10000) $fatal(1,"reply timeout opcode=%02x count=%0d state=%0d",active_opcode,reply_count,dut.state);
            end
            if(reply[0]!==8'h5a||reply[1]!==8'ha5||{reply[3],reply[2]}!==active_seq||reply[4]!==active_opcode)
                $fatal(1,"reply envelope mismatch");
            if(reply[5]!==expected_status||{reply[7],reply[6]}!==length[15:0])
                $fatal(1,"reply status/length opcode=%02x status=%0d expected=%0d length=%0d",active_opcode,reply[5],expected_status,{reply[7],reply[6]});
            for(n=0;n<length;n=n+1)
                if(reply[n+8]!==((value>>(8*n))&8'hff))
                    $fatal(1,"reply payload opcode=%02x byte=%0d got=%02x expected=%02x",active_opcode,n,reply[n+8],(value>>(8*n))&8'hff);
            check_crc=16'hffff;
            for(n=2;n<8+length;n=n+1) check_crc=crc16(check_crc,reply[n]);
            if({reply[9+length],reply[8+length]}!==check_crc) $fatal(1,"reply CRC mismatch");
            repeat(3) @(negedge clk);
            if(busy||tx_valid||reply_count!=length+10) $fatal(1,"reply did not terminate exactly");
            checked=checked+1;
        end
    endtask
    task read_sum(input signed [47:0] value,input [7:0] status);
        begin packet(3,0,0,0);expect_reply(status,6,{16'd0,value});end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        packet(0,0,0,0);expect_reply(0,8,64'h0000000131525341);
        set_payload(10,6);packet(1,0,6,0);expect_reply(0,6,10);
        set_payload({16'd7,16'hfffd},4);packet(2,0,4,0);expect_reply(0,6,64'h0000fffffffffff5);
        set_payload({16'd2,16'd2},4);packet(2,0,4,1);expect_reply(1,0,0);read_sum(-11,0);
        set_payload(999,6);packet(1,2,6,0);expect_reply(3,0,0);read_sum(-11,0);
        packet(2,0,3,0);expect_reply(2,0,0);read_sum(-11,0);
        packet(7,0,0,0);expect_reply(3,0,0);
        start_packet(2,0,1025);expect_reply(2,0,0);read_sum(-11,0);
        packet(5,2,4,0);expect_reply(3,0,0);read_sum(-11,0);
        packet(5,0,0,0);expect_reply(2,0,0);read_sum(-11,0);

        // A partial request must time out without changing the accumulator.
        start_packet(1,0,6);crc_in(8'h42);crc_in(8'h19);
        repeat(40) @(negedge clk);
        if(busy||tx_valid||reply_count) $fatal(1,"partial packet timeout did not resynchronize");
        read_sum(-11,0);
        start_packet(1,0,6);crc_in(8'hab);
        @(negedge clk);rx_error=1;
        @(negedge clk);rx_error=0;
        repeat(3) @(negedge clk);
        if(busy||tx_valid||reply_count) $fatal(1,"UART error did not discard request");
        read_sum(-11,0);

        // Full original-model longest dot product: 38 packets of 256 pairs.
        for(i=0;i<256;i=i+1) begin
            payload[4*i]=0;payload[4*i+1]=8'h80;
            payload[4*i+2]=0;payload[4*i+3]=8'h80;
        end
        expected_acc=0;
        for(j=0;j<38;j=j+1) begin
            packet(5,j==0?1:0,1024,0);
            expected_acc=expected_acc+48'd274877906944;
            expect_reply(0,6,{16'd0,expected_acc});
        end
        if(expected_acc!==48'd10445360463872) $fatal(1,"K9728 test reference wrong");
        read_sum(expected_acc,0);

        set_payload({48'd0,8'd1,32'd1,48'hfffffffffffb},17);
        packet(4,0,17,0);expect_reply(0,2,16'hfffe);
        set_payload({48'd2,8'd1,32'd3,48'd1},17);
        packet(4,0,17,0);expect_reply(0,2,4);
        payload[10]=8'h80;packet(4,0,17,0);expect_reply(3,0,0);
        read_sum(expected_acc,0);

        // Scalar op 14 is signed48 to binary32; op 15 rounds and clamps i16.
        set_payload(64'h0000ffffffffffff,8);packet(8'h2e,0,8,0);expect_reply(0,5,64'h00000000bf800000);
        set_payload(64'h0000010000000000,8);packet(8'h2e,0,8,0);expect_reply(0,5,64'h0000000053800000);
        set_payload(64'h00000000c0200000,8);packet(8'h2f,0,8,0);expect_reply(0,5,64'h00000000fffffffe);
        set_payload(64'h0000000047800000,8);packet(8'h2f,0,8,0);expect_reply(0,5,64'h0000000000007fff);
        set_payload(64'h000000007fc00000,8);packet(8'h2f,0,8,0);expect_reply(4,5,64'h0000000100000000);

        set_payload(48'h7fffffffffff,6);packet(1,0,6,0);expect_reply(0,6,48'h7fffffffffff);
        set_payload({16'd1,16'hffff,16'd1,16'd1},8);
        packet(5,0,8,0);expect_reply(4,6,48'h800000000000);read_sum(48'h800000000000,4);
        set_payload(0,6);packet(1,0,6,0);expect_reply(0,6,0);read_sum(0,0);
        $display("PASS tb_asr_command_engine replies=%0d CRC flags length timeout stalls K9728 requant scalar",checked);
        $finish;
    end
    initial begin #5000000;$fatal(1,"command engine global timeout");end
endmodule
