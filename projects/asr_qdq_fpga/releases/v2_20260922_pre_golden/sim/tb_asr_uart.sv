`timescale 1ns/1ps
module tb_asr_uart;
    localparam CLK_HZ=50000000,BAUD=115200,DIVISOR=(CLK_HZ+BAUD/2)/BAUD;
    reg clk=0;
    always #10 clk=!clk;
    reg rst_n=0,valid=0;
    reg [7:0] data=0;
    wire ready,tx;
    reg manual=0,manual_rx=1;
    wire serial_rx=manual?manual_rx:tx;
    wire received_valid,framing_error;
    wire [7:0] received_data;
    asr_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) transmitter(.clk(clk),.rst_n(rst_n),.valid(valid),.ready(ready),.data(data),.tx(tx));
    asr_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) receiver(.clk(clk),.rst_n(rst_n),.rx(serial_rx),.valid(received_valid),.data(received_data),.framing_error(framing_error));
    // Separate physical-pin test of the assembled board top.
    reg board_rx=1;
    wire board_tx,board_reply_valid,board_reply_error;
    wire [7:0] board_reply_data;
    asr_uart_top #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) board(.clk(clk),.rst_n(rst_n),.uart_rx(board_rx),.uart_tx(board_tx));
    asr_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) host_receiver(.clk(clk),.rst_n(rst_n),.rx(board_tx),.valid(board_reply_valid),.data(board_reply_data),.framing_error(board_reply_error));
    reg [7:0] board_reply[0:31];
    integer board_reply_count=0,board_wait=0;
    reg [15:0] board_crc;
    reg [7:0] expected[0:511];
    integer sent=0,received=0,errors=0,i,total=0;
    reg previous_valid=0,previous_error=0;
    always @(posedge clk) begin
        if(!rst_n) begin sent=0;received=0;errors=0;previous_valid=0;previous_error=0;end
        else begin
            if(previous_valid&&received_valid) $fatal(1,"RX valid wider than one clock");
            if(previous_error&&framing_error) $fatal(1,"RX error wider than one clock");
            previous_valid=received_valid;previous_error=framing_error;
            if(received_valid) begin
                if(received>=sent||received_data!==expected[received])
                    $fatal(1,"UART RX mismatch index=%0d got=%02x expected=%02x",received,received_data,expected[received]);
                received=received+1;total=total+1;
            end
            if(framing_error) errors=errors+1;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) board_reply_count=0;
        else begin
            if(board_reply_error) $fatal(1,"full top reply UART framing error");
            if(board_reply_valid) begin
                if(board_reply_count>=32) $fatal(1,"full top reply too long");
                board_reply[board_reply_count]=board_reply_data;
                board_reply_count=board_reply_count+1;
            end
        end
    end
    function automatic [15:0] crc16(input [15:0] start,input [7:0] value);
        reg [15:0] c;
        integer k;
        begin
            c=start^(value<<8);
            for(k=0;k<8;k=k+1) c=c[15]?(c<<1)^16'h1021:c<<1;
            crc16=c;
        end
    endfunction
    task send_tx(input [7:0] value);
        integer bit_no,tick;
        reg expected_bit;
        begin
            @(negedge clk);while(!ready) @(negedge clk);
            expected[sent]=value;sent=sent+1;
            data=value;valid=1;
            @(posedge clk);#1;
            for(bit_no=0;bit_no<10;bit_no=bit_no+1) begin
                if(bit_no==0) expected_bit=0;
                else if(bit_no==9) expected_bit=1;
                else expected_bit=value[bit_no-1];
                for(tick=0;tick<DIVISOR;tick=tick+1) begin
                    if(tx!==expected_bit||ready) $fatal(1,"TX bit timing mismatch bit=%0d tick=%0d",bit_no,tick);
                    if(bit_no==0&&tick==0) begin
                        @(negedge clk);valid=0;data=~value;
                    end
                    @(posedge clk);#1;
                end
            end
            if(!ready||tx!==1) $fatal(1,"TX did not return to idle");
        end
    endtask
    task bit_in(input value);
        begin manual_rx=value;repeat(DIVISOR) @(negedge clk);end
    endtask
    task send_manual(input [7:0] value,input good_stop);
        integer bit_no;
        begin
            @(negedge clk);
            if(good_stop) begin expected[sent]=value;sent=sent+1;end
            bit_in(0);
            for(bit_no=0;bit_no<8;bit_no=bit_no+1) bit_in(value[bit_no]);
            bit_in(good_stop);
            manual_rx=1;repeat(DIVISOR*2) @(negedge clk);
        end
    endtask
    task board_byte(input [7:0] value);
        integer k;
        begin
            @(negedge clk);board_rx=0;repeat(DIVISOR) @(negedge clk);
            for(k=0;k<8;k=k+1) begin board_rx=value[k];repeat(DIVISOR) @(negedge clk);end
            board_rx=1;repeat(DIVISOR) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(i=0;i<256;i=i+1) send_tx(i[7:0]);
        repeat(DIVISOR) @(negedge clk);
        if(received!=sent||errors) $fatal(1,"loopback missing byte or error");
        manual=1;manual_rx=1;
        repeat(DIVISOR) @(negedge clk);
        manual_rx=0;repeat(20) @(negedge clk);manual_rx=1;
        repeat(DIVISOR*2) @(negedge clk);
        if(received!=sent||errors) $fatal(1,"short start glitch produced a packet");
        send_manual(8'ha6,0);
        if(errors!=1||received!=sent) $fatal(1,"bad stop not rejected exactly once");
        send_manual(8'h55,1);send_manual(8'haa,1);send_manual(8'h00,1);send_manual(8'hff,1);
        if(received!=sent||errors!=1) $fatal(1,"manual RX recovery failed");
        manual=0;
        @(negedge clk);data=8'h57;valid=1;
        @(negedge clk);valid=0;
        repeat(DIVISOR*3) @(negedge clk);
        rst_n=0;repeat(3) @(negedge clk);
        if(tx!==1||!ready||received_valid) $fatal(1,"UART reset failed");
        rst_n=1;repeat(3) @(negedge clk);
        send_tx(8'hc3);send_tx(8'h3c);
        repeat(DIVISOR) @(negedge clk);
        if(received!=sent||errors) $fatal(1,"UART post-reset recovery failed");
        board_byte(8'ha5);board_byte(8'h5a);
        board_crc=16'hffff;
        for(i=0;i<6;i=i+1) begin board_byte(0);board_crc=crc16(board_crc,0);end
        board_byte(board_crc[7:0]);board_byte(board_crc[15:8]);
        while(board_reply_count<18) begin
            @(negedge clk);board_wait=board_wait+1;
            if(board_wait>100000) $fatal(1,"full top HELLO timeout");
        end
        if({board_reply[1],board_reply[0]}!==16'ha55a ||
           {board_reply[7],board_reply[6],board_reply[5],board_reply[4],board_reply[3],board_reply[2]}!==48'h000800000000 ||
           {board_reply[15],board_reply[14],board_reply[13],board_reply[12],board_reply[11],board_reply[10],board_reply[9],board_reply[8]}!==64'h0000000131525341)
            $fatal(1,"full top HELLO payload mismatch");
        board_crc=16'hffff;
        for(i=2;i<16;i=i+1) board_crc=crc16(board_crc,board_reply[i]);
        if({board_reply[17],board_reply[16]}!==board_crc) $fatal(1,"full top HELLO CRC mismatch");
        $display("PASS tb_asr_uart bytes=%0d 50MHz/115200 actual bit timing, all256, glitch, framing, reset, full-top HELLO",total);
        $finish;
    end
    initial begin #30000000;$fatal(1,"UART timeout");end
endmodule
