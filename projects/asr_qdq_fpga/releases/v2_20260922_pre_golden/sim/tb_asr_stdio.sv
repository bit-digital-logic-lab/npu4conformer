`timescale 1ns/1ps
// Persistent simulation bridge. stdin records are decimal byte count followed
// by that many hexadecimal bytes, separated by whitespace. stdout response:
// R <decimal-byte-count> <two-digit-hex-byte> ... <newline>
// All packet decoding and arithmetic use the actual synthesizable RTL.
module tb_asr_stdio;
    localparam integer STDIN=32'h80000000;
    localparam integer STDOUT=32'h80000001;
    localparam integer MAX_FRAME=1034;
    reg clk=0;
    always #5 clk=!clk;
    reg rst_n=0,rx_valid=0,rx_error=0;
    reg [7:0] rx_data=0;
    wire tx_valid,busy;
    wire [7:0] tx_data;
    wire tx_ready=1'b1;
    asr_command_engine #(.MAX_PAYLOAD(1024),.RX_TIMEOUT_CYCLES(1024)) dut(.*);
    reg [7:0] reply[0:MAX_FRAME-1];
    reg [31:0] input_byte;
    integer reply_count=0,reply_expected=0,input_length,scan_status;
    integer index,wait_cycles;
    always @(posedge clk) begin
        if(!rst_n) begin reply_count=0;reply_expected=0;end
        else if(tx_valid) begin
            if(reply_count>=MAX_FRAME) $fatal(1,"stdio bridge reply exceeds bounded frame buffer");
            reply[reply_count]=tx_data;
            reply_count=reply_count+1;
            if(reply_count==8) begin
                reply_expected=10+{reply[7],reply[6]};
                if(reply_expected>MAX_FRAME) $fatal(1,"stdio bridge invalid reply length");
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
            if(scan_status!=1) $fatal(1,"stdio bridge expected decimal request byte count");
            if(input_length<10||input_length>MAX_FRAME)
                $fatal(1,"stdio bridge request count outside [10,1034]");
            @(negedge clk);
            if(busy||tx_valid) $fatal(1,"stdio bridge engine unexpectedly busy");
            reply_count=0;reply_expected=0;
            for(index=0;index<input_length;index=index+1) begin
                scan_status=$fscanf(STDIN,"%h",input_byte);
                if(scan_status!=1||(^input_byte)===1'bx||input_byte>255)
                    $fatal(1,"stdio bridge expected hexadecimal request byte");
                send_byte(input_byte[7:0]);
            end
            wait_cycles=0;
            while(reply_expected==0||reply_count<reply_expected) begin
                @(negedge clk);wait_cycles=wait_cycles+1;
                if(wait_cycles>1000000) $fatal(1,"stdio bridge request produced no reply within 1000000 clocks");
            end
            repeat(2) @(negedge clk);
            if(busy||tx_valid||reply_count!=reply_expected)
                $fatal(1,"stdio bridge response framing did not terminate");
            $write("R %0d",reply_count);
            for(index=0;index<reply_count;index=index+1) $write(" %02x",reply[index]);
            $write("\n");
            $fflush(STDOUT);
        end
    end
endmodule
