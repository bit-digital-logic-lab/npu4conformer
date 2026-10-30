`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_skid_backpressure.sv
// Clean, race-free verification of skid_buffer.sv under randomized backpressure.
// Stimulus is driven on negedge clk; monitoring occurs on posedge clk.
// -----------------------------------------------------------------------------

module tb_skid_backpressure;

    localparam integer WIDTH = 32;
    localparam integer NUM_TRANSACTIONS = 5000;

    reg clk;
    reg reset;

    reg             s_valid;
    wire            s_ready;
    reg [WIDTH-1:0] s_data;

    wire            m_valid;
    reg             m_ready;
    wire [WIDTH-1:0] m_data;

    always #5 clk = ~clk;

    skid_buffer #(.DATA_WIDTH(WIDTH)) dut (
        .clk(clk),
        .reset(reset),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data(s_data),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data(m_data)
    );

    // Scoreboard queue
    reg [WIDTH-1:0] expected_queue [0:NUM_TRANSACTIONS+100];
    integer wr_ptr, rd_ptr;
    integer tx_sent, tx_received;
    integer mismatches;

    // Pseudo-random LFSR
    reg [31:0] lfsr;
    function [31:0] rnd;
        begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            rnd = lfsr;
        end
    endfunction

    // Monitor on posedge clk
    always @(posedge clk) begin
        if (!reset) begin
            // Check slave transaction accept
            if (s_valid && s_ready) begin
                expected_queue[wr_ptr] <= s_data;
                wr_ptr <= wr_ptr + 1;
                tx_sent <= tx_sent + 1;
            end

            // Check master transaction output
            if (m_valid && m_ready) begin
                if (rd_ptr < wr_ptr || (s_valid && s_ready && rd_ptr == wr_ptr)) begin
                    reg [WIDTH-1:0] exp_val;
                    exp_val = (rd_ptr < wr_ptr) ? expected_queue[rd_ptr] : s_data;
                    if (m_data !== exp_val) begin
                        $display("[ERROR] Data mismatch at rx %0d: got %08h, expected %08h",
                                 tx_received, m_data, exp_val);
                        mismatches <= mismatches + 1;
                    end
                    rd_ptr <= rd_ptr + 1;
                    tx_received <= tx_received + 1;
                end else begin
                    $display("[ERROR] Spurious output data at rx %0d: %08h", tx_received, m_data);
                    mismatches <= mismatches + 1;
                end
            end
        end
    end

    // Driver on negedge clk
    initial begin
        clk = 0;
        reset = 1;
        s_valid = 0;
        s_data = 0;
        m_ready = 0;
        wr_ptr = 0;
        rd_ptr = 0;
        tx_sent = 0;
        tx_received = 0;
        mismatches = 0;
        lfsr = 32'hDEAD_BEEF;

        #40;
        @(negedge clk);
        reset = 0;

        $display("\n========================================================");
        $display("[TB] Starting Skid Buffer Random Backpressure Test...");
        $display("[TB] Total transactions: %0d", NUM_TRANSACTIONS);
        $display("========================================================");

        while (tx_sent < NUM_TRANSACTIONS) begin
            @(negedge clk);
            // Random backpressure: 50% probability
            m_ready <= ((rnd() % 100) < 50);

            // Drive slave port
            if (!s_valid || s_ready) begin
                if ((rnd() % 100) < 75) begin
                    s_valid <= 1'b1;
                    s_data  <= rnd();
                end else begin
                    s_valid <= 1'b0;
                end
            end
        end

        // Finish pushing
        while (s_valid && !s_ready) begin
            @(negedge clk);
            m_ready <= ((rnd() % 100) < 50);
        end

        @(negedge clk);
        s_valid <= 1'b0;

        // Drain pipeline
        while (tx_received < NUM_TRANSACTIONS) begin
            @(negedge clk);
            m_ready <= 1'b1;
        end

        #50;
        $display("\n========================================================");
        $display("[TB] Skid Buffer Test Completed!");
        $display("========================================================");
        $display("Sent: %0d, Received: %0d, Mismatches: %0d", tx_sent, tx_received, mismatches);

        if (mismatches == 0 && tx_received >= NUM_TRANSACTIONS) begin
            $display("[SUCCESS] Skid buffer passed %0d randomized backpressure beats with ZERO loss or deadlock!", NUM_TRANSACTIONS);
        end else begin
            $display("[FAILURE] Skid buffer failed backpressure verification!");
            $finish(1);
        end

        $finish(0);
    end

endmodule
