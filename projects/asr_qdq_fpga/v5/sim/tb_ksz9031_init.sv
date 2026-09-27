`timescale 1ns/1ps
module tb_ksz9031_init;
    reg clk=0; always #10 clk=~clk;
    reg rst=1;
    wire phy_reset_n, mdc, config_done, config_error;
    wire [31:0] phy_id;
    wire [15:0] basic_status;
    tri1 mdio;
    reg phy_drive=0, phy_bit=1, present=1;
    assign mdio=phy_drive ? phy_bit : 1'bz;
    asr_ksz9031_init #(.RESET_CYCLES(20), .SETTLE_CYCLES(20),
        .POLL_CYCLES(30), .MDIO_HALF_CYCLES(5)) dut (.*);
    integer bit_num=0, transactions=0, writes=0;
    reg [63:0] captured=0;
    reg read_selected=0;
    reg [15:0] return_word=16'hffff;
    reg [4:0] requested_reg;
    reg [20:0] expected_write [0:10];
    always @(posedge rst) begin
        bit_num=0; transactions=0; writes=0; captured=0;
        read_selected=0; phy_drive=0; return_word=16'hffff;
    end
    always @(posedge mdc) begin
        captured={captured[62:0],mdio};
        if (bit_num==45) begin
            requested_reg=captured[4:0];
            read_selected=present && captured[9:5]==7 && captured[11:10]==2'b10;
            case (requested_reg)
                2: return_word=16'h0022;
                3: return_word=16'h1622;
                1: return_word=16'h782d;
                default: return_word=16'h0000;
            endcase
        end
        if (bit_num==63) begin
            transactions=transactions+1;
            if (captured[63:32]!==32'hffffffff || captured[31:30]!==2'b01)
                $fatal(1,"bad preamble/start %h",captured);
            if (captured[29:28]==2'b01) begin
                if (!present || captured[27:23]!=7) $fatal(1,"write before recognized PHY");
                if (captured[17:16]!==2'b10) $fatal(1,"bad write turnaround");
                if (writes>10 || {captured[22:18],captured[15:0]}!==expected_write[writes])
                    $fatal(1,"wrong write step %0d: %h",writes,captured);
                writes=writes+1;
            end
            bit_num=0;
            read_selected=0;
        end else bit_num=bit_num+1;
    end
    always @(negedge mdc) begin
        phy_drive=0;
        if (read_selected && bit_num==47) begin phy_drive=1; phy_bit=0; end
        if (read_selected && bit_num>=48) begin
            phy_drive=1; phy_bit=return_word[63-bit_num];
        end
    end
    initial begin
        expected_write[0]={5'd4,16'h0141};
        expected_write[1]={5'd9,16'h0200};
        expected_write[2]={5'd13,16'h0000};
        expected_write[3]={5'd14,16'h0004};
        expected_write[4]={5'd13,16'h4000};
        expected_write[5]={5'd14,16'h0006};
        expected_write[6]={5'd13,16'h0000};
        expected_write[7]={5'd14,16'h0003};
        expected_write[8]={5'd13,16'h4000};
        expected_write[9]={5'd14,16'h1a80};
        expected_write[10]={5'd0,16'h1200};
        repeat(5) @(negedge clk); rst=0;
        wait(config_done); wait(basic_status==16'h782d);
        if (config_error || phy_id!==32'h00221622 || writes!=11 || transactions<22)
            $fatal(1,"scan/config/status failure");
        $display("PASS recognized PHY at nondefault address7, 11 exact setup writes, BMSR polling");
        @(negedge clk); rst=1; present=0;
        repeat(5) @(negedge clk); rst=0;
        wait(config_error);
        if (config_done || writes!=0 || transactions!=64)
            $fatal(1,"missing PHY must scan32 addresses and never write");
        $display("PASS absent PHY safely fails after32 addresses, no writes");
        $display("KSZ9031_INIT_TEST_PASS"); $finish;
    end
    initial begin #5000000; $fatal(1,"timeout"); end
endmodule
