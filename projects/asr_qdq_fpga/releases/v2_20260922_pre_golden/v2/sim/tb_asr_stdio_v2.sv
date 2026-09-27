`timescale 1ns/1ps
// stdin: decimal frame length then hexadecimal bytes. stdout: R length bytes.
// This bridge executes synthesizable RTL; it contains no numeric substitute.
module tb_asr_stdio_v2;
    localparam integer STDIN=32'h80000000,STDOUT=32'h80000001,MAX_FRAME=1034;
    reg clk=0;
    always #5 clk=!clk;
    reg rst_n=0,rx_valid=0,rx_error=0;
    reg [7:0] rx_data=0;
    wire tx_valid,busy;
    wire [7:0] tx_data;
    wire tx_ready=1'b1;
    asr_command_engine_v2 #(.MAX_PAYLOAD(1024),.RX_TIMEOUT_CYCLES(1024)) dut(.*);
    reg [7:0] reply[0:MAX_FRAME-1];
    reg [31:0] input_byte;
    integer reply_count=0,reply_expected=0,input_length,scan_status;
    integer index,wait_cycles,reset_after;
    always @(posedge clk) begin
        if(!rst_n) begin reply_count=0;reply_expected=0;end
        else if(tx_valid) begin
            if(reply_count>=MAX_FRAME) $fatal(1,"V2 bridge reply exceeds frame buffer");
            reply[reply_count]=tx_data;reply_count=reply_count+1;
            if(reply_count==8) begin
                reply_expected=10+{reply[7],reply[6]};
                if(reply_expected>MAX_FRAME) $fatal(1,"V2 bridge invalid reply length");
            end
        end
    end
    task send_byte(input [7:0] value);
        begin
            @(negedge clk);rx_data=value;rx_valid=1;
            @(negedge clk);rx_valid=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        forever begin
            scan_status=$fscanf(STDIN,"%d",input_length);
            if(scan_status==-1 || (scan_status==0 && $feof(STDIN))) $finish(0);
            if(scan_status!=1) $fatal(1,"V2 bridge expected decimal frame length");
            // Test-only record: -2 frame_length clocks_before_reset frame_bytes.
            // Normal host records are unchanged. This models interrupted jobs.
            reset_after=0;
            if(input_length==-2) begin
                scan_status=$fscanf(STDIN,"%d %d",input_length,reset_after);
                if(scan_status!=2 || reset_after<1) $fatal(1,"V2 bridge invalid reset-injection record");
            end
            if(input_length<10||input_length>MAX_FRAME) $fatal(1,"V2 bridge invalid request length");
            @(negedge clk);
            if(busy||tx_valid) $fatal(1,"V2 bridge engine unexpectedly busy");
            reply_count=0;reply_expected=0;
            for(index=0;index<input_length;index=index+1) begin
                scan_status=$fscanf(STDIN,"%h",input_byte);
                if(scan_status!=1||(^input_byte)===1'bx||input_byte>255)
                    $fatal(1,"V2 bridge expected hexadecimal byte");
                send_byte(input_byte[7:0]);
            end
            if(reset_after!=0) begin
                repeat(reset_after) @(negedge clk);
                if(!busy || tx_valid) $fatal(1,"V2 reset injection did not interrupt active work");
                rst_n=0;
                repeat(3) @(negedge clk);
                rst_n=1;
                repeat(3) @(negedge clk);
                if(busy || tx_valid) $fatal(1,"V2 reset failed to recover framing");
                $write("RESET\n");$fflush(STDOUT);
            end else begin
                wait_cycles=0;
                while(reply_expected==0||reply_count<reply_expected) begin
                    @(negedge clk);wait_cycles=wait_cycles+1;
                    if(wait_cycles>100000000) $fatal(1,"V2 bridge no reply after 100000000 clocks");
                end
                repeat(2) @(negedge clk);
                if(busy||tx_valid||reply_count!=reply_expected) $fatal(1,"V2 bridge response did not terminate");
                $write("R %0d",reply_count);
                for(index=0;index<reply_count;index=index+1) $write(" %02x",reply[index]);
                $write("\n");$fflush(STDOUT);
            end
        end
    end
endmodule
