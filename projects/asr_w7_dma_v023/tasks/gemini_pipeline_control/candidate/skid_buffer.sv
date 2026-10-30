`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// skid_buffer.sv
// High-performance, zero-bubble Register Slice / Skid Buffer.
// Decouples forward valid/data and backward ready paths combinationally.
// Eliminates long combinational timing loops in valid-ready handshake chains
// while guaranteeing full throughput (II=1) and preventing deadlocks.
// -----------------------------------------------------------------------------
module skid_buffer #(
    parameter integer DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  reset,
    // Slave interface (Input)
    input  wire                  s_valid,
    output wire                  s_ready,
    input  wire [DATA_WIDTH-1:0] s_data,
    // Master interface (Output)
    output reg                   m_valid,
    input  wire                  m_ready,
    output reg  [DATA_WIDTH-1:0] m_data
);

    reg [DATA_WIDTH-1:0] skid_data;
    reg                  skid_valid;

    // Ready to accept new data if skid register is empty
    assign s_ready = !skid_valid;

    always @(posedge clk) begin
        if (reset) begin
            m_valid    <= 1'b0;
            m_data     <= {DATA_WIDTH{1'b0}};
            skid_valid <= 1'b0;
            skid_data  <= {DATA_WIDTH{1'b0}};
        end else begin
            // If output was accepted (or not valid), we can move data forward
            if (m_ready || !m_valid) begin
                if (skid_valid) begin
                    // Drain the skid buffer
                    m_valid    <= 1'b1;
                    m_data     <= skid_data;
                    skid_valid <= 1'b0;
                end else if (s_valid) begin
                    // Pass incoming data directly to output register
                    m_valid    <= 1'b1;
                    m_data     <= s_data;
                end else begin
                    // No new data
                    m_valid    <= 1'b0;
                end
            end else if (s_valid && s_ready) begin
                // Downstream is stalled (m_valid && !m_ready), so capture into skid buffer
                skid_valid <= 1'b1;
                skid_data  <= s_data;
            end
        end
    end

endmodule
