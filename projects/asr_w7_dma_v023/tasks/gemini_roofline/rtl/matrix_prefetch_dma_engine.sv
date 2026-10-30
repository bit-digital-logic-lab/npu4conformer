// matrix_prefetch_dma_engine.sv
// Candidate RTL for Overlapped Ping-Pong Prefetch & Posted Writeback DMA
//
// Solves the 88.6% non-PE matrix queue serialization bottleneck.
// Supports both Serial Mode (Before) and Overlapped Ping-Pong Mode (After).
// Compatible with AXI 128-bit / 64-bit memory busses.
// Preserves numerical contract: A16, W7 (S/J/M), C48 accumulation.

`timescale 1ns/1ps

module matrix_prefetch_dma_engine #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 32,
    parameter TILE_A_BYTES = 2048,  // 32x32 of 16-bit A
    parameter TILE_W_BYTES = 1024,  // 32x32 of 8-bit (W7+parity) W
    parameter TILE_C_BYTES = 6144   // 32x32 of 48-bit C
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Control & Status
    input  wire                   start,
    input  wire                   mode_overlap, // 0 = Serial (Before), 1 = Overlapped Ping-Pong (After)
    input  wire [15:0]            num_tiles,
    output reg                    busy,
    output reg                    done,

    // Tile Address Bases
    input  wire [ADDR_WIDTH-1:0]  a_base_addr,
    input  wire [ADDR_WIDTH-1:0]  w_base_addr,
    input  wire [ADDR_WIDTH-1:0]  c_base_addr,

    // Performance Monitoring Counters
    output reg [31:0]             cnt_total_cycles,
    output reg [31:0]             cnt_compute_cycles,
    output reg [31:0]             cnt_dma_wait_cycles,

    // AXI Read Master (DMA Fetch)
    output reg                    m_axi_arvalid,
    input  wire                   m_axi_arready,
    output reg [ADDR_WIDTH-1:0]   m_axi_araddr,
    output reg [7:0]              m_axi_arlen,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready,
    input  wire [DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire                   m_axi_rlast,

    // AXI Write Master (Posted C Writeback)
    output reg                    m_axi_awvalid,
    input  wire                   m_axi_awready,
    output reg [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output reg [7:0]              m_axi_awlen,
    output reg                    m_axi_wvalid,
    input  wire                   m_axi_wready,
    output wire [DATA_WIDTH-1:0]  m_axi_wdata,
    output wire                   m_axi_wlast,
    input  wire                   m_axi_bvalid,
    output wire                   m_axi_bready,

    // PE Compute Core Handshake
    output reg                    core_start,
    output reg                    core_page,
    input  wire                   core_done,
    input  wire [15:0]            core_read_addr,
    output wire [15:0]            core_a_data,
    output wire [6:0]             core_w_data,
    input  wire                   core_c_wen,
    input  wire [15:0]            core_c_addr,
    input  wire [47:0]            core_c_data
);

    localparam BEATS_PER_A = TILE_A_BYTES / (DATA_WIDTH / 8); // 128 beats for 128-bit
    localparam BEATS_PER_W = TILE_W_BYTES / (DATA_WIDTH / 8); // 64 beats for 128-bit
    localparam BEATS_PER_C = TILE_C_BYTES / (DATA_WIDTH / 8); // 384 beats for 128-bit

    // Ping-Pong SRAM Banks for A and W
    // Bank 0 (page 0), Bank 1 (page 1)
    reg [DATA_WIDTH-1:0] ram_a0 [0:BEATS_PER_A-1];
    reg [DATA_WIDTH-1:0] ram_a1 [0:BEATS_PER_A-1];
    reg [DATA_WIDTH-1:0] ram_w0 [0:BEATS_PER_W-1];
    reg [DATA_WIDTH-1:0] ram_w1 [0:BEATS_PER_W-1];

    // C Writeback buffer (double-buffered)
    reg [DATA_WIDTH-1:0] ram_c0 [0:BEATS_PER_C-1];
    reg [DATA_WIDTH-1:0] ram_c1 [0:BEATS_PER_C-1];

    // Read channel is always ready to receive incoming burst beats
    assign m_axi_rready = 1'b1;
    assign m_axi_bready = 1'b1;

    // FSM States
    localparam S_IDLE       = 4'd0;
    localparam S_PROLOGUE   = 4'd1;
    localparam S_RUN        = 4'd2;
    localparam S_DRAIN_WB   = 4'd3;
    localparam S_DONE       = 4'd4;

    reg [3:0] state;

    // DMA Read Sub-FSM
    localparam RD_IDLE   = 3'd0;
    localparam RD_AR_A   = 3'd1;
    localparam RD_DATA_A = 3'd2;
    localparam RD_AR_W   = 3'd3;
    localparam RD_DATA_W = 3'd4;
    localparam RD_DONE   = 3'd5;

    reg [2:0] rd_state;
    reg [15:0] rd_tile_idx;
    reg        rd_page;
    reg [15:0] rd_beat_cnt;

    // DMA Write Sub-FSM
    localparam WR_IDLE   = 3'd0;
    localparam WR_AW     = 3'd1;
    localparam WR_DATA   = 3'd2;
    localparam WR_RESP   = 3'd3;

    reg [2:0] wr_state;
    reg [15:0] wr_tile_idx;
    reg        wr_page;
    reg [15:0] wr_beat_cnt;

    // Core Compute State
    reg [15:0] comp_tile_idx;
    reg        comp_page;
    reg        comp_running;
    reg        comp_finished;

    // Prefetch coordination flags
    reg prefetch_done;
    reg writeback_busy;

    // Performance Counters
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_total_cycles    <= 32'd0;
            cnt_compute_cycles  <= 32'd0;
            cnt_dma_wait_cycles <= 32'd0;
        end else if (busy) begin
            cnt_total_cycles <= cnt_total_cycles + 1'b1;
            if (comp_running)
                cnt_compute_cycles <= cnt_compute_cycles + 1'b1;
            if (!comp_running && rd_state != RD_IDLE)
                cnt_dma_wait_cycles <= cnt_dma_wait_cycles + 1'b1;
        end
    end

    // Main Control FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            core_start    <= 1'b0;
            core_page     <= 1'b0;
            comp_tile_idx <= 16'd0;
            comp_page     <= 1'b0;
            comp_running  <= 1'b0;
        end else begin
            core_start <= 1'b0; // default pulse

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy          <= 1'b1;
                        comp_tile_idx <= 16'd0;
                        comp_page     <= 1'b0;
                        if (mode_overlap) begin
                            // Overlapped: Fetch Tile 0 in prologue
                            state <= S_PROLOGUE;
                        end else begin
                            // Serial: start run immediately
                            state <= S_RUN;
                        end
                    end
                end

                S_PROLOGUE: begin
                    // Wait for Tile 0 prefetch to complete
                    if (rd_tile_idx >= 16'd1) begin
                        core_start    <= 1'b1;
                        core_page     <= comp_page;
                        comp_running  <= 1'b1;
                        comp_tile_idx <= 16'd1;
                        state         <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (!mode_overlap) begin
                        // SERIAL MODE (Before):
                        // Step 1: Wait for A & W fetch
                        // Step 2: Compute
                        // Step 3: Writeback C
                        if (!comp_running && rd_tile_idx == comp_tile_idx + 1'b1) begin
                            core_start   <= 1'b1;
                            core_page    <= comp_page;
                            comp_running <= 1'b1;
                        end else if (comp_running && core_done) begin
                            comp_running  <= 1'b0;
                            comp_tile_idx <= comp_tile_idx + 1'b1;
                            if (comp_tile_idx + 1'b1 >= num_tiles) begin
                                state <= S_DRAIN_WB;
                            end
                        end
                    end else begin
                        // OVERLAPPED MODE (After):
                        // Compute is running on comp_page while DMA prefetches into ~comp_page
                        if (comp_running && core_done) begin
                            comp_running <= 1'b0;
                            if (comp_tile_idx >= num_tiles) begin
                                state <= S_DRAIN_WB;
                            end else if (rd_tile_idx > comp_tile_idx) begin
                                // Alternate page is ready! Launch next tile compute with 0 bubble!
                                core_start    <= 1'b1;
                                core_page     <= ~comp_page;
                                comp_page     <= ~comp_page;
                                comp_running  <= 1'b1;
                                comp_tile_idx <= comp_tile_idx + 1'b1;
                            end else begin
                                // Must wait for DMA to finish prefetch
                                comp_page <= ~comp_page;
                            end
                        end else if (!comp_running && comp_tile_idx < num_tiles) begin
                            if (rd_tile_idx > comp_tile_idx) begin
                                core_start    <= 1'b1;
                                core_page     <= comp_page;
                                comp_running  <= 1'b1;
                                comp_tile_idx <= comp_tile_idx + 1'b1;
                            end
                        end
                    end
                end

                S_DRAIN_WB: begin
                    if (!writeback_busy && wr_state == WR_IDLE) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // DMA Read Channel Controller (Prefetch Engine)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= 32'd0;
            m_axi_arlen   <= 8'd0;
            rd_tile_idx   <= 16'd0;
            rd_page       <= 1'b0;
            rd_beat_cnt   <= 16'd0;
            prefetch_done <= 1'b0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    prefetch_done <= 1'b0;
                    if (start) begin
                        rd_tile_idx <= 16'd0;
                        rd_page     <= 1'b0;
                        rd_state    <= RD_AR_A;
                    end else if (busy && rd_tile_idx < num_tiles) begin
                        if (!mode_overlap) begin
                            // Serial: only fetch when compute & writeback for previous tile are idle
                            if (!comp_running && !writeback_busy && wr_state == WR_IDLE && rd_tile_idx == comp_tile_idx) begin
                                rd_state <= RD_AR_A;
                            end
                        end else begin
                            // Overlapped: prefetch next tile if read is within 1 tile ahead of compute
                            if (rd_tile_idx <= comp_tile_idx) begin
                                rd_page  <= ~comp_page;
                                rd_state <= RD_AR_A;
                            end
                        end
                    end
                end

                RD_AR_A: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_araddr  <= a_base_addr + rd_tile_idx * TILE_A_BYTES;
                    m_axi_arlen   <= BEATS_PER_A - 1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        rd_beat_cnt   <= 16'd0;
                        rd_state      <= RD_DATA_A;
                    end
                end

                RD_DATA_A: begin
                    if (m_axi_rvalid) begin
                        if (rd_page == 1'b0)
                            ram_a0[rd_beat_cnt] <= m_axi_rdata;
                        else
                            ram_a1[rd_beat_cnt] <= m_axi_rdata;

                        rd_beat_cnt <= rd_beat_cnt + 1'b1;
                        if (m_axi_rlast || rd_beat_cnt == BEATS_PER_A - 1) begin
                            rd_state <= RD_AR_W;
                        end
                    end
                end

                RD_AR_W: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_araddr  <= w_base_addr + rd_tile_idx * TILE_W_BYTES;
                    m_axi_arlen   <= BEATS_PER_W - 1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        rd_beat_cnt   <= 16'd0;
                        rd_state      <= RD_DATA_W;
                    end
                end

                RD_DATA_W: begin
                    if (m_axi_rvalid) begin
                        if (rd_page == 1'b0)
                            ram_w0[rd_beat_cnt] <= m_axi_rdata;
                        else
                            ram_w1[rd_beat_cnt] <= m_axi_rdata;

                        rd_beat_cnt <= rd_beat_cnt + 1'b1;
                        if (m_axi_rlast || rd_beat_cnt == BEATS_PER_W - 1) begin
                            rd_tile_idx   <= rd_tile_idx + 1'b1;
                            prefetch_done <= 1'b1;
                            rd_state      <= RD_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    // DMA Write Channel Controller (Posted C Writeback)
    assign m_axi_wdata = (wr_page == 1'b0) ? ram_c0[wr_beat_cnt] : ram_c1[wr_beat_cnt];
    assign m_axi_wlast = (wr_beat_cnt == BEATS_PER_C - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            m_axi_awvalid  <= 1'b0;
            m_axi_awaddr   <= 32'd0;
            m_axi_awlen    <= 8'd0;
            m_axi_wvalid   <= 1'b0;
            wr_tile_idx    <= 16'd0;
            wr_page        <= 1'b0;
            wr_beat_cnt    <= 16'd0;
            writeback_busy <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (core_done) begin
                        // Core completed: trigger posted writeback of current core_page
                        writeback_busy <= 1'b1;
                        wr_page        <= core_page;
                        wr_tile_idx    <= comp_tile_idx;
                        wr_state       <= WR_AW;
                    end
                end

                WR_AW: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awaddr  <= c_base_addr + wr_tile_idx * TILE_C_BYTES;
                    m_axi_awlen   <= BEATS_PER_C - 1;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        wr_beat_cnt   <= 16'd0;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        wr_beat_cnt <= wr_beat_cnt + 1'b1;
                        if (wr_beat_cnt == BEATS_PER_C - 1) begin
                            m_axi_wvalid <= 1'b0;
                            wr_state     <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    if (m_axi_bvalid) begin
                        writeback_busy <= 1'b0;
                        wr_state       <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // Core Memory Read Interface (A & W operands)
    wire [DATA_WIDTH-1:0] cur_a_word = (core_page == 1'b0) ? ram_a0[core_read_addr >> 3] : ram_a1[core_read_addr >> 3];
    wire [DATA_WIDTH-1:0] cur_w_word = (core_page == 1'b0) ? ram_w0[core_read_addr >> 4] : ram_w1[core_read_addr >> 4];

    assign core_a_data = cur_a_word[(core_read_addr[2:0]*16) +: 16];
    assign core_w_data = cur_w_word[(core_read_addr[3:0]*8)  +: 7];

    // Core Memory Write Interface (C Accumulation Result)
    always @(posedge clk) begin
        if (core_c_wen) begin
            if (core_page == 1'b0)
                ram_c0[core_c_addr] <= {{(DATA_WIDTH-48){1'b0}}, core_c_data};
            else
                ram_c1[core_c_addr] <= {{(DATA_WIDTH-48){1'b0}}, core_c_data};
        end
    end

endmodule
