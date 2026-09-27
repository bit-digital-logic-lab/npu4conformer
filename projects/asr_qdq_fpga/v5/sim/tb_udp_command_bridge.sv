`timescale 1ns/1ps
module tb_udp_command_bridge;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0;
    reg s_hdr_valid=0;wire s_hdr_ready;
    reg [31:0] s_src_ip=32'hc0a84d01;
    reg [15:0] s_src_port=50000,s_dst_port=49152,s_udp_length=0;
    reg [7:0] s_axis_tdata=0;
    reg s_axis_tvalid=0;wire s_axis_tready;
    reg s_axis_tlast=0,s_axis_tuser=0;
    wire m_hdr_valid;reg m_hdr_ready=0;
    wire [31:0] m_dst_ip;
    wire [15:0] m_dst_port,m_src_port,m_udp_length;
    wire [7:0] m_axis_tdata;
    wire m_axis_tvalid;reg m_axis_tready=0;
    wire m_axis_tlast,m_axis_tuser;
    wire engine_rx_valid;wire [7:0] engine_rx_data;wire engine_rx_error;
    wire engine_tx_valid;wire [7:0] engine_tx_data;wire engine_tx_ready,engine_busy;
    reg block_engine_reply=0;
    wire real_engine_tx_valid;
    wire real_engine_tx_ready=engine_tx_ready && !block_engine_reply;
    assign engine_tx_valid=real_engine_tx_valid && !block_engine_reply;
    asr_udp_command_bridge #(.RX_TIMEOUT_CYCLES(200),.ENGINE_TIMEOUT_CYCLES(20000)) dut(.*);
    asr_command_engine_v2 #(.RX_TIMEOUT_CYCLES(1000)) engine(
        .clk(clk),.rst_n(rst_n),.rx_valid(engine_rx_valid),.rx_data(engine_rx_data),.rx_error(engine_rx_error),
        .tx_valid(real_engine_tx_valid),.tx_data(engine_tx_data),.tx_ready(real_engine_tx_ready),.busy(engine_busy));
    reg [7:0] payload[0:1023],body[0:4095],packet[0:4095],reply[0:4095],saved_reply[0:4095];
    integer body_count=0,packet_count,reply_count=0,reply_done=0,headers=0;
    integer saved_count=0,engine_bytes=0,cycle=0,checks=0,i,j,n,baseline;
    reg [31:0] test_word;
    reg [15:0] inner_seq=0;
    reg tx_stalled=0,hdr_stalled=0;
    reg [7:0] stalled_data;
    reg stalled_last;
    reg [79:0] stalled_header;
    function automatic [15:0] crc16(input [15:0] crc,input [7:0] value);
        reg [15:0] c;integer n;
        begin c=crc^{value,8'h00};for(n=0;n<8;n=n+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc16=c;end
    endfunction
    always @(negedge clk) begin
        cycle=cycle+1;m_axis_tready=(cycle%7!=0 && cycle%7!=1 && cycle%11!=3);
        m_hdr_ready=(cycle%5==1);
    end
    always @(posedge clk) if(rst_n) begin
        if(tx_stalled && (!m_axis_tvalid || m_axis_tdata!==stalled_data || m_axis_tlast!==stalled_last))
            $fatal(1,"TX changed under backpressure");
        if(hdr_stalled && (!m_hdr_valid || {m_dst_ip,m_dst_port,m_src_port,m_udp_length}!==stalled_header))
            $fatal(1,"TX header changed under backpressure");
        tx_stalled=m_axis_tvalid&&!m_axis_tready;stalled_data=m_axis_tdata;stalled_last=m_axis_tlast;
        hdr_stalled=m_hdr_valid&&!m_hdr_ready;stalled_header={m_dst_ip,m_dst_port,m_src_port,m_udp_length};
        if(engine_rx_valid) engine_bytes=engine_bytes+1;
        if(m_hdr_valid && m_hdr_ready) begin
            if(m_dst_ip!==s_src_ip || m_dst_port!==s_src_port || m_src_port!==49152) $fatal(1,"bad reply routing");
            headers=headers+1;reply_count=0;reply_done=0;
        end
        if(m_axis_tvalid && m_axis_tready) begin
            if(reply_count>=4096 || m_axis_tuser) $fatal(1,"bad TX stream");
            reply[reply_count]=m_axis_tdata;reply_count=reply_count+1;
            if(m_axis_tlast) begin
                if(reply_count+8!=m_udp_length) $fatal(1,"UDP length mismatch");
                reply_done=1;
            end
        end
    end else begin tx_stalled=0;hdr_stalled=0;end
    task reset_all;
        begin
            @(negedge clk);rst_n=0;s_hdr_valid=0;s_axis_tvalid=0;block_engine_reply=0;
            repeat(4) @(negedge clk);rst_n=1;reply_count=0;reply_done=0;body_count=0;
            repeat(3) @(negedge clk);
        end
    endtask
    task append_frame(input [7:0] op,input [7:0] flags,input integer length,input bad_crc);
        integer n,first;reg [15:0] crc;
        begin
            first=body_count;
            body[first]=8'ha5;body[first+1]=8'h5a;body[first+2]=inner_seq[7:0];body[first+3]=inner_seq[15:8];
            body[first+4]=op;body[first+5]=flags;body[first+6]=length[7:0];body[first+7]=length[15:8];
            for(n=0;n<length;n=n+1)body[first+8+n]=payload[n];
            crc=16'hffff;for(n=2;n<length+8;n=n+1)crc=crc16(crc,body[first+n]);
            body[first+8+length]=crc[7:0]^(bad_crc?8'h01:0);body[first+9+length]=crc[15:8];
            body_count=body_count+length+10;inner_seq=inner_seq+1;
        end
    endtask
    task set_payload(input [135:0] value,input integer length);
        integer n;begin for(n=0;n<length;n=n+1)payload[n]=value>>(8*n);end
    endtask
    task build_packet(input [7:0] kind,input [31:0] session_id,input [31:0] seq,input bad_crc);
        integer n;reg [15:0] crc;
        begin
            packet[0]="A";packet[1]="S";packet[2]="R";packet[3]="4";
            for(n=0;n<4;n=n+1)begin packet[4+n]=session_id>>(8*n);packet[8+n]=seq>>(8*n);end
            packet[12]=kind;packet[13]=0;packet[14]=body_count%256;packet[15]=body_count/256;
            for(n=0;n<body_count;n=n+1)packet[n+16]=body[n];
            crc=16'hffff;for(n=0;n<body_count+16;n=n+1)crc=crc16(crc,packet[n]);
            packet[16+body_count]=crc[7:0]^(bad_crc?1:0);packet[17+body_count]=crc[15:8];
            packet_count=body_count+18;
        end
    endtask
    task send_packet(input integer length_delta,input bad_user,input integer truncate);
        integer n,count;
        begin
            @(negedge clk);while(!s_hdr_ready)@(negedge clk);
            reply_done=0;reply_count=0;s_udp_length=packet_count+8+length_delta;s_hdr_valid=1;
            @(negedge clk);s_hdr_valid=0;
            count=truncate>0?truncate:packet_count;
            for(n=0;n<count;n=n+1)begin
                s_axis_tdata=packet[n];s_axis_tvalid=1;s_axis_tlast=(n==count-1);s_axis_tuser=bad_user && n==count-1;
                @(posedge clk);while(!s_axis_tready)@(posedge clk);
                @(negedge clk);
                s_axis_tvalid=0;s_axis_tlast=0;s_axis_tuser=0;
                if(n%13==0)repeat(2)@(negedge clk);
            end
        end
    endtask
    task expect_response(input [7:0] status,input integer length);
        integer n,t;reg [15:0] crc;
        begin
            t=0;while(!reply_done)begin @(negedge clk);t=t+1;
                if(t>100000)$fatal(1,"response timeout state=%0d engine=%0d",dut.state,engine.state);end
            if(reply_count!=length+18 || reply[13]!==status || {reply[15],reply[14]}!==length[15:0])
                $fatal(1,"response status/length got status=%0d len=%0d expected=%0d/%0d state=%0d",reply[13],reply_count,status,length,dut.state);
            for(n=0;n<12;n=n+1)if(reply[n]!==packet[n])$fatal(1,"response header differs byte %0d",n);
            if(reply[12]!== (packet[12]|8'h80))$fatal(1,"response kind");
            crc=16'hffff;for(n=0;n<reply_count-2;n=n+1)crc=crc16(crc,reply[n]);
            if({reply[reply_count-1],reply[reply_count-2]}!==crc)$fatal(1,"response CRC");
            repeat(3)@(negedge clk);if(!s_hdr_ready)$fatal(1,"bridge did not idle");checks=checks+1;
        end
    endtask
    task expect_drop;
        begin repeat(100)@(negedge clk);if(reply_done || !s_hdr_ready || engine_bytes!=baseline)$fatal(1,"bad packet not dropped safely");checks=checks+1;end
    endtask
    task exchange(input [7:0] kind,input [31:0] session_id,input [31:0] seq,input [7:0] status,input integer length);
        begin build_packet(kind,session_id,seq,0);send_packet(0,0,0);expect_response(status,length);end
    endtask
    task verify_inner(input integer start,input [7:0] op,input integer length,input [63:0] expected);
        integer n;reg [15:0] crc;
        begin
            if(reply[start]!==8'h5a || reply[start+1]!==8'ha5 || reply[start+4]!==op || reply[start+5]!==0 ||
                {reply[start+7],reply[start+6]}!==length[15:0])$fatal(1,"inner header op=%02x",op);
            for(n=0;n<length && n<8;n=n+1)if(reply[start+8+n]!==((expected>>(8*n))&255))
                $fatal(1,"inner result op=%02x byte%0d got%02x expected%02x",op,n,reply[start+8+n],(expected>>(8*n))&255);
            crc=16'hffff;for(n=2;n<length+8;n=n+1)crc=crc16(crc,reply[start+n]);
            if({reply[start+length+9],reply[start+length+8]}!==crc)$fatal(1,"inner CRC");
        end
    endtask
    initial begin
        reset_all;
        body_count=0;exchange(0,32'h10203040,0,0,16);
        if({reply[31],reply[30],reply[29],reply[28]}!==1382 || {reply[27],reply[26],reply[25],reply[24]}!==32768)
            $fatal(1,"HELLO capabilities");
        exchange(0,32'h55667788,0,2,0);exchange(0,32'h10203040,0,0,16);
        // Three commands in one batch, including a stateful signed multiply.
        body_count=0;set_payload(10,6);append_frame(1,0,6,0);
        set_payload({16'd7,16'hfffd},4);append_frame(2,0,4,0);append_frame(3,0,0,0);
        exchange(1,32'h10203040,1,0,48);
        verify_inner(16,1,6,10);verify_inner(32,2,6,48'hfffffffffff5);verify_inner(48,3,6,48'hfffffffffff5);
        saved_count=reply_count;for(i=0;i<saved_count;i=i+1)saved_reply[i]=reply[i];baseline=engine_bytes;
        // Exact replay does not multiply again and response is byte-identical.
        send_packet(0,0,0);expect_response(0,48);
        if(engine_bytes!=baseline)$fatal(1,"duplicate executed");
        for(i=0;i<saved_count;i=i+1)if(reply[i]!==saved_reply[i])$fatal(1,"cached response changed");
        body[8]=11;exchange(1,32'h10203040,1,5,0);if(engine_bytes!=baseline)$fatal(1,"ID conflict executed");
        body_count=0;append_frame(3,0,0,0);exchange(1,32'h10203040,3,3,0);
        // New peer cannot mutate a session even with its ID and next sequence.
        s_src_port=50001;exchange(1,32'h10203040,2,2,0);s_src_port=50000;
        // A bad second frame must stop the FIRST (otherwise accumulator changes).
        body_count=0;set_payload(999,6);append_frame(1,0,6,0);append_frame(3,0,0,1);
        exchange(1,32'h10203040,2,4,0);if(engine_bytes!=baseline)$fatal(1,"bad batch partially executed");
        body_count=0;append_frame(3,0,0,0);exchange(1,32'h10203040,2,0,16);verify_inner(16,3,6,48'hfffffffffff5);
        // Original V2 resident write+read with signed/bit-pattern values.
        body_count=0;set_payload({32'hdeadbeef,32'h80008000,16'd2,16'd100},12);append_frame(8'h41,0,12,0);
        set_payload({16'd2,16'd100},4);append_frame(8'h42,0,4,0);
        exchange(1,32'h10203040,3,0,28);verify_inner(26,8'h42,8,64'hdeadbeef80008000);
        // Read amplification must be rejected before executing any command.
        baseline=engine_bytes;body_count=0;set_payload({16'd256,16'd100},4);
        append_frame(8'h42,0,4,0);append_frame(8'h42,0,4,0);exchange(1,32'h10203040,4,4,0);
        if(engine_bytes!=baseline)$fatal(1,"reply capacity check too late");
        // 65 tiny commands exceed the bounded queue, even if replies would fit.
        body_count=0;for(i=0;i<65;i=i+1)append_frame(3,0,0,0);exchange(1,32'h10203040,4,4,0);
        if(engine_bytes!=baseline)$fatal(1,"command count check too late");
        body_count=0;append_frame(3,0,0,0);build_packet(1,32'h10203040,4,1);send_packet(0,0,0);expect_drop;
        build_packet(1,32'h10203040,4,0);send_packet(0,1,0);expect_drop;
        send_packet(1,0,0);expect_drop;send_packet(0,0,12);expect_drop;
        // A successful next request acknowledges cached sequence 3.
        exchange(1,32'h10203040,4,0,16);verify_inner(16,3,6,48'hfffffffffff5);
        exchange(1,32'h10203040,3,3,0);
        body_count=0;exchange(2,32'h10203040,5,0,0);
        exchange(1,32'h10203040,5,2,0);exchange(0,32'h55667788,0,0,16);
        // Nonzero inner status poisons, no later command is dispatched.
        body_count=0;append_frame(8'h7f,0,0,0);set_payload(123,6);append_frame(1,0,6,0);
        baseline=engine_bytes;exchange(1,32'h55667788,1,6,0);
        if(engine_bytes!=baseline+10)$fatal(1,"executed beyond failed command");
        body_count=0;exchange(0,32'h55667788,0,6,0);
        exchange(2,32'h55667788,1,6,0);
        // Coordinated reset is the only way to recover uncertainty.
        reset_all;body_count=0;exchange(0,32'haabbccdd,0,0,16);
        body_count=0;append_frame(3,0,0,0);block_engine_reply=1;exchange(1,32'haabbccdd,1,6,0);
        block_engine_reply=0;baseline=engine_bytes;exchange(1,32'haabbccdd,1,6,0);
        if(engine_bytes!=baseline)$fatal(1,"timeout replay re-executed");
        reset_all;body_count=0;append_frame(3,0,0,0);exchange(1,32'haabbccdd,1,2,0);
        // Near-MTU upload and download use the host's chosen 168-word chunks.
        body_count=0;exchange(0,32'h11223344,0,0,16);
        body_count=0;
        for(j=0;j<2;j=j+1)begin
            payload[0]=(1000+j*168)%256;payload[1]=(1000+j*168)/256;payload[2]=168;payload[3]=0;
            for(i=0;i<168;i=i+1)begin
                test_word=32'h80000000^(j*168+i)*32'h1020307;
                for(n=0;n<4;n=n+1)payload[4+4*i+n]=test_word>>(8*n);
            end
            append_frame(8'h41,0,676,0);
        end
        if(body_count!=1372)$fatal(1,"near MTU setup");exchange(1,32'h11223344,1,0,20);
        baseline=engine_bytes;send_packet(0,0,0);expect_response(0,20);
        if(engine_bytes!=baseline)$fatal(1,"near MTU upload replay executed");
        body_count=0;set_payload({16'd168,16'd1000},4);append_frame(8'h42,0,4,0);
        set_payload({16'd168,16'd1168},4);append_frame(8'h42,0,4,0);
        exchange(1,32'h11223344,2,0,1364);
        for(j=0;j<2;j=j+1)for(i=0;i<168;i=i+1)begin
            test_word=32'h80000000^(j*168+i)*32'h1020307;
            for(n=0;n<4;n=n+1)if(reply[16+682*j+8+4*i+n]!==((test_word>>(8*n))&255))
                $fatal(1,"near MTU read data index=%0d byte=%0d",j*168+i,n);
        end
        saved_count=reply_count;for(i=0;i<saved_count;i=i+1)saved_reply[i]=reply[i];baseline=engine_bytes;
        send_packet(0,0,0);expect_response(0,1364);
        if(engine_bytes!=baseline)$fatal(1,"near MTU download replay executed");
        for(i=0;i<saved_count;i=i+1)if(reply[i]!==saved_reply[i])$fatal(1,"near MTU replay differs");
        body_count=0;set_payload({16'd256,16'd1000},4);append_frame(8'h42,0,4,0);
        exchange(1,32'h11223344,3,0,1034);
        for(i=0;i<256;i=i+1)begin
            test_word=32'h80000000^i*32'h1020307;
            for(n=0;n<4;n=n+1)if(reply[24+4*i+n]!==((test_word>>(8*n))&255))$fatal(1,"1024-byte reply");
        end
        body_count=0;for(i=0;i<64;i=i+1)append_frame(3,0,0,0);exchange(1,32'h11223344,4,0,1024);
        baseline=engine_bytes;body_count=0;append_frame(3,0,0,0);body[body_count]=0;body_count=body_count+1;
        exchange(1,32'h11223344,5,4,0);if(engine_bytes!=baseline)$fatal(1,"trailing garbage executed");
        body_count=0;append_frame(3,0,0,0);build_packet(1,32'h11223344,5,0);
        s_dst_port=49153;send_packet(0,0,0);expect_drop;s_dst_port=49152;
        $display("PASS tb_udp_command_bridge checks=%0d real_frozen_v2_engine CRC batch preflight replay conflict peer capacity timeout poison backpressure",checks);
        $finish;
    end
    initial begin #200000000;$fatal(1,"global timeout state=%0d",dut.state);end
endmodule
