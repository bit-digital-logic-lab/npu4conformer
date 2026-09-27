`timescale 1ns/1ps
module tb_asr_fp32_reset;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,in_valid=0,out_ready=0;
    reg [7:0] op=0;
    reg [31:0] a=0,b=0;
    wire in_ready,out_valid;
    wire [31:0] result;
    wire [7:0] flags;
    integer i,j,k,watchdog,checked=0;
    reg [7:0] tested_ops[0:5];
    asr_fp32_alu dut(.*);
    task launch(input [7:0] code,input [31:0] x,input [31:0] y);
        begin
            while(!in_ready) @(negedge clk);
            op=code;a=x;b=y;in_valid=1;
            @(negedge clk);in_valid=0;
        end
    endtask
    task reset_and_check;
        begin
            rst_n=0;in_valid=0;out_ready=0;
            repeat(3) @(negedge clk);
            if(out_valid!==0) $fatal(1,"Reset did not cancel pending output");
            rst_n=1;
            @(negedge clk);
            if(in_ready!==1 || out_valid!==0) $fatal(1,"Reset did not restore idle handshake");
            launch(0,32'h3f800000,32'h40000000);
            watchdog=0;
            while(!out_valid) begin
                @(negedge clk);watchdog=watchdog+1;
                if(watchdog>200) $fatal(1,"Post-reset operation timed out");
            end
            if(result!==32'h40400000 || flags!==0) $fatal(1,"Stale pre-reset computation escaped");
            out_ready=1;@(negedge clk);out_ready=0;
            checked=checked+1;
        end
    endtask
    initial begin
        tested_ops[0]=0;tested_ops[1]=2;tested_ops[2]=3;
        tested_ops[3]=4;tested_ops[4]=5;tested_ops[5]=6;
        repeat(3) @(negedge clk);rst_n=1;
        for(i=0;i<6;i=i+1) begin
            for(j=0;j<5;j=j+1) begin
                launch(tested_ops[i],32'h40000000,32'h40400000);
                for(k=0;k<j*7;k=k+1) @(negedge clk);
                reset_and_check;
            end
        end
        // Also cancel a completed result under sustained output backpressure.
        launch(5,32'h3f800000,0);
        while(!out_valid) @(negedge clk);
        repeat(8) @(negedge clk);
        reset_and_check;
        $display("PASS tb_asr_fp32_reset checked=%0d pipeline/div/sqrt/exp/log and stalled-output resets",checked);
        $finish;
    end
    initial begin #10000000; $fatal(1,"Reset bench timeout"); end
endmodule
