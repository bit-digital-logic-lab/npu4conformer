`timescale 1ns/1ps
module tb_asr_fp32_alu;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,in_valid=0,out_ready=0;
    reg [7:0] op=0;reg [31:0] a=0,b=0;
    wire in_ready,out_valid;wire [31:0] result;wire [7:0] flags;
    asr_fp32_alu dut(.*);
    integer fd,fo,scan,count=0,delay_count,timeout_count;
    integer op_int;reg [31:0] aa,bb,held_result;reg [7:0] held_flags;
    reg [2047:0] vectors_file,results_file;
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors_file)) vectors_file="scalar_vectors.txt";
        if(!$value$plusargs("RESULTS=%s",results_file)) results_file="scalar_results.txt";
        fd=$fopen(vectors_file,"r");fo=$fopen(results_file,"w");
        if(!fd||!fo) $fatal(1,"Cannot open scalar vectors/results");
        repeat(4) @(negedge clk);rst_n=1;
        while(!$feof(fd)) begin
            scan=$fscanf(fd,"%d %h %h\n",op_int,aa,bb);
            if(scan==3) begin
                while(!in_ready) @(negedge clk);
                op=op_int;a=aa;b=bb;in_valid=1;out_ready=0;
                @(negedge clk);in_valid=0;
                timeout_count=0;
                while(!out_valid) begin
                    @(negedge clk);timeout_count=timeout_count+1;
                    if(timeout_count>200) $fatal(1,"Scalar timeout");
                end
                held_result=result;held_flags=flags;
                // Check that output and flags remain stable under backpressure.
                for(delay_count=0;delay_count<3;delay_count=delay_count+1) begin
                    @(negedge clk);
                    if(!out_valid || result!==held_result || flags!==held_flags || in_ready)
                        $fatal(1,"Backpressure protocol violated");
                end
                $fwrite(fo,"%0d %08h %08h %08h %02h\n",op_int,aa,bb,result,flags);
                out_ready=1;@(negedge clk);out_ready=0;count=count+1;
            end
        end
        $fclose(fd);$fclose(fo);$display("PASS scalar protocol: %0d cases",count);$finish;
    end
    initial begin #1000000000; $fatal(1,"Global timeout");end
endmodule
