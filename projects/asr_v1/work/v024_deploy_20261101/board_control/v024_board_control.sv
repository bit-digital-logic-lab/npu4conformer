`timescale 1ns/1ps
// Board-side register access only. All inputs are synchronous to aclk.
module v024_board_control #(
    parameter integer MAX_NODES = 128
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 16, READ_WRITE_MODE READ_WRITE, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input wire [15:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input wire [15:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input wire s_axi_rready,

    output wire core_reset_n,
    output reg pc_wr_valid,
    output reg [7:0] pc_wr_addr,
    output reg [31:0] pc_wr_data,
    input wire pc_wr_ready,
    input wire busy, done, fault, requires_reset, port_quiesced,
    input wire [31:0] b_pending, rd_pending, wr_pending,
    input wire [31:0] completed, last_node,
    input wire [7:0] error_code,
    input wire [63:0] cycles,
    input wire matrix_fused_used,
    input wire [31:0] fuse_c48_ddr_bytes, fuse_a16_bytes
);
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    reg release_core_reset;
    reg aw_held, w_held;
    reg [15:0] awaddr_held;
    reg [31:0] wdata_held;
    reg [3:0] wstrb_held;
    reg [31:0] pc_shadow [0:65];
    wire [7:0] write_index = (awaddr_held - 16'h0100) >> 2;
    wire [7:0] read_index = (s_axi_araddr - 16'h0100) >> 2;
    wire write_param = awaddr_held >= 16'h0100 &&
                       awaddr_held <= 16'h0204 && awaddr_held[1:0] == 2'b00;
    wire read_param = s_axi_araddr >= 16'h0100 &&
                      s_axi_araddr <= 16'h0204 && s_axi_araddr[1:0] == 2'b00;
    integer i;

    assign core_reset_n = aresetn && release_core_reset;
    assign s_axi_awready = aresetn && !aw_held && !s_axi_bvalid && !pc_wr_valid;
    assign s_axi_wready = aresetn && !w_held && !s_axi_bvalid && !pc_wr_valid;
    assign s_axi_arready = aresetn && !s_axi_rvalid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            release_core_reset <= 1'b0;
            aw_held <= 1'b0;
            w_held <= 1'b0;
            awaddr_held <= 16'b0;
            wdata_held <= 32'b0;
            wstrb_held <= 4'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= OKAY;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= OKAY;
            s_axi_rdata <= 32'b0;
            pc_wr_valid <= 1'b0;
            pc_wr_addr <= 8'b0;
            pc_wr_data <= 32'b0;
            for (i = 0; i < 66; i = i + 1) pc_shadow[i] <= 32'b0;
        end else begin
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                aw_held <= 1'b1;
                awaddr_held <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_held <= 1'b1;
                wdata_held <= s_axi_wdata;
                wstrb_held <= s_axi_wstrb;
            end

            // Process each independently captured AW/W pair exactly once.
            if (aw_held && w_held) begin
                aw_held <= 1'b0;
                w_held <= 1'b0;
                if (awaddr_held == 16'h0008) begin
                    if (wstrb_held[0]) release_core_reset <= wdata_held[0];
                    s_axi_bresp <= OKAY;
                    s_axi_bvalid <= 1'b1;
                end else if (write_param && wstrb_held == 4'hf && release_core_reset) begin
                    pc_wr_addr <= write_index;
                    pc_wr_data <= wdata_held;
                    pc_wr_valid <= 1'b1;
                end else begin
                    s_axi_bresp <= SLVERR;
                    s_axi_bvalid <= 1'b1;
                end
            end

            // A parameter write is complete only when the core accepts it.
            if (pc_wr_valid && pc_wr_ready) begin
                pc_wr_valid <= 1'b0;
                pc_shadow[pc_wr_addr] <= pc_wr_data;
                s_axi_bresp <= OKAY;
                s_axi_bvalid <= 1'b1;
            end

            // Register data at AR acceptance so R backpressure cannot change it.
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= OKAY;
                case (s_axi_araddr)
                    16'h0000: s_axi_rdata <= 32'ha51a2480;
                    16'h0004: s_axi_rdata <= MAX_NODES;
                    16'h0008: s_axi_rdata <= {31'b0, release_core_reset};
                    16'h0010: s_axi_rdata <= {26'b0, matrix_fused_used, port_quiesced,
                                             requires_reset, fault, done, busy};
                    16'h0014: s_axi_rdata <= {24'b0, error_code};
                    16'h0018: s_axi_rdata <= completed;
                    16'h001c: s_axi_rdata <= last_node;
                    16'h0020: s_axi_rdata <= cycles[31:0];
                    16'h0024: s_axi_rdata <= cycles[63:32];
                    16'h0028: s_axi_rdata <= rd_pending;
                    16'h002c: s_axi_rdata <= wr_pending;
                    16'h0030: s_axi_rdata <= b_pending;
                    16'h0034: s_axi_rdata <= fuse_c48_ddr_bytes;
                    16'h0038: s_axi_rdata <= fuse_a16_bytes;
                    default: begin
                        if (read_param) s_axi_rdata <= pc_shadow[read_index];
                        else begin
                            s_axi_rdata <= 32'b0;
                            s_axi_rresp <= SLVERR;
                        end
                    end
                endcase
            end
        end
    end
    // AWPROT/ARPROT are accepted but do not alter this local register bank.
endmodule
