`timescale 1ns/1ps
module tb_v5_numeric;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,rx_valid=0;reg [7:0] rx_data=0;
    wire tx_valid,busy;wire [7:0] tx_data;
    asr_command_engine_v5 dut(.clk(clk),.rst_n(rst_n),.rx_valid(rx_valid),.rx_data(rx_data),
        .rx_error(1'b0),.tx_valid(tx_valid),.tx_ready(1'b1),.tx_data(tx_data),.busy(busy));
    reg [7:0] bytes[0:1999999];
    integer source,output_file,read_count,i,c,frame_size,cursor,commands;
    string input_path,output_path;
    initial begin
        if(!$value$plusargs("INPUT=%s",input_path))input_path="input.hex";
        if(!$value$plusargs("OUTPUT=%s",output_path))output_path="output.hex";
        source=$fopen(input_path,"r");
        if(!source)$fatal(1,"No simulation stimulus");
        read_count=0;
        while(!$feof(source))begin
            c=$fscanf(source,"%h\n",bytes[read_count]);if(c==1)read_count=read_count+1;
        end
        $fclose(source);
        output_file=$fopen(output_path,"w");
        if(!output_file)$fatal(1,"Cannot open simulation output");
        repeat(20)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
        cursor=0;commands=0;
        while(cursor<read_count)begin
            frame_size=10+bytes[cursor+6]+256*bytes[cursor+7];
            for(i=0;i<frame_size;i=i+1)begin
                @(negedge clk);rx_data=bytes[cursor+i];rx_valid=1;
                @(negedge clk);rx_valid=0;
            end
            @(negedge clk);wait(!busy);repeat(4)@(negedge clk);
            cursor=cursor+frame_size;commands=commands+1;
        end
        repeat(20)@(negedge clk);$fclose(output_file);
        $display("V5_NUMERIC_SIM_COMPLETED commands=%0d bytes=%0d",commands,read_count);$finish;
    end
    always @(posedge clk)if(rst_n&&tx_valid)$fdisplay(output_file,"%02x",tx_data);
    initial begin #1000000000;$fatal(1,"V5 simulation watchdog");end
endmodule
