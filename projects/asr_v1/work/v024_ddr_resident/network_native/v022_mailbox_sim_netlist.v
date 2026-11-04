// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Tue Oct 13 18:38:38 2026
// Host        : ZYF running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/program/python/ASR-ONNX/software4npu/temp/model_a_v0_22/soc_full/build/full002/project/full.gen/sources_1/bd/ps_gateway/ip/ps_gateway_mailbox_0/ps_gateway_mailbox_0_sim_netlist.v
// Design      : ps_gateway_mailbox_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xczu15eg-ffvb1156-2-i
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "ps_gateway_mailbox_0,v13_ps_mailbox,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "module_ref" *) 
(* X_CORE_INFO = "v13_ps_mailbox,Vivado 2025.2" *) 
(* NotValidForBitStream *)
module ps_gateway_mailbox_0
   (clk,
    rst_n,
    rx_valid,
    rx_data,
    rx_error,
    tx_valid,
    tx_data,
    tx_ready,
    busy,
    fast_active,
    fast_cmd_valid,
    fast_cmd_data,
    fast_reply_valid,
    fast_reply_data,
    fast_reply_ready,
    engine_busy,
    queue_active,
    s_axi_awaddr,
    s_axi_awvalid,
    s_axi_awready,
    s_axi_wdata,
    s_axi_wstrb,
    s_axi_wvalid,
    s_axi_wready,
    s_axi_bresp,
    s_axi_bvalid,
    s_axi_bready,
    s_axi_araddr,
    s_axi_arvalid,
    s_axi_arready,
    s_axi_rdata,
    s_axi_rresp,
    s_axi_rvalid,
    s_axi_rready);
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF s_axi, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN ps_gateway_aclk, INSERT_VIP 0" *) input clk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input rst_n;
  input rx_valid;
  input [7:0]rx_data;
  input rx_error;
  output tx_valid;
  output [7:0]tx_data;
  input tx_ready;
  output busy;
  output fast_active;
  output fast_cmd_valid;
  output [7:0]fast_cmd_data;
  input fast_reply_valid;
  input [7:0]fast_reply_data;
  output fast_reply_ready;
  input engine_busy;
  input queue_active;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWADDR" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi, DATA_WIDTH 32, PROTOCOL AXI4LITE, FREQ_HZ 125000000, ID_WIDTH 0, ADDR_WIDTH 24, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 1, PHASE 0.0, CLK_DOMAIN ps_gateway_aclk, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *) input [23:0]s_axi_awaddr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWVALID" *) input s_axi_awvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWREADY" *) output s_axi_awready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WDATA" *) input [31:0]s_axi_wdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WSTRB" *) input [3:0]s_axi_wstrb;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WVALID" *) input s_axi_wvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WREADY" *) output s_axi_wready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BRESP" *) output [1:0]s_axi_bresp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BVALID" *) output s_axi_bvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BREADY" *) input s_axi_bready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARADDR" *) input [23:0]s_axi_araddr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARVALID" *) input s_axi_arvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARREADY" *) output s_axi_arready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RDATA" *) output [31:0]s_axi_rdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RRESP" *) output [1:0]s_axi_rresp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RVALID" *) output s_axi_rvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RREADY" *) input s_axi_rready;

  wire \<const0> ;
  wire busy;
  wire clk;
  wire engine_busy;
  wire fast_active;
  wire [7:0]fast_cmd_data;
  wire fast_cmd_valid;
  wire [7:0]fast_reply_data;
  wire fast_reply_ready;
  wire fast_reply_valid;
  wire queue_active;
  wire rst_n;
  wire [7:0]rx_data;
  wire rx_error;
  wire rx_valid;
  wire [23:0]s_axi_araddr;
  wire s_axi_arready;
  wire s_axi_arvalid;
  wire [23:0]s_axi_awaddr;
  wire s_axi_awready;
  wire s_axi_awvalid;
  wire s_axi_bready;
  wire [1:1]\^s_axi_bresp ;
  wire s_axi_bvalid;
  wire [31:0]s_axi_rdata;
  wire s_axi_rready;
  wire [1:1]\^s_axi_rresp ;
  wire s_axi_rvalid;
  wire [31:0]s_axi_wdata;
  wire s_axi_wready;
  wire [3:0]s_axi_wstrb;
  wire s_axi_wvalid;
  wire [7:0]tx_data;
  wire tx_ready;
  wire tx_valid;

  assign s_axi_bresp[1] = \^s_axi_bresp [1];
  assign s_axi_bresp[0] = \<const0> ;
  assign s_axi_rresp[1] = \^s_axi_rresp [1];
  assign s_axi_rresp[0] = \<const0> ;
  GND GND
       (.G(\<const0> ));
  ps_gateway_mailbox_0_v13_ps_mailbox inst
       (.busy(busy),
        .clk(clk),
        .engine_busy(engine_busy),
        .fast_active(fast_active),
        .fast_cmd_data(fast_cmd_data),
        .fast_reply_data(fast_reply_data),
        .fast_reply_ready(fast_reply_ready),
        .fast_reply_valid(fast_reply_valid),
        .queue_active(queue_active),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_error(rx_error),
        .rx_valid(rx_valid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arready(s_axi_arready),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awready(s_axi_awready),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_bresp(\^s_axi_bresp ),
        .s_axi_bvalid_reg_0(s_axi_bvalid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rready(s_axi_rready),
        .s_axi_rresp(\^s_axi_rresp ),
        .s_axi_rvalid_reg_0(s_axi_rvalid),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wready(s_axi_wready),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .\state_reg[1]_0 (fast_cmd_valid),
        .tx_data(tx_data),
        .tx_ready(tx_ready),
        .tx_valid(tx_valid));
endmodule

(* ORIG_REF_NAME = "v13_ps_mailbox" *) 
module ps_gateway_mailbox_0_v13_ps_mailbox
   (s_axi_bvalid_reg_0,
    tx_valid,
    s_axi_bresp,
    s_axi_rdata,
    fast_active,
    s_axi_rresp,
    \state_reg[1]_0 ,
    s_axi_wready,
    s_axi_awready,
    fast_reply_ready,
    s_axi_rvalid_reg_0,
    s_axi_arready,
    busy,
    tx_data,
    fast_cmd_data,
    rst_n,
    tx_ready,
    s_axi_araddr,
    engine_busy,
    rx_valid,
    fast_reply_data,
    rx_data,
    clk,
    s_axi_awvalid,
    s_axi_wvalid,
    s_axi_wdata,
    s_axi_awaddr,
    s_axi_wstrb,
    fast_reply_valid,
    s_axi_arvalid,
    queue_active,
    rx_error,
    s_axi_bready,
    s_axi_rready);
  output s_axi_bvalid_reg_0;
  output tx_valid;
  output [0:0]s_axi_bresp;
  output [31:0]s_axi_rdata;
  output fast_active;
  output [0:0]s_axi_rresp;
  output \state_reg[1]_0 ;
  output s_axi_wready;
  output s_axi_awready;
  output fast_reply_ready;
  output s_axi_rvalid_reg_0;
  output s_axi_arready;
  output busy;
  output [7:0]tx_data;
  output [7:0]fast_cmd_data;
  input rst_n;
  input tx_ready;
  input [23:0]s_axi_araddr;
  input engine_busy;
  input rx_valid;
  input [7:0]fast_reply_data;
  input [7:0]rx_data;
  input clk;
  input s_axi_awvalid;
  input s_axi_wvalid;
  input [31:0]s_axi_wdata;
  input [23:0]s_axi_awaddr;
  input [3:0]s_axi_wstrb;
  input fast_reply_valid;
  input s_axi_arvalid;
  input queue_active;
  input rx_error;
  input s_axi_bready;
  input s_axi_rready;

  wire [23:0]aw;
  wire aw_full;
  wire aw_full0;
  wire aw_full_i_1_n_0;
  wire aw_full_i_2_n_0;
  wire busy;
  wire busy_INST_0_i_1_n_0;
  wire busy_INST_0_i_2_n_0;
  wire busy_INST_0_i_3_n_0;
  wire busy_INST_0_i_4_n_0;
  wire busy_INST_0_i_5_n_0;
  wire clk;
  wire [0:0]cmd_index;
  wire \cmd_index[0]_i_1_n_0 ;
  wire \cmd_index[10]_i_1_n_0 ;
  wire \cmd_index[11]_i_1_n_0 ;
  wire \cmd_index[11]_i_2_n_0 ;
  wire \cmd_index[12]_i_1_n_0 ;
  wire \cmd_index[13]_i_1_n_0 ;
  wire \cmd_index[13]_i_2_n_0 ;
  wire \cmd_index[14]_i_1_n_0 ;
  wire \cmd_index[14]_i_2_n_0 ;
  wire \cmd_index[15]_i_10_n_0 ;
  wire \cmd_index[15]_i_11_n_0 ;
  wire \cmd_index[15]_i_12_n_0 ;
  wire \cmd_index[15]_i_1_n_0 ;
  wire \cmd_index[15]_i_2_n_0 ;
  wire \cmd_index[15]_i_3_n_0 ;
  wire \cmd_index[15]_i_4_n_0 ;
  wire \cmd_index[15]_i_5_n_0 ;
  wire \cmd_index[15]_i_6_n_0 ;
  wire \cmd_index[15]_i_7_n_0 ;
  wire \cmd_index[15]_i_8_n_0 ;
  wire \cmd_index[15]_i_9_n_0 ;
  wire \cmd_index[1]_i_1_n_0 ;
  wire \cmd_index[2]_i_1_n_0 ;
  wire \cmd_index[3]_i_1_n_0 ;
  wire \cmd_index[4]_i_1_n_0 ;
  wire \cmd_index[5]_i_1_n_0 ;
  wire \cmd_index[6]_i_1_n_0 ;
  wire \cmd_index[6]_i_2_n_0 ;
  wire \cmd_index[7]_i_1_n_0 ;
  wire \cmd_index[8]_i_1_n_0 ;
  wire \cmd_index[8]_i_2_n_0 ;
  wire \cmd_index[9]_i_1_n_0 ;
  wire \cmd_index_reg_n_0_[0] ;
  wire \cmd_index_reg_n_0_[10] ;
  wire \cmd_index_reg_n_0_[11] ;
  wire \cmd_index_reg_n_0_[12] ;
  wire \cmd_index_reg_n_0_[13] ;
  wire \cmd_index_reg_n_0_[14] ;
  wire \cmd_index_reg_n_0_[15] ;
  wire \cmd_index_reg_n_0_[1] ;
  wire \cmd_index_reg_n_0_[2] ;
  wire \cmd_index_reg_n_0_[3] ;
  wire \cmd_index_reg_n_0_[4] ;
  wire \cmd_index_reg_n_0_[5] ;
  wire \cmd_index_reg_n_0_[6] ;
  wire \cmd_index_reg_n_0_[7] ;
  wire \cmd_index_reg_n_0_[8] ;
  wire \cmd_index_reg_n_0_[9] ;
  wire [127:0]cmd_word;
  wire \cmd_word[127]_i_1_n_0 ;
  wire \completed[0]_i_1_n_0 ;
  wire \completed[0]_i_3_n_0 ;
  wire [31:0]completed_reg;
  wire \completed_reg[0]_i_2_n_0 ;
  wire \completed_reg[0]_i_2_n_1 ;
  wire \completed_reg[0]_i_2_n_10 ;
  wire \completed_reg[0]_i_2_n_11 ;
  wire \completed_reg[0]_i_2_n_12 ;
  wire \completed_reg[0]_i_2_n_13 ;
  wire \completed_reg[0]_i_2_n_14 ;
  wire \completed_reg[0]_i_2_n_15 ;
  wire \completed_reg[0]_i_2_n_2 ;
  wire \completed_reg[0]_i_2_n_3 ;
  wire \completed_reg[0]_i_2_n_4 ;
  wire \completed_reg[0]_i_2_n_5 ;
  wire \completed_reg[0]_i_2_n_6 ;
  wire \completed_reg[0]_i_2_n_7 ;
  wire \completed_reg[0]_i_2_n_8 ;
  wire \completed_reg[0]_i_2_n_9 ;
  wire \completed_reg[16]_i_1_n_0 ;
  wire \completed_reg[16]_i_1_n_1 ;
  wire \completed_reg[16]_i_1_n_10 ;
  wire \completed_reg[16]_i_1_n_11 ;
  wire \completed_reg[16]_i_1_n_12 ;
  wire \completed_reg[16]_i_1_n_13 ;
  wire \completed_reg[16]_i_1_n_14 ;
  wire \completed_reg[16]_i_1_n_15 ;
  wire \completed_reg[16]_i_1_n_2 ;
  wire \completed_reg[16]_i_1_n_3 ;
  wire \completed_reg[16]_i_1_n_4 ;
  wire \completed_reg[16]_i_1_n_5 ;
  wire \completed_reg[16]_i_1_n_6 ;
  wire \completed_reg[16]_i_1_n_7 ;
  wire \completed_reg[16]_i_1_n_8 ;
  wire \completed_reg[16]_i_1_n_9 ;
  wire \completed_reg[24]_i_1_n_1 ;
  wire \completed_reg[24]_i_1_n_10 ;
  wire \completed_reg[24]_i_1_n_11 ;
  wire \completed_reg[24]_i_1_n_12 ;
  wire \completed_reg[24]_i_1_n_13 ;
  wire \completed_reg[24]_i_1_n_14 ;
  wire \completed_reg[24]_i_1_n_15 ;
  wire \completed_reg[24]_i_1_n_2 ;
  wire \completed_reg[24]_i_1_n_3 ;
  wire \completed_reg[24]_i_1_n_4 ;
  wire \completed_reg[24]_i_1_n_5 ;
  wire \completed_reg[24]_i_1_n_6 ;
  wire \completed_reg[24]_i_1_n_7 ;
  wire \completed_reg[24]_i_1_n_8 ;
  wire \completed_reg[24]_i_1_n_9 ;
  wire \completed_reg[8]_i_1_n_0 ;
  wire \completed_reg[8]_i_1_n_1 ;
  wire \completed_reg[8]_i_1_n_10 ;
  wire \completed_reg[8]_i_1_n_11 ;
  wire \completed_reg[8]_i_1_n_12 ;
  wire \completed_reg[8]_i_1_n_13 ;
  wire \completed_reg[8]_i_1_n_14 ;
  wire \completed_reg[8]_i_1_n_15 ;
  wire \completed_reg[8]_i_1_n_2 ;
  wire \completed_reg[8]_i_1_n_3 ;
  wire \completed_reg[8]_i_1_n_4 ;
  wire \completed_reg[8]_i_1_n_5 ;
  wire \completed_reg[8]_i_1_n_6 ;
  wire \completed_reg[8]_i_1_n_7 ;
  wire \completed_reg[8]_i_1_n_8 ;
  wire \completed_reg[8]_i_1_n_9 ;
  wire \count[0]_i_1_n_0 ;
  wire \count[10]_i_1_n_0 ;
  wire \count[11]_i_1_n_0 ;
  wire \count[12]_i_1_n_0 ;
  wire \count[12]_i_2_n_0 ;
  wire \count[13]_i_1_n_0 ;
  wire \count[14]_i_1_n_0 ;
  wire \count[14]_i_2_n_0 ;
  wire \count[15]_i_1_n_0 ;
  wire \count[15]_i_2_n_0 ;
  wire \count[15]_i_3_n_0 ;
  wire \count[1]_i_1_n_0 ;
  wire \count[2]_i_1_n_0 ;
  wire \count[3]_i_1_n_0 ;
  wire \count[4]_i_1_n_0 ;
  wire \count[5]_i_1_n_0 ;
  wire \count[6]_i_1_n_0 ;
  wire \count[7]_i_1_n_0 ;
  wire \count[8]_i_1_n_0 ;
  wire \count[9]_i_1_n_0 ;
  wire \count[9]_i_2_n_0 ;
  wire \count_reg_n_0_[0] ;
  wire \count_reg_n_0_[11] ;
  wire \count_reg_n_0_[12] ;
  wire \count_reg_n_0_[13] ;
  wire \count_reg_n_0_[14] ;
  wire \count_reg_n_0_[15] ;
  wire \count_reg_n_0_[1] ;
  wire \count_reg_n_0_[2] ;
  wire \count_reg_n_0_[3] ;
  wire [7:0]data1;
  wire [7:0]data10;
  wire [7:0]data11;
  wire [7:0]data12;
  wire [7:0]data13;
  wire [7:0]data14;
  wire [7:0]data15;
  wire [7:0]data2;
  wire [7:0]data3;
  wire [7:0]data4;
  wire [7:0]data5;
  wire [7:0]data6;
  wire [7:0]data7;
  wire [7:0]data8;
  wire [7:0]data9;
  wire engine_busy;
  wire fast_active;
  wire [7:0]fast_cmd_data;
  wire \fast_cmd_data[0]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[0]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[0]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[0]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[0]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[0]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[1]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[1]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[1]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[1]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[1]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[1]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[2]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[2]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[2]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[2]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[2]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[2]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[3]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[3]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[3]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[3]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[3]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[3]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[4]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[4]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[4]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[4]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[4]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[4]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[5]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[5]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[5]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[5]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[5]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[5]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[6]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[6]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[6]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[6]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[6]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[6]_INST_0_i_6_n_0 ;
  wire \fast_cmd_data[7]_INST_0_i_1_n_0 ;
  wire \fast_cmd_data[7]_INST_0_i_2_n_0 ;
  wire \fast_cmd_data[7]_INST_0_i_3_n_0 ;
  wire \fast_cmd_data[7]_INST_0_i_4_n_0 ;
  wire \fast_cmd_data[7]_INST_0_i_5_n_0 ;
  wire \fast_cmd_data[7]_INST_0_i_6_n_0 ;
  wire \fast_completed[0]_i_2_n_0 ;
  wire [31:0]fast_completed_reg;
  wire \fast_completed_reg[0]_i_1_n_0 ;
  wire \fast_completed_reg[0]_i_1_n_1 ;
  wire \fast_completed_reg[0]_i_1_n_10 ;
  wire \fast_completed_reg[0]_i_1_n_11 ;
  wire \fast_completed_reg[0]_i_1_n_12 ;
  wire \fast_completed_reg[0]_i_1_n_13 ;
  wire \fast_completed_reg[0]_i_1_n_14 ;
  wire \fast_completed_reg[0]_i_1_n_15 ;
  wire \fast_completed_reg[0]_i_1_n_2 ;
  wire \fast_completed_reg[0]_i_1_n_3 ;
  wire \fast_completed_reg[0]_i_1_n_4 ;
  wire \fast_completed_reg[0]_i_1_n_5 ;
  wire \fast_completed_reg[0]_i_1_n_6 ;
  wire \fast_completed_reg[0]_i_1_n_7 ;
  wire \fast_completed_reg[0]_i_1_n_8 ;
  wire \fast_completed_reg[0]_i_1_n_9 ;
  wire \fast_completed_reg[16]_i_1_n_0 ;
  wire \fast_completed_reg[16]_i_1_n_1 ;
  wire \fast_completed_reg[16]_i_1_n_10 ;
  wire \fast_completed_reg[16]_i_1_n_11 ;
  wire \fast_completed_reg[16]_i_1_n_12 ;
  wire \fast_completed_reg[16]_i_1_n_13 ;
  wire \fast_completed_reg[16]_i_1_n_14 ;
  wire \fast_completed_reg[16]_i_1_n_15 ;
  wire \fast_completed_reg[16]_i_1_n_2 ;
  wire \fast_completed_reg[16]_i_1_n_3 ;
  wire \fast_completed_reg[16]_i_1_n_4 ;
  wire \fast_completed_reg[16]_i_1_n_5 ;
  wire \fast_completed_reg[16]_i_1_n_6 ;
  wire \fast_completed_reg[16]_i_1_n_7 ;
  wire \fast_completed_reg[16]_i_1_n_8 ;
  wire \fast_completed_reg[16]_i_1_n_9 ;
  wire \fast_completed_reg[24]_i_1_n_1 ;
  wire \fast_completed_reg[24]_i_1_n_10 ;
  wire \fast_completed_reg[24]_i_1_n_11 ;
  wire \fast_completed_reg[24]_i_1_n_12 ;
  wire \fast_completed_reg[24]_i_1_n_13 ;
  wire \fast_completed_reg[24]_i_1_n_14 ;
  wire \fast_completed_reg[24]_i_1_n_15 ;
  wire \fast_completed_reg[24]_i_1_n_2 ;
  wire \fast_completed_reg[24]_i_1_n_3 ;
  wire \fast_completed_reg[24]_i_1_n_4 ;
  wire \fast_completed_reg[24]_i_1_n_5 ;
  wire \fast_completed_reg[24]_i_1_n_6 ;
  wire \fast_completed_reg[24]_i_1_n_7 ;
  wire \fast_completed_reg[24]_i_1_n_8 ;
  wire \fast_completed_reg[24]_i_1_n_9 ;
  wire \fast_completed_reg[8]_i_1_n_0 ;
  wire \fast_completed_reg[8]_i_1_n_1 ;
  wire \fast_completed_reg[8]_i_1_n_10 ;
  wire \fast_completed_reg[8]_i_1_n_11 ;
  wire \fast_completed_reg[8]_i_1_n_12 ;
  wire \fast_completed_reg[8]_i_1_n_13 ;
  wire \fast_completed_reg[8]_i_1_n_14 ;
  wire \fast_completed_reg[8]_i_1_n_15 ;
  wire \fast_completed_reg[8]_i_1_n_2 ;
  wire \fast_completed_reg[8]_i_1_n_3 ;
  wire \fast_completed_reg[8]_i_1_n_4 ;
  wire \fast_completed_reg[8]_i_1_n_5 ;
  wire \fast_completed_reg[8]_i_1_n_6 ;
  wire \fast_completed_reg[8]_i_1_n_7 ;
  wire \fast_completed_reg[8]_i_1_n_8 ;
  wire \fast_completed_reg[8]_i_1_n_9 ;
  wire \fast_cycles[0]_i_1_n_0 ;
  wire \fast_cycles[0]_i_3_n_0 ;
  wire [31:0]fast_cycles_reg;
  wire \fast_cycles_reg[0]_i_2_n_0 ;
  wire \fast_cycles_reg[0]_i_2_n_1 ;
  wire \fast_cycles_reg[0]_i_2_n_10 ;
  wire \fast_cycles_reg[0]_i_2_n_11 ;
  wire \fast_cycles_reg[0]_i_2_n_12 ;
  wire \fast_cycles_reg[0]_i_2_n_13 ;
  wire \fast_cycles_reg[0]_i_2_n_14 ;
  wire \fast_cycles_reg[0]_i_2_n_15 ;
  wire \fast_cycles_reg[0]_i_2_n_2 ;
  wire \fast_cycles_reg[0]_i_2_n_3 ;
  wire \fast_cycles_reg[0]_i_2_n_4 ;
  wire \fast_cycles_reg[0]_i_2_n_5 ;
  wire \fast_cycles_reg[0]_i_2_n_6 ;
  wire \fast_cycles_reg[0]_i_2_n_7 ;
  wire \fast_cycles_reg[0]_i_2_n_8 ;
  wire \fast_cycles_reg[0]_i_2_n_9 ;
  wire \fast_cycles_reg[16]_i_1_n_0 ;
  wire \fast_cycles_reg[16]_i_1_n_1 ;
  wire \fast_cycles_reg[16]_i_1_n_10 ;
  wire \fast_cycles_reg[16]_i_1_n_11 ;
  wire \fast_cycles_reg[16]_i_1_n_12 ;
  wire \fast_cycles_reg[16]_i_1_n_13 ;
  wire \fast_cycles_reg[16]_i_1_n_14 ;
  wire \fast_cycles_reg[16]_i_1_n_15 ;
  wire \fast_cycles_reg[16]_i_1_n_2 ;
  wire \fast_cycles_reg[16]_i_1_n_3 ;
  wire \fast_cycles_reg[16]_i_1_n_4 ;
  wire \fast_cycles_reg[16]_i_1_n_5 ;
  wire \fast_cycles_reg[16]_i_1_n_6 ;
  wire \fast_cycles_reg[16]_i_1_n_7 ;
  wire \fast_cycles_reg[16]_i_1_n_8 ;
  wire \fast_cycles_reg[16]_i_1_n_9 ;
  wire \fast_cycles_reg[24]_i_1_n_1 ;
  wire \fast_cycles_reg[24]_i_1_n_10 ;
  wire \fast_cycles_reg[24]_i_1_n_11 ;
  wire \fast_cycles_reg[24]_i_1_n_12 ;
  wire \fast_cycles_reg[24]_i_1_n_13 ;
  wire \fast_cycles_reg[24]_i_1_n_14 ;
  wire \fast_cycles_reg[24]_i_1_n_15 ;
  wire \fast_cycles_reg[24]_i_1_n_2 ;
  wire \fast_cycles_reg[24]_i_1_n_3 ;
  wire \fast_cycles_reg[24]_i_1_n_4 ;
  wire \fast_cycles_reg[24]_i_1_n_5 ;
  wire \fast_cycles_reg[24]_i_1_n_6 ;
  wire \fast_cycles_reg[24]_i_1_n_7 ;
  wire \fast_cycles_reg[24]_i_1_n_8 ;
  wire \fast_cycles_reg[24]_i_1_n_9 ;
  wire \fast_cycles_reg[8]_i_1_n_0 ;
  wire \fast_cycles_reg[8]_i_1_n_1 ;
  wire \fast_cycles_reg[8]_i_1_n_10 ;
  wire \fast_cycles_reg[8]_i_1_n_11 ;
  wire \fast_cycles_reg[8]_i_1_n_12 ;
  wire \fast_cycles_reg[8]_i_1_n_13 ;
  wire \fast_cycles_reg[8]_i_1_n_14 ;
  wire \fast_cycles_reg[8]_i_1_n_15 ;
  wire \fast_cycles_reg[8]_i_1_n_2 ;
  wire \fast_cycles_reg[8]_i_1_n_3 ;
  wire \fast_cycles_reg[8]_i_1_n_4 ;
  wire \fast_cycles_reg[8]_i_1_n_5 ;
  wire \fast_cycles_reg[8]_i_1_n_6 ;
  wire \fast_cycles_reg[8]_i_1_n_7 ;
  wire \fast_cycles_reg[8]_i_1_n_8 ;
  wire \fast_cycles_reg[8]_i_1_n_9 ;
  wire \fast_error[0]_i_1_n_0 ;
  wire \fast_error[0]_i_2_n_0 ;
  wire \fast_error[1]_i_1_n_0 ;
  wire \fast_error[2]_i_1_n_0 ;
  wire \fast_error[2]_i_2_n_0 ;
  wire \fast_error[2]_i_3_n_0 ;
  wire \fast_error[2]_i_4_n_0 ;
  wire \fast_error[2]_i_5_n_0 ;
  wire \fast_error[2]_i_6_n_0 ;
  wire \fast_error[2]_i_7_n_0 ;
  wire \fast_error[2]_i_8_n_0 ;
  wire \fast_error_reg_n_0_[0] ;
  wire \fast_error_reg_n_0_[1] ;
  wire \fast_error_reg_n_0_[2] ;
  wire [7:0]fast_reply_data;
  wire fast_reply_ready;
  wire fast_reply_ready_INST_0_i_1_n_0;
  wire fast_reply_ready_INST_0_i_2_n_0;
  wire fast_reply_ready_INST_0_i_3_n_0;
  wire fast_reply_valid;
  wire \fast_starts[0]_i_3_n_0 ;
  wire [31:0]fast_starts_reg;
  wire \fast_starts_reg[0]_i_2_n_0 ;
  wire \fast_starts_reg[0]_i_2_n_1 ;
  wire \fast_starts_reg[0]_i_2_n_10 ;
  wire \fast_starts_reg[0]_i_2_n_11 ;
  wire \fast_starts_reg[0]_i_2_n_12 ;
  wire \fast_starts_reg[0]_i_2_n_13 ;
  wire \fast_starts_reg[0]_i_2_n_14 ;
  wire \fast_starts_reg[0]_i_2_n_15 ;
  wire \fast_starts_reg[0]_i_2_n_2 ;
  wire \fast_starts_reg[0]_i_2_n_3 ;
  wire \fast_starts_reg[0]_i_2_n_4 ;
  wire \fast_starts_reg[0]_i_2_n_5 ;
  wire \fast_starts_reg[0]_i_2_n_6 ;
  wire \fast_starts_reg[0]_i_2_n_7 ;
  wire \fast_starts_reg[0]_i_2_n_8 ;
  wire \fast_starts_reg[0]_i_2_n_9 ;
  wire \fast_starts_reg[16]_i_1_n_0 ;
  wire \fast_starts_reg[16]_i_1_n_1 ;
  wire \fast_starts_reg[16]_i_1_n_10 ;
  wire \fast_starts_reg[16]_i_1_n_11 ;
  wire \fast_starts_reg[16]_i_1_n_12 ;
  wire \fast_starts_reg[16]_i_1_n_13 ;
  wire \fast_starts_reg[16]_i_1_n_14 ;
  wire \fast_starts_reg[16]_i_1_n_15 ;
  wire \fast_starts_reg[16]_i_1_n_2 ;
  wire \fast_starts_reg[16]_i_1_n_3 ;
  wire \fast_starts_reg[16]_i_1_n_4 ;
  wire \fast_starts_reg[16]_i_1_n_5 ;
  wire \fast_starts_reg[16]_i_1_n_6 ;
  wire \fast_starts_reg[16]_i_1_n_7 ;
  wire \fast_starts_reg[16]_i_1_n_8 ;
  wire \fast_starts_reg[16]_i_1_n_9 ;
  wire \fast_starts_reg[24]_i_1_n_1 ;
  wire \fast_starts_reg[24]_i_1_n_10 ;
  wire \fast_starts_reg[24]_i_1_n_11 ;
  wire \fast_starts_reg[24]_i_1_n_12 ;
  wire \fast_starts_reg[24]_i_1_n_13 ;
  wire \fast_starts_reg[24]_i_1_n_14 ;
  wire \fast_starts_reg[24]_i_1_n_15 ;
  wire \fast_starts_reg[24]_i_1_n_2 ;
  wire \fast_starts_reg[24]_i_1_n_3 ;
  wire \fast_starts_reg[24]_i_1_n_4 ;
  wire \fast_starts_reg[24]_i_1_n_5 ;
  wire \fast_starts_reg[24]_i_1_n_6 ;
  wire \fast_starts_reg[24]_i_1_n_7 ;
  wire \fast_starts_reg[24]_i_1_n_8 ;
  wire \fast_starts_reg[24]_i_1_n_9 ;
  wire \fast_starts_reg[8]_i_1_n_0 ;
  wire \fast_starts_reg[8]_i_1_n_1 ;
  wire \fast_starts_reg[8]_i_1_n_10 ;
  wire \fast_starts_reg[8]_i_1_n_11 ;
  wire \fast_starts_reg[8]_i_1_n_12 ;
  wire \fast_starts_reg[8]_i_1_n_13 ;
  wire \fast_starts_reg[8]_i_1_n_14 ;
  wire \fast_starts_reg[8]_i_1_n_15 ;
  wire \fast_starts_reg[8]_i_1_n_2 ;
  wire \fast_starts_reg[8]_i_1_n_3 ;
  wire \fast_starts_reg[8]_i_1_n_4 ;
  wire \fast_starts_reg[8]_i_1_n_5 ;
  wire \fast_starts_reg[8]_i_1_n_6 ;
  wire \fast_starts_reg[8]_i_1_n_7 ;
  wire \fast_starts_reg[8]_i_1_n_8 ;
  wire \fast_starts_reg[8]_i_1_n_9 ;
  wire \header[15]_i_1_n_0 ;
  wire \header[15]_i_3_n_0 ;
  wire \header[15]_i_4_n_0 ;
  wire \header[23]_i_1_n_0 ;
  wire \header[23]_i_3_n_0 ;
  wire \header[23]_i_4_n_0 ;
  wire \header[23]_i_5_n_0 ;
  wire \header[31]_i_1_n_0 ;
  wire \header[31]_i_3_n_0 ;
  wire \header[31]_i_4_n_0 ;
  wire \header[31]_i_5_n_0 ;
  wire \header[31]_i_6_n_0 ;
  wire \header[31]_i_7_n_0 ;
  wire \header[31]_i_8_n_0 ;
  wire \header[7]_i_1_n_0 ;
  wire \header[7]_i_3_n_0 ;
  wire \header_reg_n_0_[0] ;
  wire \header_reg_n_0_[10] ;
  wire \header_reg_n_0_[11] ;
  wire \header_reg_n_0_[12] ;
  wire \header_reg_n_0_[13] ;
  wire \header_reg_n_0_[14] ;
  wire \header_reg_n_0_[15] ;
  wire \header_reg_n_0_[16] ;
  wire \header_reg_n_0_[17] ;
  wire \header_reg_n_0_[18] ;
  wire \header_reg_n_0_[19] ;
  wire \header_reg_n_0_[1] ;
  wire \header_reg_n_0_[20] ;
  wire \header_reg_n_0_[21] ;
  wire \header_reg_n_0_[22] ;
  wire \header_reg_n_0_[23] ;
  wire \header_reg_n_0_[24] ;
  wire \header_reg_n_0_[25] ;
  wire \header_reg_n_0_[26] ;
  wire \header_reg_n_0_[27] ;
  wire \header_reg_n_0_[28] ;
  wire \header_reg_n_0_[29] ;
  wire \header_reg_n_0_[2] ;
  wire \header_reg_n_0_[30] ;
  wire \header_reg_n_0_[31] ;
  wire \header_reg_n_0_[3] ;
  wire \header_reg_n_0_[4] ;
  wire \header_reg_n_0_[5] ;
  wire \header_reg_n_0_[6] ;
  wire \header_reg_n_0_[7] ;
  wire \header_reg_n_0_[8] ;
  wire \header_reg_n_0_[9] ;
  wire \host_quarter[1]_i_1_n_0 ;
  wire \host_quarter[1]_i_2_n_0 ;
  wire \host_quarter[1]_i_3_n_0 ;
  wire \host_quarter[1]_i_4_n_0 ;
  wire \host_quarter[1]_i_5_n_0 ;
  wire \host_quarter[1]_i_6_n_0 ;
  wire \host_quarter_reg_n_0_[0] ;
  wire \host_quarter_reg_n_0_[1] ;
  wire \hr[0]_i_1_n_0 ;
  wire \hr[1]_i_1_n_0 ;
  wire \hr_reg_n_0_[0] ;
  wire \hr_reg_n_0_[1] ;
  wire [31:0]last_cycles;
  wire \last_cycles[0]_i_1_n_0 ;
  wire \last_cycles[31]_i_1_n_0 ;
  wire \last_cycles_reg[16]_i_1_n_0 ;
  wire \last_cycles_reg[16]_i_1_n_1 ;
  wire \last_cycles_reg[16]_i_1_n_10 ;
  wire \last_cycles_reg[16]_i_1_n_11 ;
  wire \last_cycles_reg[16]_i_1_n_12 ;
  wire \last_cycles_reg[16]_i_1_n_13 ;
  wire \last_cycles_reg[16]_i_1_n_14 ;
  wire \last_cycles_reg[16]_i_1_n_15 ;
  wire \last_cycles_reg[16]_i_1_n_2 ;
  wire \last_cycles_reg[16]_i_1_n_3 ;
  wire \last_cycles_reg[16]_i_1_n_4 ;
  wire \last_cycles_reg[16]_i_1_n_5 ;
  wire \last_cycles_reg[16]_i_1_n_6 ;
  wire \last_cycles_reg[16]_i_1_n_7 ;
  wire \last_cycles_reg[16]_i_1_n_8 ;
  wire \last_cycles_reg[16]_i_1_n_9 ;
  wire \last_cycles_reg[24]_i_1_n_0 ;
  wire \last_cycles_reg[24]_i_1_n_1 ;
  wire \last_cycles_reg[24]_i_1_n_10 ;
  wire \last_cycles_reg[24]_i_1_n_11 ;
  wire \last_cycles_reg[24]_i_1_n_12 ;
  wire \last_cycles_reg[24]_i_1_n_13 ;
  wire \last_cycles_reg[24]_i_1_n_14 ;
  wire \last_cycles_reg[24]_i_1_n_15 ;
  wire \last_cycles_reg[24]_i_1_n_2 ;
  wire \last_cycles_reg[24]_i_1_n_3 ;
  wire \last_cycles_reg[24]_i_1_n_4 ;
  wire \last_cycles_reg[24]_i_1_n_5 ;
  wire \last_cycles_reg[24]_i_1_n_6 ;
  wire \last_cycles_reg[24]_i_1_n_7 ;
  wire \last_cycles_reg[24]_i_1_n_8 ;
  wire \last_cycles_reg[24]_i_1_n_9 ;
  wire \last_cycles_reg[31]_i_2_n_10 ;
  wire \last_cycles_reg[31]_i_2_n_11 ;
  wire \last_cycles_reg[31]_i_2_n_12 ;
  wire \last_cycles_reg[31]_i_2_n_13 ;
  wire \last_cycles_reg[31]_i_2_n_14 ;
  wire \last_cycles_reg[31]_i_2_n_15 ;
  wire \last_cycles_reg[31]_i_2_n_2 ;
  wire \last_cycles_reg[31]_i_2_n_3 ;
  wire \last_cycles_reg[31]_i_2_n_4 ;
  wire \last_cycles_reg[31]_i_2_n_5 ;
  wire \last_cycles_reg[31]_i_2_n_6 ;
  wire \last_cycles_reg[31]_i_2_n_7 ;
  wire \last_cycles_reg[31]_i_2_n_9 ;
  wire \last_cycles_reg[8]_i_1_n_0 ;
  wire \last_cycles_reg[8]_i_1_n_1 ;
  wire \last_cycles_reg[8]_i_1_n_10 ;
  wire \last_cycles_reg[8]_i_1_n_11 ;
  wire \last_cycles_reg[8]_i_1_n_12 ;
  wire \last_cycles_reg[8]_i_1_n_13 ;
  wire \last_cycles_reg[8]_i_1_n_14 ;
  wire \last_cycles_reg[8]_i_1_n_15 ;
  wire \last_cycles_reg[8]_i_1_n_2 ;
  wire \last_cycles_reg[8]_i_1_n_3 ;
  wire \last_cycles_reg[8]_i_1_n_4 ;
  wire \last_cycles_reg[8]_i_1_n_5 ;
  wire \last_cycles_reg[8]_i_1_n_6 ;
  wire \last_cycles_reg[8]_i_1_n_7 ;
  wire \last_cycles_reg[8]_i_1_n_8 ;
  wire \last_cycles_reg[8]_i_1_n_9 ;
  wire \last_reply_len_reg_n_0_[0] ;
  wire \last_reply_len_reg_n_0_[10] ;
  wire \last_reply_len_reg_n_0_[11] ;
  wire \last_reply_len_reg_n_0_[12] ;
  wire \last_reply_len_reg_n_0_[13] ;
  wire \last_reply_len_reg_n_0_[14] ;
  wire \last_reply_len_reg_n_0_[15] ;
  wire \last_reply_len_reg_n_0_[1] ;
  wire \last_reply_len_reg_n_0_[2] ;
  wire \last_reply_len_reg_n_0_[3] ;
  wire \last_reply_len_reg_n_0_[4] ;
  wire \last_reply_len_reg_n_0_[5] ;
  wire \last_reply_len_reg_n_0_[6] ;
  wire \last_reply_len_reg_n_0_[7] ;
  wire \last_reply_len_reg_n_0_[8] ;
  wire \last_reply_len_reg_n_0_[9] ;
  wire [7:0]p_0_in;
  wire p_0_in10_in;
  wire p_0_in12_in;
  wire p_0_in14_in;
  wire p_0_in16_in;
  wire p_0_in18_in;
  wire p_0_in20_in;
  wire p_0_in22_in;
  wire p_0_in24_in;
  wire p_0_in26_in;
  wire p_0_in28_in;
  wire p_0_in30_in;
  wire p_0_in4_in;
  wire p_0_in6_in;
  wire p_0_in8_in;
  wire [7:0]p_0_in__0;
  wire p_104_in;
  wire p_105_in;
  wire [6:0]p_1_in;
  wire p_32_in;
  wire p_35_in;
  wire p_38_in;
  wire p_41_in;
  wire p_44_in;
  wire p_47_in;
  wire [31:0]p_4_out;
  wire p_50_in;
  wire p_56_in;
  wire p_59_in;
  wire p_62_in;
  wire p_65_in;
  wire p_68_in;
  wire p_71_in;
  wire p_74_in;
  wire p_80_in;
  wire p_81_in;
  wire \payload_len[10]_i_1_n_0 ;
  wire \payload_len[11]_i_1_n_0 ;
  wire \payload_len[12]_i_1_n_0 ;
  wire \payload_len[13]_i_1_n_0 ;
  wire \payload_len[14]_i_1_n_0 ;
  wire \payload_len[15]_i_1_n_0 ;
  wire \payload_len[15]_i_2_n_0 ;
  wire \payload_len[15]_i_3_n_0 ;
  wire \payload_len[15]_i_4_n_0 ;
  wire \payload_len[15]_i_5_n_0 ;
  wire \payload_len[15]_i_6_n_0 ;
  wire \payload_len[15]_i_7_n_0 ;
  wire \payload_len[7]_i_1_n_0 ;
  wire \payload_len[7]_i_2_n_0 ;
  wire \payload_len[8]_i_1_n_0 ;
  wire \payload_len[9]_i_1_n_0 ;
  wire \payload_len_reg_n_0_[0] ;
  wire \payload_len_reg_n_0_[10] ;
  wire \payload_len_reg_n_0_[11] ;
  wire \payload_len_reg_n_0_[12] ;
  wire \payload_len_reg_n_0_[13] ;
  wire \payload_len_reg_n_0_[14] ;
  wire \payload_len_reg_n_0_[15] ;
  wire \payload_len_reg_n_0_[1] ;
  wire \payload_len_reg_n_0_[2] ;
  wire \payload_len_reg_n_0_[3] ;
  wire \payload_len_reg_n_0_[4] ;
  wire \payload_len_reg_n_0_[5] ;
  wire \payload_len_reg_n_0_[6] ;
  wire \payload_len_reg_n_0_[7] ;
  wire \payload_len_reg_n_0_[8] ;
  wire \payload_len_reg_n_0_[9] ;
  wire queue_active;
  wire [0:0]received;
  wire \received[0]_i_2_n_0 ;
  wire [31:0]received_reg;
  wire \received_reg[0]_i_1_n_0 ;
  wire \received_reg[0]_i_1_n_1 ;
  wire \received_reg[0]_i_1_n_10 ;
  wire \received_reg[0]_i_1_n_11 ;
  wire \received_reg[0]_i_1_n_12 ;
  wire \received_reg[0]_i_1_n_13 ;
  wire \received_reg[0]_i_1_n_14 ;
  wire \received_reg[0]_i_1_n_15 ;
  wire \received_reg[0]_i_1_n_2 ;
  wire \received_reg[0]_i_1_n_3 ;
  wire \received_reg[0]_i_1_n_4 ;
  wire \received_reg[0]_i_1_n_5 ;
  wire \received_reg[0]_i_1_n_6 ;
  wire \received_reg[0]_i_1_n_7 ;
  wire \received_reg[0]_i_1_n_8 ;
  wire \received_reg[0]_i_1_n_9 ;
  wire \received_reg[16]_i_1_n_0 ;
  wire \received_reg[16]_i_1_n_1 ;
  wire \received_reg[16]_i_1_n_10 ;
  wire \received_reg[16]_i_1_n_11 ;
  wire \received_reg[16]_i_1_n_12 ;
  wire \received_reg[16]_i_1_n_13 ;
  wire \received_reg[16]_i_1_n_14 ;
  wire \received_reg[16]_i_1_n_15 ;
  wire \received_reg[16]_i_1_n_2 ;
  wire \received_reg[16]_i_1_n_3 ;
  wire \received_reg[16]_i_1_n_4 ;
  wire \received_reg[16]_i_1_n_5 ;
  wire \received_reg[16]_i_1_n_6 ;
  wire \received_reg[16]_i_1_n_7 ;
  wire \received_reg[16]_i_1_n_8 ;
  wire \received_reg[16]_i_1_n_9 ;
  wire \received_reg[24]_i_1_n_1 ;
  wire \received_reg[24]_i_1_n_10 ;
  wire \received_reg[24]_i_1_n_11 ;
  wire \received_reg[24]_i_1_n_12 ;
  wire \received_reg[24]_i_1_n_13 ;
  wire \received_reg[24]_i_1_n_14 ;
  wire \received_reg[24]_i_1_n_15 ;
  wire \received_reg[24]_i_1_n_2 ;
  wire \received_reg[24]_i_1_n_3 ;
  wire \received_reg[24]_i_1_n_4 ;
  wire \received_reg[24]_i_1_n_5 ;
  wire \received_reg[24]_i_1_n_6 ;
  wire \received_reg[24]_i_1_n_7 ;
  wire \received_reg[24]_i_1_n_8 ;
  wire \received_reg[24]_i_1_n_9 ;
  wire \received_reg[8]_i_1_n_0 ;
  wire \received_reg[8]_i_1_n_1 ;
  wire \received_reg[8]_i_1_n_10 ;
  wire \received_reg[8]_i_1_n_11 ;
  wire \received_reg[8]_i_1_n_12 ;
  wire \received_reg[8]_i_1_n_13 ;
  wire \received_reg[8]_i_1_n_14 ;
  wire \received_reg[8]_i_1_n_15 ;
  wire \received_reg[8]_i_1_n_2 ;
  wire \received_reg[8]_i_1_n_3 ;
  wire \received_reg[8]_i_1_n_4 ;
  wire \received_reg[8]_i_1_n_5 ;
  wire \received_reg[8]_i_1_n_6 ;
  wire \received_reg[8]_i_1_n_7 ;
  wire \received_reg[8]_i_1_n_8 ;
  wire \received_reg[8]_i_1_n_9 ;
  wire [0:0]reply_index;
  wire \reply_index[0]_i_1_n_0 ;
  wire \reply_index[10]_i_1_n_0 ;
  wire \reply_index[10]_i_2_n_0 ;
  wire \reply_index[15]_i_2_n_0 ;
  wire \reply_index[15]_i_3_n_0 ;
  wire \reply_index[15]_i_4_n_0 ;
  wire \reply_index[15]_i_5_n_0 ;
  wire \reply_index[15]_i_6_n_0 ;
  wire \reply_index[15]_i_7_n_0 ;
  wire \reply_index[15]_i_8_n_0 ;
  wire \reply_index[1]_i_1_n_0 ;
  wire \reply_index[2]_i_1_n_0 ;
  wire \reply_index[3]_i_1_n_0 ;
  wire \reply_index[4]_i_1_n_0 ;
  wire \reply_index[5]_i_1_n_0 ;
  wire \reply_index[6]_i_1_n_0 ;
  wire \reply_index[6]_i_2_n_0 ;
  wire \reply_index[7]_i_1_n_0 ;
  wire \reply_index[8]_i_1_n_0 ;
  wire \reply_index[9]_i_1_n_0 ;
  wire \reply_index[9]_i_2_n_0 ;
  wire \reply_index_reg_n_0_[0] ;
  wire \reply_index_reg_n_0_[10] ;
  wire \reply_index_reg_n_0_[15] ;
  wire \reply_index_reg_n_0_[1] ;
  wire \reply_index_reg_n_0_[2] ;
  wire \reply_index_reg_n_0_[3] ;
  wire \reply_index_reg_n_0_[4] ;
  wire \reply_index_reg_n_0_[5] ;
  wire \reply_index_reg_n_0_[6] ;
  wire \reply_index_reg_n_0_[7] ;
  wire \reply_index_reg_n_0_[8] ;
  wire \reply_index_reg_n_0_[9] ;
  wire \reply_len[0]_i_1_n_0 ;
  wire \reply_len[0]_i_2_n_0 ;
  wire \reply_len[10]_i_1_n_0 ;
  wire \reply_len[10]_i_2_n_0 ;
  wire \reply_len[10]_i_3_n_0 ;
  wire \reply_len[10]_i_4_n_0 ;
  wire \reply_len[10]_i_5_n_0 ;
  wire \reply_len[10]_i_6_n_0 ;
  wire \reply_len[11]_i_1_n_0 ;
  wire \reply_len[11]_i_2_n_0 ;
  wire \reply_len[12]_i_1_n_0 ;
  wire \reply_len[13]_i_1_n_0 ;
  wire \reply_len[13]_i_2_n_0 ;
  wire \reply_len[13]_i_3_n_0 ;
  wire \reply_len[14]_i_1_n_0 ;
  wire \reply_len[15]_i_1_n_0 ;
  wire \reply_len[15]_i_2_n_0 ;
  wire \reply_len[15]_i_3_n_0 ;
  wire \reply_len[15]_i_4_n_0 ;
  wire \reply_len[15]_i_5_n_0 ;
  wire \reply_len[15]_i_6_n_0 ;
  wire \reply_len[15]_i_7_n_0 ;
  wire \reply_len[15]_i_8_n_0 ;
  wire \reply_len[15]_i_9_n_0 ;
  wire \reply_len[1]_i_1_n_0 ;
  wire \reply_len[1]_i_2_n_0 ;
  wire \reply_len[2]_i_1_n_0 ;
  wire \reply_len[2]_i_2_n_0 ;
  wire \reply_len[3]_i_1_n_0 ;
  wire \reply_len[3]_i_2_n_0 ;
  wire \reply_len[3]_i_3_n_0 ;
  wire \reply_len[4]_i_1_n_0 ;
  wire \reply_len[4]_i_2_n_0 ;
  wire \reply_len[4]_i_3_n_0 ;
  wire \reply_len[5]_i_1_n_0 ;
  wire \reply_len[5]_i_2_n_0 ;
  wire \reply_len[5]_i_3_n_0 ;
  wire \reply_len[6]_i_1_n_0 ;
  wire \reply_len[6]_i_2_n_0 ;
  wire \reply_len[6]_i_3_n_0 ;
  wire \reply_len[7]_i_1_n_0 ;
  wire \reply_len[7]_i_2_n_0 ;
  wire \reply_len[7]_i_3_n_0 ;
  wire \reply_len[7]_i_4_n_0 ;
  wire \reply_len[7]_i_5_n_0 ;
  wire \reply_len[7]_i_6_n_0 ;
  wire \reply_len[8]_i_1_n_0 ;
  wire \reply_len[8]_i_2_n_0 ;
  wire \reply_len[8]_i_3_n_0 ;
  wire \reply_len[8]_i_4_n_0 ;
  wire \reply_len[9]_i_1_n_0 ;
  wire \reply_len[9]_i_2_n_0 ;
  wire \reply_len[9]_i_3_n_0 ;
  wire \reply_len[9]_i_4_n_0 ;
  wire \reply_len_reg_n_0_[10] ;
  wire \reply_len_reg_n_0_[11] ;
  wire \reply_len_reg_n_0_[12] ;
  wire \reply_len_reg_n_0_[13] ;
  wire \reply_len_reg_n_0_[14] ;
  wire \reply_len_reg_n_0_[15] ;
  wire \reply_len_reg_n_0_[8] ;
  wire \reply_len_reg_n_0_[9] ;
  wire reply_mem_reg_0_i_10_n_0;
  wire reply_mem_reg_0_i_11_n_0;
  wire reply_mem_reg_0_i_12_n_0;
  wire reply_mem_reg_0_i_13_n_0;
  wire reply_mem_reg_0_i_14_n_0;
  wire reply_mem_reg_0_i_15_n_0;
  wire reply_mem_reg_0_i_16_n_0;
  wire reply_mem_reg_0_i_17_n_0;
  wire reply_mem_reg_0_i_18_n_0;
  wire reply_mem_reg_0_i_19_n_0;
  wire reply_mem_reg_0_i_20_n_0;
  wire reply_mem_reg_0_i_21_n_0;
  wire reply_mem_reg_0_i_22_n_0;
  wire reply_mem_reg_0_i_23_n_0;
  wire reply_mem_reg_0_i_24_n_0;
  wire reply_mem_reg_0_i_25_n_0;
  wire reply_mem_reg_0_i_26_n_0;
  wire reply_mem_reg_0_i_27_n_0;
  wire reply_mem_reg_0_i_28_n_0;
  wire reply_mem_reg_0_i_29_n_0;
  wire reply_mem_reg_0_i_2_n_0;
  wire reply_mem_reg_0_i_30_n_0;
  wire reply_mem_reg_0_i_31_n_0;
  wire reply_mem_reg_0_i_32_n_0;
  wire reply_mem_reg_0_i_33_n_0;
  wire reply_mem_reg_0_i_48_n_0;
  wire reply_mem_reg_0_i_49_n_0;
  wire reply_mem_reg_0_i_50_n_0;
  wire reply_mem_reg_0_i_51_n_0;
  wire reply_mem_reg_0_i_52_n_0;
  wire reply_mem_reg_0_i_53_n_0;
  wire reply_mem_reg_0_i_54_n_0;
  wire reply_mem_reg_0_i_55_n_0;
  wire reply_mem_reg_0_i_56_n_0;
  wire reply_mem_reg_0_i_57_n_0;
  wire reply_mem_reg_1_i_10_n_0;
  wire reply_mem_reg_1_i_11_n_0;
  wire reply_mem_reg_1_i_12_n_0;
  wire reply_mem_reg_1_i_9_n_0;
  wire [7:0]reply_q;
  wire [6:0]reply_wa;
  wire reply_we;
  wire \request_len[0]_i_1_n_0 ;
  wire \request_len[10]_i_1_n_0 ;
  wire \request_len[11]_i_1_n_0 ;
  wire \request_len[12]_i_1_n_0 ;
  wire \request_len[13]_i_1_n_0 ;
  wire \request_len[14]_i_1_n_0 ;
  wire \request_len[15]_i_10_n_0 ;
  wire \request_len[15]_i_11_n_0 ;
  wire \request_len[15]_i_12_n_0 ;
  wire \request_len[15]_i_13_n_0 ;
  wire \request_len[15]_i_14_n_0 ;
  wire \request_len[15]_i_15_n_0 ;
  wire \request_len[15]_i_16_n_0 ;
  wire \request_len[15]_i_17_n_0 ;
  wire \request_len[15]_i_18_n_0 ;
  wire \request_len[15]_i_19_n_0 ;
  wire \request_len[15]_i_20_n_0 ;
  wire \request_len[15]_i_21_n_0 ;
  wire \request_len[15]_i_22_n_0 ;
  wire \request_len[15]_i_23_n_0 ;
  wire \request_len[15]_i_2_n_0 ;
  wire \request_len[15]_i_3_n_0 ;
  wire \request_len[15]_i_5_n_0 ;
  wire \request_len[15]_i_6_n_0 ;
  wire \request_len[15]_i_7_n_0 ;
  wire \request_len[15]_i_8_n_0 ;
  wire \request_len[15]_i_9_n_0 ;
  wire \request_len[1]_i_1_n_0 ;
  wire \request_len[2]_i_1_n_0 ;
  wire \request_len[3]_i_1_n_0 ;
  wire \request_len[4]_i_1_n_0 ;
  wire \request_len[5]_i_1_n_0 ;
  wire \request_len[6]_i_1_n_0 ;
  wire \request_len[7]_i_1_n_0 ;
  wire \request_len[8]_i_1_n_0 ;
  wire \request_len[9]_i_1_n_0 ;
  wire [15:0]request_len__0;
  wire \request_len_reg[15]_i_4_n_3 ;
  wire \request_len_reg[15]_i_4_n_4 ;
  wire \request_len_reg[15]_i_4_n_5 ;
  wire \request_len_reg[15]_i_4_n_6 ;
  wire \request_len_reg[15]_i_4_n_7 ;
  wire request_mem_reg_0_i_10_n_0;
  wire request_mem_reg_0_i_18_n_0;
  wire request_mem_reg_0_i_19_n_0;
  wire request_mem_reg_0_i_20_n_0;
  wire [127:0]request_q;
  wire request_q0;
  wire [6:0]request_q1;
  wire rst_n;
  wire [7:0]rx_data;
  wire rx_error;
  wire rx_valid;
  wire [23:0]s_axi_araddr;
  wire s_axi_arready;
  wire s_axi_arvalid;
  wire [23:0]s_axi_awaddr;
  wire s_axi_awready;
  wire s_axi_awvalid;
  wire s_axi_bready;
  wire [0:0]s_axi_bresp;
  wire \s_axi_bresp[1]_i_10_n_0 ;
  wire \s_axi_bresp[1]_i_11_n_0 ;
  wire \s_axi_bresp[1]_i_12_n_0 ;
  wire \s_axi_bresp[1]_i_13_n_0 ;
  wire \s_axi_bresp[1]_i_14_n_0 ;
  wire \s_axi_bresp[1]_i_15_n_0 ;
  wire \s_axi_bresp[1]_i_16_n_0 ;
  wire \s_axi_bresp[1]_i_17_n_0 ;
  wire \s_axi_bresp[1]_i_18_n_0 ;
  wire \s_axi_bresp[1]_i_19_n_0 ;
  wire \s_axi_bresp[1]_i_1_n_0 ;
  wire \s_axi_bresp[1]_i_20_n_0 ;
  wire \s_axi_bresp[1]_i_21_n_0 ;
  wire \s_axi_bresp[1]_i_2_n_0 ;
  wire \s_axi_bresp[1]_i_3_n_0 ;
  wire \s_axi_bresp[1]_i_4_n_0 ;
  wire \s_axi_bresp[1]_i_5_n_0 ;
  wire \s_axi_bresp[1]_i_7_n_0 ;
  wire \s_axi_bresp[1]_i_8_n_0 ;
  wire \s_axi_bresp[1]_i_9_n_0 ;
  wire s_axi_bvalid_i_1_n_0;
  wire s_axi_bvalid_reg_0;
  wire [31:0]s_axi_rdata;
  wire \s_axi_rdata[0]_i_1_n_0 ;
  wire \s_axi_rdata[0]_i_2_n_0 ;
  wire \s_axi_rdata[0]_i_3_n_0 ;
  wire \s_axi_rdata[0]_i_4_n_0 ;
  wire \s_axi_rdata[0]_i_5_n_0 ;
  wire \s_axi_rdata[0]_i_6_n_0 ;
  wire \s_axi_rdata[0]_i_7_n_0 ;
  wire \s_axi_rdata[0]_i_8_n_0 ;
  wire \s_axi_rdata[10]_i_1_n_0 ;
  wire \s_axi_rdata[10]_i_2_n_0 ;
  wire \s_axi_rdata[10]_i_3_n_0 ;
  wire \s_axi_rdata[10]_i_4_n_0 ;
  wire \s_axi_rdata[10]_i_5_n_0 ;
  wire \s_axi_rdata[10]_i_6_n_0 ;
  wire \s_axi_rdata[11]_i_1_n_0 ;
  wire \s_axi_rdata[11]_i_2_n_0 ;
  wire \s_axi_rdata[11]_i_3_n_0 ;
  wire \s_axi_rdata[11]_i_4_n_0 ;
  wire \s_axi_rdata[11]_i_5_n_0 ;
  wire \s_axi_rdata[11]_i_6_n_0 ;
  wire \s_axi_rdata[12]_i_1_n_0 ;
  wire \s_axi_rdata[12]_i_2_n_0 ;
  wire \s_axi_rdata[12]_i_3_n_0 ;
  wire \s_axi_rdata[12]_i_4_n_0 ;
  wire \s_axi_rdata[12]_i_5_n_0 ;
  wire \s_axi_rdata[12]_i_6_n_0 ;
  wire \s_axi_rdata[13]_i_1_n_0 ;
  wire \s_axi_rdata[13]_i_2_n_0 ;
  wire \s_axi_rdata[13]_i_3_n_0 ;
  wire \s_axi_rdata[13]_i_4_n_0 ;
  wire \s_axi_rdata[13]_i_5_n_0 ;
  wire \s_axi_rdata[13]_i_6_n_0 ;
  wire \s_axi_rdata[14]_i_1_n_0 ;
  wire \s_axi_rdata[14]_i_2_n_0 ;
  wire \s_axi_rdata[14]_i_3_n_0 ;
  wire \s_axi_rdata[14]_i_4_n_0 ;
  wire \s_axi_rdata[14]_i_5_n_0 ;
  wire \s_axi_rdata[14]_i_6_n_0 ;
  wire \s_axi_rdata[15]_i_1_n_0 ;
  wire \s_axi_rdata[15]_i_2_n_0 ;
  wire \s_axi_rdata[15]_i_3_n_0 ;
  wire \s_axi_rdata[15]_i_4_n_0 ;
  wire \s_axi_rdata[15]_i_5_n_0 ;
  wire \s_axi_rdata[15]_i_6_n_0 ;
  wire \s_axi_rdata[15]_i_7_n_0 ;
  wire \s_axi_rdata[16]_i_1_n_0 ;
  wire \s_axi_rdata[16]_i_2_n_0 ;
  wire \s_axi_rdata[16]_i_3_n_0 ;
  wire \s_axi_rdata[16]_i_4_n_0 ;
  wire \s_axi_rdata[16]_i_5_n_0 ;
  wire \s_axi_rdata[17]_i_1_n_0 ;
  wire \s_axi_rdata[17]_i_2_n_0 ;
  wire \s_axi_rdata[17]_i_3_n_0 ;
  wire \s_axi_rdata[17]_i_4_n_0 ;
  wire \s_axi_rdata[17]_i_5_n_0 ;
  wire \s_axi_rdata[18]_i_1_n_0 ;
  wire \s_axi_rdata[18]_i_2_n_0 ;
  wire \s_axi_rdata[18]_i_3_n_0 ;
  wire \s_axi_rdata[18]_i_4_n_0 ;
  wire \s_axi_rdata[18]_i_5_n_0 ;
  wire \s_axi_rdata[19]_i_1_n_0 ;
  wire \s_axi_rdata[19]_i_2_n_0 ;
  wire \s_axi_rdata[19]_i_3_n_0 ;
  wire \s_axi_rdata[19]_i_4_n_0 ;
  wire \s_axi_rdata[19]_i_5_n_0 ;
  wire \s_axi_rdata[1]_i_1_n_0 ;
  wire \s_axi_rdata[1]_i_2_n_0 ;
  wire \s_axi_rdata[1]_i_3_n_0 ;
  wire \s_axi_rdata[1]_i_4_n_0 ;
  wire \s_axi_rdata[1]_i_5_n_0 ;
  wire \s_axi_rdata[1]_i_6_n_0 ;
  wire \s_axi_rdata[1]_i_7_n_0 ;
  wire \s_axi_rdata[1]_i_8_n_0 ;
  wire \s_axi_rdata[1]_i_9_n_0 ;
  wire \s_axi_rdata[20]_i_1_n_0 ;
  wire \s_axi_rdata[20]_i_2_n_0 ;
  wire \s_axi_rdata[20]_i_3_n_0 ;
  wire \s_axi_rdata[20]_i_4_n_0 ;
  wire \s_axi_rdata[20]_i_5_n_0 ;
  wire \s_axi_rdata[21]_i_1_n_0 ;
  wire \s_axi_rdata[21]_i_2_n_0 ;
  wire \s_axi_rdata[21]_i_3_n_0 ;
  wire \s_axi_rdata[21]_i_4_n_0 ;
  wire \s_axi_rdata[21]_i_5_n_0 ;
  wire \s_axi_rdata[22]_i_1_n_0 ;
  wire \s_axi_rdata[22]_i_2_n_0 ;
  wire \s_axi_rdata[22]_i_3_n_0 ;
  wire \s_axi_rdata[22]_i_4_n_0 ;
  wire \s_axi_rdata[22]_i_5_n_0 ;
  wire \s_axi_rdata[23]_i_1_n_0 ;
  wire \s_axi_rdata[23]_i_2_n_0 ;
  wire \s_axi_rdata[23]_i_3_n_0 ;
  wire \s_axi_rdata[23]_i_4_n_0 ;
  wire \s_axi_rdata[23]_i_5_n_0 ;
  wire \s_axi_rdata[24]_i_1_n_0 ;
  wire \s_axi_rdata[24]_i_2_n_0 ;
  wire \s_axi_rdata[24]_i_3_n_0 ;
  wire \s_axi_rdata[24]_i_4_n_0 ;
  wire \s_axi_rdata[24]_i_5_n_0 ;
  wire \s_axi_rdata[25]_i_1_n_0 ;
  wire \s_axi_rdata[25]_i_2_n_0 ;
  wire \s_axi_rdata[25]_i_3_n_0 ;
  wire \s_axi_rdata[25]_i_4_n_0 ;
  wire \s_axi_rdata[25]_i_5_n_0 ;
  wire \s_axi_rdata[26]_i_1_n_0 ;
  wire \s_axi_rdata[26]_i_2_n_0 ;
  wire \s_axi_rdata[26]_i_3_n_0 ;
  wire \s_axi_rdata[26]_i_4_n_0 ;
  wire \s_axi_rdata[26]_i_5_n_0 ;
  wire \s_axi_rdata[27]_i_1_n_0 ;
  wire \s_axi_rdata[27]_i_2_n_0 ;
  wire \s_axi_rdata[27]_i_3_n_0 ;
  wire \s_axi_rdata[27]_i_4_n_0 ;
  wire \s_axi_rdata[27]_i_5_n_0 ;
  wire \s_axi_rdata[28]_i_1_n_0 ;
  wire \s_axi_rdata[28]_i_2_n_0 ;
  wire \s_axi_rdata[28]_i_3_n_0 ;
  wire \s_axi_rdata[28]_i_4_n_0 ;
  wire \s_axi_rdata[28]_i_5_n_0 ;
  wire \s_axi_rdata[28]_i_6_n_0 ;
  wire \s_axi_rdata[29]_i_1_n_0 ;
  wire \s_axi_rdata[29]_i_2_n_0 ;
  wire \s_axi_rdata[29]_i_3_n_0 ;
  wire \s_axi_rdata[29]_i_4_n_0 ;
  wire \s_axi_rdata[29]_i_5_n_0 ;
  wire \s_axi_rdata[2]_i_1_n_0 ;
  wire \s_axi_rdata[2]_i_2_n_0 ;
  wire \s_axi_rdata[2]_i_3_n_0 ;
  wire \s_axi_rdata[2]_i_4_n_0 ;
  wire \s_axi_rdata[2]_i_5_n_0 ;
  wire \s_axi_rdata[2]_i_6_n_0 ;
  wire \s_axi_rdata[2]_i_7_n_0 ;
  wire \s_axi_rdata[2]_i_8_n_0 ;
  wire \s_axi_rdata[2]_i_9_n_0 ;
  wire \s_axi_rdata[30]_i_1_n_0 ;
  wire \s_axi_rdata[30]_i_2_n_0 ;
  wire \s_axi_rdata[30]_i_3_n_0 ;
  wire \s_axi_rdata[30]_i_4_n_0 ;
  wire \s_axi_rdata[30]_i_5_n_0 ;
  wire \s_axi_rdata[30]_i_6_n_0 ;
  wire \s_axi_rdata[31]_i_10_n_0 ;
  wire \s_axi_rdata[31]_i_11_n_0 ;
  wire \s_axi_rdata[31]_i_12_n_0 ;
  wire \s_axi_rdata[31]_i_1_n_0 ;
  wire \s_axi_rdata[31]_i_2_n_0 ;
  wire \s_axi_rdata[31]_i_3_n_0 ;
  wire \s_axi_rdata[31]_i_5_n_0 ;
  wire \s_axi_rdata[31]_i_6_n_0 ;
  wire \s_axi_rdata[31]_i_7_n_0 ;
  wire \s_axi_rdata[31]_i_8_n_0 ;
  wire \s_axi_rdata[31]_i_9_n_0 ;
  wire \s_axi_rdata[3]_i_1_n_0 ;
  wire \s_axi_rdata[3]_i_2_n_0 ;
  wire \s_axi_rdata[3]_i_3_n_0 ;
  wire \s_axi_rdata[3]_i_4_n_0 ;
  wire \s_axi_rdata[3]_i_5_n_0 ;
  wire \s_axi_rdata[3]_i_6_n_0 ;
  wire \s_axi_rdata[4]_i_1_n_0 ;
  wire \s_axi_rdata[4]_i_2_n_0 ;
  wire \s_axi_rdata[4]_i_3_n_0 ;
  wire \s_axi_rdata[4]_i_4_n_0 ;
  wire \s_axi_rdata[4]_i_5_n_0 ;
  wire \s_axi_rdata[4]_i_6_n_0 ;
  wire \s_axi_rdata[5]_i_1_n_0 ;
  wire \s_axi_rdata[5]_i_2_n_0 ;
  wire \s_axi_rdata[5]_i_3_n_0 ;
  wire \s_axi_rdata[5]_i_4_n_0 ;
  wire \s_axi_rdata[5]_i_5_n_0 ;
  wire \s_axi_rdata[5]_i_6_n_0 ;
  wire \s_axi_rdata[6]_i_1_n_0 ;
  wire \s_axi_rdata[6]_i_2_n_0 ;
  wire \s_axi_rdata[6]_i_3_n_0 ;
  wire \s_axi_rdata[6]_i_4_n_0 ;
  wire \s_axi_rdata[6]_i_5_n_0 ;
  wire \s_axi_rdata[6]_i_6_n_0 ;
  wire \s_axi_rdata[7]_i_1_n_0 ;
  wire \s_axi_rdata[7]_i_2_n_0 ;
  wire \s_axi_rdata[7]_i_3_n_0 ;
  wire \s_axi_rdata[7]_i_4_n_0 ;
  wire \s_axi_rdata[7]_i_5_n_0 ;
  wire \s_axi_rdata[7]_i_6_n_0 ;
  wire \s_axi_rdata[8]_i_1_n_0 ;
  wire \s_axi_rdata[8]_i_2_n_0 ;
  wire \s_axi_rdata[8]_i_3_n_0 ;
  wire \s_axi_rdata[8]_i_4_n_0 ;
  wire \s_axi_rdata[8]_i_5_n_0 ;
  wire \s_axi_rdata[8]_i_6_n_0 ;
  wire \s_axi_rdata[9]_i_1_n_0 ;
  wire \s_axi_rdata[9]_i_2_n_0 ;
  wire \s_axi_rdata[9]_i_3_n_0 ;
  wire \s_axi_rdata[9]_i_4_n_0 ;
  wire \s_axi_rdata[9]_i_5_n_0 ;
  wire \s_axi_rdata[9]_i_6_n_0 ;
  wire s_axi_rready;
  wire [0:0]s_axi_rresp;
  wire \s_axi_rresp[1]_i_1_n_0 ;
  wire \s_axi_rresp[1]_i_2_n_0 ;
  wire \s_axi_rresp[1]_i_3_n_0 ;
  wire s_axi_rvalid_i_1_n_0;
  wire s_axi_rvalid_i_2_n_0;
  wire s_axi_rvalid_i_3_n_0;
  wire s_axi_rvalid_reg_0;
  wire [31:0]s_axi_wdata;
  wire s_axi_wready;
  wire [3:0]s_axi_wstrb;
  wire s_axi_wvalid;
  wire state1;
  wire state2;
  wire state23_out;
  wire \state[0]_i_1_n_0 ;
  wire \state[0]_i_2_n_0 ;
  wire \state[0]_i_3_n_0 ;
  wire \state[1]_i_10_n_0 ;
  wire \state[1]_i_11_n_0 ;
  wire \state[1]_i_12_n_0 ;
  wire \state[1]_i_13_n_0 ;
  wire \state[1]_i_14_n_0 ;
  wire \state[1]_i_15_n_0 ;
  wire \state[1]_i_16_n_0 ;
  wire \state[1]_i_17_n_0 ;
  wire \state[1]_i_18_n_0 ;
  wire \state[1]_i_19_n_0 ;
  wire \state[1]_i_1_n_0 ;
  wire \state[1]_i_20_n_0 ;
  wire \state[1]_i_21_n_0 ;
  wire \state[1]_i_22_n_0 ;
  wire \state[1]_i_23_n_0 ;
  wire \state[1]_i_24_n_0 ;
  wire \state[1]_i_2_n_0 ;
  wire \state[1]_i_4_n_0 ;
  wire \state[1]_i_5_n_0 ;
  wire \state[1]_i_6_n_0 ;
  wire \state[1]_i_7_n_0 ;
  wire \state[1]_i_8_n_0 ;
  wire \state[1]_i_9_n_0 ;
  wire \state[2]_i_10_n_0 ;
  wire \state[2]_i_11_n_0 ;
  wire \state[2]_i_12_n_0 ;
  wire \state[2]_i_13_n_0 ;
  wire \state[2]_i_14_n_0 ;
  wire \state[2]_i_15_n_0 ;
  wire \state[2]_i_16_n_0 ;
  wire \state[2]_i_1_n_0 ;
  wire \state[2]_i_2_n_0 ;
  wire \state[2]_i_3_n_0 ;
  wire \state[2]_i_4_n_0 ;
  wire \state[2]_i_5_n_0 ;
  wire \state[2]_i_6_n_0 ;
  wire \state[2]_i_7_n_0 ;
  wire \state[2]_i_8_n_0 ;
  wire \state[2]_i_9_n_0 ;
  wire \state[3]_i_10_n_0 ;
  wire \state[3]_i_11_n_0 ;
  wire \state[3]_i_12_n_0 ;
  wire \state[3]_i_13_n_0 ;
  wire \state[3]_i_14_n_0 ;
  wire \state[3]_i_15_n_0 ;
  wire \state[3]_i_17_n_0 ;
  wire \state[3]_i_18_n_0 ;
  wire \state[3]_i_19_n_0 ;
  wire \state[3]_i_1_n_0 ;
  wire \state[3]_i_20_n_0 ;
  wire \state[3]_i_21_n_0 ;
  wire \state[3]_i_22_n_0 ;
  wire \state[3]_i_23_n_0 ;
  wire \state[3]_i_24_n_0 ;
  wire \state[3]_i_25_n_0 ;
  wire \state[3]_i_26_n_0 ;
  wire \state[3]_i_27_n_0 ;
  wire \state[3]_i_28_n_0 ;
  wire \state[3]_i_29_n_0 ;
  wire \state[3]_i_2_n_0 ;
  wire \state[3]_i_30_n_0 ;
  wire \state[3]_i_31_n_0 ;
  wire \state[3]_i_32_n_0 ;
  wire \state[3]_i_33_n_0 ;
  wire \state[3]_i_34_n_0 ;
  wire \state[3]_i_35_n_0 ;
  wire \state[3]_i_36_n_0 ;
  wire \state[3]_i_37_n_0 ;
  wire \state[3]_i_38_n_0 ;
  wire \state[3]_i_39_n_0 ;
  wire \state[3]_i_3_n_0 ;
  wire \state[3]_i_40_n_0 ;
  wire \state[3]_i_41_n_0 ;
  wire \state[3]_i_42_n_0 ;
  wire \state[3]_i_43_n_0 ;
  wire \state[3]_i_44_n_0 ;
  wire \state[3]_i_4_n_0 ;
  wire \state[3]_i_5_n_0 ;
  wire \state[3]_i_6_n_0 ;
  wire \state[3]_i_7_n_0 ;
  wire \state[3]_i_8_n_0 ;
  wire \state_reg[1]_0 ;
  wire \state_reg[1]_i_3_n_2 ;
  wire \state_reg[1]_i_3_n_3 ;
  wire \state_reg[1]_i_3_n_4 ;
  wire \state_reg[1]_i_3_n_5 ;
  wire \state_reg[1]_i_3_n_6 ;
  wire \state_reg[1]_i_3_n_7 ;
  wire \state_reg[3]_i_16_n_3 ;
  wire \state_reg[3]_i_16_n_4 ;
  wire \state_reg[3]_i_16_n_5 ;
  wire \state_reg[3]_i_16_n_6 ;
  wire \state_reg[3]_i_16_n_7 ;
  wire \state_reg[3]_i_9_n_3 ;
  wire \state_reg[3]_i_9_n_4 ;
  wire \state_reg[3]_i_9_n_5 ;
  wire \state_reg[3]_i_9_n_6 ;
  wire \state_reg[3]_i_9_n_7 ;
  wire \state_reg_n_0_[0] ;
  wire \state_reg_n_0_[1] ;
  wire \state_reg_n_0_[2] ;
  wire \state_reg_n_0_[3] ;
  wire [7:0]tx_data;
  wire \tx_data[0]_INST_0_i_1_n_0 ;
  wire \tx_data[0]_INST_0_i_2_n_0 ;
  wire \tx_data[0]_INST_0_i_3_n_0 ;
  wire \tx_data[0]_INST_0_i_4_n_0 ;
  wire \tx_data[0]_INST_0_i_5_n_0 ;
  wire \tx_data[0]_INST_0_i_6_n_0 ;
  wire \tx_data[1]_INST_0_i_1_n_0 ;
  wire \tx_data[1]_INST_0_i_2_n_0 ;
  wire \tx_data[1]_INST_0_i_3_n_0 ;
  wire \tx_data[1]_INST_0_i_4_n_0 ;
  wire \tx_data[1]_INST_0_i_5_n_0 ;
  wire \tx_data[1]_INST_0_i_6_n_0 ;
  wire \tx_data[2]_INST_0_i_1_n_0 ;
  wire \tx_data[2]_INST_0_i_2_n_0 ;
  wire \tx_data[2]_INST_0_i_3_n_0 ;
  wire \tx_data[2]_INST_0_i_4_n_0 ;
  wire \tx_data[2]_INST_0_i_5_n_0 ;
  wire \tx_data[2]_INST_0_i_6_n_0 ;
  wire \tx_data[3]_INST_0_i_1_n_0 ;
  wire \tx_data[3]_INST_0_i_2_n_0 ;
  wire \tx_data[3]_INST_0_i_3_n_0 ;
  wire \tx_data[3]_INST_0_i_4_n_0 ;
  wire \tx_data[3]_INST_0_i_5_n_0 ;
  wire \tx_data[3]_INST_0_i_6_n_0 ;
  wire \tx_data[4]_INST_0_i_1_n_0 ;
  wire \tx_data[4]_INST_0_i_2_n_0 ;
  wire \tx_data[4]_INST_0_i_3_n_0 ;
  wire \tx_data[4]_INST_0_i_4_n_0 ;
  wire \tx_data[4]_INST_0_i_5_n_0 ;
  wire \tx_data[4]_INST_0_i_6_n_0 ;
  wire \tx_data[5]_INST_0_i_1_n_0 ;
  wire \tx_data[5]_INST_0_i_2_n_0 ;
  wire \tx_data[5]_INST_0_i_3_n_0 ;
  wire \tx_data[5]_INST_0_i_4_n_0 ;
  wire \tx_data[5]_INST_0_i_5_n_0 ;
  wire \tx_data[5]_INST_0_i_6_n_0 ;
  wire \tx_data[6]_INST_0_i_1_n_0 ;
  wire \tx_data[6]_INST_0_i_2_n_0 ;
  wire \tx_data[6]_INST_0_i_3_n_0 ;
  wire \tx_data[6]_INST_0_i_4_n_0 ;
  wire \tx_data[6]_INST_0_i_5_n_0 ;
  wire \tx_data[6]_INST_0_i_6_n_0 ;
  wire \tx_data[7]_INST_0_i_1_n_0 ;
  wire \tx_data[7]_INST_0_i_2_n_0 ;
  wire \tx_data[7]_INST_0_i_3_n_0 ;
  wire \tx_data[7]_INST_0_i_4_n_0 ;
  wire \tx_data[7]_INST_0_i_5_n_0 ;
  wire \tx_data[7]_INST_0_i_6_n_0 ;
  wire [10:4]tx_index;
  wire \tx_index[11]_i_2_n_0 ;
  wire \tx_index[13]_i_2_n_0 ;
  wire \tx_index[13]_i_3_n_0 ;
  wire \tx_index[15]_i_10_n_0 ;
  wire \tx_index[15]_i_11_n_0 ;
  wire \tx_index[15]_i_12_n_0 ;
  wire \tx_index[15]_i_13_n_0 ;
  wire \tx_index[15]_i_14_n_0 ;
  wire \tx_index[15]_i_15_n_0 ;
  wire \tx_index[15]_i_16_n_0 ;
  wire \tx_index[15]_i_17_n_0 ;
  wire \tx_index[15]_i_1_n_0 ;
  wire \tx_index[15]_i_3_n_0 ;
  wire \tx_index[15]_i_4_n_0 ;
  wire \tx_index[15]_i_5_n_0 ;
  wire \tx_index[15]_i_6_n_0 ;
  wire \tx_index[15]_i_7_n_0 ;
  wire \tx_index[15]_i_8_n_0 ;
  wire \tx_index[15]_i_9_n_0 ;
  wire \tx_index[4]_i_2_n_0 ;
  wire \tx_index[7]_i_2_n_0 ;
  wire [15:0]tx_index__0;
  wire \tx_index_reg_n_0_[0] ;
  wire \tx_index_reg_n_0_[10] ;
  wire \tx_index_reg_n_0_[11] ;
  wire \tx_index_reg_n_0_[12] ;
  wire \tx_index_reg_n_0_[13] ;
  wire \tx_index_reg_n_0_[14] ;
  wire \tx_index_reg_n_0_[15] ;
  wire \tx_index_reg_n_0_[1] ;
  wire \tx_index_reg_n_0_[2] ;
  wire \tx_index_reg_n_0_[3] ;
  wire \tx_index_reg_n_0_[4] ;
  wire \tx_index_reg_n_0_[5] ;
  wire \tx_index_reg_n_0_[6] ;
  wire \tx_index_reg_n_0_[7] ;
  wire \tx_index_reg_n_0_[8] ;
  wire \tx_index_reg_n_0_[9] ;
  wire tx_ready;
  wire tx_valid;
  wire w_full0;
  wire w_full_i_1_n_0;
  wire w_full_reg_n_0;
  wire [31:0]watchdog;
  wire [31:1]watchdog0;
  wire \watchdog[0]_i_1_n_0 ;
  wire \watchdog[10]_i_1_n_0 ;
  wire \watchdog[11]_i_1_n_0 ;
  wire \watchdog[12]_i_1_n_0 ;
  wire \watchdog[13]_i_1_n_0 ;
  wire \watchdog[14]_i_1_n_0 ;
  wire \watchdog[15]_i_1_n_0 ;
  wire \watchdog[16]_i_1_n_0 ;
  wire \watchdog[17]_i_1_n_0 ;
  wire \watchdog[18]_i_1_n_0 ;
  wire \watchdog[19]_i_1_n_0 ;
  wire \watchdog[1]_i_1_n_0 ;
  wire \watchdog[20]_i_1_n_0 ;
  wire \watchdog[21]_i_1_n_0 ;
  wire \watchdog[22]_i_1_n_0 ;
  wire \watchdog[23]_i_1_n_0 ;
  wire \watchdog[24]_i_1_n_0 ;
  wire \watchdog[25]_i_1_n_0 ;
  wire \watchdog[26]_i_1_n_0 ;
  wire \watchdog[27]_i_1_n_0 ;
  wire \watchdog[28]_i_1_n_0 ;
  wire \watchdog[29]_i_1_n_0 ;
  wire \watchdog[2]_i_1_n_0 ;
  wire \watchdog[30]_i_1_n_0 ;
  wire \watchdog[31]_i_1_n_0 ;
  wire \watchdog[31]_i_2_n_0 ;
  wire \watchdog[31]_i_3_n_0 ;
  wire \watchdog[3]_i_1_n_0 ;
  wire \watchdog[4]_i_1_n_0 ;
  wire \watchdog[5]_i_1_n_0 ;
  wire \watchdog[6]_i_1_n_0 ;
  wire \watchdog[7]_i_1_n_0 ;
  wire \watchdog[8]_i_1_n_0 ;
  wire \watchdog[9]_i_1_n_0 ;
  wire \watchdog_reg[16]_i_2_n_0 ;
  wire \watchdog_reg[16]_i_2_n_1 ;
  wire \watchdog_reg[16]_i_2_n_2 ;
  wire \watchdog_reg[16]_i_2_n_3 ;
  wire \watchdog_reg[16]_i_2_n_4 ;
  wire \watchdog_reg[16]_i_2_n_5 ;
  wire \watchdog_reg[16]_i_2_n_6 ;
  wire \watchdog_reg[16]_i_2_n_7 ;
  wire \watchdog_reg[24]_i_2_n_0 ;
  wire \watchdog_reg[24]_i_2_n_1 ;
  wire \watchdog_reg[24]_i_2_n_2 ;
  wire \watchdog_reg[24]_i_2_n_3 ;
  wire \watchdog_reg[24]_i_2_n_4 ;
  wire \watchdog_reg[24]_i_2_n_5 ;
  wire \watchdog_reg[24]_i_2_n_6 ;
  wire \watchdog_reg[24]_i_2_n_7 ;
  wire \watchdog_reg[31]_i_4_n_2 ;
  wire \watchdog_reg[31]_i_4_n_3 ;
  wire \watchdog_reg[31]_i_4_n_4 ;
  wire \watchdog_reg[31]_i_4_n_5 ;
  wire \watchdog_reg[31]_i_4_n_6 ;
  wire \watchdog_reg[31]_i_4_n_7 ;
  wire \watchdog_reg[8]_i_2_n_0 ;
  wire \watchdog_reg[8]_i_2_n_1 ;
  wire \watchdog_reg[8]_i_2_n_2 ;
  wire \watchdog_reg[8]_i_2_n_3 ;
  wire \watchdog_reg[8]_i_2_n_4 ;
  wire \watchdog_reg[8]_i_2_n_5 ;
  wire \watchdog_reg[8]_i_2_n_6 ;
  wire \watchdog_reg[8]_i_2_n_7 ;
  wire [31:0]wd;
  wire [3:0]ws;
  wire [7:7]\NLW_completed_reg[24]_i_1_CO_UNCONNECTED ;
  wire [7:7]\NLW_fast_completed_reg[24]_i_1_CO_UNCONNECTED ;
  wire [7:7]\NLW_fast_cycles_reg[24]_i_1_CO_UNCONNECTED ;
  wire [7:7]\NLW_fast_starts_reg[24]_i_1_CO_UNCONNECTED ;
  wire [7:6]\NLW_last_cycles_reg[31]_i_2_CO_UNCONNECTED ;
  wire [7:7]\NLW_last_cycles_reg[31]_i_2_O_UNCONNECTED ;
  wire [7:7]\NLW_received_reg[24]_i_1_CO_UNCONNECTED ;
  wire NLW_reply_mem_reg_0_CASOUTDBITERR_UNCONNECTED;
  wire NLW_reply_mem_reg_0_CASOUTSBITERR_UNCONNECTED;
  wire NLW_reply_mem_reg_0_DBITERR_UNCONNECTED;
  wire NLW_reply_mem_reg_0_SBITERR_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_0_CASDINA_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_0_CASDINB_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_0_CASDINPA_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_0_CASDINPB_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_0_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_0_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_0_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_0_CASDOUTPB_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_0_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_0_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_reply_mem_reg_0_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_reply_mem_reg_0_RDADDRECC_UNCONNECTED;
  wire NLW_reply_mem_reg_1_CASOUTDBITERR_UNCONNECTED;
  wire NLW_reply_mem_reg_1_CASOUTSBITERR_UNCONNECTED;
  wire NLW_reply_mem_reg_1_DBITERR_UNCONNECTED;
  wire NLW_reply_mem_reg_1_SBITERR_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_1_CASDINA_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_1_CASDINB_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_1_CASDINPA_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_1_CASDINPB_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_1_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_reply_mem_reg_1_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_1_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_1_CASDOUTPB_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_1_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_reply_mem_reg_1_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_reply_mem_reg_1_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_reply_mem_reg_1_RDADDRECC_UNCONNECTED;
  wire [7:6]\NLW_request_len_reg[15]_i_4_CO_UNCONNECTED ;
  wire [7:0]\NLW_request_len_reg[15]_i_4_O_UNCONNECTED ;
  wire NLW_request_mem_reg_0_CASOUTDBITERR_UNCONNECTED;
  wire NLW_request_mem_reg_0_CASOUTSBITERR_UNCONNECTED;
  wire NLW_request_mem_reg_0_DBITERR_UNCONNECTED;
  wire NLW_request_mem_reg_0_SBITERR_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_0_CASDINA_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_0_CASDINB_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_0_CASDINPA_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_0_CASDINPB_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_0_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_0_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_0_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_0_CASDOUTPB_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_0_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_0_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_request_mem_reg_0_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_request_mem_reg_0_RDADDRECC_UNCONNECTED;
  wire NLW_request_mem_reg_1_CASOUTDBITERR_UNCONNECTED;
  wire NLW_request_mem_reg_1_CASOUTSBITERR_UNCONNECTED;
  wire NLW_request_mem_reg_1_DBITERR_UNCONNECTED;
  wire NLW_request_mem_reg_1_SBITERR_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_1_CASDINA_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_1_CASDINB_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_1_CASDINPA_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_1_CASDINPB_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_1_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_request_mem_reg_1_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_1_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_1_CASDOUTPB_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_1_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_request_mem_reg_1_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_request_mem_reg_1_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_request_mem_reg_1_RDADDRECC_UNCONNECTED;
  wire [7:6]\NLW_state_reg[1]_i_3_CO_UNCONNECTED ;
  wire [7:0]\NLW_state_reg[1]_i_3_O_UNCONNECTED ;
  wire [7:6]\NLW_state_reg[3]_i_16_CO_UNCONNECTED ;
  wire [7:0]\NLW_state_reg[3]_i_16_O_UNCONNECTED ;
  wire [7:6]\NLW_state_reg[3]_i_9_CO_UNCONNECTED ;
  wire [7:0]\NLW_state_reg[3]_i_9_O_UNCONNECTED ;
  wire [7:6]\NLW_watchdog_reg[31]_i_4_CO_UNCONNECTED ;
  wire [7:7]\NLW_watchdog_reg[31]_i_4_O_UNCONNECTED ;

  LUT3 #(
    .INIT(8'h02)) 
    \aw[23]_i_1 
       (.I0(s_axi_awvalid),
        .I1(s_axi_bvalid_reg_0),
        .I2(aw_full),
        .O(aw_full0));
  LUT4 #(
    .INIT(16'h08FF)) 
    aw_full_i_1
       (.I0(aw_full),
        .I1(w_full_reg_n_0),
        .I2(s_axi_bvalid_reg_0),
        .I3(rst_n),
        .O(aw_full_i_1_n_0));
  (* SOFT_HLUTNM = "soft_lutpair84" *) 
  LUT3 #(
    .INIT(8'hF4)) 
    aw_full_i_2
       (.I0(s_axi_bvalid_reg_0),
        .I1(s_axi_awvalid),
        .I2(aw_full),
        .O(aw_full_i_2_n_0));
  FDRE aw_full_reg
       (.C(clk),
        .CE(1'b1),
        .D(aw_full_i_2_n_0),
        .Q(aw_full),
        .R(aw_full_i_1_n_0));
  FDRE \aw_reg[0] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[0]),
        .Q(aw[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[10] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[10]),
        .Q(aw[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[11] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[11]),
        .Q(aw[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[12] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[12]),
        .Q(aw[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[13] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[13]),
        .Q(aw[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[14] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[14]),
        .Q(aw[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[15] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[15]),
        .Q(aw[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[16] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[16]),
        .Q(aw[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[17] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[17]),
        .Q(aw[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[18] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[18]),
        .Q(aw[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[19] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[19]),
        .Q(aw[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[1] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[1]),
        .Q(aw[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[20] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[20]),
        .Q(aw[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[21] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[21]),
        .Q(aw[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[22] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[22]),
        .Q(aw[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[23] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[23]),
        .Q(aw[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[2] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[2]),
        .Q(aw[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[3] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[3]),
        .Q(aw[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[4] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[4]),
        .Q(aw[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[5] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[5]),
        .Q(aw[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[6] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[6]),
        .Q(aw[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[7] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[7]),
        .Q(aw[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[8] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[8]),
        .Q(aw[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \aw_reg[9] 
       (.C(clk),
        .CE(aw_full0),
        .D(s_axi_awaddr[9]),
        .Q(aw[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair40" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    busy_INST_0
       (.I0(busy_INST_0_i_1_n_0),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[1] ),
        .I4(\state_reg_n_0_[2] ),
        .O(busy));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFD)) 
    busy_INST_0_i_1
       (.I0(busy_INST_0_i_2_n_0),
        .I1(\count_reg_n_0_[3] ),
        .I2(\count_reg_n_0_[0] ),
        .I3(busy_INST_0_i_3_n_0),
        .I4(busy_INST_0_i_4_n_0),
        .I5(busy_INST_0_i_5_n_0),
        .O(busy_INST_0_i_1_n_0));
  (* SOFT_HLUTNM = "soft_lutpair41" *) 
  LUT2 #(
    .INIT(4'h1)) 
    busy_INST_0_i_2
       (.I0(\count_reg_n_0_[1] ),
        .I1(\count_reg_n_0_[2] ),
        .O(busy_INST_0_i_2_n_0));
  (* SOFT_HLUTNM = "soft_lutpair43" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    busy_INST_0_i_3
       (.I0(p_1_in[2]),
        .I1(p_1_in[1]),
        .I2(p_1_in[3]),
        .I3(p_1_in[0]),
        .O(busy_INST_0_i_3_n_0));
  (* SOFT_HLUTNM = "soft_lutpair42" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    busy_INST_0_i_4
       (.I0(\count_reg_n_0_[11] ),
        .I1(p_1_in[6]),
        .I2(p_1_in[5]),
        .I3(p_1_in[4]),
        .O(busy_INST_0_i_4_n_0));
  (* SOFT_HLUTNM = "soft_lutpair45" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    busy_INST_0_i_5
       (.I0(\count_reg_n_0_[12] ),
        .I1(\count_reg_n_0_[13] ),
        .I2(\count_reg_n_0_[14] ),
        .I3(\count_reg_n_0_[15] ),
        .O(busy_INST_0_i_5_n_0));
  LUT6 #(
    .INIT(64'hAAAAAAAAAAABAAAA)) 
    \cmd_index[0]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\cmd_index_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[3] ),
        .I5(\state_reg_n_0_[2] ),
        .O(\cmd_index[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair10" *) 
  LUT5 #(
    .INIT(32'hEAEEAEAA)) 
    \cmd_index[10]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index[11]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[9] ),
        .I4(\cmd_index_reg_n_0_[10] ),
        .O(\cmd_index[10]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hEAAEEAEAEAEAEAEA)) 
    \cmd_index[11]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[11] ),
        .I3(\cmd_index[11]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[9] ),
        .I5(\cmd_index_reg_n_0_[10] ),
        .O(\cmd_index[11]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hF7FFFFFFFFFFFFFF)) 
    \cmd_index[11]_i_2 
       (.I0(\cmd_index_reg_n_0_[7] ),
        .I1(\cmd_index_reg_n_0_[5] ),
        .I2(\cmd_index[6]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[4] ),
        .I4(\cmd_index_reg_n_0_[6] ),
        .I5(\cmd_index_reg_n_0_[8] ),
        .O(\cmd_index[11]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hAEEAEAEA)) 
    \cmd_index[12]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[12] ),
        .I3(\cmd_index[13]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[11] ),
        .O(\cmd_index[12]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hAEEAEAEAEAEAEAEA)) 
    \cmd_index[13]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[13] ),
        .I3(\cmd_index_reg_n_0_[11] ),
        .I4(\cmd_index[13]_i_2_n_0 ),
        .I5(\cmd_index_reg_n_0_[12] ),
        .O(\cmd_index[13]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0080000000000000)) 
    \cmd_index[13]_i_2 
       (.I0(\cmd_index_reg_n_0_[10] ),
        .I1(\cmd_index_reg_n_0_[9] ),
        .I2(\cmd_index_reg_n_0_[7] ),
        .I3(\cmd_index[8]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[6] ),
        .I5(\cmd_index_reg_n_0_[8] ),
        .O(\cmd_index[13]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAABAAAAAAAAAA)) 
    \cmd_index[14]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[2] ),
        .I5(\cmd_index[14]_i_2_n_0 ),
        .O(\cmd_index[14]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h6AAAAAAA)) 
    \cmd_index[14]_i_2 
       (.I0(\cmd_index_reg_n_0_[14] ),
        .I1(\cmd_index_reg_n_0_[12] ),
        .I2(\cmd_index[13]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[11] ),
        .I4(\cmd_index_reg_n_0_[13] ),
        .O(\cmd_index[14]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h8888888888888F88)) 
    \cmd_index[15]_i_1 
       (.I0(\tx_index[15]_i_5_n_0 ),
        .I1(\cmd_index[15]_i_3_n_0 ),
        .I2(\state_reg_n_0_[2] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\state_reg_n_0_[1] ),
        .O(\cmd_index[15]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair57" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    \cmd_index[15]_i_10 
       (.I0(\hr_reg_n_0_[0] ),
        .I1(\hr_reg_n_0_[1] ),
        .I2(aw[7]),
        .I3(aw[6]),
        .O(\cmd_index[15]_i_10_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \cmd_index[15]_i_11 
       (.I0(aw[3]),
        .I1(aw[2]),
        .I2(aw[1]),
        .I3(engine_busy),
        .O(\cmd_index[15]_i_11_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \cmd_index[15]_i_12 
       (.I0(\fast_error_reg_n_0_[2] ),
        .I1(aw[0]),
        .I2(\fast_error_reg_n_0_[1] ),
        .I3(\fast_error_reg_n_0_[0] ),
        .O(\cmd_index[15]_i_12_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAABAAAAAAAAAA)) 
    \cmd_index[15]_i_2 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[2] ),
        .I5(\cmd_index[15]_i_4_n_0 ),
        .O(\cmd_index[15]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \cmd_index[15]_i_3 
       (.I0(\tx_index[15]_i_10_n_0 ),
        .I1(\s_axi_bresp[1]_i_11_n_0 ),
        .I2(\cmd_index[15]_i_5_n_0 ),
        .I3(\cmd_index[15]_i_6_n_0 ),
        .I4(\cmd_index[15]_i_7_n_0 ),
        .I5(\host_quarter[1]_i_1_n_0 ),
        .O(\cmd_index[15]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h6AAAAAAAAAAAAAAA)) 
    \cmd_index[15]_i_4 
       (.I0(\cmd_index_reg_n_0_[15] ),
        .I1(\cmd_index_reg_n_0_[13] ),
        .I2(\cmd_index_reg_n_0_[11] ),
        .I3(\cmd_index[13]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[12] ),
        .I5(\cmd_index_reg_n_0_[14] ),
        .O(\cmd_index[15]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'h0004)) 
    \cmd_index[15]_i_5 
       (.I0(\header_reg_n_0_[5] ),
        .I1(\header_reg_n_0_[6] ),
        .I2(\header_reg_n_0_[2] ),
        .I3(\cmd_index[15]_i_8_n_0 ),
        .O(\cmd_index[15]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \cmd_index[15]_i_6 
       (.I0(\reply_index[15]_i_8_n_0 ),
        .I1(\cmd_index[15]_i_9_n_0 ),
        .I2(\s_axi_bresp[1]_i_14_n_0 ),
        .I3(\reply_index[15]_i_5_n_0 ),
        .O(\cmd_index[15]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFEFF)) 
    \cmd_index[15]_i_7 
       (.I0(\cmd_index[15]_i_10_n_0 ),
        .I1(\cmd_index[15]_i_11_n_0 ),
        .I2(\cmd_index[15]_i_12_n_0 ),
        .I3(aw[5]),
        .I4(queue_active),
        .I5(aw[4]),
        .O(\cmd_index[15]_i_7_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFF9FF)) 
    \cmd_index[15]_i_8 
       (.I0(\header_reg_n_0_[1] ),
        .I1(\header_reg_n_0_[0] ),
        .I2(\header_reg_n_0_[4] ),
        .I3(\header_reg_n_0_[31] ),
        .I4(\header_reg_n_0_[3] ),
        .I5(\header_reg_n_0_[7] ),
        .O(\cmd_index[15]_i_8_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair25" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    \cmd_index[15]_i_9 
       (.I0(aw[21]),
        .I1(aw[20]),
        .I2(aw[22]),
        .I3(aw[16]),
        .O(\cmd_index[15]_i_9_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair12" *) 
  LUT4 #(
    .INIT(16'hAEEA)) 
    \cmd_index[1]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[0] ),
        .I3(\cmd_index_reg_n_0_[1] ),
        .O(\cmd_index[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair12" *) 
  LUT5 #(
    .INIT(32'hAEEAEAEA)) 
    \cmd_index[2]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[2] ),
        .I3(\cmd_index_reg_n_0_[1] ),
        .I4(\cmd_index_reg_n_0_[0] ),
        .O(\cmd_index[2]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hAEEAEAEAEAEAEAEA)) 
    \cmd_index[3]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[3] ),
        .I3(\cmd_index_reg_n_0_[1] ),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(\cmd_index_reg_n_0_[2] ),
        .O(\cmd_index[3]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair11" *) 
  LUT4 #(
    .INIT(16'hEAAE)) 
    \cmd_index[4]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[4] ),
        .I3(\cmd_index[6]_i_2_n_0 ),
        .O(\cmd_index[4]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair11" *) 
  LUT5 #(
    .INIT(32'hEAAEEAEA)) 
    \cmd_index[5]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[5] ),
        .I3(\cmd_index[6]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[4] ),
        .O(\cmd_index[5]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hEAEAAEEAEAEAEAEA)) 
    \cmd_index[6]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[6] ),
        .I3(\cmd_index_reg_n_0_[4] ),
        .I4(\cmd_index[6]_i_2_n_0 ),
        .I5(\cmd_index_reg_n_0_[5] ),
        .O(\cmd_index[6]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair32" *) 
  LUT4 #(
    .INIT(16'h7FFF)) 
    \cmd_index[6]_i_2 
       (.I0(\cmd_index_reg_n_0_[2] ),
        .I1(\cmd_index_reg_n_0_[0] ),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(\cmd_index_reg_n_0_[3] ),
        .O(\cmd_index[6]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hEAAEEAEA)) 
    \cmd_index[7]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[7] ),
        .I3(\cmd_index[8]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[6] ),
        .O(\cmd_index[7]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hEAEAAEEAEAEAEAEA)) 
    \cmd_index[8]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[8] ),
        .I3(\cmd_index_reg_n_0_[6] ),
        .I4(\cmd_index[8]_i_2_n_0 ),
        .I5(\cmd_index_reg_n_0_[7] ),
        .O(\cmd_index[8]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h7FFFFFFFFFFFFFFF)) 
    \cmd_index[8]_i_2 
       (.I0(\cmd_index_reg_n_0_[4] ),
        .I1(\cmd_index_reg_n_0_[2] ),
        .I2(\cmd_index_reg_n_0_[0] ),
        .I3(\cmd_index_reg_n_0_[1] ),
        .I4(\cmd_index_reg_n_0_[3] ),
        .I5(\cmd_index_reg_n_0_[5] ),
        .O(\cmd_index[8]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair10" *) 
  LUT4 #(
    .INIT(16'hEAAE)) 
    \cmd_index[9]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg[1]_0 ),
        .I2(\cmd_index_reg_n_0_[9] ),
        .I3(\cmd_index[11]_i_2_n_0 ),
        .O(\cmd_index[9]_i_1_n_0 ));
  FDRE \cmd_index_reg[0] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[0]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[10] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[10]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[11] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[11]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[12] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[12]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[13] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[13]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[14] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[14]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[15] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[15]_i_2_n_0 ),
        .Q(\cmd_index_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[1] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[1]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[2] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[2]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[3] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[3]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[4] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[4]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[4] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[5] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[5]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[5] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[6] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[6]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[6] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[7] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[7]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[7] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[8] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[8]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_index_reg[9] 
       (.C(clk),
        .CE(\cmd_index[15]_i_1_n_0 ),
        .D(\cmd_index[9]_i_1_n_0 ),
        .Q(\cmd_index_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT4 #(
    .INIT(16'h0080)) 
    \cmd_word[127]_i_1 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .O(\cmd_word[127]_i_1_n_0 ));
  FDRE \cmd_word_reg[0] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[0]),
        .Q(cmd_word[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[100] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[100]),
        .Q(cmd_word[100]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[101] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[101]),
        .Q(cmd_word[101]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[102] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[102]),
        .Q(cmd_word[102]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[103] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[103]),
        .Q(cmd_word[103]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[104] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[104]),
        .Q(cmd_word[104]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[105] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[105]),
        .Q(cmd_word[105]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[106] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[106]),
        .Q(cmd_word[106]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[107] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[107]),
        .Q(cmd_word[107]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[108] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[108]),
        .Q(cmd_word[108]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[109] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[109]),
        .Q(cmd_word[109]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[10] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[10]),
        .Q(cmd_word[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[110] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[110]),
        .Q(cmd_word[110]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[111] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[111]),
        .Q(cmd_word[111]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[112] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[112]),
        .Q(cmd_word[112]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[113] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[113]),
        .Q(cmd_word[113]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[114] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[114]),
        .Q(cmd_word[114]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[115] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[115]),
        .Q(cmd_word[115]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[116] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[116]),
        .Q(cmd_word[116]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[117] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[117]),
        .Q(cmd_word[117]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[118] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[118]),
        .Q(cmd_word[118]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[119] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[119]),
        .Q(cmd_word[119]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[11] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[11]),
        .Q(cmd_word[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[120] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[120]),
        .Q(cmd_word[120]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[121] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[121]),
        .Q(cmd_word[121]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[122] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[122]),
        .Q(cmd_word[122]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[123] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[123]),
        .Q(cmd_word[123]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[124] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[124]),
        .Q(cmd_word[124]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[125] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[125]),
        .Q(cmd_word[125]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[126] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[126]),
        .Q(cmd_word[126]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[127] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[127]),
        .Q(cmd_word[127]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[12] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[12]),
        .Q(cmd_word[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[13] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[13]),
        .Q(cmd_word[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[14] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[14]),
        .Q(cmd_word[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[15] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[15]),
        .Q(cmd_word[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[16] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[16]),
        .Q(cmd_word[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[17] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[17]),
        .Q(cmd_word[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[18] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[18]),
        .Q(cmd_word[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[19] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[19]),
        .Q(cmd_word[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[1] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[1]),
        .Q(cmd_word[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[20] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[20]),
        .Q(cmd_word[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[21] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[21]),
        .Q(cmd_word[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[22] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[22]),
        .Q(cmd_word[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[23] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[23]),
        .Q(cmd_word[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[24] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[24]),
        .Q(cmd_word[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[25] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[25]),
        .Q(cmd_word[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[26] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[26]),
        .Q(cmd_word[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[27] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[27]),
        .Q(cmd_word[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[28] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[28]),
        .Q(cmd_word[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[29] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[29]),
        .Q(cmd_word[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[2] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[2]),
        .Q(cmd_word[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[30] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[30]),
        .Q(cmd_word[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[31] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[31]),
        .Q(cmd_word[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[32] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[32]),
        .Q(cmd_word[32]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[33] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[33]),
        .Q(cmd_word[33]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[34] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[34]),
        .Q(cmd_word[34]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[35] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[35]),
        .Q(cmd_word[35]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[36] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[36]),
        .Q(cmd_word[36]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[37] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[37]),
        .Q(cmd_word[37]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[38] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[38]),
        .Q(cmd_word[38]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[39] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[39]),
        .Q(cmd_word[39]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[3] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[3]),
        .Q(cmd_word[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[40] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[40]),
        .Q(cmd_word[40]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[41] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[41]),
        .Q(cmd_word[41]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[42] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[42]),
        .Q(cmd_word[42]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[43] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[43]),
        .Q(cmd_word[43]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[44] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[44]),
        .Q(cmd_word[44]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[45] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[45]),
        .Q(cmd_word[45]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[46] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[46]),
        .Q(cmd_word[46]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[47] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[47]),
        .Q(cmd_word[47]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[48] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[48]),
        .Q(cmd_word[48]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[49] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[49]),
        .Q(cmd_word[49]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[4] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[4]),
        .Q(cmd_word[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[50] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[50]),
        .Q(cmd_word[50]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[51] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[51]),
        .Q(cmd_word[51]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[52] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[52]),
        .Q(cmd_word[52]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[53] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[53]),
        .Q(cmd_word[53]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[54] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[54]),
        .Q(cmd_word[54]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[55] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[55]),
        .Q(cmd_word[55]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[56] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[56]),
        .Q(cmd_word[56]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[57] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[57]),
        .Q(cmd_word[57]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[58] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[58]),
        .Q(cmd_word[58]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[59] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[59]),
        .Q(cmd_word[59]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[5] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[5]),
        .Q(cmd_word[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[60] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[60]),
        .Q(cmd_word[60]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[61] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[61]),
        .Q(cmd_word[61]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[62] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[62]),
        .Q(cmd_word[62]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[63] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[63]),
        .Q(cmd_word[63]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[64] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[64]),
        .Q(cmd_word[64]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[65] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[65]),
        .Q(cmd_word[65]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[66] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[66]),
        .Q(cmd_word[66]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[67] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[67]),
        .Q(cmd_word[67]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[68] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[68]),
        .Q(cmd_word[68]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[69] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[69]),
        .Q(cmd_word[69]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[6] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[6]),
        .Q(cmd_word[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[70] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[70]),
        .Q(cmd_word[70]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[71] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[71]),
        .Q(cmd_word[71]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[72] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[72]),
        .Q(cmd_word[72]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[73] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[73]),
        .Q(cmd_word[73]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[74] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[74]),
        .Q(cmd_word[74]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[75] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[75]),
        .Q(cmd_word[75]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[76] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[76]),
        .Q(cmd_word[76]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[77] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[77]),
        .Q(cmd_word[77]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[78] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[78]),
        .Q(cmd_word[78]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[79] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[79]),
        .Q(cmd_word[79]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[7] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[7]),
        .Q(cmd_word[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[80] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[80]),
        .Q(cmd_word[80]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[81] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[81]),
        .Q(cmd_word[81]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[82] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[82]),
        .Q(cmd_word[82]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[83] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[83]),
        .Q(cmd_word[83]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[84] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[84]),
        .Q(cmd_word[84]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[85] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[85]),
        .Q(cmd_word[85]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[86] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[86]),
        .Q(cmd_word[86]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[87] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[87]),
        .Q(cmd_word[87]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[88] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[88]),
        .Q(cmd_word[88]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[89] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[89]),
        .Q(cmd_word[89]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[8] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[8]),
        .Q(cmd_word[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[90] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[90]),
        .Q(cmd_word[90]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[91] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[91]),
        .Q(cmd_word[91]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[92] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[92]),
        .Q(cmd_word[92]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[93] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[93]),
        .Q(cmd_word[93]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[94] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[94]),
        .Q(cmd_word[94]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[95] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[95]),
        .Q(cmd_word[95]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[96] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[96]),
        .Q(cmd_word[96]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[97] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[97]),
        .Q(cmd_word[97]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[98] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[98]),
        .Q(cmd_word[98]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[99] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[99]),
        .Q(cmd_word[99]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \cmd_word_reg[9] 
       (.C(clk),
        .CE(\cmd_word[127]_i_1_n_0 ),
        .D(request_q[9]),
        .Q(cmd_word[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0000000002000000)) 
    \completed[0]_i_1 
       (.I0(\state_reg[1]_i_3_n_2 ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(tx_ready),
        .I5(\state_reg_n_0_[3] ),
        .O(\completed[0]_i_1_n_0 ));
  LUT1 #(
    .INIT(2'h1)) 
    \completed[0]_i_3 
       (.I0(completed_reg[0]),
        .O(\completed[0]_i_3_n_0 ));
  FDRE \completed_reg[0] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_15 ),
        .Q(completed_reg[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \completed_reg[0]_i_2 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\completed_reg[0]_i_2_n_0 ,\completed_reg[0]_i_2_n_1 ,\completed_reg[0]_i_2_n_2 ,\completed_reg[0]_i_2_n_3 ,\completed_reg[0]_i_2_n_4 ,\completed_reg[0]_i_2_n_5 ,\completed_reg[0]_i_2_n_6 ,\completed_reg[0]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\completed_reg[0]_i_2_n_8 ,\completed_reg[0]_i_2_n_9 ,\completed_reg[0]_i_2_n_10 ,\completed_reg[0]_i_2_n_11 ,\completed_reg[0]_i_2_n_12 ,\completed_reg[0]_i_2_n_13 ,\completed_reg[0]_i_2_n_14 ,\completed_reg[0]_i_2_n_15 }),
        .S({completed_reg[7:1],\completed[0]_i_3_n_0 }));
  FDRE \completed_reg[10] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_13 ),
        .Q(completed_reg[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[11] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_12 ),
        .Q(completed_reg[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[12] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_11 ),
        .Q(completed_reg[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[13] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_10 ),
        .Q(completed_reg[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[14] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_9 ),
        .Q(completed_reg[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[15] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_8 ),
        .Q(completed_reg[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[16] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_15 ),
        .Q(completed_reg[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \completed_reg[16]_i_1 
       (.CI(\completed_reg[8]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\completed_reg[16]_i_1_n_0 ,\completed_reg[16]_i_1_n_1 ,\completed_reg[16]_i_1_n_2 ,\completed_reg[16]_i_1_n_3 ,\completed_reg[16]_i_1_n_4 ,\completed_reg[16]_i_1_n_5 ,\completed_reg[16]_i_1_n_6 ,\completed_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\completed_reg[16]_i_1_n_8 ,\completed_reg[16]_i_1_n_9 ,\completed_reg[16]_i_1_n_10 ,\completed_reg[16]_i_1_n_11 ,\completed_reg[16]_i_1_n_12 ,\completed_reg[16]_i_1_n_13 ,\completed_reg[16]_i_1_n_14 ,\completed_reg[16]_i_1_n_15 }),
        .S(completed_reg[23:16]));
  FDRE \completed_reg[17] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_14 ),
        .Q(completed_reg[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[18] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_13 ),
        .Q(completed_reg[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[19] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_12 ),
        .Q(completed_reg[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[1] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_14 ),
        .Q(completed_reg[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[20] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_11 ),
        .Q(completed_reg[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[21] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_10 ),
        .Q(completed_reg[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[22] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_9 ),
        .Q(completed_reg[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[23] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[16]_i_1_n_8 ),
        .Q(completed_reg[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[24] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_15 ),
        .Q(completed_reg[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \completed_reg[24]_i_1 
       (.CI(\completed_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_completed_reg[24]_i_1_CO_UNCONNECTED [7],\completed_reg[24]_i_1_n_1 ,\completed_reg[24]_i_1_n_2 ,\completed_reg[24]_i_1_n_3 ,\completed_reg[24]_i_1_n_4 ,\completed_reg[24]_i_1_n_5 ,\completed_reg[24]_i_1_n_6 ,\completed_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\completed_reg[24]_i_1_n_8 ,\completed_reg[24]_i_1_n_9 ,\completed_reg[24]_i_1_n_10 ,\completed_reg[24]_i_1_n_11 ,\completed_reg[24]_i_1_n_12 ,\completed_reg[24]_i_1_n_13 ,\completed_reg[24]_i_1_n_14 ,\completed_reg[24]_i_1_n_15 }),
        .S(completed_reg[31:24]));
  FDRE \completed_reg[25] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_14 ),
        .Q(completed_reg[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[26] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_13 ),
        .Q(completed_reg[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[27] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_12 ),
        .Q(completed_reg[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[28] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_11 ),
        .Q(completed_reg[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[29] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_10 ),
        .Q(completed_reg[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[2] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_13 ),
        .Q(completed_reg[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[30] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_9 ),
        .Q(completed_reg[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[31] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[24]_i_1_n_8 ),
        .Q(completed_reg[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[3] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_12 ),
        .Q(completed_reg[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[4] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_11 ),
        .Q(completed_reg[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[5] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_10 ),
        .Q(completed_reg[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[6] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_9 ),
        .Q(completed_reg[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[7] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[0]_i_2_n_8 ),
        .Q(completed_reg[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \completed_reg[8] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_15 ),
        .Q(completed_reg[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \completed_reg[8]_i_1 
       (.CI(\completed_reg[0]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\completed_reg[8]_i_1_n_0 ,\completed_reg[8]_i_1_n_1 ,\completed_reg[8]_i_1_n_2 ,\completed_reg[8]_i_1_n_3 ,\completed_reg[8]_i_1_n_4 ,\completed_reg[8]_i_1_n_5 ,\completed_reg[8]_i_1_n_6 ,\completed_reg[8]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\completed_reg[8]_i_1_n_8 ,\completed_reg[8]_i_1_n_9 ,\completed_reg[8]_i_1_n_10 ,\completed_reg[8]_i_1_n_11 ,\completed_reg[8]_i_1_n_12 ,\completed_reg[8]_i_1_n_13 ,\completed_reg[8]_i_1_n_14 ,\completed_reg[8]_i_1_n_15 }),
        .S(completed_reg[15:8]));
  FDRE \completed_reg[9] 
       (.C(clk),
        .CE(\completed[0]_i_1_n_0 ),
        .D(\completed_reg[8]_i_1_n_14 ),
        .Q(completed_reg[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair134" *) 
  LUT2 #(
    .INIT(4'h1)) 
    \count[0]_i_1 
       (.I0(\count_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[2] ),
        .O(\count[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair47" *) 
  LUT4 #(
    .INIT(16'h00B4)) 
    \count[10]_i_1 
       (.I0(\count[12]_i_2_n_0 ),
        .I1(p_1_in[5]),
        .I2(p_1_in[6]),
        .I3(\state_reg_n_0_[2] ),
        .O(\count[10]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair47" *) 
  LUT5 #(
    .INIT(32'h0000DF20)) 
    \count[11]_i_1 
       (.I0(p_1_in[5]),
        .I1(\count[12]_i_2_n_0 ),
        .I2(p_1_in[6]),
        .I3(\count_reg_n_0_[11] ),
        .I4(\state_reg_n_0_[2] ),
        .O(\count[11]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h00000000DFFF2000)) 
    \count[12]_i_1 
       (.I0(p_1_in[6]),
        .I1(\count[12]_i_2_n_0 ),
        .I2(p_1_in[5]),
        .I3(\count_reg_n_0_[11] ),
        .I4(\count_reg_n_0_[12] ),
        .I5(\state_reg_n_0_[2] ),
        .O(\count[12]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h7FFFFFFFFFFFFFFF)) 
    \count[12]_i_2 
       (.I0(p_1_in[3]),
        .I1(p_1_in[1]),
        .I2(p_1_in[0]),
        .I3(p_80_in),
        .I4(p_1_in[2]),
        .I5(p_1_in[4]),
        .O(\count[12]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'h51550400)) 
    \count[13]_i_1 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[11] ),
        .I2(\count[14]_i_2_n_0 ),
        .I3(\count_reg_n_0_[12] ),
        .I4(\count_reg_n_0_[13] ),
        .O(\count[13]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h5515555500400000)) 
    \count[14]_i_1 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[13] ),
        .I2(\count_reg_n_0_[12] ),
        .I3(\count[14]_i_2_n_0 ),
        .I4(\count_reg_n_0_[11] ),
        .I5(\count_reg_n_0_[14] ),
        .O(\count[14]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hF7FFFFFFFFFFFFFF)) 
    \count[14]_i_2 
       (.I0(p_1_in[5]),
        .I1(p_1_in[3]),
        .I2(\count[9]_i_2_n_0 ),
        .I3(p_1_in[2]),
        .I4(p_1_in[4]),
        .I5(p_1_in[6]),
        .O(\count[14]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAAAAAAAAABA)) 
    \count[15]_i_1 
       (.I0(\completed[0]_i_1_n_0 ),
        .I1(\state_reg_n_0_[2] ),
        .I2(rx_valid),
        .I3(\state_reg_n_0_[1] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\state_reg_n_0_[3] ),
        .O(\count[15]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair72" *) 
  LUT4 #(
    .INIT(16'h0078)) 
    \count[15]_i_2 
       (.I0(\count[15]_i_3_n_0 ),
        .I1(\count_reg_n_0_[14] ),
        .I2(\count_reg_n_0_[15] ),
        .I3(\state_reg_n_0_[2] ),
        .O(\count[15]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0080000000000000)) 
    \count[15]_i_3 
       (.I0(\count_reg_n_0_[13] ),
        .I1(\count_reg_n_0_[12] ),
        .I2(p_1_in[6]),
        .I3(\count[12]_i_2_n_0 ),
        .I4(p_1_in[5]),
        .I5(\count_reg_n_0_[11] ),
        .O(\count[15]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair127" *) 
  LUT3 #(
    .INIT(8'h06)) 
    \count[1]_i_1 
       (.I0(\count_reg_n_0_[1] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[2] ),
        .O(\count[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair8" *) 
  LUT4 #(
    .INIT(16'h1540)) 
    \count[2]_i_1 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[2] ),
        .O(\count[2]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair8" *) 
  LUT5 #(
    .INIT(32'h15554000)) 
    \count[3]_i_1 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[2] ),
        .I4(\count_reg_n_0_[3] ),
        .O(\count[3]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h000000007FFF8000)) 
    \count[4]_i_1 
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[1] ),
        .I4(p_1_in[0]),
        .I5(\state_reg_n_0_[2] ),
        .O(\count[4]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair46" *) 
  LUT4 #(
    .INIT(16'h0078)) 
    \count[5]_i_1 
       (.I0(p_1_in[0]),
        .I1(p_80_in),
        .I2(p_1_in[1]),
        .I3(\state_reg_n_0_[2] ),
        .O(\count[5]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair46" *) 
  LUT5 #(
    .INIT(32'h00007F80)) 
    \count[6]_i_1 
       (.I0(p_80_in),
        .I1(p_1_in[0]),
        .I2(p_1_in[1]),
        .I3(p_1_in[2]),
        .I4(\state_reg_n_0_[2] ),
        .O(\count[6]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h000000007FFF8000)) 
    \count[7]_i_1 
       (.I0(p_1_in[1]),
        .I1(p_1_in[0]),
        .I2(p_80_in),
        .I3(p_1_in[2]),
        .I4(p_1_in[3]),
        .I5(\state_reg_n_0_[2] ),
        .O(\count[7]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h0000DF20)) 
    \count[8]_i_1 
       (.I0(p_1_in[2]),
        .I1(\count[9]_i_2_n_0 ),
        .I2(p_1_in[3]),
        .I3(p_1_in[4]),
        .I4(\state_reg_n_0_[2] ),
        .O(\count[8]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h00000000DFFF2000)) 
    \count[9]_i_1 
       (.I0(p_1_in[3]),
        .I1(\count[9]_i_2_n_0 ),
        .I2(p_1_in[2]),
        .I3(p_1_in[4]),
        .I4(p_1_in[5]),
        .I5(\state_reg_n_0_[2] ),
        .O(\count[9]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h7FFFFFFFFFFFFFFF)) 
    \count[9]_i_2 
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[1] ),
        .I4(p_1_in[0]),
        .I5(p_1_in[1]),
        .O(\count[9]_i_2_n_0 ));
  FDRE \count_reg[0] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[0]_i_1_n_0 ),
        .Q(\count_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[10] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[10]_i_1_n_0 ),
        .Q(p_1_in[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[11] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[11]_i_1_n_0 ),
        .Q(\count_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[12] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[12]_i_1_n_0 ),
        .Q(\count_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[13] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[13]_i_1_n_0 ),
        .Q(\count_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[14] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[14]_i_1_n_0 ),
        .Q(\count_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[15] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[15]_i_2_n_0 ),
        .Q(\count_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[1] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[1]_i_1_n_0 ),
        .Q(\count_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[2] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[2]_i_1_n_0 ),
        .Q(\count_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[3] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[3]_i_1_n_0 ),
        .Q(\count_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[4] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[4]_i_1_n_0 ),
        .Q(p_1_in[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[5] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[5]_i_1_n_0 ),
        .Q(p_1_in[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[6] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[6]_i_1_n_0 ),
        .Q(p_1_in[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[7] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[7]_i_1_n_0 ),
        .Q(p_1_in[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[8] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[8]_i_1_n_0 ),
        .Q(p_1_in[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \count_reg[9] 
       (.C(clk),
        .CE(\count[15]_i_1_n_0 ),
        .D(\count[9]_i_1_n_0 ),
        .Q(p_1_in[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT4 #(
    .INIT(16'h13C0)) 
    fast_active_INST_0
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .O(fast_active));
  MUXF8 \fast_cmd_data[0]_INST_0 
       (.I0(\fast_cmd_data[0]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[0]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[0]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[0]_INST_0_i_1 
       (.I0(\fast_cmd_data[0]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[0]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[0]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[0]_INST_0_i_2 
       (.I0(\fast_cmd_data[0]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[0]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[0]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[0]_INST_0_i_3 
       (.I0(cmd_word[24]),
        .I1(cmd_word[16]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[8]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[0]),
        .O(\fast_cmd_data[0]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[0]_INST_0_i_4 
       (.I0(cmd_word[56]),
        .I1(cmd_word[48]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[40]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[32]),
        .O(\fast_cmd_data[0]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[0]_INST_0_i_5 
       (.I0(cmd_word[88]),
        .I1(cmd_word[80]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[72]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[64]),
        .O(\fast_cmd_data[0]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[0]_INST_0_i_6 
       (.I0(cmd_word[120]),
        .I1(cmd_word[112]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[104]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[96]),
        .O(\fast_cmd_data[0]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[1]_INST_0 
       (.I0(\fast_cmd_data[1]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[1]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[1]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[1]_INST_0_i_1 
       (.I0(\fast_cmd_data[1]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[1]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[1]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[1]_INST_0_i_2 
       (.I0(\fast_cmd_data[1]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[1]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[1]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[1]_INST_0_i_3 
       (.I0(cmd_word[25]),
        .I1(cmd_word[17]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[9]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[1]),
        .O(\fast_cmd_data[1]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[1]_INST_0_i_4 
       (.I0(cmd_word[57]),
        .I1(cmd_word[49]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[41]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[33]),
        .O(\fast_cmd_data[1]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[1]_INST_0_i_5 
       (.I0(cmd_word[89]),
        .I1(cmd_word[81]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[73]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[65]),
        .O(\fast_cmd_data[1]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[1]_INST_0_i_6 
       (.I0(cmd_word[121]),
        .I1(cmd_word[113]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[105]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[97]),
        .O(\fast_cmd_data[1]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[2]_INST_0 
       (.I0(\fast_cmd_data[2]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[2]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[2]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[2]_INST_0_i_1 
       (.I0(\fast_cmd_data[2]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[2]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[2]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[2]_INST_0_i_2 
       (.I0(\fast_cmd_data[2]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[2]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[2]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[2]_INST_0_i_3 
       (.I0(cmd_word[26]),
        .I1(cmd_word[18]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[10]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[2]),
        .O(\fast_cmd_data[2]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[2]_INST_0_i_4 
       (.I0(cmd_word[58]),
        .I1(cmd_word[50]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[42]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[34]),
        .O(\fast_cmd_data[2]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[2]_INST_0_i_5 
       (.I0(cmd_word[90]),
        .I1(cmd_word[82]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[74]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[66]),
        .O(\fast_cmd_data[2]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[2]_INST_0_i_6 
       (.I0(cmd_word[122]),
        .I1(cmd_word[114]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[106]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[98]),
        .O(\fast_cmd_data[2]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[3]_INST_0 
       (.I0(\fast_cmd_data[3]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[3]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[3]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[3]_INST_0_i_1 
       (.I0(\fast_cmd_data[3]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[3]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[3]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[3]_INST_0_i_2 
       (.I0(\fast_cmd_data[3]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[3]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[3]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[3]_INST_0_i_3 
       (.I0(cmd_word[27]),
        .I1(cmd_word[19]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[11]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[3]),
        .O(\fast_cmd_data[3]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[3]_INST_0_i_4 
       (.I0(cmd_word[59]),
        .I1(cmd_word[51]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[43]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[35]),
        .O(\fast_cmd_data[3]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[3]_INST_0_i_5 
       (.I0(cmd_word[91]),
        .I1(cmd_word[83]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[75]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[67]),
        .O(\fast_cmd_data[3]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[3]_INST_0_i_6 
       (.I0(cmd_word[123]),
        .I1(cmd_word[115]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[107]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[99]),
        .O(\fast_cmd_data[3]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[4]_INST_0 
       (.I0(\fast_cmd_data[4]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[4]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[4]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[4]_INST_0_i_1 
       (.I0(\fast_cmd_data[4]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[4]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[4]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[4]_INST_0_i_2 
       (.I0(\fast_cmd_data[4]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[4]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[4]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[4]_INST_0_i_3 
       (.I0(cmd_word[28]),
        .I1(cmd_word[20]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[12]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[4]),
        .O(\fast_cmd_data[4]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[4]_INST_0_i_4 
       (.I0(cmd_word[60]),
        .I1(cmd_word[52]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[44]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[36]),
        .O(\fast_cmd_data[4]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[4]_INST_0_i_5 
       (.I0(cmd_word[92]),
        .I1(cmd_word[84]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[76]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[68]),
        .O(\fast_cmd_data[4]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[4]_INST_0_i_6 
       (.I0(cmd_word[124]),
        .I1(cmd_word[116]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[108]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[100]),
        .O(\fast_cmd_data[4]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[5]_INST_0 
       (.I0(\fast_cmd_data[5]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[5]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[5]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[5]_INST_0_i_1 
       (.I0(\fast_cmd_data[5]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[5]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[5]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[5]_INST_0_i_2 
       (.I0(\fast_cmd_data[5]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[5]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[5]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[5]_INST_0_i_3 
       (.I0(cmd_word[29]),
        .I1(cmd_word[21]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[13]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[5]),
        .O(\fast_cmd_data[5]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[5]_INST_0_i_4 
       (.I0(cmd_word[61]),
        .I1(cmd_word[53]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[45]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[37]),
        .O(\fast_cmd_data[5]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[5]_INST_0_i_5 
       (.I0(cmd_word[93]),
        .I1(cmd_word[85]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[77]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[69]),
        .O(\fast_cmd_data[5]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[5]_INST_0_i_6 
       (.I0(cmd_word[125]),
        .I1(cmd_word[117]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[109]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[101]),
        .O(\fast_cmd_data[5]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[6]_INST_0 
       (.I0(\fast_cmd_data[6]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[6]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[6]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[6]_INST_0_i_1 
       (.I0(\fast_cmd_data[6]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[6]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[6]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[6]_INST_0_i_2 
       (.I0(\fast_cmd_data[6]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[6]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[6]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[6]_INST_0_i_3 
       (.I0(cmd_word[30]),
        .I1(cmd_word[22]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[14]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[6]),
        .O(\fast_cmd_data[6]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[6]_INST_0_i_4 
       (.I0(cmd_word[62]),
        .I1(cmd_word[54]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[46]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[38]),
        .O(\fast_cmd_data[6]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[6]_INST_0_i_5 
       (.I0(cmd_word[94]),
        .I1(cmd_word[86]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[78]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[70]),
        .O(\fast_cmd_data[6]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[6]_INST_0_i_6 
       (.I0(cmd_word[126]),
        .I1(cmd_word[118]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[110]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[102]),
        .O(\fast_cmd_data[6]_INST_0_i_6_n_0 ));
  MUXF8 \fast_cmd_data[7]_INST_0 
       (.I0(\fast_cmd_data[7]_INST_0_i_1_n_0 ),
        .I1(\fast_cmd_data[7]_INST_0_i_2_n_0 ),
        .O(fast_cmd_data[7]),
        .S(\cmd_index_reg_n_0_[3] ));
  MUXF7 \fast_cmd_data[7]_INST_0_i_1 
       (.I0(\fast_cmd_data[7]_INST_0_i_3_n_0 ),
        .I1(\fast_cmd_data[7]_INST_0_i_4_n_0 ),
        .O(\fast_cmd_data[7]_INST_0_i_1_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  MUXF7 \fast_cmd_data[7]_INST_0_i_2 
       (.I0(\fast_cmd_data[7]_INST_0_i_5_n_0 ),
        .I1(\fast_cmd_data[7]_INST_0_i_6_n_0 ),
        .O(\fast_cmd_data[7]_INST_0_i_2_n_0 ),
        .S(\cmd_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[7]_INST_0_i_3 
       (.I0(cmd_word[31]),
        .I1(cmd_word[23]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[15]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[7]),
        .O(\fast_cmd_data[7]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[7]_INST_0_i_4 
       (.I0(cmd_word[63]),
        .I1(cmd_word[55]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[47]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[39]),
        .O(\fast_cmd_data[7]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[7]_INST_0_i_5 
       (.I0(cmd_word[95]),
        .I1(cmd_word[87]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[79]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[71]),
        .O(\fast_cmd_data[7]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \fast_cmd_data[7]_INST_0_i_6 
       (.I0(cmd_word[127]),
        .I1(cmd_word[119]),
        .I2(\cmd_index_reg_n_0_[1] ),
        .I3(cmd_word[111]),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(cmd_word[103]),
        .O(\fast_cmd_data[7]_INST_0_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair30" *) 
  LUT4 #(
    .INIT(16'h0010)) 
    fast_cmd_valid_INST_0
       (.I0(\state_reg_n_0_[1] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[2] ),
        .O(\state_reg[1]_0 ));
  LUT1 #(
    .INIT(2'h1)) 
    \fast_completed[0]_i_2 
       (.I0(fast_completed_reg[0]),
        .O(\fast_completed[0]_i_2_n_0 ));
  FDRE \fast_completed_reg[0] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_15 ),
        .Q(fast_completed_reg[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_completed_reg[0]_i_1 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\fast_completed_reg[0]_i_1_n_0 ,\fast_completed_reg[0]_i_1_n_1 ,\fast_completed_reg[0]_i_1_n_2 ,\fast_completed_reg[0]_i_1_n_3 ,\fast_completed_reg[0]_i_1_n_4 ,\fast_completed_reg[0]_i_1_n_5 ,\fast_completed_reg[0]_i_1_n_6 ,\fast_completed_reg[0]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\fast_completed_reg[0]_i_1_n_8 ,\fast_completed_reg[0]_i_1_n_9 ,\fast_completed_reg[0]_i_1_n_10 ,\fast_completed_reg[0]_i_1_n_11 ,\fast_completed_reg[0]_i_1_n_12 ,\fast_completed_reg[0]_i_1_n_13 ,\fast_completed_reg[0]_i_1_n_14 ,\fast_completed_reg[0]_i_1_n_15 }),
        .S({fast_completed_reg[7:1],\fast_completed[0]_i_2_n_0 }));
  FDRE \fast_completed_reg[10] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_13 ),
        .Q(fast_completed_reg[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[11] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_12 ),
        .Q(fast_completed_reg[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[12] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_11 ),
        .Q(fast_completed_reg[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[13] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_10 ),
        .Q(fast_completed_reg[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[14] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_9 ),
        .Q(fast_completed_reg[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[15] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_8 ),
        .Q(fast_completed_reg[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[16] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_15 ),
        .Q(fast_completed_reg[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_completed_reg[16]_i_1 
       (.CI(\fast_completed_reg[8]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\fast_completed_reg[16]_i_1_n_0 ,\fast_completed_reg[16]_i_1_n_1 ,\fast_completed_reg[16]_i_1_n_2 ,\fast_completed_reg[16]_i_1_n_3 ,\fast_completed_reg[16]_i_1_n_4 ,\fast_completed_reg[16]_i_1_n_5 ,\fast_completed_reg[16]_i_1_n_6 ,\fast_completed_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_completed_reg[16]_i_1_n_8 ,\fast_completed_reg[16]_i_1_n_9 ,\fast_completed_reg[16]_i_1_n_10 ,\fast_completed_reg[16]_i_1_n_11 ,\fast_completed_reg[16]_i_1_n_12 ,\fast_completed_reg[16]_i_1_n_13 ,\fast_completed_reg[16]_i_1_n_14 ,\fast_completed_reg[16]_i_1_n_15 }),
        .S(fast_completed_reg[23:16]));
  FDRE \fast_completed_reg[17] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_14 ),
        .Q(fast_completed_reg[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[18] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_13 ),
        .Q(fast_completed_reg[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[19] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_12 ),
        .Q(fast_completed_reg[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[1] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_14 ),
        .Q(fast_completed_reg[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[20] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_11 ),
        .Q(fast_completed_reg[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[21] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_10 ),
        .Q(fast_completed_reg[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[22] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_9 ),
        .Q(fast_completed_reg[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[23] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[16]_i_1_n_8 ),
        .Q(fast_completed_reg[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[24] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_15 ),
        .Q(fast_completed_reg[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_completed_reg[24]_i_1 
       (.CI(\fast_completed_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_fast_completed_reg[24]_i_1_CO_UNCONNECTED [7],\fast_completed_reg[24]_i_1_n_1 ,\fast_completed_reg[24]_i_1_n_2 ,\fast_completed_reg[24]_i_1_n_3 ,\fast_completed_reg[24]_i_1_n_4 ,\fast_completed_reg[24]_i_1_n_5 ,\fast_completed_reg[24]_i_1_n_6 ,\fast_completed_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_completed_reg[24]_i_1_n_8 ,\fast_completed_reg[24]_i_1_n_9 ,\fast_completed_reg[24]_i_1_n_10 ,\fast_completed_reg[24]_i_1_n_11 ,\fast_completed_reg[24]_i_1_n_12 ,\fast_completed_reg[24]_i_1_n_13 ,\fast_completed_reg[24]_i_1_n_14 ,\fast_completed_reg[24]_i_1_n_15 }),
        .S(fast_completed_reg[31:24]));
  FDRE \fast_completed_reg[25] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_14 ),
        .Q(fast_completed_reg[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[26] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_13 ),
        .Q(fast_completed_reg[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[27] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_12 ),
        .Q(fast_completed_reg[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[28] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_11 ),
        .Q(fast_completed_reg[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[29] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_10 ),
        .Q(fast_completed_reg[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[2] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_13 ),
        .Q(fast_completed_reg[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[30] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_9 ),
        .Q(fast_completed_reg[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[31] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[24]_i_1_n_8 ),
        .Q(fast_completed_reg[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[3] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_12 ),
        .Q(fast_completed_reg[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[4] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_11 ),
        .Q(fast_completed_reg[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[5] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_10 ),
        .Q(fast_completed_reg[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[6] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_9 ),
        .Q(fast_completed_reg[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[7] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[0]_i_1_n_8 ),
        .Q(fast_completed_reg[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_completed_reg[8] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_15 ),
        .Q(fast_completed_reg[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_completed_reg[8]_i_1 
       (.CI(\fast_completed_reg[0]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\fast_completed_reg[8]_i_1_n_0 ,\fast_completed_reg[8]_i_1_n_1 ,\fast_completed_reg[8]_i_1_n_2 ,\fast_completed_reg[8]_i_1_n_3 ,\fast_completed_reg[8]_i_1_n_4 ,\fast_completed_reg[8]_i_1_n_5 ,\fast_completed_reg[8]_i_1_n_6 ,\fast_completed_reg[8]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_completed_reg[8]_i_1_n_8 ,\fast_completed_reg[8]_i_1_n_9 ,\fast_completed_reg[8]_i_1_n_10 ,\fast_completed_reg[8]_i_1_n_11 ,\fast_completed_reg[8]_i_1_n_12 ,\fast_completed_reg[8]_i_1_n_13 ,\fast_completed_reg[8]_i_1_n_14 ,\fast_completed_reg[8]_i_1_n_15 }),
        .S(fast_completed_reg[15:8]));
  FDRE \fast_completed_reg[9] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\fast_completed_reg[8]_i_1_n_14 ),
        .Q(fast_completed_reg[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT3 #(
    .INIT(8'h8F)) 
    \fast_cycles[0]_i_1 
       (.I0(\tx_index[15]_i_5_n_0 ),
        .I1(\cmd_index[15]_i_3_n_0 ),
        .I2(rst_n),
        .O(\fast_cycles[0]_i_1_n_0 ));
  LUT1 #(
    .INIT(2'h1)) 
    \fast_cycles[0]_i_3 
       (.I0(fast_cycles_reg[0]),
        .O(\fast_cycles[0]_i_3_n_0 ));
  FDRE \fast_cycles_reg[0] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_15 ),
        .Q(fast_cycles_reg[0]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_cycles_reg[0]_i_2 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\fast_cycles_reg[0]_i_2_n_0 ,\fast_cycles_reg[0]_i_2_n_1 ,\fast_cycles_reg[0]_i_2_n_2 ,\fast_cycles_reg[0]_i_2_n_3 ,\fast_cycles_reg[0]_i_2_n_4 ,\fast_cycles_reg[0]_i_2_n_5 ,\fast_cycles_reg[0]_i_2_n_6 ,\fast_cycles_reg[0]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\fast_cycles_reg[0]_i_2_n_8 ,\fast_cycles_reg[0]_i_2_n_9 ,\fast_cycles_reg[0]_i_2_n_10 ,\fast_cycles_reg[0]_i_2_n_11 ,\fast_cycles_reg[0]_i_2_n_12 ,\fast_cycles_reg[0]_i_2_n_13 ,\fast_cycles_reg[0]_i_2_n_14 ,\fast_cycles_reg[0]_i_2_n_15 }),
        .S({fast_cycles_reg[7:1],\fast_cycles[0]_i_3_n_0 }));
  FDRE \fast_cycles_reg[10] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_13 ),
        .Q(fast_cycles_reg[10]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[11] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_12 ),
        .Q(fast_cycles_reg[11]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[12] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_11 ),
        .Q(fast_cycles_reg[12]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[13] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_10 ),
        .Q(fast_cycles_reg[13]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[14] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_9 ),
        .Q(fast_cycles_reg[14]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[15] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_8 ),
        .Q(fast_cycles_reg[15]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[16] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_15 ),
        .Q(fast_cycles_reg[16]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_cycles_reg[16]_i_1 
       (.CI(\fast_cycles_reg[8]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\fast_cycles_reg[16]_i_1_n_0 ,\fast_cycles_reg[16]_i_1_n_1 ,\fast_cycles_reg[16]_i_1_n_2 ,\fast_cycles_reg[16]_i_1_n_3 ,\fast_cycles_reg[16]_i_1_n_4 ,\fast_cycles_reg[16]_i_1_n_5 ,\fast_cycles_reg[16]_i_1_n_6 ,\fast_cycles_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_cycles_reg[16]_i_1_n_8 ,\fast_cycles_reg[16]_i_1_n_9 ,\fast_cycles_reg[16]_i_1_n_10 ,\fast_cycles_reg[16]_i_1_n_11 ,\fast_cycles_reg[16]_i_1_n_12 ,\fast_cycles_reg[16]_i_1_n_13 ,\fast_cycles_reg[16]_i_1_n_14 ,\fast_cycles_reg[16]_i_1_n_15 }),
        .S(fast_cycles_reg[23:16]));
  FDRE \fast_cycles_reg[17] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_14 ),
        .Q(fast_cycles_reg[17]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[18] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_13 ),
        .Q(fast_cycles_reg[18]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[19] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_12 ),
        .Q(fast_cycles_reg[19]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[1] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_14 ),
        .Q(fast_cycles_reg[1]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[20] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_11 ),
        .Q(fast_cycles_reg[20]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[21] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_10 ),
        .Q(fast_cycles_reg[21]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[22] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_9 ),
        .Q(fast_cycles_reg[22]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[23] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[16]_i_1_n_8 ),
        .Q(fast_cycles_reg[23]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[24] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_15 ),
        .Q(fast_cycles_reg[24]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_cycles_reg[24]_i_1 
       (.CI(\fast_cycles_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_fast_cycles_reg[24]_i_1_CO_UNCONNECTED [7],\fast_cycles_reg[24]_i_1_n_1 ,\fast_cycles_reg[24]_i_1_n_2 ,\fast_cycles_reg[24]_i_1_n_3 ,\fast_cycles_reg[24]_i_1_n_4 ,\fast_cycles_reg[24]_i_1_n_5 ,\fast_cycles_reg[24]_i_1_n_6 ,\fast_cycles_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_cycles_reg[24]_i_1_n_8 ,\fast_cycles_reg[24]_i_1_n_9 ,\fast_cycles_reg[24]_i_1_n_10 ,\fast_cycles_reg[24]_i_1_n_11 ,\fast_cycles_reg[24]_i_1_n_12 ,\fast_cycles_reg[24]_i_1_n_13 ,\fast_cycles_reg[24]_i_1_n_14 ,\fast_cycles_reg[24]_i_1_n_15 }),
        .S(fast_cycles_reg[31:24]));
  FDRE \fast_cycles_reg[25] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_14 ),
        .Q(fast_cycles_reg[25]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[26] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_13 ),
        .Q(fast_cycles_reg[26]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[27] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_12 ),
        .Q(fast_cycles_reg[27]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[28] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_11 ),
        .Q(fast_cycles_reg[28]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[29] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_10 ),
        .Q(fast_cycles_reg[29]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[2] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_13 ),
        .Q(fast_cycles_reg[2]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[30] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_9 ),
        .Q(fast_cycles_reg[30]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[31] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[24]_i_1_n_8 ),
        .Q(fast_cycles_reg[31]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[3] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_12 ),
        .Q(fast_cycles_reg[3]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[4] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_11 ),
        .Q(fast_cycles_reg[4]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[5] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_10 ),
        .Q(fast_cycles_reg[5]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[6] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_9 ),
        .Q(fast_cycles_reg[6]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[7] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[0]_i_2_n_8 ),
        .Q(fast_cycles_reg[7]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  FDRE \fast_cycles_reg[8] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_15 ),
        .Q(fast_cycles_reg[8]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_cycles_reg[8]_i_1 
       (.CI(\fast_cycles_reg[0]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\fast_cycles_reg[8]_i_1_n_0 ,\fast_cycles_reg[8]_i_1_n_1 ,\fast_cycles_reg[8]_i_1_n_2 ,\fast_cycles_reg[8]_i_1_n_3 ,\fast_cycles_reg[8]_i_1_n_4 ,\fast_cycles_reg[8]_i_1_n_5 ,\fast_cycles_reg[8]_i_1_n_6 ,\fast_cycles_reg[8]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_cycles_reg[8]_i_1_n_8 ,\fast_cycles_reg[8]_i_1_n_9 ,\fast_cycles_reg[8]_i_1_n_10 ,\fast_cycles_reg[8]_i_1_n_11 ,\fast_cycles_reg[8]_i_1_n_12 ,\fast_cycles_reg[8]_i_1_n_13 ,\fast_cycles_reg[8]_i_1_n_14 ,\fast_cycles_reg[8]_i_1_n_15 }),
        .S(fast_cycles_reg[15:8]));
  FDRE \fast_cycles_reg[9] 
       (.C(clk),
        .CE(fast_active),
        .D(\fast_cycles_reg[8]_i_1_n_14 ),
        .Q(fast_cycles_reg[9]),
        .R(\fast_cycles[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair59" *) 
  LUT4 #(
    .INIT(16'h8A88)) 
    \fast_error[0]_i_1 
       (.I0(rst_n),
        .I1(rx_error),
        .I2(\fast_error[0]_i_2_n_0 ),
        .I3(\fast_error[2]_i_3_n_0 ),
        .O(\fast_error[0]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0060000000600060)) 
    \fast_error[0]_i_2 
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(\state[3]_i_11_n_0 ),
        .I5(\state[3]_i_10_n_0 ),
        .O(\fast_error[0]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair129" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \fast_error[1]_i_1 
       (.I0(rst_n),
        .I1(\state[3]_i_4_n_0 ),
        .O(\fast_error[1]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'hBBBBFFBF)) 
    \fast_error[2]_i_1 
       (.I0(\state[3]_i_4_n_0 ),
        .I1(rst_n),
        .I2(\fast_error[2]_i_3_n_0 ),
        .I3(\fast_error[2]_i_4_n_0 ),
        .I4(reply_mem_reg_0_i_50_n_0),
        .O(\fast_error[2]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair129" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \fast_error[2]_i_2 
       (.I0(\state[3]_i_4_n_0 ),
        .I1(rst_n),
        .O(\fast_error[2]_i_2_n_0 ));
  LUT4 #(
    .INIT(16'hD0FF)) 
    \fast_error[2]_i_3 
       (.I0(fast_reply_data[2]),
        .I1(\fast_error[2]_i_5_n_0 ),
        .I2(\fast_error[2]_i_6_n_0 ),
        .I3(\reply_len[7]_i_6_n_0 ),
        .O(\fast_error[2]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hFEFF000000000000)) 
    \fast_error[2]_i_4 
       (.I0(fast_reply_data[0]),
        .I1(fast_reply_data[2]),
        .I2(fast_reply_data[1]),
        .I3(\fast_error[2]_i_6_n_0 ),
        .I4(\fast_error[2]_i_7_n_0 ),
        .I5(\reply_len[15]_i_8_n_0 ),
        .O(\fast_error[2]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0155015501550555)) 
    \fast_error[2]_i_5 
       (.I0(fast_reply_data[1]),
        .I1(p_0_in[6]),
        .I2(p_0_in[7]),
        .I3(fast_reply_data[0]),
        .I4(p_0_in[5]),
        .I5(\fast_error[2]_i_8_n_0 ),
        .O(\fast_error[2]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'h00000001)) 
    \fast_error[2]_i_6 
       (.I0(fast_reply_data[3]),
        .I1(fast_reply_data[5]),
        .I2(fast_reply_data[6]),
        .I3(fast_reply_data[4]),
        .I4(fast_reply_data[7]),
        .O(\fast_error[2]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair35" *) 
  LUT4 #(
    .INIT(16'h0040)) 
    \fast_error[2]_i_7 
       (.I0(\reply_index_reg_n_0_[1] ),
        .I1(\reply_index_reg_n_0_[0] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .I3(\reply_index_reg_n_0_[3] ),
        .O(\fast_error[2]_i_7_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair49" *) 
  LUT5 #(
    .INIT(32'hFE000000)) 
    \fast_error[2]_i_8 
       (.I0(p_0_in[2]),
        .I1(p_0_in[1]),
        .I2(p_0_in[0]),
        .I3(p_0_in[3]),
        .I4(p_0_in[4]),
        .O(\fast_error[2]_i_8_n_0 ));
  FDRE \fast_error_reg[0] 
       (.C(clk),
        .CE(\fast_error[2]_i_1_n_0 ),
        .D(\fast_error[0]_i_1_n_0 ),
        .Q(\fast_error_reg_n_0_[0] ),
        .R(1'b0));
  FDRE \fast_error_reg[1] 
       (.C(clk),
        .CE(\fast_error[2]_i_1_n_0 ),
        .D(\fast_error[1]_i_1_n_0 ),
        .Q(\fast_error_reg_n_0_[1] ),
        .R(1'b0));
  FDRE \fast_error_reg[2] 
       (.C(clk),
        .CE(\fast_error[2]_i_1_n_0 ),
        .D(\fast_error[2]_i_2_n_0 ),
        .Q(\fast_error_reg_n_0_[2] ),
        .R(1'b0));
  (* SOFT_HLUTNM = "soft_lutpair22" *) 
  LUT1 #(
    .INIT(2'h1)) 
    fast_reply_ready_INST_0
       (.I0(fast_reply_ready_INST_0_i_1_n_0),
        .O(fast_reply_ready));
  LUT6 #(
    .INIT(64'hFFFFFFFFFEAA0000)) 
    fast_reply_ready_INST_0_i_1
       (.I0(\reply_index_reg_n_0_[9] ),
        .I1(\reply_index_reg_n_0_[7] ),
        .I2(fast_reply_ready_INST_0_i_2_n_0),
        .I3(\reply_index_reg_n_0_[8] ),
        .I4(\reply_index_reg_n_0_[10] ),
        .I5(fast_reply_ready_INST_0_i_3_n_0),
        .O(fast_reply_ready_INST_0_i_1_n_0));
  LUT6 #(
    .INIT(64'hFFFE000000000000)) 
    fast_reply_ready_INST_0_i_2
       (.I0(\reply_index_reg_n_0_[2] ),
        .I1(\reply_index_reg_n_0_[3] ),
        .I2(\reply_index_reg_n_0_[4] ),
        .I3(\reply_index_reg_n_0_[1] ),
        .I4(\reply_index_reg_n_0_[5] ),
        .I5(\reply_index_reg_n_0_[6] ),
        .O(fast_reply_ready_INST_0_i_2_n_0));
  (* SOFT_HLUTNM = "soft_lutpair23" *) 
  LUT5 #(
    .INIT(32'hFFFFFDFF)) 
    fast_reply_ready_INST_0_i_3
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[2] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\reply_index_reg_n_0_[15] ),
        .O(fast_reply_ready_INST_0_i_3_n_0));
  LUT2 #(
    .INIT(4'h8)) 
    \fast_starts[0]_i_1 
       (.I0(\cmd_index[15]_i_3_n_0 ),
        .I1(\tx_index[15]_i_5_n_0 ),
        .O(cmd_index));
  LUT1 #(
    .INIT(2'h1)) 
    \fast_starts[0]_i_3 
       (.I0(fast_starts_reg[0]),
        .O(\fast_starts[0]_i_3_n_0 ));
  FDRE \fast_starts_reg[0] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_15 ),
        .Q(fast_starts_reg[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_starts_reg[0]_i_2 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\fast_starts_reg[0]_i_2_n_0 ,\fast_starts_reg[0]_i_2_n_1 ,\fast_starts_reg[0]_i_2_n_2 ,\fast_starts_reg[0]_i_2_n_3 ,\fast_starts_reg[0]_i_2_n_4 ,\fast_starts_reg[0]_i_2_n_5 ,\fast_starts_reg[0]_i_2_n_6 ,\fast_starts_reg[0]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\fast_starts_reg[0]_i_2_n_8 ,\fast_starts_reg[0]_i_2_n_9 ,\fast_starts_reg[0]_i_2_n_10 ,\fast_starts_reg[0]_i_2_n_11 ,\fast_starts_reg[0]_i_2_n_12 ,\fast_starts_reg[0]_i_2_n_13 ,\fast_starts_reg[0]_i_2_n_14 ,\fast_starts_reg[0]_i_2_n_15 }),
        .S({fast_starts_reg[7:1],\fast_starts[0]_i_3_n_0 }));
  FDRE \fast_starts_reg[10] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_13 ),
        .Q(fast_starts_reg[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[11] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_12 ),
        .Q(fast_starts_reg[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[12] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_11 ),
        .Q(fast_starts_reg[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[13] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_10 ),
        .Q(fast_starts_reg[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[14] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_9 ),
        .Q(fast_starts_reg[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[15] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_8 ),
        .Q(fast_starts_reg[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[16] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_15 ),
        .Q(fast_starts_reg[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_starts_reg[16]_i_1 
       (.CI(\fast_starts_reg[8]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\fast_starts_reg[16]_i_1_n_0 ,\fast_starts_reg[16]_i_1_n_1 ,\fast_starts_reg[16]_i_1_n_2 ,\fast_starts_reg[16]_i_1_n_3 ,\fast_starts_reg[16]_i_1_n_4 ,\fast_starts_reg[16]_i_1_n_5 ,\fast_starts_reg[16]_i_1_n_6 ,\fast_starts_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_starts_reg[16]_i_1_n_8 ,\fast_starts_reg[16]_i_1_n_9 ,\fast_starts_reg[16]_i_1_n_10 ,\fast_starts_reg[16]_i_1_n_11 ,\fast_starts_reg[16]_i_1_n_12 ,\fast_starts_reg[16]_i_1_n_13 ,\fast_starts_reg[16]_i_1_n_14 ,\fast_starts_reg[16]_i_1_n_15 }),
        .S(fast_starts_reg[23:16]));
  FDRE \fast_starts_reg[17] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_14 ),
        .Q(fast_starts_reg[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[18] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_13 ),
        .Q(fast_starts_reg[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[19] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_12 ),
        .Q(fast_starts_reg[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[1] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_14 ),
        .Q(fast_starts_reg[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[20] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_11 ),
        .Q(fast_starts_reg[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[21] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_10 ),
        .Q(fast_starts_reg[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[22] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_9 ),
        .Q(fast_starts_reg[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[23] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[16]_i_1_n_8 ),
        .Q(fast_starts_reg[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[24] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_15 ),
        .Q(fast_starts_reg[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_starts_reg[24]_i_1 
       (.CI(\fast_starts_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_fast_starts_reg[24]_i_1_CO_UNCONNECTED [7],\fast_starts_reg[24]_i_1_n_1 ,\fast_starts_reg[24]_i_1_n_2 ,\fast_starts_reg[24]_i_1_n_3 ,\fast_starts_reg[24]_i_1_n_4 ,\fast_starts_reg[24]_i_1_n_5 ,\fast_starts_reg[24]_i_1_n_6 ,\fast_starts_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_starts_reg[24]_i_1_n_8 ,\fast_starts_reg[24]_i_1_n_9 ,\fast_starts_reg[24]_i_1_n_10 ,\fast_starts_reg[24]_i_1_n_11 ,\fast_starts_reg[24]_i_1_n_12 ,\fast_starts_reg[24]_i_1_n_13 ,\fast_starts_reg[24]_i_1_n_14 ,\fast_starts_reg[24]_i_1_n_15 }),
        .S(fast_starts_reg[31:24]));
  FDRE \fast_starts_reg[25] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_14 ),
        .Q(fast_starts_reg[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[26] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_13 ),
        .Q(fast_starts_reg[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[27] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_12 ),
        .Q(fast_starts_reg[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[28] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_11 ),
        .Q(fast_starts_reg[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[29] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_10 ),
        .Q(fast_starts_reg[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[2] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_13 ),
        .Q(fast_starts_reg[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[30] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_9 ),
        .Q(fast_starts_reg[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[31] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[24]_i_1_n_8 ),
        .Q(fast_starts_reg[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[3] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_12 ),
        .Q(fast_starts_reg[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[4] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_11 ),
        .Q(fast_starts_reg[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[5] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_10 ),
        .Q(fast_starts_reg[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[6] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_9 ),
        .Q(fast_starts_reg[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[7] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[0]_i_2_n_8 ),
        .Q(fast_starts_reg[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \fast_starts_reg[8] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_15 ),
        .Q(fast_starts_reg[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \fast_starts_reg[8]_i_1 
       (.CI(\fast_starts_reg[0]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\fast_starts_reg[8]_i_1_n_0 ,\fast_starts_reg[8]_i_1_n_1 ,\fast_starts_reg[8]_i_1_n_2 ,\fast_starts_reg[8]_i_1_n_3 ,\fast_starts_reg[8]_i_1_n_4 ,\fast_starts_reg[8]_i_1_n_5 ,\fast_starts_reg[8]_i_1_n_6 ,\fast_starts_reg[8]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\fast_starts_reg[8]_i_1_n_8 ,\fast_starts_reg[8]_i_1_n_9 ,\fast_starts_reg[8]_i_1_n_10 ,\fast_starts_reg[8]_i_1_n_11 ,\fast_starts_reg[8]_i_1_n_12 ,\fast_starts_reg[8]_i_1_n_13 ,\fast_starts_reg[8]_i_1_n_14 ,\fast_starts_reg[8]_i_1_n_15 }),
        .S(fast_starts_reg[15:8]));
  FDRE \fast_starts_reg[9] 
       (.C(clk),
        .CE(cmd_index),
        .D(\fast_starts_reg[8]_i_1_n_14 ),
        .Q(fast_starts_reg[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair141" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[0]_i_1 
       (.I0(rx_data[0]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[0]));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[10]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[2]),
        .O(p_4_out[10]));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[11]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[3]),
        .O(p_4_out[11]));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[12]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[4]),
        .O(p_4_out[12]));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[13]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[5]),
        .O(p_4_out[13]));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[14]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[6]),
        .O(p_4_out[14]));
  LUT6 #(
    .INIT(64'h08000000AAAAAAAA)) 
    \header[15]_i_1 
       (.I0(\header[31]_i_3_n_0 ),
        .I1(\header[31]_i_4_n_0 ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[2] ),
        .I4(\header[15]_i_3_n_0 ),
        .I5(busy_INST_0_i_1_n_0),
        .O(\header[15]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[15]_i_2 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[7]),
        .O(p_4_out[15]));
  (* SOFT_HLUTNM = "soft_lutpair70" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \header[15]_i_3 
       (.I0(\count_reg_n_0_[0] ),
        .I1(\count_reg_n_0_[1] ),
        .O(\header[15]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFEFEE)) 
    \header[15]_i_4 
       (.I0(\payload_len[15]_i_5_n_0 ),
        .I1(p_1_in[1]),
        .I2(p_1_in[0]),
        .I3(\count_reg_n_0_[3] ),
        .I4(\count_reg_n_0_[1] ),
        .I5(\count_reg_n_0_[15] ),
        .O(\header[15]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair66" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[16]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[0]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[16]));
  (* SOFT_HLUTNM = "soft_lutpair66" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[17]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[1]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[17]));
  (* SOFT_HLUTNM = "soft_lutpair67" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[18]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[2]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[18]));
  (* SOFT_HLUTNM = "soft_lutpair67" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[19]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[3]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[19]));
  (* SOFT_HLUTNM = "soft_lutpair140" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[1]_i_1 
       (.I0(rx_data[1]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[1]));
  (* SOFT_HLUTNM = "soft_lutpair68" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[20]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[4]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[20]));
  (* SOFT_HLUTNM = "soft_lutpair68" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[21]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[5]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[21]));
  (* SOFT_HLUTNM = "soft_lutpair69" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[22]_i_1 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[6]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[22]));
  LUT6 #(
    .INIT(64'h08000000AAAAAAAA)) 
    \header[23]_i_1 
       (.I0(\header[31]_i_3_n_0 ),
        .I1(\header[31]_i_4_n_0 ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[3] ),
        .I4(busy_INST_0_i_2_n_0),
        .I5(busy_INST_0_i_1_n_0),
        .O(\header[23]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair69" *) 
  LUT4 #(
    .INIT(16'h0020)) 
    \header[23]_i_2 
       (.I0(\header[23]_i_3_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(rx_data[7]),
        .I3(\header[23]_i_4_n_0 ),
        .O(p_4_out[23]));
  (* SOFT_HLUTNM = "soft_lutpair70" *) 
  LUT4 #(
    .INIT(16'h0010)) 
    \header[23]_i_3 
       (.I0(busy_INST_0_i_3_n_0),
        .I1(p_1_in[4]),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[0] ),
        .O(\header[23]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair44" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \header[23]_i_4 
       (.I0(p_1_in[5]),
        .I1(\count_reg_n_0_[12] ),
        .I2(p_1_in[6]),
        .I3(\count_reg_n_0_[11] ),
        .I4(\header[23]_i_5_n_0 ),
        .O(\header[23]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair71" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    \header[23]_i_5 
       (.I0(\count_reg_n_0_[14] ),
        .I1(\count_reg_n_0_[13] ),
        .I2(\count_reg_n_0_[15] ),
        .I3(\count_reg_n_0_[1] ),
        .O(\header[23]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair123" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[24]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[0]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[24]));
  (* SOFT_HLUTNM = "soft_lutpair123" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[25]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[1]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[25]));
  (* SOFT_HLUTNM = "soft_lutpair124" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[26]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[2]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[26]));
  (* SOFT_HLUTNM = "soft_lutpair124" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[27]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[3]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[27]));
  (* SOFT_HLUTNM = "soft_lutpair125" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[28]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[4]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[28]));
  (* SOFT_HLUTNM = "soft_lutpair125" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[29]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[5]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[29]));
  (* SOFT_HLUTNM = "soft_lutpair141" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[2]_i_1 
       (.I0(rx_data[2]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[2]));
  (* SOFT_HLUTNM = "soft_lutpair126" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[30]_i_1 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[6]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[30]));
  LUT6 #(
    .INIT(64'h80000000AAAAAAAA)) 
    \header[31]_i_1 
       (.I0(\header[31]_i_3_n_0 ),
        .I1(\header[31]_i_4_n_0 ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[3] ),
        .I4(busy_INST_0_i_2_n_0),
        .I5(busy_INST_0_i_1_n_0),
        .O(\header[31]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair126" *) 
  LUT3 #(
    .INIT(8'h08)) 
    \header[31]_i_2 
       (.I0(\header[31]_i_5_n_0 ),
        .I1(rx_data[7]),
        .I2(\count_reg_n_0_[2] ),
        .O(p_4_out[31]));
  (* SOFT_HLUTNM = "soft_lutpair30" *) 
  LUT5 #(
    .INIT(32'h00000100)) 
    \header[31]_i_3 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(rx_valid),
        .I4(\state_reg_n_0_[2] ),
        .O(\header[31]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \header[31]_i_4 
       (.I0(busy_INST_0_i_5_n_0),
        .I1(\count_reg_n_0_[11] ),
        .I2(p_1_in[6]),
        .I3(p_1_in[5]),
        .I4(p_1_in[4]),
        .I5(busy_INST_0_i_3_n_0),
        .O(\header[31]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \header[31]_i_5 
       (.I0(\header[31]_i_6_n_0 ),
        .I1(\header[31]_i_7_n_0 ),
        .I2(\count_reg_n_0_[14] ),
        .I3(\count_reg_n_0_[13] ),
        .I4(\count_reg_n_0_[15] ),
        .I5(\count_reg_n_0_[1] ),
        .O(\header[31]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair42" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \header[31]_i_6 
       (.I0(busy_INST_0_i_3_n_0),
        .I1(p_1_in[4]),
        .I2(p_1_in[5]),
        .I3(p_1_in[6]),
        .I4(\count_reg_n_0_[11] ),
        .O(\header[31]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair53" *) 
  LUT5 #(
    .INIT(32'hEFEFFFEF)) 
    \header[31]_i_7 
       (.I0(\header[31]_i_8_n_0 ),
        .I1(\count_reg_n_0_[14] ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[12] ),
        .I4(\count_reg_n_0_[13] ),
        .O(\header[31]_i_7_n_0 ));
  LUT3 #(
    .INIT(8'h45)) 
    \header[31]_i_8 
       (.I0(p_1_in[1]),
        .I1(p_1_in[0]),
        .I2(\count_reg_n_0_[3] ),
        .O(\header[31]_i_8_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair139" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[3]_i_1 
       (.I0(rx_data[3]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[3]));
  (* SOFT_HLUTNM = "soft_lutpair138" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[4]_i_1 
       (.I0(rx_data[4]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[4]));
  (* SOFT_HLUTNM = "soft_lutpair137" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[5]_i_1 
       (.I0(rx_data[5]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[5]));
  (* SOFT_HLUTNM = "soft_lutpair136" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[6]_i_1 
       (.I0(rx_data[6]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[6]));
  LUT6 #(
    .INIT(64'h0000000400000000)) 
    \header[7]_i_1 
       (.I0(\state_reg_n_0_[2] ),
        .I1(rx_valid),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[3] ),
        .I5(\header[7]_i_3_n_0 ),
        .O(\header[7]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair135" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \header[7]_i_2 
       (.I0(rx_data[7]),
        .I1(\count_reg_n_0_[2] ),
        .O(p_4_out[7]));
  LUT6 #(
    .INIT(64'h5557555555555555)) 
    \header[7]_i_3 
       (.I0(busy_INST_0_i_1_n_0),
        .I1(\count_reg_n_0_[3] ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[1] ),
        .I4(\count_reg_n_0_[2] ),
        .I5(\header[31]_i_4_n_0 ),
        .O(\header[7]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[8]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[0]),
        .O(p_4_out[8]));
  LUT6 #(
    .INIT(64'h0000080000000000)) 
    \header[9]_i_1 
       (.I0(\payload_len[7]_i_2_n_0 ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\header[15]_i_4_n_0 ),
        .I5(rx_data[1]),
        .O(p_4_out[9]));
  FDRE \header_reg[0] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[0]),
        .Q(\header_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[10] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[10]),
        .Q(\header_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[11] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[11]),
        .Q(\header_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[12] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[12]),
        .Q(\header_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[13] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[13]),
        .Q(\header_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[14] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[14]),
        .Q(\header_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[15] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[15]),
        .Q(\header_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[16] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[16]),
        .Q(\header_reg_n_0_[16] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[17] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[17]),
        .Q(\header_reg_n_0_[17] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[18] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[18]),
        .Q(\header_reg_n_0_[18] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[19] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[19]),
        .Q(\header_reg_n_0_[19] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[1] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[1]),
        .Q(\header_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[20] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[20]),
        .Q(\header_reg_n_0_[20] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[21] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[21]),
        .Q(\header_reg_n_0_[21] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[22] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[22]),
        .Q(\header_reg_n_0_[22] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[23] 
       (.C(clk),
        .CE(\header[23]_i_1_n_0 ),
        .D(p_4_out[23]),
        .Q(\header_reg_n_0_[23] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[24] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[24]),
        .Q(\header_reg_n_0_[24] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[25] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[25]),
        .Q(\header_reg_n_0_[25] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[26] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[26]),
        .Q(\header_reg_n_0_[26] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[27] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[27]),
        .Q(\header_reg_n_0_[27] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[28] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[28]),
        .Q(\header_reg_n_0_[28] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[29] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[29]),
        .Q(\header_reg_n_0_[29] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[2] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[2]),
        .Q(\header_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[30] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[30]),
        .Q(\header_reg_n_0_[30] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[31] 
       (.C(clk),
        .CE(\header[31]_i_1_n_0 ),
        .D(p_4_out[31]),
        .Q(\header_reg_n_0_[31] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[3] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[3]),
        .Q(\header_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[4] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[4]),
        .Q(\header_reg_n_0_[4] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[5] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[5]),
        .Q(\header_reg_n_0_[5] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[6] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[6]),
        .Q(\header_reg_n_0_[6] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[7] 
       (.C(clk),
        .CE(\header[7]_i_1_n_0 ),
        .D(p_4_out[7]),
        .Q(\header_reg_n_0_[7] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[8] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[8]),
        .Q(\header_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \header_reg[9] 
       (.C(clk),
        .CE(\header[15]_i_1_n_0 ),
        .D(p_4_out[9]),
        .Q(\header_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0000008000000000)) 
    \host_quarter[1]_i_1 
       (.I0(\host_quarter[1]_i_2_n_0 ),
        .I1(\host_quarter[1]_i_3_n_0 ),
        .I2(\host_quarter[1]_i_4_n_0 ),
        .I3(\host_quarter[1]_i_5_n_0 ),
        .I4(\host_quarter[1]_i_6_n_0 ),
        .I5(p_104_in),
        .O(\host_quarter[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair23" *) 
  LUT4 #(
    .INIT(16'h0010)) 
    \host_quarter[1]_i_2 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[1] ),
        .O(\host_quarter[1]_i_2_n_0 ));
  LUT4 #(
    .INIT(16'h0010)) 
    \host_quarter[1]_i_3 
       (.I0(s_axi_araddr[16]),
        .I1(s_axi_araddr[17]),
        .I2(s_axi_araddr[12]),
        .I3(s_axi_araddr[11]),
        .O(\host_quarter[1]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair28" *) 
  LUT3 #(
    .INIT(8'h01)) 
    \host_quarter[1]_i_4 
       (.I0(s_axi_araddr[15]),
        .I1(s_axi_araddr[22]),
        .I2(s_axi_araddr[14]),
        .O(\host_quarter[1]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \host_quarter[1]_i_5 
       (.I0(s_axi_araddr[0]),
        .I1(s_axi_araddr[1]),
        .I2(s_axi_araddr[18]),
        .I3(s_axi_araddr[21]),
        .O(\host_quarter[1]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \host_quarter[1]_i_6 
       (.I0(s_axi_araddr[19]),
        .I1(s_axi_araddr[20]),
        .I2(s_axi_araddr[13]),
        .I3(s_axi_araddr[23]),
        .O(\host_quarter[1]_i_6_n_0 ));
  FDRE \host_quarter_reg[0] 
       (.C(clk),
        .CE(\host_quarter[1]_i_1_n_0 ),
        .D(s_axi_araddr[2]),
        .Q(\host_quarter_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \host_quarter_reg[1] 
       (.C(clk),
        .CE(\host_quarter[1]_i_1_n_0 ),
        .D(s_axi_araddr[3]),
        .Q(\host_quarter_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair57" *) 
  LUT3 #(
    .INIT(8'hF8)) 
    \hr[0]_i_1 
       (.I0(\hr_reg_n_0_[0] ),
        .I1(\hr_reg_n_0_[1] ),
        .I2(\host_quarter[1]_i_1_n_0 ),
        .O(\hr[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair58" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \hr[1]_i_1 
       (.I0(\hr_reg_n_0_[0] ),
        .I1(\s_axi_rdata[31]_i_5_n_0 ),
        .O(\hr[1]_i_1_n_0 ));
  FDRE \hr_reg[0] 
       (.C(clk),
        .CE(1'b1),
        .D(\hr[0]_i_1_n_0 ),
        .Q(\hr_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \hr_reg[1] 
       (.C(clk),
        .CE(1'b1),
        .D(\hr[1]_i_1_n_0 ),
        .Q(\hr_reg_n_0_[1] ),
        .R(1'b0));
  LUT1 #(
    .INIT(2'h1)) 
    \last_cycles[0]_i_1 
       (.I0(fast_cycles_reg[0]),
        .O(\last_cycles[0]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h00000020)) 
    \last_cycles[31]_i_1 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(engine_busy),
        .O(\last_cycles[31]_i_1_n_0 ));
  FDRE \last_cycles_reg[0] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles[0]_i_1_n_0 ),
        .Q(last_cycles[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[10] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_14 ),
        .Q(last_cycles[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[11] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_13 ),
        .Q(last_cycles[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[12] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_12 ),
        .Q(last_cycles[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[13] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_11 ),
        .Q(last_cycles[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[14] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_10 ),
        .Q(last_cycles[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[15] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_9 ),
        .Q(last_cycles[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[16] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_8 ),
        .Q(last_cycles[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \last_cycles_reg[16]_i_1 
       (.CI(\last_cycles_reg[8]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\last_cycles_reg[16]_i_1_n_0 ,\last_cycles_reg[16]_i_1_n_1 ,\last_cycles_reg[16]_i_1_n_2 ,\last_cycles_reg[16]_i_1_n_3 ,\last_cycles_reg[16]_i_1_n_4 ,\last_cycles_reg[16]_i_1_n_5 ,\last_cycles_reg[16]_i_1_n_6 ,\last_cycles_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\last_cycles_reg[16]_i_1_n_8 ,\last_cycles_reg[16]_i_1_n_9 ,\last_cycles_reg[16]_i_1_n_10 ,\last_cycles_reg[16]_i_1_n_11 ,\last_cycles_reg[16]_i_1_n_12 ,\last_cycles_reg[16]_i_1_n_13 ,\last_cycles_reg[16]_i_1_n_14 ,\last_cycles_reg[16]_i_1_n_15 }),
        .S(fast_cycles_reg[16:9]));
  FDRE \last_cycles_reg[17] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_15 ),
        .Q(last_cycles[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[18] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_14 ),
        .Q(last_cycles[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[19] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_13 ),
        .Q(last_cycles[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[1] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_15 ),
        .Q(last_cycles[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[20] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_12 ),
        .Q(last_cycles[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[21] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_11 ),
        .Q(last_cycles[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[22] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_10 ),
        .Q(last_cycles[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[23] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_9 ),
        .Q(last_cycles[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[24] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[24]_i_1_n_8 ),
        .Q(last_cycles[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \last_cycles_reg[24]_i_1 
       (.CI(\last_cycles_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\last_cycles_reg[24]_i_1_n_0 ,\last_cycles_reg[24]_i_1_n_1 ,\last_cycles_reg[24]_i_1_n_2 ,\last_cycles_reg[24]_i_1_n_3 ,\last_cycles_reg[24]_i_1_n_4 ,\last_cycles_reg[24]_i_1_n_5 ,\last_cycles_reg[24]_i_1_n_6 ,\last_cycles_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\last_cycles_reg[24]_i_1_n_8 ,\last_cycles_reg[24]_i_1_n_9 ,\last_cycles_reg[24]_i_1_n_10 ,\last_cycles_reg[24]_i_1_n_11 ,\last_cycles_reg[24]_i_1_n_12 ,\last_cycles_reg[24]_i_1_n_13 ,\last_cycles_reg[24]_i_1_n_14 ,\last_cycles_reg[24]_i_1_n_15 }),
        .S(fast_cycles_reg[24:17]));
  FDRE \last_cycles_reg[25] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_15 ),
        .Q(last_cycles[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[26] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_14 ),
        .Q(last_cycles[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[27] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_13 ),
        .Q(last_cycles[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[28] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_12 ),
        .Q(last_cycles[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[29] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_11 ),
        .Q(last_cycles[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[2] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_14 ),
        .Q(last_cycles[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[30] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_10 ),
        .Q(last_cycles[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[31] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[31]_i_2_n_9 ),
        .Q(last_cycles[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \last_cycles_reg[31]_i_2 
       (.CI(\last_cycles_reg[24]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_last_cycles_reg[31]_i_2_CO_UNCONNECTED [7:6],\last_cycles_reg[31]_i_2_n_2 ,\last_cycles_reg[31]_i_2_n_3 ,\last_cycles_reg[31]_i_2_n_4 ,\last_cycles_reg[31]_i_2_n_5 ,\last_cycles_reg[31]_i_2_n_6 ,\last_cycles_reg[31]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\NLW_last_cycles_reg[31]_i_2_O_UNCONNECTED [7],\last_cycles_reg[31]_i_2_n_9 ,\last_cycles_reg[31]_i_2_n_10 ,\last_cycles_reg[31]_i_2_n_11 ,\last_cycles_reg[31]_i_2_n_12 ,\last_cycles_reg[31]_i_2_n_13 ,\last_cycles_reg[31]_i_2_n_14 ,\last_cycles_reg[31]_i_2_n_15 }),
        .S({1'b0,fast_cycles_reg[31:25]}));
  FDRE \last_cycles_reg[3] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_13 ),
        .Q(last_cycles[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[4] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_12 ),
        .Q(last_cycles[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[5] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_11 ),
        .Q(last_cycles[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[6] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_10 ),
        .Q(last_cycles[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[7] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_9 ),
        .Q(last_cycles[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_cycles_reg[8] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[8]_i_1_n_8 ),
        .Q(last_cycles[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \last_cycles_reg[8]_i_1 
       (.CI(fast_cycles_reg[0]),
        .CI_TOP(1'b0),
        .CO({\last_cycles_reg[8]_i_1_n_0 ,\last_cycles_reg[8]_i_1_n_1 ,\last_cycles_reg[8]_i_1_n_2 ,\last_cycles_reg[8]_i_1_n_3 ,\last_cycles_reg[8]_i_1_n_4 ,\last_cycles_reg[8]_i_1_n_5 ,\last_cycles_reg[8]_i_1_n_6 ,\last_cycles_reg[8]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\last_cycles_reg[8]_i_1_n_8 ,\last_cycles_reg[8]_i_1_n_9 ,\last_cycles_reg[8]_i_1_n_10 ,\last_cycles_reg[8]_i_1_n_11 ,\last_cycles_reg[8]_i_1_n_12 ,\last_cycles_reg[8]_i_1_n_13 ,\last_cycles_reg[8]_i_1_n_14 ,\last_cycles_reg[8]_i_1_n_15 }),
        .S(fast_cycles_reg[8:1]));
  FDRE \last_cycles_reg[9] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\last_cycles_reg[16]_i_1_n_15 ),
        .Q(last_cycles[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[0] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[0]),
        .Q(\last_reply_len_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[10] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[10] ),
        .Q(\last_reply_len_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[11] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[11] ),
        .Q(\last_reply_len_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[12] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[12] ),
        .Q(\last_reply_len_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[13] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[13] ),
        .Q(\last_reply_len_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[14] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[14] ),
        .Q(\last_reply_len_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[15] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[15] ),
        .Q(\last_reply_len_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[1] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[1]),
        .Q(\last_reply_len_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[2] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[2]),
        .Q(\last_reply_len_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[3] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[3]),
        .Q(\last_reply_len_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[4] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[4]),
        .Q(\last_reply_len_reg_n_0_[4] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[5] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[5]),
        .Q(\last_reply_len_reg_n_0_[5] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[6] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[6]),
        .Q(\last_reply_len_reg_n_0_[6] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[7] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(p_0_in[7]),
        .Q(\last_reply_len_reg_n_0_[7] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[8] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[8] ),
        .Q(\last_reply_len_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \last_reply_len_reg[9] 
       (.C(clk),
        .CE(\last_cycles[31]_i_1_n_0 ),
        .D(\reply_len_reg_n_0_[9] ),
        .Q(\last_reply_len_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair80" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[10]_i_1 
       (.I0(rx_data[2]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[10]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair139" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[11]_i_1 
       (.I0(rx_data[3]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[11]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair138" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[12]_i_1 
       (.I0(rx_data[4]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[12]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair137" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[13]_i_1 
       (.I0(rx_data[5]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[13]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair136" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[14]_i_1 
       (.I0(rx_data[6]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[14]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAAAAAAAAABA)) 
    \payload_len[15]_i_1 
       (.I0(\completed[0]_i_1_n_0 ),
        .I1(\payload_len[15]_i_3_n_0 ),
        .I2(request_mem_reg_0_i_10_n_0),
        .I3(\payload_len[15]_i_4_n_0 ),
        .I4(\payload_len[15]_i_5_n_0 ),
        .I5(\payload_len[15]_i_6_n_0 ),
        .O(\payload_len[15]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair135" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[15]_i_2 
       (.I0(rx_data[7]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[15]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFEFFFF)) 
    \payload_len[15]_i_3 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(rx_valid),
        .I5(\count_reg_n_0_[15] ),
        .O(\payload_len[15]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair64" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \payload_len[15]_i_4 
       (.I0(\count_reg_n_0_[11] ),
        .I1(p_1_in[6]),
        .I2(p_1_in[5]),
        .O(\payload_len[15]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair6" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \payload_len[15]_i_5 
       (.I0(p_1_in[4]),
        .I1(p_1_in[3]),
        .I2(p_1_in[2]),
        .O(\payload_len[15]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair65" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    \payload_len[15]_i_6 
       (.I0(\payload_len[15]_i_7_n_0 ),
        .I1(\count_reg_n_0_[13] ),
        .I2(\count_reg_n_0_[14] ),
        .I3(\count_reg_n_0_[12] ),
        .O(\payload_len[15]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \payload_len[15]_i_7 
       (.I0(p_1_in[3]),
        .I1(p_1_in[0]),
        .I2(p_1_in[6]),
        .I3(\count_reg_n_0_[11] ),
        .I4(p_1_in[1]),
        .I5(p_1_in[4]),
        .O(\payload_len[15]_i_7_n_0 ));
  LUT5 #(
    .INIT(32'hAABAAAAA)) 
    \payload_len[7]_i_1 
       (.I0(\completed[0]_i_1_n_0 ),
        .I1(\payload_len[15]_i_3_n_0 ),
        .I2(p_50_in),
        .I3(\payload_len[15]_i_5_n_0 ),
        .I4(\payload_len[7]_i_2_n_0 ),
        .O(\payload_len[7]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair64" *) 
  LUT4 #(
    .INIT(16'h000D)) 
    \payload_len[7]_i_2 
       (.I0(p_1_in[5]),
        .I1(p_1_in[6]),
        .I2(\count_reg_n_0_[11] ),
        .I3(\payload_len[15]_i_6_n_0 ),
        .O(\payload_len[7]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair81" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[8]_i_1 
       (.I0(rx_data[0]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[8]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair140" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \payload_len[9]_i_1 
       (.I0(rx_data[1]),
        .I1(\state_reg_n_0_[2] ),
        .O(\payload_len[9]_i_1_n_0 ));
  FDRE \payload_len_reg[0] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[8]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[10] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[10]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[11] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[11]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[12] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[12]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[13] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[13]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[14] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[14]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[15] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[15]_i_2_n_0 ),
        .Q(\payload_len_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[1] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[9]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[2] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[10]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[3] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[11]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[4] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[12]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[4] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[5] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[13]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[5] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[6] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[14]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[6] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[7] 
       (.C(clk),
        .CE(\payload_len[7]_i_1_n_0 ),
        .D(\payload_len[15]_i_2_n_0 ),
        .Q(\payload_len_reg_n_0_[7] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[8] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[8]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \payload_len_reg[9] 
       (.C(clk),
        .CE(\payload_len[15]_i_1_n_0 ),
        .D(\payload_len[9]_i_1_n_0 ),
        .Q(\payload_len_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT1 #(
    .INIT(2'h1)) 
    \received[0]_i_2 
       (.I0(received_reg[0]),
        .O(\received[0]_i_2_n_0 ));
  FDRE \received_reg[0] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_15 ),
        .Q(received_reg[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \received_reg[0]_i_1 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\received_reg[0]_i_1_n_0 ,\received_reg[0]_i_1_n_1 ,\received_reg[0]_i_1_n_2 ,\received_reg[0]_i_1_n_3 ,\received_reg[0]_i_1_n_4 ,\received_reg[0]_i_1_n_5 ,\received_reg[0]_i_1_n_6 ,\received_reg[0]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\received_reg[0]_i_1_n_8 ,\received_reg[0]_i_1_n_9 ,\received_reg[0]_i_1_n_10 ,\received_reg[0]_i_1_n_11 ,\received_reg[0]_i_1_n_12 ,\received_reg[0]_i_1_n_13 ,\received_reg[0]_i_1_n_14 ,\received_reg[0]_i_1_n_15 }),
        .S({received_reg[7:1],\received[0]_i_2_n_0 }));
  FDRE \received_reg[10] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_13 ),
        .Q(received_reg[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[11] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_12 ),
        .Q(received_reg[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[12] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_11 ),
        .Q(received_reg[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[13] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_10 ),
        .Q(received_reg[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[14] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_9 ),
        .Q(received_reg[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[15] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_8 ),
        .Q(received_reg[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[16] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_15 ),
        .Q(received_reg[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \received_reg[16]_i_1 
       (.CI(\received_reg[8]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\received_reg[16]_i_1_n_0 ,\received_reg[16]_i_1_n_1 ,\received_reg[16]_i_1_n_2 ,\received_reg[16]_i_1_n_3 ,\received_reg[16]_i_1_n_4 ,\received_reg[16]_i_1_n_5 ,\received_reg[16]_i_1_n_6 ,\received_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\received_reg[16]_i_1_n_8 ,\received_reg[16]_i_1_n_9 ,\received_reg[16]_i_1_n_10 ,\received_reg[16]_i_1_n_11 ,\received_reg[16]_i_1_n_12 ,\received_reg[16]_i_1_n_13 ,\received_reg[16]_i_1_n_14 ,\received_reg[16]_i_1_n_15 }),
        .S(received_reg[23:16]));
  FDRE \received_reg[17] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_14 ),
        .Q(received_reg[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[18] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_13 ),
        .Q(received_reg[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[19] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_12 ),
        .Q(received_reg[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[1] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_14 ),
        .Q(received_reg[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[20] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_11 ),
        .Q(received_reg[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[21] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_10 ),
        .Q(received_reg[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[22] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_9 ),
        .Q(received_reg[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[23] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[16]_i_1_n_8 ),
        .Q(received_reg[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[24] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_15 ),
        .Q(received_reg[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \received_reg[24]_i_1 
       (.CI(\received_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_received_reg[24]_i_1_CO_UNCONNECTED [7],\received_reg[24]_i_1_n_1 ,\received_reg[24]_i_1_n_2 ,\received_reg[24]_i_1_n_3 ,\received_reg[24]_i_1_n_4 ,\received_reg[24]_i_1_n_5 ,\received_reg[24]_i_1_n_6 ,\received_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\received_reg[24]_i_1_n_8 ,\received_reg[24]_i_1_n_9 ,\received_reg[24]_i_1_n_10 ,\received_reg[24]_i_1_n_11 ,\received_reg[24]_i_1_n_12 ,\received_reg[24]_i_1_n_13 ,\received_reg[24]_i_1_n_14 ,\received_reg[24]_i_1_n_15 }),
        .S(received_reg[31:24]));
  FDRE \received_reg[25] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_14 ),
        .Q(received_reg[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[26] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_13 ),
        .Q(received_reg[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[27] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_12 ),
        .Q(received_reg[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[28] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_11 ),
        .Q(received_reg[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[29] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_10 ),
        .Q(received_reg[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[2] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_13 ),
        .Q(received_reg[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[30] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_9 ),
        .Q(received_reg[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[31] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[24]_i_1_n_8 ),
        .Q(received_reg[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[3] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_12 ),
        .Q(received_reg[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[4] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_11 ),
        .Q(received_reg[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[5] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_10 ),
        .Q(received_reg[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[6] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_9 ),
        .Q(received_reg[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[7] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[0]_i_1_n_8 ),
        .Q(received_reg[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \received_reg[8] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_15 ),
        .Q(received_reg[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \received_reg[8]_i_1 
       (.CI(\received_reg[0]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\received_reg[8]_i_1_n_0 ,\received_reg[8]_i_1_n_1 ,\received_reg[8]_i_1_n_2 ,\received_reg[8]_i_1_n_3 ,\received_reg[8]_i_1_n_4 ,\received_reg[8]_i_1_n_5 ,\received_reg[8]_i_1_n_6 ,\received_reg[8]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\received_reg[8]_i_1_n_8 ,\received_reg[8]_i_1_n_9 ,\received_reg[8]_i_1_n_10 ,\received_reg[8]_i_1_n_11 ,\received_reg[8]_i_1_n_12 ,\received_reg[8]_i_1_n_13 ,\received_reg[8]_i_1_n_14 ,\received_reg[8]_i_1_n_15 }),
        .S(received_reg[15:8]));
  FDRE \received_reg[9] 
       (.C(clk),
        .CE(received),
        .D(\received_reg[8]_i_1_n_14 ),
        .Q(received_reg[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair16" *) 
  LUT5 #(
    .INIT(32'hAAAAABAA)) 
    \reply_index[0]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[2] ),
        .O(\reply_index[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair54" *) 
  LUT4 #(
    .INIT(16'hABBA)) 
    \reply_index[10]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[10] ),
        .I3(\reply_index[10]_i_2_n_0 ),
        .O(\reply_index[10]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h8000000000000000)) 
    \reply_index[10]_i_2 
       (.I0(\reply_index_reg_n_0_[9] ),
        .I1(\reply_index_reg_n_0_[8] ),
        .I2(\reply_index[6]_i_2_n_0 ),
        .I3(\reply_index_reg_n_0_[6] ),
        .I4(\reply_index_reg_n_0_[5] ),
        .I5(\reply_index_reg_n_0_[7] ),
        .O(\reply_index[10]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h8888888888888FFF)) 
    \reply_index[15]_i_1 
       (.I0(\tx_index[15]_i_5_n_0 ),
        .I1(\cmd_index[15]_i_3_n_0 ),
        .I2(\state_reg_n_0_[0] ),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(\reply_index[15]_i_3_n_0 ),
        .I5(\reply_index[15]_i_4_n_0 ),
        .O(reply_index));
  LUT5 #(
    .INIT(32'h04000000)) 
    \reply_index[15]_i_2 
       (.I0(\reply_index[15]_i_5_n_0 ),
        .I1(aw[13]),
        .I2(\reply_index[15]_i_6_n_0 ),
        .I3(\reply_index[15]_i_7_n_0 ),
        .I4(p_105_in),
        .O(\reply_index[15]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair79" *) 
  LUT3 #(
    .INIT(8'h45)) 
    \reply_index[15]_i_3 
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[1] ),
        .I2(state1),
        .O(\reply_index[15]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair72" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \reply_index[15]_i_4 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[3] ),
        .O(\reply_index[15]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \reply_index[15]_i_5 
       (.I0(aw[15]),
        .I1(aw[14]),
        .I2(aw[12]),
        .I3(aw[11]),
        .O(\reply_index[15]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair25" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \reply_index[15]_i_6 
       (.I0(aw[16]),
        .I1(aw[22]),
        .I2(aw[20]),
        .I3(aw[21]),
        .I4(\reply_index[15]_i_8_n_0 ),
        .O(\reply_index[15]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000004)) 
    \reply_index[15]_i_7 
       (.I0(\state_reg_n_0_[1] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(aw[1]),
        .I5(aw[0]),
        .O(\reply_index[15]_i_7_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \reply_index[15]_i_8 
       (.I0(aw[19]),
        .I1(aw[17]),
        .I2(aw[23]),
        .I3(aw[18]),
        .O(\reply_index[15]_i_8_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair15" *) 
  LUT4 #(
    .INIT(16'hAABE)) 
    \reply_index[1]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\reply_index_reg_n_0_[0] ),
        .I2(\reply_index_reg_n_0_[1] ),
        .I3(reply_mem_reg_0_i_50_n_0),
        .O(\reply_index[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair15" *) 
  LUT5 #(
    .INIT(32'hABBABABA)) 
    \reply_index[2]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[2] ),
        .I3(\reply_index_reg_n_0_[0] ),
        .I4(\reply_index_reg_n_0_[1] ),
        .O(\reply_index[2]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAAABFFFEAAA)) 
    \reply_index[3]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\reply_index_reg_n_0_[2] ),
        .I2(\reply_index_reg_n_0_[0] ),
        .I3(\reply_index_reg_n_0_[1] ),
        .I4(\reply_index_reg_n_0_[3] ),
        .I5(reply_mem_reg_0_i_50_n_0),
        .O(\reply_index[3]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hABBABABABABABABA)) 
    \reply_index[4]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[4] ),
        .I3(\reply_index_reg_n_0_[2] ),
        .I4(\reply_index_reg_n_0_[3] ),
        .I5(reply_mem_reg_0_i_57_n_0),
        .O(\reply_index[4]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair14" *) 
  LUT4 #(
    .INIT(16'hABBA)) 
    \reply_index[5]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[5] ),
        .I3(\reply_index[6]_i_2_n_0 ),
        .O(\reply_index[5]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair14" *) 
  LUT5 #(
    .INIT(32'hABBABABA)) 
    \reply_index[6]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[6] ),
        .I3(\reply_index[6]_i_2_n_0 ),
        .I4(\reply_index_reg_n_0_[5] ),
        .O(\reply_index[6]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair37" *) 
  LUT5 #(
    .INIT(32'h80000000)) 
    \reply_index[6]_i_2 
       (.I0(\reply_index_reg_n_0_[4] ),
        .I1(\reply_index_reg_n_0_[2] ),
        .I2(\reply_index_reg_n_0_[3] ),
        .I3(\reply_index_reg_n_0_[1] ),
        .I4(\reply_index_reg_n_0_[0] ),
        .O(\reply_index[6]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAAABAABAAAA)) 
    \reply_index[7]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index[9]_i_2_n_0 ),
        .I3(\reply_index_reg_n_0_[7] ),
        .I4(\state_reg_n_0_[3] ),
        .I5(\state_reg_n_0_[2] ),
        .O(\reply_index[7]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair13" *) 
  LUT5 #(
    .INIT(32'hBABAABBA)) 
    \reply_index[8]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[8] ),
        .I3(\reply_index_reg_n_0_[7] ),
        .I4(\reply_index[9]_i_2_n_0 ),
        .O(\reply_index[8]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hBABAABBABABABABA)) 
    \reply_index[9]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[9] ),
        .I3(\reply_index_reg_n_0_[8] ),
        .I4(\reply_index[9]_i_2_n_0 ),
        .I5(\reply_index_reg_n_0_[7] ),
        .O(\reply_index[9]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h7FFFFFFFFFFFFFFF)) 
    \reply_index[9]_i_2 
       (.I0(\reply_index_reg_n_0_[5] ),
        .I1(\reply_index_reg_n_0_[6] ),
        .I2(reply_mem_reg_0_i_57_n_0),
        .I3(\reply_index_reg_n_0_[3] ),
        .I4(\reply_index_reg_n_0_[2] ),
        .I5(\reply_index_reg_n_0_[4] ),
        .O(\reply_index[9]_i_2_n_0 ));
  FDRE \reply_index_reg[0] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[0]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[10] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[10]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[15] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[15]_i_2_n_0 ),
        .Q(\reply_index_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[1] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[1]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[2] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[2]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[3] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[3]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[4] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[4]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[4] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[5] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[5]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[5] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[6] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[6]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[6] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[7] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[7]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[7] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[8] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[8]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_index_reg[9] 
       (.C(clk),
        .CE(reply_index),
        .D(\reply_index[9]_i_1_n_0 ),
        .Q(\reply_index_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'hFFFF0100)) 
    \reply_len[0]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[0]),
        .I4(\reply_len[0]_i_2_n_0 ),
        .O(\reply_len[0]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h0000F808)) 
    \reply_len[0]_i_2 
       (.I0(\reply_len[7]_i_5_n_0 ),
        .I1(fast_reply_data[0]),
        .I2(\reply_len[7]_i_6_n_0 ),
        .I3(p_0_in[0]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .O(\reply_len[0]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hCF0ACF0A0B0A0A0A)) 
    \reply_len[10]_i_1 
       (.I0(\reply_len[10]_i_2_n_0 ),
        .I1(\reply_len[15]_i_7_n_0 ),
        .I2(\reply_len[10]_i_3_n_0 ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\reply_len[10]_i_4_n_0 ),
        .O(\reply_len[10]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h5555555155555555)) 
    \reply_len[10]_i_2 
       (.I0(\state_reg_n_0_[3] ),
        .I1(rx_valid),
        .I2(\state_reg_n_0_[2] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[1] ),
        .I5(\request_len[15]_i_3_n_0 ),
        .O(\reply_len[10]_i_2_n_0 ));
  LUT2 #(
    .INIT(4'hB)) 
    \reply_len[10]_i_3 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(wd[10]),
        .O(\reply_len[10]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h90FF909090909090)) 
    \reply_len[10]_i_4 
       (.I0(fast_reply_data[2]),
        .I1(\reply_len[10]_i_5_n_0 ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\s_axi_bresp[1]_i_3_n_0 ),
        .I4(wd[10]),
        .I5(\reply_len[10]_i_6_n_0 ),
        .O(\reply_len[10]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair52" *) 
  LUT4 #(
    .INIT(16'hDFFF)) 
    \reply_len[10]_i_5 
       (.I0(fast_reply_data[0]),
        .I1(\reply_len[13]_i_3_n_0 ),
        .I2(p_0_in[7]),
        .I3(fast_reply_data[1]),
        .O(\reply_len[10]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair79" *) 
  LUT4 #(
    .INIT(16'hAAFB)) 
    \reply_len[10]_i_6 
       (.I0(\state_reg_n_0_[2] ),
        .I1(state1),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .O(\reply_len[10]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair55" *) 
  LUT4 #(
    .INIT(16'h8008)) 
    \reply_len[11]_i_1 
       (.I0(\state_reg_n_0_[0] ),
        .I1(\reply_len[15]_i_7_n_0 ),
        .I2(\reply_len[11]_i_2_n_0 ),
        .I3(fast_reply_data[3]),
        .O(\reply_len[11]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair52" *) 
  LUT5 #(
    .INIT(32'hF7FFFFFF)) 
    \reply_len[11]_i_2 
       (.I0(fast_reply_data[1]),
        .I1(p_0_in[7]),
        .I2(\reply_len[13]_i_3_n_0 ),
        .I3(fast_reply_data[0]),
        .I4(fast_reply_data[2]),
        .O(\reply_len[11]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair18" *) 
  LUT4 #(
    .INIT(16'h8008)) 
    \reply_len[12]_i_1 
       (.I0(\state_reg_n_0_[0] ),
        .I1(\reply_len[15]_i_7_n_0 ),
        .I2(\reply_len[13]_i_2_n_0 ),
        .I3(fast_reply_data[4]),
        .O(\reply_len[12]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair18" *) 
  LUT5 #(
    .INIT(32'hA2080000)) 
    \reply_len[13]_i_1 
       (.I0(\state_reg_n_0_[0] ),
        .I1(fast_reply_data[4]),
        .I2(\reply_len[13]_i_2_n_0 ),
        .I3(fast_reply_data[5]),
        .I4(\reply_len[15]_i_7_n_0 ),
        .O(\reply_len[13]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hF7FFFFFFFFFFFFFF)) 
    \reply_len[13]_i_2 
       (.I0(fast_reply_data[2]),
        .I1(fast_reply_data[0]),
        .I2(\reply_len[13]_i_3_n_0 ),
        .I3(p_0_in[7]),
        .I4(fast_reply_data[1]),
        .I5(fast_reply_data[3]),
        .O(\reply_len[13]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h557FFFFFFFFFFFFF)) 
    \reply_len[13]_i_3 
       (.I0(p_0_in[5]),
        .I1(p_0_in[2]),
        .I2(p_0_in[1]),
        .I3(p_0_in[3]),
        .I4(p_0_in[4]),
        .I5(p_0_in[6]),
        .O(\reply_len[13]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair19" *) 
  LUT3 #(
    .INIT(8'h82)) 
    \reply_len[14]_i_1 
       (.I0(\reply_len[15]_i_7_n_0 ),
        .I1(\reply_len[15]_i_6_n_0 ),
        .I2(fast_reply_data[6]),
        .O(\reply_len[14]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFF4F444F4F)) 
    \reply_len[15]_i_1 
       (.I0(\reply_len[15]_i_3_n_0 ),
        .I1(\reply_len[15]_i_4_n_0 ),
        .I2(\reply_len[15]_i_5_n_0 ),
        .I3(\cmd_index[15]_i_3_n_0 ),
        .I4(\s_axi_bresp[1]_i_3_n_0 ),
        .I5(received),
        .O(\reply_len[15]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair19" *) 
  LUT5 #(
    .INIT(32'h82880000)) 
    \reply_len[15]_i_2 
       (.I0(\state_reg_n_0_[0] ),
        .I1(fast_reply_data[7]),
        .I2(\reply_len[15]_i_6_n_0 ),
        .I3(fast_reply_data[6]),
        .I4(\reply_len[15]_i_7_n_0 ),
        .O(\reply_len[15]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair20" *) 
  LUT5 #(
    .INIT(32'hA2AAAAAA)) 
    \reply_len[15]_i_3 
       (.I0(\state_reg_n_0_[0] ),
        .I1(fast_reply_valid),
        .I2(fast_reply_ready_INST_0_i_1_n_0),
        .I3(reply_mem_reg_0_i_51_n_0),
        .I4(\reply_len[15]_i_8_n_0 ),
        .O(\reply_len[15]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT5 #(
    .INIT(32'h22220020)) 
    \reply_len[15]_i_4 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(state1),
        .I3(\state_reg_n_0_[1] ),
        .I4(\state_reg_n_0_[0] ),
        .O(\reply_len[15]_i_4_n_0 ));
  LUT5 #(
    .INIT(32'h5575FFFF)) 
    \reply_len[15]_i_5 
       (.I0(p_105_in),
        .I1(\reply_index[15]_i_6_n_0 ),
        .I2(aw[13]),
        .I3(\reply_index[15]_i_5_n_0 ),
        .I4(\s_axi_bresp[1]_i_5_n_0 ),
        .O(\reply_len[15]_i_5_n_0 ));
  LUT3 #(
    .INIT(8'hDF)) 
    \reply_len[15]_i_6 
       (.I0(fast_reply_data[4]),
        .I1(\reply_len[13]_i_2_n_0 ),
        .I2(fast_reply_data[5]),
        .O(\reply_len[15]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair20" *) 
  LUT4 #(
    .INIT(16'h0800)) 
    \reply_len[15]_i_7 
       (.I0(\reply_len[15]_i_8_n_0 ),
        .I1(reply_mem_reg_0_i_51_n_0),
        .I2(fast_reply_ready_INST_0_i_1_n_0),
        .I3(fast_reply_valid),
        .O(\reply_len[15]_i_7_n_0 ));
  LUT5 #(
    .INIT(32'h00000001)) 
    \reply_len[15]_i_8 
       (.I0(\reply_index_reg_n_0_[15] ),
        .I1(\reply_index_reg_n_0_[10] ),
        .I2(\reply_index_reg_n_0_[9] ),
        .I3(\reply_index_reg_n_0_[8] ),
        .I4(\reply_len[15]_i_9_n_0 ),
        .O(\reply_len[15]_i_8_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \reply_len[15]_i_9 
       (.I0(\reply_index_reg_n_0_[6] ),
        .I1(\reply_index_reg_n_0_[7] ),
        .I2(\reply_index_reg_n_0_[4] ),
        .I3(\reply_index_reg_n_0_[5] ),
        .O(\reply_len[15]_i_9_n_0 ));
  LUT5 #(
    .INIT(32'hFFFF0100)) 
    \reply_len[1]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[1]),
        .I4(\reply_len[1]_i_2_n_0 ),
        .O(\reply_len[1]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h00405540)) 
    \reply_len[1]_i_2 
       (.I0(reply_mem_reg_0_i_50_n_0),
        .I1(\reply_len[7]_i_5_n_0 ),
        .I2(fast_reply_data[1]),
        .I3(\reply_len[7]_i_6_n_0 ),
        .I4(p_0_in[1]),
        .O(\reply_len[1]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0100FFFF01000100)) 
    \reply_len[2]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[2]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[2]_i_2_n_0 ),
        .O(\reply_len[2]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h6060FF6060606060)) 
    \reply_len[2]_i_2 
       (.I0(p_0_in[2]),
        .I1(p_0_in[1]),
        .I2(\reply_len[7]_i_6_n_0 ),
        .I3(fast_reply_data[2]),
        .I4(reply_mem_reg_0_i_51_n_0),
        .I5(\reply_len[7]_i_5_n_0 ),
        .O(\reply_len[2]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0100FFFF01000100)) 
    \reply_len[3]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[3]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[3]_i_2_n_0 ),
        .O(\reply_len[3]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hFF4040FF40404040)) 
    \reply_len[3]_i_2 
       (.I0(reply_mem_reg_0_i_51_n_0),
        .I1(fast_reply_data[3]),
        .I2(\reply_len[7]_i_5_n_0 ),
        .I3(p_0_in[3]),
        .I4(\reply_len[3]_i_3_n_0 ),
        .I5(\reply_len[7]_i_6_n_0 ),
        .O(\reply_len[3]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair49" *) 
  LUT2 #(
    .INIT(4'h8)) 
    \reply_len[3]_i_3 
       (.I0(p_0_in[2]),
        .I1(p_0_in[1]),
        .O(\reply_len[3]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0100FFFF01000100)) 
    \reply_len[4]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[4]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[4]_i_2_n_0 ),
        .O(\reply_len[4]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h9090FF9090909090)) 
    \reply_len[4]_i_2 
       (.I0(p_0_in[4]),
        .I1(\reply_len[4]_i_3_n_0 ),
        .I2(\reply_len[7]_i_6_n_0 ),
        .I3(fast_reply_data[4]),
        .I4(reply_mem_reg_0_i_51_n_0),
        .I5(\reply_len[7]_i_5_n_0 ),
        .O(\reply_len[4]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair39" *) 
  LUT3 #(
    .INIT(8'h15)) 
    \reply_len[4]_i_3 
       (.I0(p_0_in[3]),
        .I1(p_0_in[1]),
        .I2(p_0_in[2]),
        .O(\reply_len[4]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0100FFFF01000100)) 
    \reply_len[5]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[5]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[5]_i_2_n_0 ),
        .O(\reply_len[5]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h8282FF8282828282)) 
    \reply_len[5]_i_2 
       (.I0(\reply_len[7]_i_6_n_0 ),
        .I1(p_0_in[5]),
        .I2(\reply_len[5]_i_3_n_0 ),
        .I3(fast_reply_data[5]),
        .I4(reply_mem_reg_0_i_51_n_0),
        .I5(\reply_len[7]_i_5_n_0 ),
        .O(\reply_len[5]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair9" *) 
  LUT4 #(
    .INIT(16'h07FF)) 
    \reply_len[5]_i_3 
       (.I0(p_0_in[2]),
        .I1(p_0_in[1]),
        .I2(p_0_in[3]),
        .I3(p_0_in[4]),
        .O(\reply_len[5]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0100FFFF01000100)) 
    \reply_len[6]_i_1 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[6]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[6]_i_2_n_0 ),
        .O(\reply_len[6]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h8282FF8282828282)) 
    \reply_len[6]_i_2 
       (.I0(\reply_len[7]_i_6_n_0 ),
        .I1(p_0_in[6]),
        .I2(\reply_len[6]_i_3_n_0 ),
        .I3(fast_reply_data[6]),
        .I4(reply_mem_reg_0_i_51_n_0),
        .I5(\reply_len[7]_i_5_n_0 ),
        .O(\reply_len[6]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair9" *) 
  LUT5 #(
    .INIT(32'h5777FFFF)) 
    \reply_len[6]_i_3 
       (.I0(p_0_in[4]),
        .I1(p_0_in[3]),
        .I2(p_0_in[1]),
        .I3(p_0_in[2]),
        .I4(p_0_in[5]),
        .O(\reply_len[6]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFF45)) 
    \reply_len[7]_i_1 
       (.I0(\reply_len[15]_i_5_n_0 ),
        .I1(\cmd_index[15]_i_3_n_0 ),
        .I2(\s_axi_bresp[1]_i_3_n_0 ),
        .I3(received),
        .I4(\reply_len[7]_i_3_n_0 ),
        .O(\reply_len[7]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0100FFFF01000100)) 
    \reply_len[7]_i_2 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[7]_i_3_n_0 ),
        .I2(received),
        .I3(wd[7]),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[7]_i_4_n_0 ),
        .O(\reply_len[7]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0000100010101010)) 
    \reply_len[7]_i_3 
       (.I0(\reply_index[15]_i_3_n_0 ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\reply_len[7]_i_5_n_0 ),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\reply_len[15]_i_3_n_0 ),
        .O(\reply_len[7]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hFF4040404040FF40)) 
    \reply_len[7]_i_4 
       (.I0(reply_mem_reg_0_i_51_n_0),
        .I1(fast_reply_data[7]),
        .I2(\reply_len[7]_i_5_n_0 ),
        .I3(\reply_len[7]_i_6_n_0 ),
        .I4(p_0_in[7]),
        .I5(\reply_len[13]_i_3_n_0 ),
        .O(\reply_len[7]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair35" *) 
  LUT5 #(
    .INIT(32'h00002000)) 
    \reply_len[7]_i_5 
       (.I0(\reply_len[15]_i_8_n_0 ),
        .I1(\reply_index_reg_n_0_[3] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .I3(\reply_index_reg_n_0_[1] ),
        .I4(\reply_index_reg_n_0_[0] ),
        .O(\reply_len[7]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h0000000100000000)) 
    \reply_len[7]_i_6 
       (.I0(\reply_len[15]_i_9_n_0 ),
        .I1(\reply_index_reg_n_0_[8] ),
        .I2(\reply_index_reg_n_0_[9] ),
        .I3(\reply_index_reg_n_0_[10] ),
        .I4(\reply_index_reg_n_0_[15] ),
        .I5(reply_mem_reg_0_i_51_n_0),
        .O(\reply_len[7]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hCF0ACF0A0B0A0A0A)) 
    \reply_len[8]_i_1 
       (.I0(\reply_len[10]_i_2_n_0 ),
        .I1(\reply_len[15]_i_7_n_0 ),
        .I2(\reply_len[8]_i_2_n_0 ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\reply_len[8]_i_3_n_0 ),
        .O(\reply_len[8]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair56" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \reply_len[8]_i_2 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(wd[8]),
        .O(\reply_len[8]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h90FF909090909090)) 
    \reply_len[8]_i_3 
       (.I0(fast_reply_data[0]),
        .I1(\reply_len[8]_i_4_n_0 ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\s_axi_bresp[1]_i_3_n_0 ),
        .I4(wd[8]),
        .I5(\reply_len[10]_i_6_n_0 ),
        .O(\reply_len[8]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair83" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \reply_len[8]_i_4 
       (.I0(\reply_len[13]_i_3_n_0 ),
        .I1(p_0_in[7]),
        .O(\reply_len[8]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hCF0ACF0A0B0A0A0A)) 
    \reply_len[9]_i_1 
       (.I0(\reply_len[10]_i_2_n_0 ),
        .I1(\reply_len[15]_i_7_n_0 ),
        .I2(\reply_len[9]_i_2_n_0 ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\reply_len[9]_i_3_n_0 ),
        .O(\reply_len[9]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair128" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \reply_len[9]_i_2 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(wd[9]),
        .O(\reply_len[9]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h90FF909090909090)) 
    \reply_len[9]_i_3 
       (.I0(fast_reply_data[1]),
        .I1(\reply_len[9]_i_4_n_0 ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\s_axi_bresp[1]_i_3_n_0 ),
        .I4(wd[9]),
        .I5(\reply_len[10]_i_6_n_0 ),
        .O(\reply_len[9]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair83" *) 
  LUT3 #(
    .INIT(8'hDF)) 
    \reply_len[9]_i_4 
       (.I0(p_0_in[7]),
        .I1(\reply_len[13]_i_3_n_0 ),
        .I2(fast_reply_data[0]),
        .O(\reply_len[9]_i_4_n_0 ));
  FDRE \reply_len_reg[0] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[0]_i_1_n_0 ),
        .Q(p_0_in[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[10] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[10]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[11] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[11]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[12] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[12]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[13] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[13]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[14] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[14]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[15] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[15]_i_2_n_0 ),
        .Q(\reply_len_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[1] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[1]_i_1_n_0 ),
        .Q(p_0_in[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[2] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[2]_i_1_n_0 ),
        .Q(p_0_in[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[3] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[3]_i_1_n_0 ),
        .Q(p_0_in[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[4] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[4]_i_1_n_0 ),
        .Q(p_0_in[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[5] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[5]_i_1_n_0 ),
        .Q(p_0_in[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[6] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[6]_i_1_n_0 ),
        .Q(p_0_in[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[7] 
       (.C(clk),
        .CE(\reply_len[7]_i_1_n_0 ),
        .D(\reply_len[7]_i_2_n_0 ),
        .Q(p_0_in[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[8] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[8]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \reply_len_reg[9] 
       (.C(clk),
        .CE(\reply_len[15]_i_1_n_0 ),
        .D(\reply_len[9]_i_1_n_0 ),
        .Q(\reply_len_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* METHODOLOGY_DRC_VIOS = "" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "16384" *) 
  (* RTL_RAM_NAME = "v13_ps_mailbox/reply_mem_reg" *) 
  (* RTL_RAM_STYLE = "block" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "127" *) 
  (* ram_offset = "384" *) 
  (* ram_slice_begin = "0" *) 
  (* ram_slice_end = "63" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("NONE"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(1),
    .DOB_REG(1),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(72),
    .READ_WIDTH_B(0),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("READ_FIRST"),
    .WRITE_WIDTH_A(0),
    .WRITE_WIDTH_B(72)) 
    reply_mem_reg_0
       (.ADDRARDADDR({1'b1,1'b1,\tx_index_reg_n_0_[10] ,\tx_index_reg_n_0_[9] ,\tx_index_reg_n_0_[8] ,\tx_index_reg_n_0_[7] ,\tx_index_reg_n_0_[6] ,\tx_index_reg_n_0_[5] ,\tx_index_reg_n_0_[4] ,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRBWRADDR({1'b1,1'b1,reply_wa,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA(NLW_reply_mem_reg_0_CASDINA_UNCONNECTED[31:0]),
        .CASDINB(NLW_reply_mem_reg_0_CASDINB_UNCONNECTED[31:0]),
        .CASDINPA(NLW_reply_mem_reg_0_CASDINPA_UNCONNECTED[3:0]),
        .CASDINPB(NLW_reply_mem_reg_0_CASDINPB_UNCONNECTED[3:0]),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_reply_mem_reg_0_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_reply_mem_reg_0_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_reply_mem_reg_0_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_reply_mem_reg_0_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_reply_mem_reg_0_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_reply_mem_reg_0_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .DBITERR(NLW_reply_mem_reg_0_DBITERR_UNCONNECTED),
        .DINADIN({reply_mem_reg_0_i_10_n_0,reply_mem_reg_0_i_11_n_0,reply_mem_reg_0_i_12_n_0,reply_mem_reg_0_i_13_n_0,reply_mem_reg_0_i_14_n_0,reply_mem_reg_0_i_15_n_0,reply_mem_reg_0_i_16_n_0,reply_mem_reg_0_i_17_n_0,reply_mem_reg_0_i_18_n_0,reply_mem_reg_0_i_19_n_0,reply_mem_reg_0_i_20_n_0,reply_mem_reg_0_i_21_n_0,reply_mem_reg_0_i_22_n_0,reply_mem_reg_0_i_23_n_0,reply_mem_reg_0_i_24_n_0,reply_mem_reg_0_i_25_n_0,reply_mem_reg_0_i_26_n_0,reply_mem_reg_0_i_27_n_0,reply_mem_reg_0_i_28_n_0,reply_mem_reg_0_i_29_n_0,reply_mem_reg_0_i_30_n_0,reply_mem_reg_0_i_31_n_0,reply_mem_reg_0_i_32_n_0,reply_mem_reg_0_i_33_n_0,p_0_in__0}),
        .DINBDIN({reply_mem_reg_0_i_10_n_0,reply_mem_reg_0_i_11_n_0,reply_mem_reg_0_i_12_n_0,reply_mem_reg_0_i_13_n_0,reply_mem_reg_0_i_14_n_0,reply_mem_reg_0_i_15_n_0,reply_mem_reg_0_i_16_n_0,reply_mem_reg_0_i_17_n_0,reply_mem_reg_0_i_18_n_0,reply_mem_reg_0_i_19_n_0,reply_mem_reg_0_i_20_n_0,reply_mem_reg_0_i_21_n_0,reply_mem_reg_0_i_22_n_0,reply_mem_reg_0_i_23_n_0,reply_mem_reg_0_i_24_n_0,reply_mem_reg_0_i_25_n_0,reply_mem_reg_0_i_26_n_0,reply_mem_reg_0_i_27_n_0,reply_mem_reg_0_i_28_n_0,reply_mem_reg_0_i_29_n_0,reply_mem_reg_0_i_30_n_0,reply_mem_reg_0_i_31_n_0,reply_mem_reg_0_i_32_n_0,reply_mem_reg_0_i_33_n_0,p_0_in__0}),
        .DINPADINP({1'b1,1'b1,1'b1,1'b1}),
        .DINPBDINP({1'b1,1'b1,1'b1,1'b1}),
        .DOUTADOUT({data3,data2,data1,reply_q}),
        .DOUTBDOUT({data7,data6,data5,data4}),
        .DOUTPADOUTP(NLW_reply_mem_reg_0_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_reply_mem_reg_0_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_reply_mem_reg_0_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(1'b1),
        .ENBWREN(reply_we),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_reply_mem_reg_0_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(reply_mem_reg_0_i_2_n_0),
        .REGCEB(1'b0),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(\s_axi_bresp[1]_i_1_n_0 ),
        .RSTREGB(1'b0),
        .SBITERR(NLW_reply_mem_reg_0_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({1'b0,1'b0,1'b0,1'b0}),
        .WEBWE({p_0_in14_in,p_0_in12_in,p_0_in10_in,p_0_in8_in,p_0_in6_in,p_0_in4_in,reply_mem_reg_0_i_48_n_0,reply_mem_reg_0_i_49_n_0}));
  (* SOFT_HLUTNM = "soft_lutpair13" *) 
  LUT2 #(
    .INIT(4'hB)) 
    reply_mem_reg_0_i_1
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .O(reply_we));
  (* SOFT_HLUTNM = "soft_lutpair120" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_10
       (.I0(wd[31]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[7]),
        .O(reply_mem_reg_0_i_10_n_0));
  (* SOFT_HLUTNM = "soft_lutpair119" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_11
       (.I0(wd[30]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[6]),
        .O(reply_mem_reg_0_i_11_n_0));
  (* SOFT_HLUTNM = "soft_lutpair118" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_12
       (.I0(wd[29]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[5]),
        .O(reply_mem_reg_0_i_12_n_0));
  (* SOFT_HLUTNM = "soft_lutpair117" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_13
       (.I0(wd[28]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[4]),
        .O(reply_mem_reg_0_i_13_n_0));
  (* SOFT_HLUTNM = "soft_lutpair116" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_14
       (.I0(wd[27]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[3]),
        .O(reply_mem_reg_0_i_14_n_0));
  (* SOFT_HLUTNM = "soft_lutpair115" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_15
       (.I0(wd[26]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[2]),
        .O(reply_mem_reg_0_i_15_n_0));
  (* SOFT_HLUTNM = "soft_lutpair114" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_16
       (.I0(wd[25]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[1]),
        .O(reply_mem_reg_0_i_16_n_0));
  (* SOFT_HLUTNM = "soft_lutpair113" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_17
       (.I0(wd[24]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[0]),
        .O(reply_mem_reg_0_i_17_n_0));
  (* SOFT_HLUTNM = "soft_lutpair120" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_18
       (.I0(wd[23]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[7]),
        .O(reply_mem_reg_0_i_18_n_0));
  (* SOFT_HLUTNM = "soft_lutpair119" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_19
       (.I0(wd[22]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[6]),
        .O(reply_mem_reg_0_i_19_n_0));
  (* SOFT_HLUTNM = "soft_lutpair24" *) 
  LUT4 #(
    .INIT(16'h1000)) 
    reply_mem_reg_0_i_2
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .O(reply_mem_reg_0_i_2_n_0));
  (* SOFT_HLUTNM = "soft_lutpair118" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_20
       (.I0(wd[21]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[5]),
        .O(reply_mem_reg_0_i_20_n_0));
  (* SOFT_HLUTNM = "soft_lutpair117" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_21
       (.I0(wd[20]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[4]),
        .O(reply_mem_reg_0_i_21_n_0));
  (* SOFT_HLUTNM = "soft_lutpair116" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_22
       (.I0(wd[19]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[3]),
        .O(reply_mem_reg_0_i_22_n_0));
  (* SOFT_HLUTNM = "soft_lutpair115" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_23
       (.I0(wd[18]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[2]),
        .O(reply_mem_reg_0_i_23_n_0));
  (* SOFT_HLUTNM = "soft_lutpair114" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_24
       (.I0(wd[17]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[1]),
        .O(reply_mem_reg_0_i_24_n_0));
  (* SOFT_HLUTNM = "soft_lutpair113" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_25
       (.I0(wd[16]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[0]),
        .O(reply_mem_reg_0_i_25_n_0));
  (* SOFT_HLUTNM = "soft_lutpair112" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_26
       (.I0(wd[15]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[7]),
        .O(reply_mem_reg_0_i_26_n_0));
  (* SOFT_HLUTNM = "soft_lutpair111" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_27
       (.I0(wd[14]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[6]),
        .O(reply_mem_reg_0_i_27_n_0));
  (* SOFT_HLUTNM = "soft_lutpair110" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_28
       (.I0(wd[13]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[5]),
        .O(reply_mem_reg_0_i_28_n_0));
  (* SOFT_HLUTNM = "soft_lutpair109" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_29
       (.I0(wd[12]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[4]),
        .O(reply_mem_reg_0_i_29_n_0));
  (* SOFT_HLUTNM = "soft_lutpair54" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_3
       (.I0(aw[10]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[10] ),
        .O(reply_wa[6]));
  (* SOFT_HLUTNM = "soft_lutpair108" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_30
       (.I0(wd[11]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[3]),
        .O(reply_mem_reg_0_i_30_n_0));
  (* SOFT_HLUTNM = "soft_lutpair107" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_31
       (.I0(wd[10]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[2]),
        .O(reply_mem_reg_0_i_31_n_0));
  (* SOFT_HLUTNM = "soft_lutpair106" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_32
       (.I0(wd[9]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[1]),
        .O(reply_mem_reg_0_i_32_n_0));
  (* SOFT_HLUTNM = "soft_lutpair105" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_33
       (.I0(wd[8]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[0]),
        .O(reply_mem_reg_0_i_33_n_0));
  (* SOFT_HLUTNM = "soft_lutpair112" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_34
       (.I0(wd[7]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[7]),
        .O(p_0_in__0[7]));
  (* SOFT_HLUTNM = "soft_lutpair111" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_35
       (.I0(wd[6]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[6]),
        .O(p_0_in__0[6]));
  (* SOFT_HLUTNM = "soft_lutpair110" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_36
       (.I0(wd[5]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[5]),
        .O(p_0_in__0[5]));
  (* SOFT_HLUTNM = "soft_lutpair109" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_37
       (.I0(wd[4]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[4]),
        .O(p_0_in__0[4]));
  (* SOFT_HLUTNM = "soft_lutpair108" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_38
       (.I0(wd[3]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[3]),
        .O(p_0_in__0[3]));
  (* SOFT_HLUTNM = "soft_lutpair107" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_39
       (.I0(wd[2]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[2]),
        .O(p_0_in__0[2]));
  (* SOFT_HLUTNM = "soft_lutpair104" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_4
       (.I0(aw[9]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[9] ),
        .O(reply_wa[5]));
  (* SOFT_HLUTNM = "soft_lutpair106" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_40
       (.I0(wd[1]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[1]),
        .O(p_0_in__0[1]));
  (* SOFT_HLUTNM = "soft_lutpair105" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_41
       (.I0(wd[0]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(fast_reply_data[0]),
        .O(p_0_in__0[0]));
  (* SOFT_HLUTNM = "soft_lutpair21" *) 
  LUT5 #(
    .INIT(32'h40FF4000)) 
    reply_mem_reg_0_i_42
       (.I0(aw[3]),
        .I1(ws[3]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_51_n_0),
        .O(p_0_in14_in));
  LUT6 #(
    .INIT(64'h4000400040FF4000)) 
    reply_mem_reg_0_i_43
       (.I0(aw[3]),
        .I1(ws[2]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_52_n_0),
        .I5(reply_mem_reg_0_i_53_n_0),
        .O(p_0_in12_in));
  LUT6 #(
    .INIT(64'h4000400040FF4000)) 
    reply_mem_reg_0_i_44
       (.I0(aw[3]),
        .I1(ws[1]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_54_n_0),
        .I5(reply_mem_reg_0_i_53_n_0),
        .O(p_0_in10_in));
  LUT6 #(
    .INIT(64'h4000400040FF4000)) 
    reply_mem_reg_0_i_45
       (.I0(aw[3]),
        .I1(ws[0]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_55_n_0),
        .I5(reply_mem_reg_0_i_53_n_0),
        .O(p_0_in8_in));
  LUT6 #(
    .INIT(64'h04FF040004000400)) 
    reply_mem_reg_0_i_46
       (.I0(aw[3]),
        .I1(ws[3]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_56_n_0),
        .I5(reply_mem_reg_0_i_57_n_0),
        .O(p_0_in6_in));
  LUT6 #(
    .INIT(64'h04FF040004000400)) 
    reply_mem_reg_0_i_47
       (.I0(aw[3]),
        .I1(ws[2]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_56_n_0),
        .I5(reply_mem_reg_0_i_52_n_0),
        .O(p_0_in4_in));
  LUT6 #(
    .INIT(64'h04FF040004000400)) 
    reply_mem_reg_0_i_48
       (.I0(aw[3]),
        .I1(ws[1]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_56_n_0),
        .I5(reply_mem_reg_0_i_54_n_0),
        .O(reply_mem_reg_0_i_48_n_0));
  LUT6 #(
    .INIT(64'h04FF040004000400)) 
    reply_mem_reg_0_i_49
       (.I0(aw[3]),
        .I1(ws[0]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_0_i_56_n_0),
        .I5(reply_mem_reg_0_i_55_n_0),
        .O(reply_mem_reg_0_i_49_n_0));
  (* SOFT_HLUTNM = "soft_lutpair104" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_5
       (.I0(aw[8]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[8] ),
        .O(reply_wa[4]));
  LUT2 #(
    .INIT(4'hB)) 
    reply_mem_reg_0_i_50
       (.I0(fast_reply_ready_INST_0_i_1_n_0),
        .I1(fast_reply_valid),
        .O(reply_mem_reg_0_i_50_n_0));
  (* SOFT_HLUTNM = "soft_lutpair36" *) 
  LUT4 #(
    .INIT(16'h0080)) 
    reply_mem_reg_0_i_51
       (.I0(\reply_index_reg_n_0_[0] ),
        .I1(\reply_index_reg_n_0_[1] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .I3(\reply_index_reg_n_0_[3] ),
        .O(reply_mem_reg_0_i_51_n_0));
  (* SOFT_HLUTNM = "soft_lutpair38" *) 
  LUT2 #(
    .INIT(4'h2)) 
    reply_mem_reg_0_i_52
       (.I0(\reply_index_reg_n_0_[1] ),
        .I1(\reply_index_reg_n_0_[0] ),
        .O(reply_mem_reg_0_i_52_n_0));
  (* SOFT_HLUTNM = "soft_lutpair130" *) 
  LUT2 #(
    .INIT(4'hB)) 
    reply_mem_reg_0_i_53
       (.I0(\reply_index_reg_n_0_[3] ),
        .I1(\reply_index_reg_n_0_[2] ),
        .O(reply_mem_reg_0_i_53_n_0));
  (* SOFT_HLUTNM = "soft_lutpair131" *) 
  LUT2 #(
    .INIT(4'h2)) 
    reply_mem_reg_0_i_54
       (.I0(\reply_index_reg_n_0_[0] ),
        .I1(\reply_index_reg_n_0_[1] ),
        .O(reply_mem_reg_0_i_54_n_0));
  LUT2 #(
    .INIT(4'h1)) 
    reply_mem_reg_0_i_55
       (.I0(\reply_index_reg_n_0_[1] ),
        .I1(\reply_index_reg_n_0_[0] ),
        .O(reply_mem_reg_0_i_55_n_0));
  (* SOFT_HLUTNM = "soft_lutpair130" *) 
  LUT2 #(
    .INIT(4'h1)) 
    reply_mem_reg_0_i_56
       (.I0(\reply_index_reg_n_0_[2] ),
        .I1(\reply_index_reg_n_0_[3] ),
        .O(reply_mem_reg_0_i_56_n_0));
  (* SOFT_HLUTNM = "soft_lutpair131" *) 
  LUT2 #(
    .INIT(4'h8)) 
    reply_mem_reg_0_i_57
       (.I0(\reply_index_reg_n_0_[1] ),
        .I1(\reply_index_reg_n_0_[0] ),
        .O(reply_mem_reg_0_i_57_n_0));
  (* SOFT_HLUTNM = "soft_lutpair103" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_6
       (.I0(aw[7]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[7] ),
        .O(reply_wa[3]));
  (* SOFT_HLUTNM = "soft_lutpair103" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_7
       (.I0(aw[6]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[6] ),
        .O(reply_wa[2]));
  (* SOFT_HLUTNM = "soft_lutpair102" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_8
       (.I0(aw[5]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[5] ),
        .O(reply_wa[1]));
  (* SOFT_HLUTNM = "soft_lutpair102" *) 
  LUT3 #(
    .INIT(8'hB8)) 
    reply_mem_reg_0_i_9
       (.I0(aw[4]),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\reply_index_reg_n_0_[4] ),
        .O(reply_wa[0]));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* METHODOLOGY_DRC_VIOS = "" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "16384" *) 
  (* RTL_RAM_NAME = "v13_ps_mailbox/reply_mem_reg" *) 
  (* RTL_RAM_STYLE = "block" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "127" *) 
  (* ram_offset = "384" *) 
  (* ram_slice_begin = "64" *) 
  (* ram_slice_end = "127" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("NONE"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(1),
    .DOB_REG(1),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(72),
    .READ_WIDTH_B(0),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("READ_FIRST"),
    .WRITE_WIDTH_A(0),
    .WRITE_WIDTH_B(72)) 
    reply_mem_reg_1
       (.ADDRARDADDR({1'b1,1'b1,\tx_index_reg_n_0_[10] ,\tx_index_reg_n_0_[9] ,\tx_index_reg_n_0_[8] ,\tx_index_reg_n_0_[7] ,\tx_index_reg_n_0_[6] ,\tx_index_reg_n_0_[5] ,\tx_index_reg_n_0_[4] ,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRBWRADDR({1'b1,1'b1,reply_wa,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA(NLW_reply_mem_reg_1_CASDINA_UNCONNECTED[31:0]),
        .CASDINB(NLW_reply_mem_reg_1_CASDINB_UNCONNECTED[31:0]),
        .CASDINPA(NLW_reply_mem_reg_1_CASDINPA_UNCONNECTED[3:0]),
        .CASDINPB(NLW_reply_mem_reg_1_CASDINPB_UNCONNECTED[3:0]),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_reply_mem_reg_1_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_reply_mem_reg_1_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_reply_mem_reg_1_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_reply_mem_reg_1_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_reply_mem_reg_1_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_reply_mem_reg_1_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .DBITERR(NLW_reply_mem_reg_1_DBITERR_UNCONNECTED),
        .DINADIN({reply_mem_reg_0_i_10_n_0,reply_mem_reg_0_i_11_n_0,reply_mem_reg_0_i_12_n_0,reply_mem_reg_0_i_13_n_0,reply_mem_reg_0_i_14_n_0,reply_mem_reg_0_i_15_n_0,reply_mem_reg_0_i_16_n_0,reply_mem_reg_0_i_17_n_0,reply_mem_reg_0_i_18_n_0,reply_mem_reg_0_i_19_n_0,reply_mem_reg_0_i_20_n_0,reply_mem_reg_0_i_21_n_0,reply_mem_reg_0_i_22_n_0,reply_mem_reg_0_i_23_n_0,reply_mem_reg_0_i_24_n_0,reply_mem_reg_0_i_25_n_0,reply_mem_reg_0_i_26_n_0,reply_mem_reg_0_i_27_n_0,reply_mem_reg_0_i_28_n_0,reply_mem_reg_0_i_29_n_0,reply_mem_reg_0_i_30_n_0,reply_mem_reg_0_i_31_n_0,reply_mem_reg_0_i_32_n_0,reply_mem_reg_0_i_33_n_0,p_0_in__0}),
        .DINBDIN({reply_mem_reg_0_i_10_n_0,reply_mem_reg_0_i_11_n_0,reply_mem_reg_0_i_12_n_0,reply_mem_reg_0_i_13_n_0,reply_mem_reg_0_i_14_n_0,reply_mem_reg_0_i_15_n_0,reply_mem_reg_0_i_16_n_0,reply_mem_reg_0_i_17_n_0,reply_mem_reg_0_i_18_n_0,reply_mem_reg_0_i_19_n_0,reply_mem_reg_0_i_20_n_0,reply_mem_reg_0_i_21_n_0,reply_mem_reg_0_i_22_n_0,reply_mem_reg_0_i_23_n_0,reply_mem_reg_0_i_24_n_0,reply_mem_reg_0_i_25_n_0,reply_mem_reg_0_i_26_n_0,reply_mem_reg_0_i_27_n_0,reply_mem_reg_0_i_28_n_0,reply_mem_reg_0_i_29_n_0,reply_mem_reg_0_i_30_n_0,reply_mem_reg_0_i_31_n_0,reply_mem_reg_0_i_32_n_0,reply_mem_reg_0_i_33_n_0,p_0_in__0}),
        .DINPADINP({1'b1,1'b1,1'b1,1'b1}),
        .DINPBDINP({1'b1,1'b1,1'b1,1'b1}),
        .DOUTADOUT({data11,data10,data9,data8}),
        .DOUTBDOUT({data15,data14,data13,data12}),
        .DOUTPADOUTP(NLW_reply_mem_reg_1_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_reply_mem_reg_1_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_reply_mem_reg_1_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(1'b1),
        .ENBWREN(reply_we),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_reply_mem_reg_1_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(reply_mem_reg_0_i_2_n_0),
        .REGCEB(1'b0),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(\s_axi_bresp[1]_i_1_n_0 ),
        .RSTREGB(1'b0),
        .SBITERR(NLW_reply_mem_reg_1_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({1'b0,1'b0,1'b0,1'b0}),
        .WEBWE({p_0_in30_in,p_0_in28_in,p_0_in26_in,p_0_in24_in,p_0_in22_in,p_0_in20_in,p_0_in18_in,p_0_in16_in}));
  LUT5 #(
    .INIT(32'h80FF8000)) 
    reply_mem_reg_1_i_1
       (.I0(aw[3]),
        .I1(ws[3]),
        .I2(aw[2]),
        .I3(reply_mem_reg_0_i_50_n_0),
        .I4(reply_mem_reg_1_i_9_n_0),
        .O(p_0_in30_in));
  (* SOFT_HLUTNM = "soft_lutpair21" *) 
  LUT2 #(
    .INIT(4'h8)) 
    reply_mem_reg_1_i_10
       (.I0(reply_mem_reg_0_i_50_n_0),
        .I1(aw[3]),
        .O(reply_mem_reg_1_i_10_n_0));
  (* SOFT_HLUTNM = "soft_lutpair121" *) 
  LUT3 #(
    .INIT(8'hBF)) 
    reply_mem_reg_1_i_11
       (.I0(reply_mem_reg_0_i_50_n_0),
        .I1(\reply_index_reg_n_0_[3] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .O(reply_mem_reg_1_i_11_n_0));
  (* SOFT_HLUTNM = "soft_lutpair121" *) 
  LUT3 #(
    .INIT(8'hFB)) 
    reply_mem_reg_1_i_12
       (.I0(reply_mem_reg_0_i_50_n_0),
        .I1(\reply_index_reg_n_0_[3] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .O(reply_mem_reg_1_i_12_n_0));
  LUT6 #(
    .INIT(64'h8080808080FF8080)) 
    reply_mem_reg_1_i_2
       (.I0(aw[2]),
        .I1(ws[2]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_11_n_0),
        .I4(\reply_index_reg_n_0_[1] ),
        .I5(\reply_index_reg_n_0_[0] ),
        .O(p_0_in28_in));
  LUT6 #(
    .INIT(64'h8080808080FF8080)) 
    reply_mem_reg_1_i_3
       (.I0(aw[2]),
        .I1(ws[1]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_11_n_0),
        .I4(\reply_index_reg_n_0_[0] ),
        .I5(\reply_index_reg_n_0_[1] ),
        .O(p_0_in26_in));
  LUT6 #(
    .INIT(64'h80808080808080FF)) 
    reply_mem_reg_1_i_4
       (.I0(aw[2]),
        .I1(ws[0]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_11_n_0),
        .I4(\reply_index_reg_n_0_[1] ),
        .I5(\reply_index_reg_n_0_[0] ),
        .O(p_0_in24_in));
  LUT6 #(
    .INIT(64'h40FF404040404040)) 
    reply_mem_reg_1_i_5
       (.I0(aw[2]),
        .I1(ws[3]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_12_n_0),
        .I4(\reply_index_reg_n_0_[1] ),
        .I5(\reply_index_reg_n_0_[0] ),
        .O(p_0_in22_in));
  LUT6 #(
    .INIT(64'h4040404040FF4040)) 
    reply_mem_reg_1_i_6
       (.I0(aw[2]),
        .I1(ws[2]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_12_n_0),
        .I4(\reply_index_reg_n_0_[1] ),
        .I5(\reply_index_reg_n_0_[0] ),
        .O(p_0_in20_in));
  LUT6 #(
    .INIT(64'h4040404040FF4040)) 
    reply_mem_reg_1_i_7
       (.I0(aw[2]),
        .I1(ws[1]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_12_n_0),
        .I4(\reply_index_reg_n_0_[0] ),
        .I5(\reply_index_reg_n_0_[1] ),
        .O(p_0_in18_in));
  LUT6 #(
    .INIT(64'h40404040404040FF)) 
    reply_mem_reg_1_i_8
       (.I0(aw[2]),
        .I1(ws[0]),
        .I2(reply_mem_reg_1_i_10_n_0),
        .I3(reply_mem_reg_1_i_12_n_0),
        .I4(\reply_index_reg_n_0_[1] ),
        .I5(\reply_index_reg_n_0_[0] ),
        .O(p_0_in16_in));
  (* SOFT_HLUTNM = "soft_lutpair37" *) 
  LUT4 #(
    .INIT(16'h8000)) 
    reply_mem_reg_1_i_9
       (.I0(\reply_index_reg_n_0_[0] ),
        .I1(\reply_index_reg_n_0_[1] ),
        .I2(\reply_index_reg_n_0_[3] ),
        .I3(\reply_index_reg_n_0_[2] ),
        .O(reply_mem_reg_1_i_9_n_0));
  (* SOFT_HLUTNM = "soft_lutpair53" *) 
  LUT1 #(
    .INIT(2'h1)) 
    \request_len[0]_i_1 
       (.I0(\count_reg_n_0_[0] ),
        .O(\request_len[0]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hAA6AAAAAAAAAAAAA)) 
    \request_len[10]_i_1 
       (.I0(p_1_in[6]),
        .I1(p_1_in[5]),
        .I2(p_1_in[3]),
        .I3(\count[9]_i_2_n_0 ),
        .I4(p_1_in[2]),
        .I5(p_1_in[4]),
        .O(\request_len[10]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair7" *) 
  LUT4 #(
    .INIT(16'hA6AA)) 
    \request_len[11]_i_1 
       (.I0(\count_reg_n_0_[11] ),
        .I1(p_1_in[6]),
        .I2(\count[12]_i_2_n_0 ),
        .I3(p_1_in[5]),
        .O(\request_len[11]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair7" *) 
  LUT5 #(
    .INIT(32'hAA6AAAAA)) 
    \request_len[12]_i_1 
       (.I0(\count_reg_n_0_[12] ),
        .I1(\count_reg_n_0_[11] ),
        .I2(p_1_in[5]),
        .I3(\count[12]_i_2_n_0 ),
        .I4(p_1_in[6]),
        .O(\request_len[12]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'hF7FFFFFF08000000)) 
    \request_len[13]_i_1 
       (.I0(\count_reg_n_0_[11] ),
        .I1(p_1_in[5]),
        .I2(\count[12]_i_2_n_0 ),
        .I3(p_1_in[6]),
        .I4(\count_reg_n_0_[12] ),
        .I5(\count_reg_n_0_[13] ),
        .O(\request_len[13]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'hF7FF0800)) 
    \request_len[14]_i_1 
       (.I0(\count_reg_n_0_[13] ),
        .I1(\count_reg_n_0_[12] ),
        .I2(\count[14]_i_2_n_0 ),
        .I3(\count_reg_n_0_[11] ),
        .I4(\count_reg_n_0_[14] ),
        .O(\request_len[14]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000020000)) 
    \request_len[15]_i_1 
       (.I0(rx_valid),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[1] ),
        .I4(\request_len[15]_i_3_n_0 ),
        .I5(\state_reg_n_0_[3] ),
        .O(received));
  LUT6 #(
    .INIT(64'h0000000090060990)) 
    \request_len[15]_i_10 
       (.I0(\payload_len_reg_n_0_[11] ),
        .I1(\count_reg_n_0_[11] ),
        .I2(p_1_in[6]),
        .I3(\request_len[15]_i_17_n_0 ),
        .I4(\payload_len_reg_n_0_[10] ),
        .I5(\request_len[15]_i_18_n_0 ),
        .O(\request_len[15]_i_10_n_0 ));
  LUT6 #(
    .INIT(64'h00000000A6AA5955)) 
    \request_len[15]_i_11 
       (.I0(\payload_len_reg_n_0_[8] ),
        .I1(\payload_len_reg_n_0_[7] ),
        .I2(\request_len[15]_i_19_n_0 ),
        .I3(\payload_len_reg_n_0_[6] ),
        .I4(p_1_in[4]),
        .I5(\request_len[15]_i_20_n_0 ),
        .O(\request_len[15]_i_11_n_0 ));
  LUT6 #(
    .INIT(64'h0000000090060990)) 
    \request_len[15]_i_12 
       (.I0(\payload_len_reg_n_0_[5] ),
        .I1(p_1_in[1]),
        .I2(p_1_in[0]),
        .I3(\request_len[15]_i_21_n_0 ),
        .I4(\payload_len_reg_n_0_[4] ),
        .I5(\request_len[15]_i_22_n_0 ),
        .O(\request_len[15]_i_12_n_0 ));
  LUT6 #(
    .INIT(64'h0000900924420000)) 
    \request_len[15]_i_13 
       (.I0(\count_reg_n_0_[1] ),
        .I1(\payload_len_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\payload_len_reg_n_0_[2] ),
        .I4(\payload_len_reg_n_0_[0] ),
        .I5(\count_reg_n_0_[0] ),
        .O(\request_len[15]_i_13_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair34" *) 
  LUT5 #(
    .INIT(32'h08000000)) 
    \request_len[15]_i_14 
       (.I0(\payload_len_reg_n_0_[14] ),
        .I1(\payload_len_reg_n_0_[12] ),
        .I2(\request_len[15]_i_23_n_0 ),
        .I3(\payload_len_reg_n_0_[11] ),
        .I4(\payload_len_reg_n_0_[13] ),
        .O(\request_len[15]_i_14_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair34" *) 
  LUT4 #(
    .INIT(16'h0800)) 
    \request_len[15]_i_15 
       (.I0(\payload_len_reg_n_0_[13] ),
        .I1(\payload_len_reg_n_0_[11] ),
        .I2(\request_len[15]_i_23_n_0 ),
        .I3(\payload_len_reg_n_0_[12] ),
        .O(\request_len[15]_i_15_n_0 ));
  LUT6 #(
    .INIT(64'h77E7BB7BDDBDEEDE)) 
    \request_len[15]_i_16 
       (.I0(\count_reg_n_0_[12] ),
        .I1(\payload_len_reg_n_0_[13] ),
        .I2(\payload_len_reg_n_0_[11] ),
        .I3(\request_len[15]_i_23_n_0 ),
        .I4(\payload_len_reg_n_0_[12] ),
        .I5(\count_reg_n_0_[13] ),
        .O(\request_len[15]_i_16_n_0 ));
  LUT5 #(
    .INIT(32'hF7FFFFFF)) 
    \request_len[15]_i_17 
       (.I0(\payload_len_reg_n_0_[8] ),
        .I1(\payload_len_reg_n_0_[6] ),
        .I2(\request_len[15]_i_19_n_0 ),
        .I3(\payload_len_reg_n_0_[7] ),
        .I4(\payload_len_reg_n_0_[9] ),
        .O(\request_len[15]_i_17_n_0 ));
  LUT6 #(
    .INIT(64'h59555555A6AAAAAA)) 
    \request_len[15]_i_18 
       (.I0(p_1_in[5]),
        .I1(\payload_len_reg_n_0_[7] ),
        .I2(\request_len[15]_i_19_n_0 ),
        .I3(\payload_len_reg_n_0_[6] ),
        .I4(\payload_len_reg_n_0_[8] ),
        .I5(\payload_len_reg_n_0_[9] ),
        .O(\request_len[15]_i_18_n_0 ));
  LUT6 #(
    .INIT(64'h57777777FFFFFFFF)) 
    \request_len[15]_i_19 
       (.I0(\payload_len_reg_n_0_[4] ),
        .I1(\payload_len_reg_n_0_[3] ),
        .I2(\payload_len_reg_n_0_[0] ),
        .I3(\payload_len_reg_n_0_[1] ),
        .I4(\payload_len_reg_n_0_[2] ),
        .I5(\payload_len_reg_n_0_[5] ),
        .O(\request_len[15]_i_19_n_0 ));
  LUT6 #(
    .INIT(64'hAAAA6AAAAAAAAAAA)) 
    \request_len[15]_i_2 
       (.I0(\count_reg_n_0_[15] ),
        .I1(\count_reg_n_0_[14] ),
        .I2(\count_reg_n_0_[13] ),
        .I3(\count_reg_n_0_[12] ),
        .I4(\count[14]_i_2_n_0 ),
        .I5(\count_reg_n_0_[11] ),
        .O(\request_len[15]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'h7BE7DEBD)) 
    \request_len[15]_i_20 
       (.I0(p_1_in[2]),
        .I1(\payload_len_reg_n_0_[7] ),
        .I2(\payload_len_reg_n_0_[6] ),
        .I3(\request_len[15]_i_19_n_0 ),
        .I4(p_1_in[3]),
        .O(\request_len[15]_i_20_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair4" *) 
  LUT4 #(
    .INIT(16'h1555)) 
    \request_len[15]_i_21 
       (.I0(\payload_len_reg_n_0_[3] ),
        .I1(\payload_len_reg_n_0_[0] ),
        .I2(\payload_len_reg_n_0_[1] ),
        .I3(\payload_len_reg_n_0_[2] ),
        .O(\request_len[15]_i_21_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair4" *) 
  LUT5 #(
    .INIT(32'h6AAA9555)) 
    \request_len[15]_i_22 
       (.I0(\count_reg_n_0_[3] ),
        .I1(\payload_len_reg_n_0_[2] ),
        .I2(\payload_len_reg_n_0_[1] ),
        .I3(\payload_len_reg_n_0_[0] ),
        .I4(\payload_len_reg_n_0_[3] ),
        .O(\request_len[15]_i_22_n_0 ));
  LUT6 #(
    .INIT(64'hF7FFFFFFFFFFFFFF)) 
    \request_len[15]_i_23 
       (.I0(\payload_len_reg_n_0_[9] ),
        .I1(\payload_len_reg_n_0_[7] ),
        .I2(\request_len[15]_i_19_n_0 ),
        .I3(\payload_len_reg_n_0_[6] ),
        .I4(\payload_len_reg_n_0_[8] ),
        .I5(\payload_len_reg_n_0_[10] ),
        .O(\request_len[15]_i_23_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAA8AAA8AAA8)) 
    \request_len[15]_i_3 
       (.I0(state23_out),
        .I1(\request_len[15]_i_5_n_0 ),
        .I2(\request_len[15]_i_6_n_0 ),
        .I3(\request_len[15]_i_7_n_0 ),
        .I4(\count_reg_n_0_[0] ),
        .I5(\count_reg_n_0_[3] ),
        .O(\request_len[15]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair41" *) 
  LUT5 #(
    .INIT(32'hFFFEEEEE)) 
    \request_len[15]_i_5 
       (.I0(busy_INST_0_i_3_n_0),
        .I1(p_1_in[4]),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[2] ),
        .I4(\count_reg_n_0_[3] ),
        .O(\request_len[15]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair44" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    \request_len[15]_i_6 
       (.I0(\count_reg_n_0_[11] ),
        .I1(p_1_in[6]),
        .I2(\count_reg_n_0_[12] ),
        .I3(p_1_in[5]),
        .O(\request_len[15]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair65" *) 
  LUT3 #(
    .INIT(8'hFE)) 
    \request_len[15]_i_7 
       (.I0(\count_reg_n_0_[15] ),
        .I1(\count_reg_n_0_[14] ),
        .I2(\count_reg_n_0_[13] ),
        .O(\request_len[15]_i_7_n_0 ));
  LUT3 #(
    .INIT(8'h61)) 
    \request_len[15]_i_8 
       (.I0(\payload_len_reg_n_0_[15] ),
        .I1(\request_len[15]_i_14_n_0 ),
        .I2(\count_reg_n_0_[15] ),
        .O(\request_len[15]_i_8_n_0 ));
  LUT4 #(
    .INIT(16'h0069)) 
    \request_len[15]_i_9 
       (.I0(\payload_len_reg_n_0_[14] ),
        .I1(\request_len[15]_i_15_n_0 ),
        .I2(\count_reg_n_0_[14] ),
        .I3(\request_len[15]_i_16_n_0 ),
        .O(\request_len[15]_i_9_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair134" *) 
  LUT2 #(
    .INIT(4'h6)) 
    \request_len[1]_i_1 
       (.I0(\count_reg_n_0_[0] ),
        .I1(\count_reg_n_0_[1] ),
        .O(\request_len[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair127" *) 
  LUT3 #(
    .INIT(8'h78)) 
    \request_len[2]_i_1 
       (.I0(\count_reg_n_0_[0] ),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[2] ),
        .O(\request_len[2]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair77" *) 
  LUT4 #(
    .INIT(16'h7F80)) 
    \request_len[3]_i_1 
       (.I0(\count_reg_n_0_[1] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[3] ),
        .O(\request_len[3]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair48" *) 
  LUT5 #(
    .INIT(32'h6AAAAAAA)) 
    \request_len[4]_i_1 
       (.I0(p_1_in[0]),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[0] ),
        .I4(\count_reg_n_0_[3] ),
        .O(\request_len[4]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h6AAAAAAAAAAAAAAA)) 
    \request_len[5]_i_1 
       (.I0(p_1_in[1]),
        .I1(\count_reg_n_0_[3] ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[2] ),
        .I4(\count_reg_n_0_[1] ),
        .I5(p_1_in[0]),
        .O(\request_len[5]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair5" *) 
  LUT4 #(
    .INIT(16'h6AAA)) 
    \request_len[6]_i_1 
       (.I0(p_1_in[2]),
        .I1(p_1_in[1]),
        .I2(p_1_in[0]),
        .I3(p_80_in),
        .O(\request_len[6]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair5" *) 
  LUT5 #(
    .INIT(32'h6AAAAAAA)) 
    \request_len[7]_i_1 
       (.I0(p_1_in[3]),
        .I1(p_1_in[2]),
        .I2(p_80_in),
        .I3(p_1_in[0]),
        .I4(p_1_in[1]),
        .O(\request_len[7]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h6AAAAAAAAAAAAAAA)) 
    \request_len[8]_i_1 
       (.I0(p_1_in[4]),
        .I1(p_1_in[3]),
        .I2(p_1_in[1]),
        .I3(p_1_in[0]),
        .I4(p_80_in),
        .I5(p_1_in[2]),
        .O(\request_len[8]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair6" *) 
  LUT5 #(
    .INIT(32'hAA6AAAAA)) 
    \request_len[9]_i_1 
       (.I0(p_1_in[5]),
        .I1(p_1_in[4]),
        .I2(p_1_in[2]),
        .I3(\count[9]_i_2_n_0 ),
        .I4(p_1_in[3]),
        .O(\request_len[9]_i_1_n_0 ));
  FDRE \request_len_reg[0] 
       (.C(clk),
        .CE(received),
        .D(\request_len[0]_i_1_n_0 ),
        .Q(request_len__0[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[10] 
       (.C(clk),
        .CE(received),
        .D(\request_len[10]_i_1_n_0 ),
        .Q(request_len__0[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[11] 
       (.C(clk),
        .CE(received),
        .D(\request_len[11]_i_1_n_0 ),
        .Q(request_len__0[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[12] 
       (.C(clk),
        .CE(received),
        .D(\request_len[12]_i_1_n_0 ),
        .Q(request_len__0[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[13] 
       (.C(clk),
        .CE(received),
        .D(\request_len[13]_i_1_n_0 ),
        .Q(request_len__0[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[14] 
       (.C(clk),
        .CE(received),
        .D(\request_len[14]_i_1_n_0 ),
        .Q(request_len__0[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[15] 
       (.C(clk),
        .CE(received),
        .D(\request_len[15]_i_2_n_0 ),
        .Q(request_len__0[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  CARRY8 \request_len_reg[15]_i_4 
       (.CI(1'b1),
        .CI_TOP(1'b0),
        .CO({\NLW_request_len_reg[15]_i_4_CO_UNCONNECTED [7:6],state23_out,\request_len_reg[15]_i_4_n_3 ,\request_len_reg[15]_i_4_n_4 ,\request_len_reg[15]_i_4_n_5 ,\request_len_reg[15]_i_4_n_6 ,\request_len_reg[15]_i_4_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(\NLW_request_len_reg[15]_i_4_O_UNCONNECTED [7:0]),
        .S({1'b0,1'b0,\request_len[15]_i_8_n_0 ,\request_len[15]_i_9_n_0 ,\request_len[15]_i_10_n_0 ,\request_len[15]_i_11_n_0 ,\request_len[15]_i_12_n_0 ,\request_len[15]_i_13_n_0 }));
  FDRE \request_len_reg[1] 
       (.C(clk),
        .CE(received),
        .D(\request_len[1]_i_1_n_0 ),
        .Q(request_len__0[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[2] 
       (.C(clk),
        .CE(received),
        .D(\request_len[2]_i_1_n_0 ),
        .Q(request_len__0[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[3] 
       (.C(clk),
        .CE(received),
        .D(\request_len[3]_i_1_n_0 ),
        .Q(request_len__0[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[4] 
       (.C(clk),
        .CE(received),
        .D(\request_len[4]_i_1_n_0 ),
        .Q(request_len__0[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[5] 
       (.C(clk),
        .CE(received),
        .D(\request_len[5]_i_1_n_0 ),
        .Q(request_len__0[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[6] 
       (.C(clk),
        .CE(received),
        .D(\request_len[6]_i_1_n_0 ),
        .Q(request_len__0[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[7] 
       (.C(clk),
        .CE(received),
        .D(\request_len[7]_i_1_n_0 ),
        .Q(request_len__0[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[8] 
       (.C(clk),
        .CE(received),
        .D(\request_len[8]_i_1_n_0 ),
        .Q(request_len__0[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \request_len_reg[9] 
       (.C(clk),
        .CE(received),
        .D(\request_len[9]_i_1_n_0 ),
        .Q(request_len__0[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* METHODOLOGY_DRC_VIOS = "{SYNTH-6 {cell *THIS*}}" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "16384" *) 
  (* RTL_RAM_NAME = "v13_ps_mailbox/request_mem_reg" *) 
  (* RTL_RAM_STYLE = "block" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "127" *) 
  (* ram_offset = "384" *) 
  (* ram_slice_begin = "0" *) 
  (* ram_slice_end = "63" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("NONE"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(0),
    .DOB_REG(0),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(72),
    .READ_WIDTH_B(0),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("READ_FIRST"),
    .WRITE_WIDTH_A(0),
    .WRITE_WIDTH_B(72)) 
    request_mem_reg_0
       (.ADDRARDADDR({1'b1,1'b1,request_q1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRBWRADDR({1'b1,1'b1,p_1_in,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA(NLW_request_mem_reg_0_CASDINA_UNCONNECTED[31:0]),
        .CASDINB(NLW_request_mem_reg_0_CASDINB_UNCONNECTED[31:0]),
        .CASDINPA(NLW_request_mem_reg_0_CASDINPA_UNCONNECTED[3:0]),
        .CASDINPB(NLW_request_mem_reg_0_CASDINPB_UNCONNECTED[3:0]),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_request_mem_reg_0_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_request_mem_reg_0_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_request_mem_reg_0_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_request_mem_reg_0_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_request_mem_reg_0_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_request_mem_reg_0_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .DBITERR(NLW_request_mem_reg_0_DBITERR_UNCONNECTED),
        .DINADIN({rx_data,rx_data,rx_data,rx_data}),
        .DINBDIN({rx_data,rx_data,rx_data,rx_data}),
        .DINPADINP({1'b1,1'b1,1'b1,1'b1}),
        .DINPBDINP({1'b1,1'b1,1'b1,1'b1}),
        .DOUTADOUT(request_q[31:0]),
        .DOUTBDOUT(request_q[63:32]),
        .DOUTPADOUTP(NLW_request_mem_reg_0_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_request_mem_reg_0_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_request_mem_reg_0_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(request_q0),
        .ENBWREN(p_81_in),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_request_mem_reg_0_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .SBITERR(NLW_request_mem_reg_0_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({1'b0,1'b0,1'b0,1'b0}),
        .WEBWE({request_mem_reg_0_i_10_n_0,p_50_in,p_47_in,p_44_in,p_41_in,p_38_in,p_35_in,p_32_in}));
  (* SOFT_HLUTNM = "soft_lutpair24" *) 
  LUT5 #(
    .INIT(32'hABAAAAAA)) 
    request_mem_reg_0_i_1
       (.I0(\host_quarter[1]_i_1_n_0 ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[1] ),
        .I4(\state_reg_n_0_[2] ),
        .O(request_q0));
  (* SOFT_HLUTNM = "soft_lutpair48" *) 
  LUT4 #(
    .INIT(16'h4000)) 
    request_mem_reg_0_i_10
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[0] ),
        .I3(\count_reg_n_0_[1] ),
        .O(request_mem_reg_0_i_10_n_0));
  (* SOFT_HLUTNM = "soft_lutpair73" *) 
  LUT4 #(
    .INIT(16'h1000)) 
    request_mem_reg_0_i_11
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[1] ),
        .O(p_50_in));
  (* SOFT_HLUTNM = "soft_lutpair76" *) 
  LUT4 #(
    .INIT(16'h0040)) 
    request_mem_reg_0_i_12
       (.I0(\count_reg_n_0_[1] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[3] ),
        .O(p_47_in));
  (* SOFT_HLUTNM = "soft_lutpair73" *) 
  LUT4 #(
    .INIT(16'h0100)) 
    request_mem_reg_0_i_13
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[2] ),
        .O(p_44_in));
  (* SOFT_HLUTNM = "soft_lutpair77" *) 
  LUT4 #(
    .INIT(16'h1000)) 
    request_mem_reg_0_i_14
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_41_in));
  (* SOFT_HLUTNM = "soft_lutpair74" *) 
  LUT4 #(
    .INIT(16'h0010)) 
    request_mem_reg_0_i_15
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_38_in));
  (* SOFT_HLUTNM = "soft_lutpair75" *) 
  LUT4 #(
    .INIT(16'h0004)) 
    request_mem_reg_0_i_16
       (.I0(\count_reg_n_0_[1] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[2] ),
        .O(p_35_in));
  (* SOFT_HLUTNM = "soft_lutpair63" *) 
  LUT4 #(
    .INIT(16'h0001)) 
    request_mem_reg_0_i_17
       (.I0(\count_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_32_in));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFAE0000)) 
    request_mem_reg_0_i_18
       (.I0(p_1_in[5]),
        .I1(\count_reg_n_0_[3] ),
        .I2(busy_INST_0_i_2_n_0),
        .I3(request_mem_reg_0_i_19_n_0),
        .I4(p_1_in[6]),
        .I5(request_mem_reg_0_i_20_n_0),
        .O(request_mem_reg_0_i_18_n_0));
  (* SOFT_HLUTNM = "soft_lutpair43" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    request_mem_reg_0_i_19
       (.I0(p_1_in[4]),
        .I1(p_1_in[0]),
        .I2(p_1_in[3]),
        .I3(p_1_in[1]),
        .I4(p_1_in[2]),
        .O(request_mem_reg_0_i_19_n_0));
  LUT6 #(
    .INIT(64'h0000000000010000)) 
    request_mem_reg_0_i_2
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(rx_valid),
        .I5(request_mem_reg_0_i_18_n_0),
        .O(p_81_in));
  (* SOFT_HLUTNM = "soft_lutpair45" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    request_mem_reg_0_i_20
       (.I0(\count_reg_n_0_[11] ),
        .I1(\count_reg_n_0_[15] ),
        .I2(\count_reg_n_0_[14] ),
        .I3(\count_reg_n_0_[13] ),
        .I4(\count_reg_n_0_[12] ),
        .O(request_mem_reg_0_i_20_n_0));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_3
       (.I0(\cmd_index_reg_n_0_[10] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[10]),
        .O(request_q1[6]));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_4
       (.I0(\cmd_index_reg_n_0_[9] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[9]),
        .O(request_q1[5]));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_5
       (.I0(\cmd_index_reg_n_0_[8] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[8]),
        .O(request_q1[4]));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_6
       (.I0(\cmd_index_reg_n_0_[7] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[7]),
        .O(request_q1[3]));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_7
       (.I0(\cmd_index_reg_n_0_[6] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[6]),
        .O(request_q1[2]));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_8
       (.I0(\cmd_index_reg_n_0_[5] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[5]),
        .O(request_q1[1]));
  LUT6 #(
    .INIT(64'hFFFFFFBF00000080)) 
    request_mem_reg_0_i_9
       (.I0(\cmd_index_reg_n_0_[4] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(s_axi_araddr[4]),
        .O(request_q1[0]));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p0_d8_p0_d8_p0_d8_p0_d8" *) 
  (* METHODOLOGY_DRC_VIOS = "{SYNTH-6 {cell *THIS*}}" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "16384" *) 
  (* RTL_RAM_NAME = "v13_ps_mailbox/request_mem_reg" *) 
  (* RTL_RAM_STYLE = "block" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "127" *) 
  (* ram_offset = "384" *) 
  (* ram_slice_begin = "64" *) 
  (* ram_slice_end = "127" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("NONE"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(0),
    .DOB_REG(0),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(72),
    .READ_WIDTH_B(0),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("READ_FIRST"),
    .WRITE_WIDTH_A(0),
    .WRITE_WIDTH_B(72)) 
    request_mem_reg_1
       (.ADDRARDADDR({1'b1,1'b1,request_q1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRBWRADDR({1'b1,1'b1,p_1_in,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA(NLW_request_mem_reg_1_CASDINA_UNCONNECTED[31:0]),
        .CASDINB(NLW_request_mem_reg_1_CASDINB_UNCONNECTED[31:0]),
        .CASDINPA(NLW_request_mem_reg_1_CASDINPA_UNCONNECTED[3:0]),
        .CASDINPB(NLW_request_mem_reg_1_CASDINPB_UNCONNECTED[3:0]),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_request_mem_reg_1_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_request_mem_reg_1_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_request_mem_reg_1_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_request_mem_reg_1_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_request_mem_reg_1_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_request_mem_reg_1_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .DBITERR(NLW_request_mem_reg_1_DBITERR_UNCONNECTED),
        .DINADIN({rx_data,rx_data,rx_data,rx_data}),
        .DINBDIN({rx_data,rx_data,rx_data,rx_data}),
        .DINPADINP({1'b1,1'b1,1'b1,1'b1}),
        .DINPBDINP({1'b1,1'b1,1'b1,1'b1}),
        .DOUTADOUT(request_q[95:64]),
        .DOUTBDOUT(request_q[127:96]),
        .DOUTPADOUTP(NLW_request_mem_reg_1_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_request_mem_reg_1_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_request_mem_reg_1_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(request_q0),
        .ENBWREN(p_81_in),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_request_mem_reg_1_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .SBITERR(NLW_request_mem_reg_1_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({1'b0,1'b0,1'b0,1'b0}),
        .WEBWE({p_80_in,p_74_in,p_71_in,p_68_in,p_65_in,p_62_in,p_59_in,p_56_in}));
  (* SOFT_HLUTNM = "soft_lutpair63" *) 
  LUT4 #(
    .INIT(16'h8000)) 
    request_mem_reg_1_i_1
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[0] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[1] ),
        .O(p_80_in));
  (* SOFT_HLUTNM = "soft_lutpair74" *) 
  LUT4 #(
    .INIT(16'h0080)) 
    request_mem_reg_1_i_2
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_74_in));
  (* SOFT_HLUTNM = "soft_lutpair75" *) 
  LUT4 #(
    .INIT(16'h0800)) 
    request_mem_reg_1_i_3
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_71_in));
  (* SOFT_HLUTNM = "soft_lutpair76" *) 
  LUT4 #(
    .INIT(16'h0040)) 
    request_mem_reg_1_i_4
       (.I0(\count_reg_n_0_[1] ),
        .I1(\count_reg_n_0_[2] ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_68_in));
  (* SOFT_HLUTNM = "soft_lutpair78" *) 
  LUT4 #(
    .INIT(16'h4000)) 
    request_mem_reg_1_i_5
       (.I0(\count_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[3] ),
        .I2(\count_reg_n_0_[1] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_65_in));
  (* SOFT_HLUTNM = "soft_lutpair78" *) 
  LUT4 #(
    .INIT(16'h0008)) 
    request_mem_reg_1_i_6
       (.I0(\count_reg_n_0_[3] ),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[2] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_62_in));
  (* SOFT_HLUTNM = "soft_lutpair62" *) 
  LUT4 #(
    .INIT(16'h1000)) 
    request_mem_reg_1_i_7
       (.I0(\count_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_59_in));
  (* SOFT_HLUTNM = "soft_lutpair62" *) 
  LUT4 #(
    .INIT(16'h0010)) 
    request_mem_reg_1_i_8
       (.I0(\count_reg_n_0_[2] ),
        .I1(\count_reg_n_0_[1] ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[0] ),
        .O(p_56_in));
  (* SOFT_HLUTNM = "soft_lutpair58" *) 
  LUT4 #(
    .INIT(16'h0010)) 
    s_axi_arready_INST_0
       (.I0(\hr_reg_n_0_[0] ),
        .I1(\hr_reg_n_0_[1] ),
        .I2(rst_n),
        .I3(s_axi_rvalid_reg_0),
        .O(s_axi_arready));
  (* SOFT_HLUTNM = "soft_lutpair84" *) 
  LUT3 #(
    .INIT(8'h04)) 
    s_axi_awready_INST_0
       (.I0(aw_full),
        .I1(rst_n),
        .I2(s_axi_bvalid_reg_0),
        .O(s_axi_awready));
  LUT1 #(
    .INIT(2'h1)) 
    \s_axi_bresp[1]_i_1 
       (.I0(rst_n),
        .O(\s_axi_bresp[1]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h00000001)) 
    \s_axi_bresp[1]_i_10 
       (.I0(\s_axi_bresp[1]_i_15_n_0 ),
        .I1(wd[9]),
        .I2(wd[4]),
        .I3(wd[5]),
        .I4(\s_axi_bresp[1]_i_16_n_0 ),
        .O(\s_axi_bresp[1]_i_10_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \s_axi_bresp[1]_i_11 
       (.I0(\s_axi_bresp[1]_i_17_n_0 ),
        .I1(\s_axi_bresp[1]_i_18_n_0 ),
        .I2(\s_axi_bresp[1]_i_19_n_0 ),
        .I3(\s_axi_bresp[1]_i_20_n_0 ),
        .I4(\s_axi_bresp[1]_i_21_n_0 ),
        .O(\s_axi_bresp[1]_i_11_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair26" *) 
  LUT5 #(
    .INIT(32'hFFFFFFF8)) 
    \s_axi_bresp[1]_i_12 
       (.I0(wd[0]),
        .I1(wd[1]),
        .I2(wd[2]),
        .I3(wd[3]),
        .I4(wd[4]),
        .O(\s_axi_bresp[1]_i_12_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \s_axi_bresp[1]_i_13 
       (.I0(aw[1]),
        .I1(aw[0]),
        .I2(aw[6]),
        .I3(aw[7]),
        .I4(aw[5]),
        .O(\s_axi_bresp[1]_i_13_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \s_axi_bresp[1]_i_14 
       (.I0(aw[10]),
        .I1(aw[8]),
        .I2(aw[13]),
        .I3(aw[9]),
        .O(\s_axi_bresp[1]_i_14_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair56" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    \s_axi_bresp[1]_i_15 
       (.I0(wd[6]),
        .I1(wd[7]),
        .I2(wd[8]),
        .I3(wd[10]),
        .O(\s_axi_bresp[1]_i_15_n_0 ));
  LUT3 #(
    .INIT(8'hA8)) 
    \s_axi_bresp[1]_i_16 
       (.I0(wd[3]),
        .I1(wd[2]),
        .I2(wd[1]),
        .O(\s_axi_bresp[1]_i_16_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \s_axi_bresp[1]_i_17 
       (.I0(wd[24]),
        .I1(wd[25]),
        .I2(wd[26]),
        .I3(wd[27]),
        .O(\s_axi_bresp[1]_i_17_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \s_axi_bresp[1]_i_18 
       (.I0(wd[28]),
        .I1(wd[29]),
        .I2(wd[30]),
        .I3(wd[31]),
        .O(\s_axi_bresp[1]_i_18_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \s_axi_bresp[1]_i_19 
       (.I0(wd[20]),
        .I1(wd[21]),
        .I2(wd[22]),
        .I3(wd[23]),
        .O(\s_axi_bresp[1]_i_19_n_0 ));
  LUT6 #(
    .INIT(64'h4055FFFF40550000)) 
    \s_axi_bresp[1]_i_2 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\s_axi_bresp[1]_i_3_n_0 ),
        .I2(\s_axi_bresp[1]_i_4_n_0 ),
        .I3(\s_axi_bresp[1]_i_5_n_0 ),
        .I4(p_105_in),
        .I5(s_axi_bresp),
        .O(\s_axi_bresp[1]_i_2_n_0 ));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \s_axi_bresp[1]_i_20 
       (.I0(wd[16]),
        .I1(wd[17]),
        .I2(wd[18]),
        .I3(wd[19]),
        .O(\s_axi_bresp[1]_i_20_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \s_axi_bresp[1]_i_21 
       (.I0(wd[11]),
        .I1(wd[15]),
        .I2(wd[14]),
        .I3(wd[13]),
        .I4(wd[12]),
        .O(\s_axi_bresp[1]_i_21_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFF4)) 
    \s_axi_bresp[1]_i_3 
       (.I0(\s_axi_bresp[1]_i_7_n_0 ),
        .I1(wd[10]),
        .I2(\s_axi_bresp[1]_i_8_n_0 ),
        .I3(\s_axi_bresp[1]_i_9_n_0 ),
        .I4(\s_axi_bresp[1]_i_10_n_0 ),
        .I5(\s_axi_bresp[1]_i_11_n_0 ),
        .O(\s_axi_bresp[1]_i_3_n_0 ));
  LUT2 #(
    .INIT(4'h1)) 
    \s_axi_bresp[1]_i_4 
       (.I0(\cmd_index[15]_i_3_n_0 ),
        .I1(\tx_index[15]_i_4_n_0 ),
        .O(\s_axi_bresp[1]_i_4_n_0 ));
  LUT5 #(
    .INIT(32'h80000000)) 
    \s_axi_bresp[1]_i_5 
       (.I0(\reply_index[15]_i_7_n_0 ),
        .I1(ws[2]),
        .I2(ws[0]),
        .I3(ws[3]),
        .I4(ws[1]),
        .O(\s_axi_bresp[1]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair82" *) 
  LUT3 #(
    .INIT(8'h40)) 
    \s_axi_bresp[1]_i_6 
       (.I0(s_axi_bvalid_reg_0),
        .I1(w_full_reg_n_0),
        .I2(aw_full),
        .O(p_105_in));
  LUT6 #(
    .INIT(64'h0000155555555555)) 
    \s_axi_bresp[1]_i_7 
       (.I0(wd[9]),
        .I1(\s_axi_bresp[1]_i_12_n_0 ),
        .I2(wd[6]),
        .I3(wd[5]),
        .I4(wd[7]),
        .I5(wd[8]),
        .O(\s_axi_bresp[1]_i_7_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \s_axi_bresp[1]_i_8 
       (.I0(\reply_index[15]_i_8_n_0 ),
        .I1(aw[21]),
        .I2(aw[20]),
        .I3(aw[22]),
        .I4(aw[16]),
        .I5(\s_axi_bresp[1]_i_13_n_0 ),
        .O(\s_axi_bresp[1]_i_8_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFEF)) 
    \s_axi_bresp[1]_i_9 
       (.I0(\s_axi_bresp[1]_i_14_n_0 ),
        .I1(\reply_index[15]_i_5_n_0 ),
        .I2(aw[4]),
        .I3(aw[2]),
        .I4(aw[3]),
        .O(\s_axi_bresp[1]_i_9_n_0 ));
  FDRE \s_axi_bresp_reg[1] 
       (.C(clk),
        .CE(1'b1),
        .D(\s_axi_bresp[1]_i_2_n_0 ),
        .Q(s_axi_bresp),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair82" *) 
  LUT4 #(
    .INIT(16'h55C0)) 
    s_axi_bvalid_i_1
       (.I0(s_axi_bready),
        .I1(aw_full),
        .I2(w_full_reg_n_0),
        .I3(s_axi_bvalid_reg_0),
        .O(s_axi_bvalid_i_1_n_0));
  FDRE s_axi_bvalid_reg
       (.C(clk),
        .CE(1'b1),
        .D(s_axi_bvalid_i_1_n_0),
        .Q(s_axi_bvalid_reg_0),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h1F111F111F111111)) 
    \s_axi_rdata[0]_i_1 
       (.I0(\s_axi_rdata[0]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[0]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[0]_i_4_n_0 ),
        .O(\s_axi_rdata[0]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[0]_i_2 
       (.I0(request_q[64]),
        .I1(request_q[96]),
        .I2(request_q[0]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[32]),
        .O(\s_axi_rdata[0]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFF11155515)) 
    \s_axi_rdata[0]_i_3 
       (.I0(\s_axi_rdata[0]_i_5_n_0 ),
        .I1(s_axi_araddr[3]),
        .I2(fast_starts_reg[0]),
        .I3(s_axi_araddr[2]),
        .I4(\last_reply_len_reg_n_0_[0] ),
        .I5(\s_axi_rdata[0]_i_6_n_0 ),
        .O(\s_axi_rdata[0]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[0]_i_4 
       (.I0(p_0_in[0]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[0]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[0]_i_7_n_0 ),
        .O(\s_axi_rdata[0]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair50" *) 
  LUT5 #(
    .INIT(32'h777F7777)) 
    \s_axi_rdata[0]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[4]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(\fast_error_reg_n_0_[0] ),
        .O(\s_axi_rdata[0]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h505000F03030F0F0)) 
    \s_axi_rdata[0]_i_6 
       (.I0(last_cycles[0]),
        .I1(fast_completed_reg[0]),
        .I2(\s_axi_rdata[28]_i_5_n_0 ),
        .I3(\header_reg_n_0_[0] ),
        .I4(s_axi_araddr[3]),
        .I5(s_axi_araddr[2]),
        .O(\s_axi_rdata[0]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hAA0FCC00AA00CC00)) 
    \s_axi_rdata[0]_i_7 
       (.I0(received_reg[0]),
        .I1(request_len__0[0]),
        .I2(\s_axi_rdata[1]_i_8_n_0 ),
        .I3(s_axi_araddr[3]),
        .I4(s_axi_araddr[2]),
        .I5(\s_axi_rdata[0]_i_8_n_0 ),
        .O(\s_axi_rdata[0]_i_7_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair16" *) 
  LUT2 #(
    .INIT(4'h1)) 
    \s_axi_rdata[0]_i_8 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[2] ),
        .O(\s_axi_rdata[0]_i_8_n_0 ));
  LUT6 #(
    .INIT(64'h1F1F1F1111111111)) 
    \s_axi_rdata[10]_i_1 
       (.I0(\s_axi_rdata[10]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[10]_i_3_n_0 ),
        .I3(\s_axi_rdata[10]_i_4_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[10]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[10]_i_2 
       (.I0(request_q[74]),
        .I1(request_q[106]),
        .I2(request_q[10]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[42]),
        .O(\s_axi_rdata[10]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h8888888808000888)) 
    \s_axi_rdata[10]_i_3 
       (.I0(\s_axi_rdata[10]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[10] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[10]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[10]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[10]_i_4 
       (.I0(\reply_len_reg_n_0_[10] ),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[10]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[10]_i_6_n_0 ),
        .O(\s_axi_rdata[10]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[10]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[10] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[10]),
        .I5(last_cycles[10]),
        .O(\s_axi_rdata[10]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[10]_i_6 
       (.I0(request_len__0[10]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[10]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[10]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1F1F1F1111111111)) 
    \s_axi_rdata[11]_i_1 
       (.I0(\s_axi_rdata[11]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[11]_i_3_n_0 ),
        .I3(\s_axi_rdata[11]_i_4_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[11]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[11]_i_2 
       (.I0(request_q[75]),
        .I1(request_q[107]),
        .I2(request_q[11]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[43]),
        .O(\s_axi_rdata[11]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h8888888808000888)) 
    \s_axi_rdata[11]_i_3 
       (.I0(\s_axi_rdata[11]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[11] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[11]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[11]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[11]_i_4 
       (.I0(\reply_len_reg_n_0_[11] ),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[11]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[11]_i_6_n_0 ),
        .O(\s_axi_rdata[11]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[11]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[11] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[11]),
        .I5(last_cycles[11]),
        .O(\s_axi_rdata[11]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[11]_i_6 
       (.I0(request_len__0[11]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[11]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[11]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hF1F1F11111111111)) 
    \s_axi_rdata[12]_i_1 
       (.I0(\s_axi_rdata[12]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[31]_i_9_n_0 ),
        .I3(\s_axi_rdata[12]_i_3_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[12]_i_4_n_0 ),
        .O(\s_axi_rdata[12]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[12]_i_2 
       (.I0(request_q[76]),
        .I1(request_q[108]),
        .I2(request_q[12]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[44]),
        .O(\s_axi_rdata[12]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[12]_i_3 
       (.I0(\reply_len_reg_n_0_[12] ),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[12]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[12]_i_5_n_0 ),
        .O(\s_axi_rdata[12]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBBBBBBBBFBFFFBBB)) 
    \s_axi_rdata[12]_i_4 
       (.I0(\s_axi_rdata[12]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[12] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[12]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[12]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hA0CF)) 
    \s_axi_rdata[12]_i_5 
       (.I0(received_reg[12]),
        .I1(request_len__0[12]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .O(\s_axi_rdata[12]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8C83808)) 
    \s_axi_rdata[12]_i_6 
       (.I0(\header_reg_n_0_[12] ),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[12]),
        .I4(last_cycles[12]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[12]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1111FFF111111111)) 
    \s_axi_rdata[13]_i_1 
       (.I0(\s_axi_rdata[13]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[13]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[13]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[13]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[13]_i_2 
       (.I0(request_q[77]),
        .I1(request_q[109]),
        .I2(request_q[13]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[45]),
        .O(\s_axi_rdata[13]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[13]_i_3 
       (.I0(\reply_len_reg_n_0_[13] ),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[13]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[13]_i_5_n_0 ),
        .O(\s_axi_rdata[13]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h8888888808000888)) 
    \s_axi_rdata[13]_i_4 
       (.I0(\s_axi_rdata[13]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[13] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[13]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[13]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[13]_i_5 
       (.I0(request_len__0[13]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[13]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[13]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[13]_i_6 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[13] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[13]),
        .I5(last_cycles[13]),
        .O(\s_axi_rdata[13]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1111FFF111111111)) 
    \s_axi_rdata[14]_i_1 
       (.I0(\s_axi_rdata[14]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[14]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[14]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[14]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[14]_i_2 
       (.I0(request_q[78]),
        .I1(request_q[110]),
        .I2(request_q[14]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[46]),
        .O(\s_axi_rdata[14]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[14]_i_3 
       (.I0(\reply_len_reg_n_0_[14] ),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[14]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[14]_i_5_n_0 ),
        .O(\s_axi_rdata[14]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h8888888808000888)) 
    \s_axi_rdata[14]_i_4 
       (.I0(\s_axi_rdata[14]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[14] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[14]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[14]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[14]_i_5 
       (.I0(request_len__0[14]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[14]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[14]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[14]_i_6 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[14] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[14]),
        .I5(last_cycles[14]),
        .O(\s_axi_rdata[14]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1111FFF111111111)) 
    \s_axi_rdata[15]_i_1 
       (.I0(\s_axi_rdata[15]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[15]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[15]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[15]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[15]_i_2 
       (.I0(request_q[79]),
        .I1(request_q[111]),
        .I2(request_q[15]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[47]),
        .O(\s_axi_rdata[15]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[15]_i_3 
       (.I0(\reply_len_reg_n_0_[15] ),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[15]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[15]_i_5_n_0 ),
        .O(\s_axi_rdata[15]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h8888888808000888)) 
    \s_axi_rdata[15]_i_4 
       (.I0(\s_axi_rdata[15]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[15] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[15]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[15]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[15]_i_5 
       (.I0(request_len__0[15]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[15]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[15]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[15]_i_6 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[15] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[15]),
        .I5(last_cycles[15]),
        .O(\s_axi_rdata[15]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair51" *) 
  LUT2 #(
    .INIT(4'h7)) 
    \s_axi_rdata[15]_i_7 
       (.I0(s_axi_araddr[3]),
        .I1(s_axi_araddr[4]),
        .O(\s_axi_rdata[15]_i_7_n_0 ));
  LUT4 #(
    .INIT(16'h1F11)) 
    \s_axi_rdata[16]_i_1 
       (.I0(\s_axi_rdata[16]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[16]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[16]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[16]_i_2 
       (.I0(request_q[80]),
        .I1(request_q[112]),
        .I2(request_q[16]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[48]),
        .O(\s_axi_rdata[16]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h000000003F55FFFF)) 
    \s_axi_rdata[16]_i_3 
       (.I0(\s_axi_rdata[16]_i_4_n_0 ),
        .I1(fast_starts_reg[16]),
        .I2(\s_axi_rdata[30]_i_5_n_0 ),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[16]_i_5_n_0 ),
        .O(\s_axi_rdata[16]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hAFC0A0C0)) 
    \s_axi_rdata[16]_i_4 
       (.I0(last_cycles[16]),
        .I1(fast_completed_reg[16]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(\header_reg_n_0_[16] ),
        .O(\s_axi_rdata[16]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[16]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[16]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[16]),
        .O(\s_axi_rdata[16]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h1F111FFF11111111)) 
    \s_axi_rdata[17]_i_1 
       (.I0(\s_axi_rdata[17]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[17]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[17]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[17]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[17]_i_2 
       (.I0(request_q[81]),
        .I1(request_q[113]),
        .I2(request_q[17]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[49]),
        .O(\s_axi_rdata[17]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hAAAA2AAA)) 
    \s_axi_rdata[17]_i_3 
       (.I0(\s_axi_rdata[17]_i_5_n_0 ),
        .I1(s_axi_araddr[4]),
        .I2(fast_starts_reg[17]),
        .I3(s_axi_araddr[3]),
        .I4(s_axi_araddr[2]),
        .O(\s_axi_rdata[17]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hC7FCF7FC)) 
    \s_axi_rdata[17]_i_4 
       (.I0(received_reg[17]),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[4]),
        .I3(s_axi_araddr[3]),
        .I4(completed_reg[17]),
        .O(\s_axi_rdata[17]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[17]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[17] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[17]),
        .I5(last_cycles[17]),
        .O(\s_axi_rdata[17]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'h1F11)) 
    \s_axi_rdata[18]_i_1 
       (.I0(\s_axi_rdata[18]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[18]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[18]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[18]_i_2 
       (.I0(request_q[82]),
        .I1(request_q[114]),
        .I2(request_q[18]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[50]),
        .O(\s_axi_rdata[18]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h000000003F55FFFF)) 
    \s_axi_rdata[18]_i_3 
       (.I0(\s_axi_rdata[18]_i_4_n_0 ),
        .I1(fast_starts_reg[18]),
        .I2(\s_axi_rdata[30]_i_5_n_0 ),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[18]_i_5_n_0 ),
        .O(\s_axi_rdata[18]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hAFC0A0C0)) 
    \s_axi_rdata[18]_i_4 
       (.I0(last_cycles[18]),
        .I1(fast_completed_reg[18]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(\header_reg_n_0_[18] ),
        .O(\s_axi_rdata[18]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[18]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[18]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[18]),
        .O(\s_axi_rdata[18]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h1F111FFF11111111)) 
    \s_axi_rdata[19]_i_1 
       (.I0(\s_axi_rdata[19]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[19]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[19]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[19]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[19]_i_2 
       (.I0(request_q[83]),
        .I1(request_q[115]),
        .I2(request_q[19]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[51]),
        .O(\s_axi_rdata[19]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hAAAA2AAA)) 
    \s_axi_rdata[19]_i_3 
       (.I0(\s_axi_rdata[19]_i_5_n_0 ),
        .I1(s_axi_araddr[4]),
        .I2(fast_starts_reg[19]),
        .I3(s_axi_araddr[3]),
        .I4(s_axi_araddr[2]),
        .O(\s_axi_rdata[19]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hC7FCF7FC)) 
    \s_axi_rdata[19]_i_4 
       (.I0(received_reg[19]),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[4]),
        .I3(s_axi_araddr[3]),
        .I4(completed_reg[19]),
        .O(\s_axi_rdata[19]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[19]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[19] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[19]),
        .I5(last_cycles[19]),
        .O(\s_axi_rdata[19]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h1F111F111F111111)) 
    \s_axi_rdata[1]_i_1 
       (.I0(\s_axi_rdata[1]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[1]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[1]_i_4_n_0 ),
        .O(\s_axi_rdata[1]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[1]_i_2 
       (.I0(request_q[65]),
        .I1(request_q[97]),
        .I2(request_q[1]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[33]),
        .O(\s_axi_rdata[1]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFF11155515)) 
    \s_axi_rdata[1]_i_3 
       (.I0(\s_axi_rdata[1]_i_5_n_0 ),
        .I1(s_axi_araddr[3]),
        .I2(fast_starts_reg[1]),
        .I3(s_axi_araddr[2]),
        .I4(\last_reply_len_reg_n_0_[1] ),
        .I5(\s_axi_rdata[1]_i_6_n_0 ),
        .O(\s_axi_rdata[1]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0B08FFFF0B080000)) 
    \s_axi_rdata[1]_i_4 
       (.I0(completed_reg[1]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(p_0_in[1]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[1]_i_7_n_0 ),
        .O(\s_axi_rdata[1]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair51" *) 
  LUT5 #(
    .INIT(32'h777F7777)) 
    \s_axi_rdata[1]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[4]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(\fast_error_reg_n_0_[1] ),
        .O(\s_axi_rdata[1]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h505000F03030F0F0)) 
    \s_axi_rdata[1]_i_6 
       (.I0(last_cycles[1]),
        .I1(fast_completed_reg[1]),
        .I2(\s_axi_rdata[28]_i_5_n_0 ),
        .I3(\header_reg_n_0_[1] ),
        .I4(s_axi_araddr[3]),
        .I5(s_axi_araddr[2]),
        .O(\s_axi_rdata[1]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hF404F0F0F4040000)) 
    \s_axi_rdata[1]_i_7 
       (.I0(\s_axi_rdata[1]_i_8_n_0 ),
        .I1(\s_axi_rdata[1]_i_9_n_0 ),
        .I2(s_axi_araddr[3]),
        .I3(received_reg[1]),
        .I4(s_axi_araddr[2]),
        .I5(request_len__0[1]),
        .O(\s_axi_rdata[1]_i_7_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair55" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \s_axi_rdata[1]_i_8 
       (.I0(\state_reg_n_0_[1] ),
        .I1(\state_reg_n_0_[0] ),
        .O(\s_axi_rdata[1]_i_8_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair132" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \s_axi_rdata[1]_i_9 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[3] ),
        .O(\s_axi_rdata[1]_i_9_n_0 ));
  LUT5 #(
    .INIT(32'h1F111111)) 
    \s_axi_rdata[20]_i_1 
       (.I0(\s_axi_rdata[20]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[20]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .I4(\s_axi_rdata[20]_i_4_n_0 ),
        .O(\s_axi_rdata[20]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[20]_i_2 
       (.I0(request_q[84]),
        .I1(request_q[116]),
        .I2(request_q[20]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[52]),
        .O(\s_axi_rdata[20]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h5505155055551550)) 
    \s_axi_rdata[20]_i_3 
       (.I0(s_axi_araddr[5]),
        .I1(completed_reg[20]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[20]),
        .O(\s_axi_rdata[20]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBFBBBBBBBBBBBBBB)) 
    \s_axi_rdata[20]_i_4 
       (.I0(\s_axi_rdata[20]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_starts_reg[20]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[20]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8C83808)) 
    \s_axi_rdata[20]_i_5 
       (.I0(\header_reg_n_0_[20] ),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[20]),
        .I4(last_cycles[20]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[20]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'hFF1F1111)) 
    \s_axi_rdata[21]_i_1 
       (.I0(\s_axi_rdata[21]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[21]_i_3_n_0 ),
        .I3(\s_axi_rdata[21]_i_4_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[21]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[21]_i_2 
       (.I0(request_q[85]),
        .I1(request_q[117]),
        .I2(request_q[21]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[53]),
        .O(\s_axi_rdata[21]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h557F5F7FF57FFF7F)) 
    \s_axi_rdata[21]_i_3 
       (.I0(\s_axi_rdata[28]_i_5_n_0 ),
        .I1(\header_reg_n_0_[21] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[21]),
        .I5(last_cycles[21]),
        .O(\s_axi_rdata[21]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAAEAAAAAAAAAAAAA)) 
    \s_axi_rdata[21]_i_4 
       (.I0(\s_axi_rdata[21]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(fast_starts_reg[21]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(s_axi_araddr[3]),
        .O(\s_axi_rdata[21]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[21]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[21]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[21]),
        .O(\s_axi_rdata[21]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'hFF1F1111)) 
    \s_axi_rdata[22]_i_1 
       (.I0(\s_axi_rdata[22]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[22]_i_3_n_0 ),
        .I3(\s_axi_rdata[22]_i_4_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[22]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[22]_i_2 
       (.I0(request_q[86]),
        .I1(request_q[118]),
        .I2(request_q[22]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[54]),
        .O(\s_axi_rdata[22]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h557F5F7FF57FFF7F)) 
    \s_axi_rdata[22]_i_3 
       (.I0(\s_axi_rdata[28]_i_5_n_0 ),
        .I1(\header_reg_n_0_[22] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[22]),
        .I5(last_cycles[22]),
        .O(\s_axi_rdata[22]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAAEAAAAAAAAAAAAA)) 
    \s_axi_rdata[22]_i_4 
       (.I0(\s_axi_rdata[22]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(fast_starts_reg[22]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(s_axi_araddr[3]),
        .O(\s_axi_rdata[22]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[22]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[22]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[22]),
        .O(\s_axi_rdata[22]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'h1F11)) 
    \s_axi_rdata[23]_i_1 
       (.I0(\s_axi_rdata[23]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[23]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[23]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[23]_i_2 
       (.I0(request_q[87]),
        .I1(request_q[119]),
        .I2(request_q[23]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[55]),
        .O(\s_axi_rdata[23]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h000000003F55FFFF)) 
    \s_axi_rdata[23]_i_3 
       (.I0(\s_axi_rdata[23]_i_4_n_0 ),
        .I1(fast_starts_reg[23]),
        .I2(\s_axi_rdata[30]_i_5_n_0 ),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[23]_i_5_n_0 ),
        .O(\s_axi_rdata[23]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hAFC0A0C0)) 
    \s_axi_rdata[23]_i_4 
       (.I0(last_cycles[23]),
        .I1(fast_completed_reg[23]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(\header_reg_n_0_[23] ),
        .O(\s_axi_rdata[23]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[23]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[23]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[23]),
        .O(\s_axi_rdata[23]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'h1F111111)) 
    \s_axi_rdata[24]_i_1 
       (.I0(\s_axi_rdata[24]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[24]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .I4(\s_axi_rdata[24]_i_4_n_0 ),
        .O(\s_axi_rdata[24]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[24]_i_2 
       (.I0(request_q[88]),
        .I1(request_q[120]),
        .I2(request_q[24]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[56]),
        .O(\s_axi_rdata[24]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h5505155055551550)) 
    \s_axi_rdata[24]_i_3 
       (.I0(s_axi_araddr[5]),
        .I1(completed_reg[24]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[24]),
        .O(\s_axi_rdata[24]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBFBBBBBBBBBBBBBB)) 
    \s_axi_rdata[24]_i_4 
       (.I0(\s_axi_rdata[24]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_starts_reg[24]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[24]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8C83808)) 
    \s_axi_rdata[24]_i_5 
       (.I0(\header_reg_n_0_[24] ),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[24]),
        .I4(last_cycles[24]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[24]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'hFF1F1111)) 
    \s_axi_rdata[25]_i_1 
       (.I0(\s_axi_rdata[25]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[25]_i_3_n_0 ),
        .I3(\s_axi_rdata[25]_i_4_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[25]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[25]_i_2 
       (.I0(request_q[89]),
        .I1(request_q[121]),
        .I2(request_q[25]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[57]),
        .O(\s_axi_rdata[25]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h557F5F7FF57FFF7F)) 
    \s_axi_rdata[25]_i_3 
       (.I0(\s_axi_rdata[28]_i_5_n_0 ),
        .I1(\header_reg_n_0_[25] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[25]),
        .I5(last_cycles[25]),
        .O(\s_axi_rdata[25]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAAEAAAAAAAAAAAAA)) 
    \s_axi_rdata[25]_i_4 
       (.I0(\s_axi_rdata[25]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(fast_starts_reg[25]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(s_axi_araddr[3]),
        .O(\s_axi_rdata[25]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[25]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[25]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[25]),
        .O(\s_axi_rdata[25]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h1F111FFF11111111)) 
    \s_axi_rdata[26]_i_1 
       (.I0(\s_axi_rdata[26]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[26]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[26]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[26]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[26]_i_2 
       (.I0(request_q[90]),
        .I1(request_q[122]),
        .I2(request_q[26]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[58]),
        .O(\s_axi_rdata[26]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hAAAA2AAA)) 
    \s_axi_rdata[26]_i_3 
       (.I0(\s_axi_rdata[26]_i_5_n_0 ),
        .I1(s_axi_araddr[4]),
        .I2(fast_starts_reg[26]),
        .I3(s_axi_araddr[3]),
        .I4(s_axi_araddr[2]),
        .O(\s_axi_rdata[26]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hC7FCF7FC)) 
    \s_axi_rdata[26]_i_4 
       (.I0(received_reg[26]),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[4]),
        .I3(s_axi_araddr[3]),
        .I4(completed_reg[26]),
        .O(\s_axi_rdata[26]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAFBFFABFFFBF)) 
    \s_axi_rdata[26]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(\header_reg_n_0_[26] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[26]),
        .I5(last_cycles[26]),
        .O(\s_axi_rdata[26]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'hFF1F1111)) 
    \s_axi_rdata[27]_i_1 
       (.I0(\s_axi_rdata[27]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[27]_i_3_n_0 ),
        .I3(\s_axi_rdata[27]_i_4_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[27]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[27]_i_2 
       (.I0(request_q[91]),
        .I1(request_q[123]),
        .I2(request_q[27]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[59]),
        .O(\s_axi_rdata[27]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h557F5F7FF57FFF7F)) 
    \s_axi_rdata[27]_i_3 
       (.I0(\s_axi_rdata[28]_i_5_n_0 ),
        .I1(\header_reg_n_0_[27] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[27]),
        .I5(last_cycles[27]),
        .O(\s_axi_rdata[27]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAAEAAAAAAAAAAAAA)) 
    \s_axi_rdata[27]_i_4 
       (.I0(\s_axi_rdata[27]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(fast_starts_reg[27]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(s_axi_araddr[3]),
        .O(\s_axi_rdata[27]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[27]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[27]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[27]),
        .O(\s_axi_rdata[27]_i_5_n_0 ));
  LUT5 #(
    .INIT(32'hFF1F1111)) 
    \s_axi_rdata[28]_i_1 
       (.I0(\s_axi_rdata[28]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[28]_i_3_n_0 ),
        .I3(\s_axi_rdata[28]_i_4_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[28]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[28]_i_2 
       (.I0(request_q[92]),
        .I1(request_q[124]),
        .I2(request_q[28]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[60]),
        .O(\s_axi_rdata[28]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h557F5F7FF57FFF7F)) 
    \s_axi_rdata[28]_i_3 
       (.I0(\s_axi_rdata[28]_i_5_n_0 ),
        .I1(\header_reg_n_0_[28] ),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[28]),
        .I5(last_cycles[28]),
        .O(\s_axi_rdata[28]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAAEAAAAAAAAAAAAA)) 
    \s_axi_rdata[28]_i_4 
       (.I0(\s_axi_rdata[28]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(fast_starts_reg[28]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(s_axi_araddr[3]),
        .O(\s_axi_rdata[28]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair27" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \s_axi_rdata[28]_i_5 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[4]),
        .O(\s_axi_rdata[28]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[28]_i_6 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[28]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[28]),
        .O(\s_axi_rdata[28]_i_6_n_0 ));
  LUT5 #(
    .INIT(32'h1F111111)) 
    \s_axi_rdata[29]_i_1 
       (.I0(\s_axi_rdata[29]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[29]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .I4(\s_axi_rdata[29]_i_4_n_0 ),
        .O(\s_axi_rdata[29]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[29]_i_2 
       (.I0(request_q[93]),
        .I1(request_q[125]),
        .I2(request_q[29]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[61]),
        .O(\s_axi_rdata[29]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h5505155055551550)) 
    \s_axi_rdata[29]_i_3 
       (.I0(s_axi_araddr[5]),
        .I1(completed_reg[29]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[29]),
        .O(\s_axi_rdata[29]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBFBBBBBBBBBBBBBB)) 
    \s_axi_rdata[29]_i_4 
       (.I0(\s_axi_rdata[29]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(fast_starts_reg[29]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[29]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8C83808)) 
    \s_axi_rdata[29]_i_5 
       (.I0(\header_reg_n_0_[29] ),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[29]),
        .I4(last_cycles[29]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[29]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h111F111111111111)) 
    \s_axi_rdata[2]_i_1 
       (.I0(\s_axi_rdata[2]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[2]_i_3_n_0 ),
        .I3(\s_axi_rdata[2]_i_4_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .I5(\s_axi_rdata[2]_i_5_n_0 ),
        .O(\s_axi_rdata[2]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[2]_i_2 
       (.I0(request_q[66]),
        .I1(request_q[98]),
        .I2(request_q[2]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[34]),
        .O(\s_axi_rdata[2]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0000F3F500000000)) 
    \s_axi_rdata[2]_i_3 
       (.I0(p_0_in[2]),
        .I1(completed_reg[2]),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(s_axi_araddr[5]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[2]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h000000005533FF0F)) 
    \s_axi_rdata[2]_i_4 
       (.I0(\last_reply_len_reg_n_0_[2] ),
        .I1(fast_starts_reg[2]),
        .I2(\fast_error_reg_n_0_[2] ),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[3]),
        .I5(\s_axi_rdata[2]_i_6_n_0 ),
        .O(\s_axi_rdata[2]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hBBBA)) 
    \s_axi_rdata[2]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(\s_axi_rdata[2]_i_7_n_0 ),
        .I2(\s_axi_rdata[2]_i_8_n_0 ),
        .I3(\s_axi_rdata[2]_i_9_n_0 ),
        .O(\s_axi_rdata[2]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair50" *) 
  LUT2 #(
    .INIT(4'h7)) 
    \s_axi_rdata[2]_i_6 
       (.I0(s_axi_araddr[4]),
        .I1(s_axi_araddr[5]),
        .O(\s_axi_rdata[2]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h505000F03030F0F0)) 
    \s_axi_rdata[2]_i_7 
       (.I0(last_cycles[2]),
        .I1(fast_completed_reg[2]),
        .I2(s_axi_araddr[5]),
        .I3(\header_reg_n_0_[2] ),
        .I4(s_axi_araddr[3]),
        .I5(s_axi_araddr[2]),
        .O(\s_axi_rdata[2]_i_7_n_0 ));
  LUT6 #(
    .INIT(64'h0000004400000400)) 
    \s_axi_rdata[2]_i_8 
       (.I0(s_axi_araddr[3]),
        .I1(s_axi_araddr[2]),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(\state_reg_n_0_[3] ),
        .I5(\state_reg_n_0_[1] ),
        .O(\s_axi_rdata[2]_i_8_n_0 ));
  LUT5 #(
    .INIT(32'hEAEEEAAA)) 
    \s_axi_rdata[2]_i_9 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(received_reg[2]),
        .I3(s_axi_araddr[2]),
        .I4(request_len__0[2]),
        .O(\s_axi_rdata[2]_i_9_n_0 ));
  LUT4 #(
    .INIT(16'h1F11)) 
    \s_axi_rdata[30]_i_1 
       (.I0(\s_axi_rdata[30]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[30]_i_3_n_0 ),
        .I3(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[30]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[30]_i_2 
       (.I0(request_q[94]),
        .I1(request_q[126]),
        .I2(request_q[30]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[62]),
        .O(\s_axi_rdata[30]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h000000003F55FFFF)) 
    \s_axi_rdata[30]_i_3 
       (.I0(\s_axi_rdata[30]_i_4_n_0 ),
        .I1(fast_starts_reg[30]),
        .I2(\s_axi_rdata[30]_i_5_n_0 ),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[30]_i_6_n_0 ),
        .O(\s_axi_rdata[30]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'hAFC0A0C0)) 
    \s_axi_rdata[30]_i_4 
       (.I0(last_cycles[30]),
        .I1(fast_completed_reg[30]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(\header_reg_n_0_[30] ),
        .O(\s_axi_rdata[30]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair29" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \s_axi_rdata[30]_i_5 
       (.I0(s_axi_araddr[3]),
        .I1(s_axi_araddr[2]),
        .O(\s_axi_rdata[30]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h0044400000004000)) 
    \s_axi_rdata[30]_i_6 
       (.I0(s_axi_araddr[5]),
        .I1(s_axi_araddr[3]),
        .I2(completed_reg[30]),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(received_reg[30]),
        .O(\s_axi_rdata[30]_i_6_n_0 ));
  LUT4 #(
    .INIT(16'hFFA8)) 
    \s_axi_rdata[31]_i_1 
       (.I0(p_104_in),
        .I1(s_axi_araddr[1]),
        .I2(s_axi_araddr[0]),
        .I3(\s_axi_rdata[31]_i_5_n_0 ),
        .O(\s_axi_rdata[31]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h530F53FF)) 
    \s_axi_rdata[31]_i_10 
       (.I0(last_cycles[31]),
        .I1(fast_completed_reg[31]),
        .I2(s_axi_araddr[2]),
        .I3(s_axi_araddr[3]),
        .I4(\header_reg_n_0_[31] ),
        .O(\s_axi_rdata[31]_i_10_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \s_axi_rdata[31]_i_11 
       (.I0(s_axi_araddr[16]),
        .I1(s_axi_araddr[17]),
        .I2(s_axi_araddr[11]),
        .I3(s_axi_araddr[7]),
        .I4(s_axi_araddr[8]),
        .I5(s_axi_araddr[9]),
        .O(\s_axi_rdata[31]_i_11_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair28" *) 
  LUT5 #(
    .INIT(32'h00000001)) 
    \s_axi_rdata[31]_i_12 
       (.I0(s_axi_araddr[14]),
        .I1(s_axi_araddr[22]),
        .I2(s_axi_araddr[15]),
        .I3(\host_quarter[1]_i_5_n_0 ),
        .I4(\host_quarter[1]_i_6_n_0 ),
        .O(\s_axi_rdata[31]_i_12_n_0 ));
  LUT5 #(
    .INIT(32'h00FF0020)) 
    \s_axi_rdata[31]_i_2 
       (.I0(rst_n),
        .I1(s_axi_rvalid_reg_0),
        .I2(s_axi_arvalid),
        .I3(\hr_reg_n_0_[0] ),
        .I4(\hr_reg_n_0_[1] ),
        .O(\s_axi_rdata[31]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h1F111FFF11111111)) 
    \s_axi_rdata[31]_i_3 
       (.I0(\s_axi_rdata[31]_i_6_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[31]_i_7_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[31]_i_8_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[31]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'h00000020)) 
    \s_axi_rdata[31]_i_4 
       (.I0(s_axi_arvalid),
        .I1(s_axi_rvalid_reg_0),
        .I2(rst_n),
        .I3(\hr_reg_n_0_[1] ),
        .I4(\hr_reg_n_0_[0] ),
        .O(p_104_in));
  (* SOFT_HLUTNM = "soft_lutpair59" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \s_axi_rdata[31]_i_5 
       (.I0(\host_quarter[1]_i_1_n_0 ),
        .I1(rst_n),
        .O(\s_axi_rdata[31]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[31]_i_6 
       (.I0(request_q[95]),
        .I1(request_q[127]),
        .I2(request_q[31]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[63]),
        .O(\s_axi_rdata[31]_i_6_n_0 ));
  LUT5 #(
    .INIT(32'hDFFFDF00)) 
    \s_axi_rdata[31]_i_7 
       (.I0(fast_starts_reg[31]),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[4]),
        .I4(\s_axi_rdata[31]_i_10_n_0 ),
        .O(\s_axi_rdata[31]_i_7_n_0 ));
  LUT5 #(
    .INIT(32'hCFFF77CC)) 
    \s_axi_rdata[31]_i_8 
       (.I0(completed_reg[31]),
        .I1(s_axi_araddr[4]),
        .I2(received_reg[31]),
        .I3(s_axi_araddr[3]),
        .I4(s_axi_araddr[2]),
        .O(\s_axi_rdata[31]_i_8_n_0 ));
  LUT6 #(
    .INIT(64'h0000000200000000)) 
    \s_axi_rdata[31]_i_9 
       (.I0(p_104_in),
        .I1(s_axi_araddr[6]),
        .I2(s_axi_araddr[12]),
        .I3(s_axi_araddr[10]),
        .I4(\s_axi_rdata[31]_i_11_n_0 ),
        .I5(\s_axi_rdata[31]_i_12_n_0 ),
        .O(\s_axi_rdata[31]_i_9_n_0 ));
  LUT6 #(
    .INIT(64'h1FFF111111F11111)) 
    \s_axi_rdata[3]_i_1 
       (.I0(\s_axi_rdata[3]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(s_axi_araddr[5]),
        .I3(\s_axi_rdata[3]_i_3_n_0 ),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .I5(\s_axi_rdata[3]_i_4_n_0 ),
        .O(\s_axi_rdata[3]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[3]_i_2 
       (.I0(request_q[67]),
        .I1(request_q[99]),
        .I2(request_q[3]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[35]),
        .O(\s_axi_rdata[3]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h57F7FFFF57F70000)) 
    \s_axi_rdata[3]_i_3 
       (.I0(s_axi_araddr[3]),
        .I1(fast_starts_reg[3]),
        .I2(s_axi_araddr[2]),
        .I3(\last_reply_len_reg_n_0_[3] ),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[3]_i_5_n_0 ),
        .O(\s_axi_rdata[3]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h00ACFFFF00AC0000)) 
    \s_axi_rdata[3]_i_4 
       (.I0(completed_reg[3]),
        .I1(p_0_in[3]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[3]_i_6_n_0 ),
        .O(\s_axi_rdata[3]_i_4_n_0 ));
  LUT5 #(
    .INIT(32'h1D331DFF)) 
    \s_axi_rdata[3]_i_5 
       (.I0(\header_reg_n_0_[3] ),
        .I1(s_axi_araddr[3]),
        .I2(last_cycles[3]),
        .I3(s_axi_araddr[2]),
        .I4(fast_completed_reg[3]),
        .O(\s_axi_rdata[3]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair29" *) 
  LUT5 #(
    .INIT(32'hE2CCE200)) 
    \s_axi_rdata[3]_i_6 
       (.I0(fast_active),
        .I1(s_axi_araddr[3]),
        .I2(received_reg[3]),
        .I3(s_axi_araddr[2]),
        .I4(request_len__0[3]),
        .O(\s_axi_rdata[3]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1F111FFF11111111)) 
    \s_axi_rdata[4]_i_1 
       (.I0(\s_axi_rdata[4]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[4]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[4]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[4]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[4]_i_2 
       (.I0(request_q[68]),
        .I1(request_q[100]),
        .I2(request_q[4]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[36]),
        .O(\s_axi_rdata[4]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h57F7FFFF57F70000)) 
    \s_axi_rdata[4]_i_3 
       (.I0(s_axi_araddr[3]),
        .I1(fast_starts_reg[4]),
        .I2(s_axi_araddr[2]),
        .I3(\last_reply_len_reg_n_0_[4] ),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[4]_i_5_n_0 ),
        .O(\s_axi_rdata[4]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hF1FDFFFFF1FD0000)) 
    \s_axi_rdata[4]_i_4 
       (.I0(p_0_in[4]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[4]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[4]_i_6_n_0 ),
        .O(\s_axi_rdata[4]_i_4_n_0 ));
  LUT5 #(
    .INIT(32'h1D331DFF)) 
    \s_axi_rdata[4]_i_5 
       (.I0(\header_reg_n_0_[4] ),
        .I1(s_axi_araddr[3]),
        .I2(last_cycles[4]),
        .I3(s_axi_araddr[2]),
        .I4(fast_completed_reg[4]),
        .O(\s_axi_rdata[4]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'h5F30)) 
    \s_axi_rdata[4]_i_6 
       (.I0(received_reg[4]),
        .I1(request_len__0[4]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .O(\s_axi_rdata[4]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hFFF1111111111111)) 
    \s_axi_rdata[5]_i_1 
       (.I0(\s_axi_rdata[5]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[5]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .I5(\s_axi_rdata[5]_i_4_n_0 ),
        .O(\s_axi_rdata[5]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[5]_i_2 
       (.I0(request_q[69]),
        .I1(request_q[101]),
        .I2(request_q[5]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[37]),
        .O(\s_axi_rdata[5]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[5]_i_3 
       (.I0(p_0_in[5]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[5]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[5]_i_5_n_0 ),
        .O(\s_axi_rdata[5]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBBBBBBBBFBFFFBBB)) 
    \s_axi_rdata[5]_i_4 
       (.I0(\s_axi_rdata[5]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[5] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[5]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[5]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[5]_i_5 
       (.I0(request_len__0[5]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[5]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[5]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8A85808)) 
    \s_axi_rdata[5]_i_6 
       (.I0(s_axi_araddr[2]),
        .I1(\header_reg_n_0_[5] ),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[5]),
        .I4(last_cycles[5]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[5]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1F1F1F1111111111)) 
    \s_axi_rdata[6]_i_1 
       (.I0(\s_axi_rdata[6]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[6]_i_3_n_0 ),
        .I3(\s_axi_rdata[6]_i_4_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[6]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[6]_i_2 
       (.I0(request_q[70]),
        .I1(request_q[102]),
        .I2(request_q[6]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[38]),
        .O(\s_axi_rdata[6]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h8888888808000888)) 
    \s_axi_rdata[6]_i_3 
       (.I0(\s_axi_rdata[6]_i_5_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[6] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[6]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[6]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0E02FFFF0E020000)) 
    \s_axi_rdata[6]_i_4 
       (.I0(p_0_in[6]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[6]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[6]_i_6_n_0 ),
        .O(\s_axi_rdata[6]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAABFBBBFEEBFFFBF)) 
    \s_axi_rdata[6]_i_5 
       (.I0(s_axi_araddr[4]),
        .I1(s_axi_araddr[2]),
        .I2(\header_reg_n_0_[6] ),
        .I3(s_axi_araddr[3]),
        .I4(fast_completed_reg[6]),
        .I5(last_cycles[6]),
        .O(\s_axi_rdata[6]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'hE200)) 
    \s_axi_rdata[6]_i_6 
       (.I0(request_len__0[6]),
        .I1(s_axi_araddr[2]),
        .I2(received_reg[6]),
        .I3(s_axi_araddr[3]),
        .O(\s_axi_rdata[6]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h1F111FFF11111111)) 
    \s_axi_rdata[7]_i_1 
       (.I0(\s_axi_rdata[7]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[7]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[7]_i_4_n_0 ),
        .I5(\s_axi_rdata[31]_i_9_n_0 ),
        .O(\s_axi_rdata[7]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[7]_i_2 
       (.I0(request_q[71]),
        .I1(request_q[103]),
        .I2(request_q[7]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[39]),
        .O(\s_axi_rdata[7]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h00000000777FFF7F)) 
    \s_axi_rdata[7]_i_3 
       (.I0(s_axi_araddr[4]),
        .I1(s_axi_araddr[3]),
        .I2(fast_starts_reg[7]),
        .I3(s_axi_araddr[2]),
        .I4(\last_reply_len_reg_n_0_[7] ),
        .I5(\s_axi_rdata[7]_i_5_n_0 ),
        .O(\s_axi_rdata[7]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hF1FDFFFFF1FD0000)) 
    \s_axi_rdata[7]_i_4 
       (.I0(p_0_in[7]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(completed_reg[7]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[7]_i_6_n_0 ),
        .O(\s_axi_rdata[7]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h00AA00CCFFF00000)) 
    \s_axi_rdata[7]_i_5 
       (.I0(last_cycles[7]),
        .I1(fast_completed_reg[7]),
        .I2(\header_reg_n_0_[7] ),
        .I3(s_axi_araddr[4]),
        .I4(s_axi_araddr[2]),
        .I5(s_axi_araddr[3]),
        .O(\s_axi_rdata[7]_i_5_n_0 ));
  LUT4 #(
    .INIT(16'h57F7)) 
    \s_axi_rdata[7]_i_6 
       (.I0(s_axi_araddr[3]),
        .I1(request_len__0[7]),
        .I2(s_axi_araddr[2]),
        .I3(received_reg[7]),
        .O(\s_axi_rdata[7]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hFFF1111111111111)) 
    \s_axi_rdata[8]_i_1 
       (.I0(\s_axi_rdata[8]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[8]_i_3_n_0 ),
        .I3(s_axi_araddr[5]),
        .I4(\s_axi_rdata[31]_i_9_n_0 ),
        .I5(\s_axi_rdata[8]_i_4_n_0 ),
        .O(\s_axi_rdata[8]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[8]_i_2 
       (.I0(request_q[72]),
        .I1(request_q[104]),
        .I2(request_q[8]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[40]),
        .O(\s_axi_rdata[8]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h00ACFFFF00AC0000)) 
    \s_axi_rdata[8]_i_3 
       (.I0(completed_reg[8]),
        .I1(\reply_len_reg_n_0_[8] ),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[8]_i_5_n_0 ),
        .O(\s_axi_rdata[8]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBBBBBBBBFFFBBBFB)) 
    \s_axi_rdata[8]_i_4 
       (.I0(\s_axi_rdata[8]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(fast_starts_reg[8]),
        .I3(s_axi_araddr[2]),
        .I4(\last_reply_len_reg_n_0_[8] ),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[8]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hA0CF)) 
    \s_axi_rdata[8]_i_5 
       (.I0(received_reg[8]),
        .I1(request_len__0[8]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .O(\s_axi_rdata[8]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8C83808)) 
    \s_axi_rdata[8]_i_6 
       (.I0(\header_reg_n_0_[8] ),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[8]),
        .I4(last_cycles[8]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[8]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hF1F1F11111111111)) 
    \s_axi_rdata[9]_i_1 
       (.I0(\s_axi_rdata[9]_i_2_n_0 ),
        .I1(p_104_in),
        .I2(\s_axi_rdata[31]_i_9_n_0 ),
        .I3(\s_axi_rdata[9]_i_3_n_0 ),
        .I4(s_axi_araddr[5]),
        .I5(\s_axi_rdata[9]_i_4_n_0 ),
        .O(\s_axi_rdata[9]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h3355000F3355FF0F)) 
    \s_axi_rdata[9]_i_2 
       (.I0(request_q[73]),
        .I1(request_q[105]),
        .I2(request_q[9]),
        .I3(\host_quarter_reg_n_0_[0] ),
        .I4(\host_quarter_reg_n_0_[1] ),
        .I5(request_q[41]),
        .O(\s_axi_rdata[9]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0B08FFFF0B080000)) 
    \s_axi_rdata[9]_i_3 
       (.I0(completed_reg[9]),
        .I1(s_axi_araddr[3]),
        .I2(s_axi_araddr[2]),
        .I3(\reply_len_reg_n_0_[9] ),
        .I4(s_axi_araddr[4]),
        .I5(\s_axi_rdata[9]_i_5_n_0 ),
        .O(\s_axi_rdata[9]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hBBBBBBBBFBFFFBBB)) 
    \s_axi_rdata[9]_i_4 
       (.I0(\s_axi_rdata[9]_i_6_n_0 ),
        .I1(s_axi_araddr[5]),
        .I2(\last_reply_len_reg_n_0_[9] ),
        .I3(s_axi_araddr[2]),
        .I4(fast_starts_reg[9]),
        .I5(\s_axi_rdata[15]_i_7_n_0 ),
        .O(\s_axi_rdata[9]_i_4_n_0 ));
  LUT4 #(
    .INIT(16'hA0CF)) 
    \s_axi_rdata[9]_i_5 
       (.I0(received_reg[9]),
        .I1(request_len__0[9]),
        .I2(s_axi_araddr[3]),
        .I3(s_axi_araddr[2]),
        .O(\s_axi_rdata[9]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h00000000F8C83808)) 
    \s_axi_rdata[9]_i_6 
       (.I0(\header_reg_n_0_[9] ),
        .I1(s_axi_araddr[2]),
        .I2(s_axi_araddr[3]),
        .I3(fast_completed_reg[9]),
        .I4(last_cycles[9]),
        .I5(s_axi_araddr[4]),
        .O(\s_axi_rdata[9]_i_6_n_0 ));
  FDRE \s_axi_rdata_reg[0] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[0]_i_1_n_0 ),
        .Q(s_axi_rdata[0]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[10] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[10]_i_1_n_0 ),
        .Q(s_axi_rdata[10]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[11] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[11]_i_1_n_0 ),
        .Q(s_axi_rdata[11]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[12] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[12]_i_1_n_0 ),
        .Q(s_axi_rdata[12]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[13] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[13]_i_1_n_0 ),
        .Q(s_axi_rdata[13]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[14] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[14]_i_1_n_0 ),
        .Q(s_axi_rdata[14]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[15] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[15]_i_1_n_0 ),
        .Q(s_axi_rdata[15]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[16] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[16]_i_1_n_0 ),
        .Q(s_axi_rdata[16]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[17] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[17]_i_1_n_0 ),
        .Q(s_axi_rdata[17]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[18] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[18]_i_1_n_0 ),
        .Q(s_axi_rdata[18]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[19] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[19]_i_1_n_0 ),
        .Q(s_axi_rdata[19]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[1] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[1]_i_1_n_0 ),
        .Q(s_axi_rdata[1]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[20] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[20]_i_1_n_0 ),
        .Q(s_axi_rdata[20]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[21] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[21]_i_1_n_0 ),
        .Q(s_axi_rdata[21]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[22] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[22]_i_1_n_0 ),
        .Q(s_axi_rdata[22]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[23] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[23]_i_1_n_0 ),
        .Q(s_axi_rdata[23]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[24] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[24]_i_1_n_0 ),
        .Q(s_axi_rdata[24]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[25] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[25]_i_1_n_0 ),
        .Q(s_axi_rdata[25]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[26] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[26]_i_1_n_0 ),
        .Q(s_axi_rdata[26]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[27] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[27]_i_1_n_0 ),
        .Q(s_axi_rdata[27]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[28] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[28]_i_1_n_0 ),
        .Q(s_axi_rdata[28]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[29] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[29]_i_1_n_0 ),
        .Q(s_axi_rdata[29]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[2] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[2]_i_1_n_0 ),
        .Q(s_axi_rdata[2]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[30] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[30]_i_1_n_0 ),
        .Q(s_axi_rdata[30]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[31] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[31]_i_3_n_0 ),
        .Q(s_axi_rdata[31]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[3] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[3]_i_1_n_0 ),
        .Q(s_axi_rdata[3]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[4] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[4]_i_1_n_0 ),
        .Q(s_axi_rdata[4]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[5] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[5]_i_1_n_0 ),
        .Q(s_axi_rdata[5]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[6] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[6]_i_1_n_0 ),
        .Q(s_axi_rdata[6]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[7] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[7]_i_1_n_0 ),
        .Q(s_axi_rdata[7]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[8] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[8]_i_1_n_0 ),
        .Q(s_axi_rdata[8]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  FDRE \s_axi_rdata_reg[9] 
       (.C(clk),
        .CE(\s_axi_rdata[31]_i_2_n_0 ),
        .D(\s_axi_rdata[9]_i_1_n_0 ),
        .Q(s_axi_rdata[9]),
        .R(\s_axi_rdata[31]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h00000000FFAAFCAA)) 
    \s_axi_rresp[1]_i_1 
       (.I0(s_axi_rresp),
        .I1(s_axi_araddr[0]),
        .I2(s_axi_araddr[1]),
        .I3(p_104_in),
        .I4(\s_axi_rresp[1]_i_2_n_0 ),
        .I5(\s_axi_rdata[31]_i_5_n_0 ),
        .O(\s_axi_rresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair27" *) 
  LUT5 #(
    .INIT(32'hFFFF0818)) 
    \s_axi_rresp[1]_i_2 
       (.I0(s_axi_araddr[2]),
        .I1(s_axi_araddr[4]),
        .I2(s_axi_araddr[5]),
        .I3(s_axi_araddr[3]),
        .I4(\s_axi_rresp[1]_i_3_n_0 ),
        .O(\s_axi_rresp[1]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFD)) 
    \s_axi_rresp[1]_i_3 
       (.I0(\s_axi_rdata[31]_i_12_n_0 ),
        .I1(\s_axi_rdata[31]_i_11_n_0 ),
        .I2(s_axi_araddr[10]),
        .I3(s_axi_araddr[12]),
        .I4(s_axi_araddr[6]),
        .O(\s_axi_rresp[1]_i_3_n_0 ));
  FDRE \s_axi_rresp_reg[1] 
       (.C(clk),
        .CE(1'b1),
        .D(\s_axi_rresp[1]_i_1_n_0 ),
        .Q(s_axi_rresp),
        .R(1'b0));
  LUT4 #(
    .INIT(16'h8C88)) 
    s_axi_rvalid_i_1
       (.I0(s_axi_rvalid_i_2_n_0),
        .I1(rst_n),
        .I2(s_axi_rready),
        .I3(s_axi_rvalid_reg_0),
        .O(s_axi_rvalid_i_1_n_0));
  LUT6 #(
    .INIT(64'h0000FF000000FF20)) 
    s_axi_rvalid_i_2
       (.I0(s_axi_arvalid),
        .I1(s_axi_rvalid_reg_0),
        .I2(rst_n),
        .I3(\hr_reg_n_0_[1] ),
        .I4(\hr_reg_n_0_[0] ),
        .I5(s_axi_rvalid_i_3_n_0),
        .O(s_axi_rvalid_i_2_n_0));
  LUT5 #(
    .INIT(32'h10000000)) 
    s_axi_rvalid_i_3
       (.I0(\host_quarter[1]_i_6_n_0 ),
        .I1(\host_quarter[1]_i_5_n_0 ),
        .I2(\host_quarter[1]_i_4_n_0 ),
        .I3(\host_quarter[1]_i_3_n_0 ),
        .I4(\host_quarter[1]_i_2_n_0 ),
        .O(s_axi_rvalid_i_3_n_0));
  FDRE s_axi_rvalid_reg
       (.C(clk),
        .CE(1'b1),
        .D(s_axi_rvalid_i_1_n_0),
        .Q(s_axi_rvalid_reg_0),
        .R(1'b0));
  (* SOFT_HLUTNM = "soft_lutpair85" *) 
  LUT3 #(
    .INIT(8'h04)) 
    s_axi_wready_INST_0
       (.I0(w_full_reg_n_0),
        .I1(rst_n),
        .I2(s_axi_bvalid_reg_0),
        .O(s_axi_wready));
  LUT6 #(
    .INIT(64'hFFFFFFFF01005555)) 
    \state[0]_i_1 
       (.I0(\state[1]_i_2_n_0 ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state[0]_i_2_n_0 ),
        .I3(\state[1]_i_6_n_0 ),
        .I4(\state[0]_i_3_n_0 ),
        .I5(\state[3]_i_4_n_0 ),
        .O(\state[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair132" *) 
  LUT2 #(
    .INIT(4'hB)) 
    \state[0]_i_2 
       (.I0(\state_reg_n_0_[2] ),
        .I1(rx_valid),
        .O(\state[0]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair61" *) 
  LUT3 #(
    .INIT(8'h45)) 
    \state[0]_i_3 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .O(\state[0]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAABFAAAAAABFAABF)) 
    \state[1]_i_1 
       (.I0(\state[1]_i_2_n_0 ),
        .I1(\state_reg[1]_i_3_n_2 ),
        .I2(\tx_index[15]_i_3_n_0 ),
        .I3(\state[1]_i_4_n_0 ),
        .I4(\state[1]_i_5_n_0 ),
        .I5(\state[1]_i_6_n_0 ),
        .O(\state[1]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h9009000000009009)) 
    \state[1]_i_10 
       (.I0(\state[1]_i_19_n_0 ),
        .I1(\reply_len_reg_n_0_[8] ),
        .I2(p_0_in[7]),
        .I3(\state[1]_i_20_n_0 ),
        .I4(p_0_in[6]),
        .I5(\state[1]_i_21_n_0 ),
        .O(\state[1]_i_10_n_0 ));
  LUT6 #(
    .INIT(64'h0000000006909009)) 
    \state[1]_i_11 
       (.I0(\tx_index_reg_n_0_[5] ),
        .I1(p_0_in[5]),
        .I2(p_0_in[4]),
        .I3(\tx_index[4]_i_2_n_0 ),
        .I4(\tx_index_reg_n_0_[4] ),
        .I5(\state[1]_i_22_n_0 ),
        .O(\state[1]_i_11_n_0 ));
  LUT6 #(
    .INIT(64'h0000900906900000)) 
    \state[1]_i_12 
       (.I0(\tx_index_reg_n_0_[2] ),
        .I1(p_0_in[2]),
        .I2(p_0_in[1]),
        .I3(\tx_index_reg_n_0_[1] ),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(p_0_in[0]),
        .O(\state[1]_i_12_n_0 ));
  LUT6 #(
    .INIT(64'h0000000001030003)) 
    \state[1]_i_13 
       (.I0(\count_reg_n_0_[0] ),
        .I1(\request_len[15]_i_7_n_0 ),
        .I2(\request_len[15]_i_6_n_0 ),
        .I3(\count_reg_n_0_[3] ),
        .I4(busy_INST_0_i_2_n_0),
        .I5(request_mem_reg_0_i_19_n_0),
        .O(\state[1]_i_13_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair80" *) 
  LUT4 #(
    .INIT(16'hFFD0)) 
    \state[1]_i_14 
       (.I0(\state[1]_i_23_n_0 ),
        .I1(\state[1]_i_24_n_0 ),
        .I2(rx_data[2]),
        .I3(\state[2]_i_14_n_0 ),
        .O(\state[1]_i_14_n_0 ));
  LUT5 #(
    .INIT(32'hF7FFFFFF)) 
    \state[1]_i_15 
       (.I0(\tx_index_reg_n_0_[11] ),
        .I1(\tx_index_reg_n_0_[9] ),
        .I2(\tx_index[11]_i_2_n_0 ),
        .I3(\tx_index_reg_n_0_[10] ),
        .I4(\tx_index_reg_n_0_[12] ),
        .O(\state[1]_i_15_n_0 ));
  LUT6 #(
    .INIT(64'h59555555A6AAAAAA)) 
    \state[1]_i_16 
       (.I0(\reply_len_reg_n_0_[12] ),
        .I1(\tx_index_reg_n_0_[10] ),
        .I2(\tx_index[11]_i_2_n_0 ),
        .I3(\tx_index_reg_n_0_[9] ),
        .I4(\tx_index_reg_n_0_[11] ),
        .I5(\tx_index_reg_n_0_[12] ),
        .O(\state[1]_i_16_n_0 ));
  LUT6 #(
    .INIT(64'h59555555A6AAAAAA)) 
    \state[1]_i_17 
       (.I0(\reply_len_reg_n_0_[9] ),
        .I1(\tx_index_reg_n_0_[7] ),
        .I2(\tx_index[7]_i_2_n_0 ),
        .I3(\tx_index_reg_n_0_[6] ),
        .I4(\tx_index_reg_n_0_[8] ),
        .I5(\tx_index_reg_n_0_[9] ),
        .O(\state[1]_i_17_n_0 ));
  LUT5 #(
    .INIT(32'hF7FFFFFF)) 
    \state[1]_i_18 
       (.I0(\tx_index_reg_n_0_[8] ),
        .I1(\tx_index_reg_n_0_[6] ),
        .I2(\tx_index[7]_i_2_n_0 ),
        .I3(\tx_index_reg_n_0_[7] ),
        .I4(\tx_index_reg_n_0_[9] ),
        .O(\state[1]_i_18_n_0 ));
  LUT6 #(
    .INIT(64'h6AAAAAAAAAAAAAAA)) 
    \state[1]_i_19 
       (.I0(\tx_index_reg_n_0_[8] ),
        .I1(\tx_index_reg_n_0_[7] ),
        .I2(\tx_index_reg_n_0_[5] ),
        .I3(\tx_index_reg_n_0_[4] ),
        .I4(\tx_index[4]_i_2_n_0 ),
        .I5(\tx_index_reg_n_0_[6] ),
        .O(\state[1]_i_19_n_0 ));
  LUT5 #(
    .INIT(32'hAA88AA80)) 
    \state[1]_i_2 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(reply_mem_reg_0_i_50_n_0),
        .I3(\reply_len[10]_i_6_n_0 ),
        .I4(\fast_error[2]_i_3_n_0 ),
        .O(\state[1]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair2" *) 
  LUT5 #(
    .INIT(32'h6AAAAAAA)) 
    \state[1]_i_20 
       (.I0(\tx_index_reg_n_0_[7] ),
        .I1(\tx_index_reg_n_0_[6] ),
        .I2(\tx_index[4]_i_2_n_0 ),
        .I3(\tx_index_reg_n_0_[4] ),
        .I4(\tx_index_reg_n_0_[5] ),
        .O(\state[1]_i_20_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair2" *) 
  LUT4 #(
    .INIT(16'h6AAA)) 
    \state[1]_i_21 
       (.I0(\tx_index_reg_n_0_[6] ),
        .I1(\tx_index_reg_n_0_[5] ),
        .I2(\tx_index_reg_n_0_[4] ),
        .I3(\tx_index[4]_i_2_n_0 ),
        .O(\state[1]_i_21_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair3" *) 
  LUT5 #(
    .INIT(32'h95556AAA)) 
    \state[1]_i_22 
       (.I0(p_0_in[3]),
        .I1(\tx_index_reg_n_0_[1] ),
        .I2(\tx_index_reg_n_0_[0] ),
        .I3(\tx_index_reg_n_0_[2] ),
        .I4(\tx_index_reg_n_0_[3] ),
        .O(\state[1]_i_22_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair81" *) 
  LUT4 #(
    .INIT(16'h0001)) 
    \state[1]_i_23 
       (.I0(\payload_len_reg_n_0_[6] ),
        .I1(\payload_len_reg_n_0_[0] ),
        .I2(\payload_len_reg_n_0_[5] ),
        .I3(rx_data[0]),
        .O(\state[1]_i_23_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \state[1]_i_24 
       (.I0(\payload_len_reg_n_0_[4] ),
        .I1(\payload_len_reg_n_0_[1] ),
        .I2(rx_data[1]),
        .I3(\payload_len_reg_n_0_[2] ),
        .I4(\payload_len_reg_n_0_[3] ),
        .I5(\payload_len_reg_n_0_[7] ),
        .O(\state[1]_i_24_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair122" *) 
  LUT3 #(
    .INIT(8'hEA)) 
    \state[1]_i_4 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[0] ),
        .O(\state[1]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair60" *) 
  LUT4 #(
    .INIT(16'hFFFD)) 
    \state[1]_i_5 
       (.I0(rx_valid),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[1] ),
        .O(\state[1]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hFFAEAEAEAEAEAEAE)) 
    \state[1]_i_6 
       (.I0(request_mem_reg_0_i_18_n_0),
        .I1(state23_out),
        .I2(\state[1]_i_13_n_0 ),
        .I3(\header[31]_i_4_n_0 ),
        .I4(request_mem_reg_0_i_10_n_0),
        .I5(\state[1]_i_14_n_0 ),
        .O(\state[1]_i_6_n_0 ));
  LUT4 #(
    .INIT(16'h2999)) 
    \state[1]_i_7 
       (.I0(\reply_len_reg_n_0_[15] ),
        .I1(\tx_index_reg_n_0_[15] ),
        .I2(\tx_index_reg_n_0_[14] ),
        .I3(\tx_index[15]_i_6_n_0 ),
        .O(\state[1]_i_7_n_0 ));
  LUT6 #(
    .INIT(64'h0000000090060990)) 
    \state[1]_i_8 
       (.I0(\tx_index_reg_n_0_[14] ),
        .I1(\reply_len_reg_n_0_[14] ),
        .I2(\reply_len_reg_n_0_[13] ),
        .I3(\state[1]_i_15_n_0 ),
        .I4(\tx_index_reg_n_0_[13] ),
        .I5(\state[1]_i_16_n_0 ),
        .O(\state[1]_i_8_n_0 ));
  LUT6 #(
    .INIT(64'h2010012002011002)) 
    \state[1]_i_9 
       (.I0(\reply_len_reg_n_0_[10] ),
        .I1(\state[1]_i_17_n_0 ),
        .I2(\tx_index_reg_n_0_[11] ),
        .I3(\tx_index_reg_n_0_[10] ),
        .I4(\state[1]_i_18_n_0 ),
        .I5(\reply_len_reg_n_0_[11] ),
        .O(\state[1]_i_9_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFEEFE)) 
    \state[2]_i_1 
       (.I0(\state[3]_i_7_n_0 ),
        .I1(\state[3]_i_6_n_0 ),
        .I2(\tx_index[15]_i_5_n_0 ),
        .I3(\s_axi_bresp[1]_i_4_n_0 ),
        .I4(\state[2]_i_3_n_0 ),
        .I5(\state[3]_i_4_n_0 ),
        .O(\state[2]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT4 #(
    .INIT(16'h01FF)) 
    \state[2]_i_10 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[3] ),
        .O(\state[2]_i_10_n_0 ));
  LUT6 #(
    .INIT(64'hFFDFDFDFFFDFFFDF)) 
    \state[2]_i_11 
       (.I0(fast_reply_valid),
        .I1(fast_reply_ready_INST_0_i_1_n_0),
        .I2(\reply_len[7]_i_6_n_0 ),
        .I3(\fast_error[2]_i_6_n_0 ),
        .I4(\fast_error[2]_i_5_n_0 ),
        .I5(fast_reply_data[2]),
        .O(\state[2]_i_11_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair33" *) 
  LUT5 #(
    .INIT(32'hBABABAAA)) 
    \state[2]_i_12 
       (.I0(\state_reg_n_0_[1] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(tx_ready),
        .I3(\state_reg[1]_i_3_n_2 ),
        .I4(\tx_index[4]_i_2_n_0 ),
        .O(\state[2]_i_12_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair40" *) 
  LUT4 #(
    .INIT(16'hFF5D)) 
    \state[2]_i_13 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[0] ),
        .I3(\state_reg_n_0_[3] ),
        .O(\state[2]_i_13_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \state[2]_i_14 
       (.I0(rx_data[4]),
        .I1(rx_data[3]),
        .I2(rx_data[6]),
        .I3(rx_data[7]),
        .I4(rx_data[5]),
        .O(\state[2]_i_14_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAAAAAAAAAA8)) 
    \state[2]_i_15 
       (.I0(rx_data[2]),
        .I1(\state[1]_i_24_n_0 ),
        .I2(\payload_len_reg_n_0_[6] ),
        .I3(\payload_len_reg_n_0_[0] ),
        .I4(\payload_len_reg_n_0_[5] ),
        .I5(rx_data[0]),
        .O(\state[2]_i_15_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair71" *) 
  LUT2 #(
    .INIT(4'h7)) 
    \state[2]_i_16 
       (.I0(\count_reg_n_0_[0] ),
        .I1(\count_reg_n_0_[1] ),
        .O(\state[2]_i_16_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFF0B0B0B00)) 
    \state[2]_i_2 
       (.I0(\state[2]_i_4_n_0 ),
        .I1(\state[2]_i_5_n_0 ),
        .I2(\state[2]_i_6_n_0 ),
        .I3(\reply_index[15]_i_4_n_0 ),
        .I4(\state[2]_i_7_n_0 ),
        .I5(\state[3]_i_4_n_0 ),
        .O(\state[2]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h2220222022202222)) 
    \state[2]_i_3 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state[2]_i_8_n_0 ),
        .I3(\state[3]_i_8_n_0 ),
        .I4(reply_mem_reg_0_i_50_n_0),
        .I5(\fast_error[2]_i_3_n_0 ),
        .O(\state[2]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair17" *) 
  LUT5 #(
    .INIT(32'hFFFFFDCC)) 
    \state[2]_i_4 
       (.I0(\tx_index[15]_i_4_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[2] ),
        .O(\state[2]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0F0FCFCFFF4FCFCF)) 
    \state[2]_i_5 
       (.I0(\state[2]_i_9_n_0 ),
        .I1(\tx_index[15]_i_4_n_0 ),
        .I2(\state[3]_i_12_n_0 ),
        .I3(\request_len[15]_i_3_n_0 ),
        .I4(rx_valid),
        .I5(request_mem_reg_0_i_18_n_0),
        .O(\state[2]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFF4400FFF0)) 
    \state[2]_i_6 
       (.I0(\state[2]_i_10_n_0 ),
        .I1(\state[2]_i_11_n_0 ),
        .I2(\state[2]_i_12_n_0 ),
        .I3(\tx_index[15]_i_4_n_0 ),
        .I4(\state[2]_i_13_n_0 ),
        .I5(\last_cycles[31]_i_1_n_0 ),
        .O(\state[2]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h5555555515001515)) 
    \state[2]_i_7 
       (.I0(\state[3]_i_8_n_0 ),
        .I1(\tx_index[15]_i_4_n_0 ),
        .I2(\cmd_index[6]_i_2_n_0 ),
        .I3(\state_reg_n_0_[1] ),
        .I4(state1),
        .I5(\state_reg_n_0_[0] ),
        .O(\state[2]_i_7_n_0 ));
  LUT6 #(
    .INIT(64'hA888888888888888)) 
    \state[2]_i_8 
       (.I0(\state[3]_i_12_n_0 ),
        .I1(state1),
        .I2(\cmd_index_reg_n_0_[2] ),
        .I3(\cmd_index_reg_n_0_[0] ),
        .I4(\cmd_index_reg_n_0_[1] ),
        .I5(\cmd_index_reg_n_0_[3] ),
        .O(\state[2]_i_8_n_0 ));
  LUT6 #(
    .INIT(64'h00000E0000000000)) 
    \state[2]_i_9 
       (.I0(\state[2]_i_14_n_0 ),
        .I1(\state[2]_i_15_n_0 ),
        .I2(\count_reg_n_0_[3] ),
        .I3(\count_reg_n_0_[2] ),
        .I4(\state[2]_i_16_n_0 ),
        .I5(\header[31]_i_4_n_0 ),
        .O(\state[2]_i_9_n_0 ));
  LUT2 #(
    .INIT(4'hB)) 
    \state[3]_i_1 
       (.I0(\state[3]_i_4_n_0 ),
        .I1(rst_n),
        .O(\state[3]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h55555555FFFF55F7)) 
    \state[3]_i_10 
       (.I0(watchdog[26]),
        .I1(watchdog[18]),
        .I2(\state[3]_i_23_n_0 ),
        .I3(watchdog[19]),
        .I4(\state[3]_i_24_n_0 ),
        .I5(watchdog[25]),
        .O(\state[3]_i_10_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \state[3]_i_11 
       (.I0(watchdog[30]),
        .I1(watchdog[31]),
        .I2(watchdog[28]),
        .I3(watchdog[27]),
        .I4(watchdog[29]),
        .O(\state[3]_i_11_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair122" *) 
  LUT2 #(
    .INIT(4'h1)) 
    \state[3]_i_12 
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[1] ),
        .O(\state[3]_i_12_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair33" *) 
  LUT4 #(
    .INIT(16'h00E0)) 
    \state[3]_i_13 
       (.I0(\tx_index[4]_i_2_n_0 ),
        .I1(\state_reg[1]_i_3_n_2 ),
        .I2(tx_ready),
        .I3(\state_reg_n_0_[0] ),
        .O(\state[3]_i_13_n_0 ));
  LUT3 #(
    .INIT(8'hEF)) 
    \state[3]_i_14 
       (.I0(engine_busy),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .O(\state[3]_i_14_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair38" *) 
  LUT5 #(
    .INIT(32'hFFFFFE00)) 
    \state[3]_i_15 
       (.I0(\reply_index_reg_n_0_[1] ),
        .I1(\reply_index_reg_n_0_[0] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .I3(\reply_index_reg_n_0_[3] ),
        .I4(\reply_index_reg_n_0_[15] ),
        .O(\state[3]_i_15_n_0 ));
  LUT4 #(
    .INIT(16'h2999)) 
    \state[3]_i_17 
       (.I0(request_len__0[15]),
        .I1(\cmd_index_reg_n_0_[15] ),
        .I2(\state[3]_i_31_n_0 ),
        .I3(\cmd_index_reg_n_0_[14] ),
        .O(\state[3]_i_17_n_0 ));
  LUT6 #(
    .INIT(64'h0120201010020201)) 
    \state[3]_i_18 
       (.I0(request_len__0[13]),
        .I1(\state[3]_i_32_n_0 ),
        .I2(\cmd_index_reg_n_0_[14] ),
        .I3(\state[3]_i_33_n_0 ),
        .I4(\cmd_index_reg_n_0_[13] ),
        .I5(request_len__0[14]),
        .O(\state[3]_i_18_n_0 ));
  LUT6 #(
    .INIT(64'h0000000082412418)) 
    \state[3]_i_19 
       (.I0(request_len__0[11]),
        .I1(\cmd_index_reg_n_0_[10] ),
        .I2(\state[3]_i_34_n_0 ),
        .I3(\cmd_index_reg_n_0_[11] ),
        .I4(request_len__0[10]),
        .I5(\state[3]_i_35_n_0 ),
        .O(\state[3]_i_19_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFF1F11)) 
    \state[3]_i_2 
       (.I0(\state[3]_i_5_n_0 ),
        .I1(\reply_index[15]_i_4_n_0 ),
        .I2(\s_axi_bresp[1]_i_4_n_0 ),
        .I3(\tx_index[15]_i_5_n_0 ),
        .I4(\state[3]_i_6_n_0 ),
        .I5(\state[3]_i_7_n_0 ),
        .O(\state[3]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h2001102002100102)) 
    \state[3]_i_20 
       (.I0(request_len__0[7]),
        .I1(\state[3]_i_36_n_0 ),
        .I2(\cmd_index_reg_n_0_[8] ),
        .I3(\state[3]_i_37_n_0 ),
        .I4(\cmd_index_reg_n_0_[7] ),
        .I5(request_len__0[8]),
        .O(\state[3]_i_20_n_0 ));
  LUT6 #(
    .INIT(64'h2001102002100102)) 
    \state[3]_i_21 
       (.I0(request_len__0[4]),
        .I1(\state[3]_i_38_n_0 ),
        .I2(\cmd_index_reg_n_0_[5] ),
        .I3(\cmd_index[6]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[4] ),
        .I5(request_len__0[5]),
        .O(\state[3]_i_21_n_0 ));
  LUT6 #(
    .INIT(64'h0120804010020804)) 
    \state[3]_i_22 
       (.I0(request_len__0[1]),
        .I1(request_len__0[0]),
        .I2(\cmd_index_reg_n_0_[2] ),
        .I3(\cmd_index_reg_n_0_[1] ),
        .I4(\cmd_index_reg_n_0_[0] ),
        .I5(request_len__0[2]),
        .O(\state[3]_i_22_n_0 ));
  LUT6 #(
    .INIT(64'h000000007FFFFFFF)) 
    \state[3]_i_23 
       (.I0(\state[3]_i_39_n_0 ),
        .I1(watchdog[14]),
        .I2(watchdog[15]),
        .I3(watchdog[13]),
        .I4(watchdog[16]),
        .I5(watchdog[17]),
        .O(\state[3]_i_23_n_0 ));
  LUT5 #(
    .INIT(32'h7FFFFFFF)) 
    \state[3]_i_24 
       (.I0(watchdog[20]),
        .I1(watchdog[23]),
        .I2(watchdog[24]),
        .I3(watchdog[22]),
        .I4(watchdog[21]),
        .O(\state[3]_i_24_n_0 ));
  LUT4 #(
    .INIT(16'h700F)) 
    \state[3]_i_25 
       (.I0(\reply_index[10]_i_2_n_0 ),
        .I1(\reply_index_reg_n_0_[10] ),
        .I2(\reply_len_reg_n_0_[15] ),
        .I3(\reply_index_reg_n_0_[15] ),
        .O(\state[3]_i_25_n_0 ));
  LUT6 #(
    .INIT(64'h2A000000000000D5)) 
    \state[3]_i_26 
       (.I0(\reply_index_reg_n_0_[15] ),
        .I1(\reply_index[10]_i_2_n_0 ),
        .I2(\reply_index_reg_n_0_[10] ),
        .I3(\reply_len_reg_n_0_[12] ),
        .I4(\reply_len_reg_n_0_[13] ),
        .I5(\reply_len_reg_n_0_[14] ),
        .O(\state[3]_i_26_n_0 ));
  LUT6 #(
    .INIT(64'h0000000006909009)) 
    \state[3]_i_27 
       (.I0(\reply_index_reg_n_0_[15] ),
        .I1(\reply_len_reg_n_0_[11] ),
        .I2(\reply_len_reg_n_0_[10] ),
        .I3(\reply_index[10]_i_2_n_0 ),
        .I4(\reply_index_reg_n_0_[10] ),
        .I5(\state[3]_i_40_n_0 ),
        .O(\state[3]_i_27_n_0 ));
  LUT6 #(
    .INIT(64'h9009000000009009)) 
    \state[3]_i_28 
       (.I0(\state[3]_i_41_n_0 ),
        .I1(\reply_len_reg_n_0_[8] ),
        .I2(p_0_in[7]),
        .I3(\state[3]_i_42_n_0 ),
        .I4(p_0_in[6]),
        .I5(\state[3]_i_43_n_0 ),
        .O(\state[3]_i_28_n_0 ));
  LUT6 #(
    .INIT(64'h0880022020088002)) 
    \state[3]_i_29 
       (.I0(\state[3]_i_44_n_0 ),
        .I1(p_0_in[5]),
        .I2(\reply_index_reg_n_0_[4] ),
        .I3(reply_mem_reg_1_i_9_n_0),
        .I4(\reply_index_reg_n_0_[5] ),
        .I5(p_0_in[4]),
        .O(\state[3]_i_29_n_0 ));
  LUT6 #(
    .INIT(64'h0F000000A0A0A0E0)) 
    \state[3]_i_3 
       (.I0(\state[3]_i_8_n_0 ),
        .I1(state1),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[1] ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\state_reg_n_0_[2] ),
        .O(\state[3]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0000900906900000)) 
    \state[3]_i_30 
       (.I0(\reply_index_reg_n_0_[2] ),
        .I1(p_0_in[2]),
        .I2(p_0_in[1]),
        .I3(\reply_index_reg_n_0_[1] ),
        .I4(\reply_index_reg_n_0_[0] ),
        .I5(p_0_in[0]),
        .O(\state[3]_i_30_n_0 ));
  LUT6 #(
    .INIT(64'h0800000000000000)) 
    \state[3]_i_31 
       (.I0(\cmd_index_reg_n_0_[13] ),
        .I1(\cmd_index_reg_n_0_[11] ),
        .I2(\cmd_index[11]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[9] ),
        .I4(\cmd_index_reg_n_0_[10] ),
        .I5(\cmd_index_reg_n_0_[12] ),
        .O(\state[3]_i_31_n_0 ));
  LUT6 #(
    .INIT(64'h59555555A6AAAAAA)) 
    \state[3]_i_32 
       (.I0(request_len__0[12]),
        .I1(\cmd_index_reg_n_0_[11] ),
        .I2(\cmd_index[11]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[9] ),
        .I4(\cmd_index_reg_n_0_[10] ),
        .I5(\cmd_index_reg_n_0_[12] ),
        .O(\state[3]_i_32_n_0 ));
  LUT5 #(
    .INIT(32'h00800000)) 
    \state[3]_i_33 
       (.I0(\cmd_index_reg_n_0_[12] ),
        .I1(\cmd_index_reg_n_0_[10] ),
        .I2(\cmd_index_reg_n_0_[9] ),
        .I3(\cmd_index[11]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[11] ),
        .O(\state[3]_i_33_n_0 ));
  LUT5 #(
    .INIT(32'hF7FFFFFF)) 
    \state[3]_i_34 
       (.I0(\cmd_index_reg_n_0_[8] ),
        .I1(\cmd_index_reg_n_0_[6] ),
        .I2(\cmd_index[8]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[7] ),
        .I4(\cmd_index_reg_n_0_[9] ),
        .O(\state[3]_i_34_n_0 ));
  LUT6 #(
    .INIT(64'h55955555AA6AAAAA)) 
    \state[3]_i_35 
       (.I0(request_len__0[9]),
        .I1(\cmd_index_reg_n_0_[8] ),
        .I2(\cmd_index_reg_n_0_[6] ),
        .I3(\cmd_index[8]_i_2_n_0 ),
        .I4(\cmd_index_reg_n_0_[7] ),
        .I5(\cmd_index_reg_n_0_[9] ),
        .O(\state[3]_i_35_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair31" *) 
  LUT5 #(
    .INIT(32'h5955A6AA)) 
    \state[3]_i_36 
       (.I0(request_len__0[6]),
        .I1(\cmd_index_reg_n_0_[5] ),
        .I2(\cmd_index[6]_i_2_n_0 ),
        .I3(\cmd_index_reg_n_0_[4] ),
        .I4(\cmd_index_reg_n_0_[6] ),
        .O(\state[3]_i_36_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair31" *) 
  LUT4 #(
    .INIT(16'hDFFF)) 
    \state[3]_i_37 
       (.I0(\cmd_index_reg_n_0_[5] ),
        .I1(\cmd_index[6]_i_2_n_0 ),
        .I2(\cmd_index_reg_n_0_[4] ),
        .I3(\cmd_index_reg_n_0_[6] ),
        .O(\state[3]_i_37_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair32" *) 
  LUT5 #(
    .INIT(32'h95556AAA)) 
    \state[3]_i_38 
       (.I0(request_len__0[3]),
        .I1(\cmd_index_reg_n_0_[2] ),
        .I2(\cmd_index_reg_n_0_[0] ),
        .I3(\cmd_index_reg_n_0_[1] ),
        .I4(\cmd_index_reg_n_0_[3] ),
        .O(\state[3]_i_38_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \state[3]_i_39 
       (.I0(watchdog[9]),
        .I1(watchdog[11]),
        .I2(watchdog[8]),
        .I3(watchdog[12]),
        .I4(watchdog[10]),
        .O(\state[3]_i_39_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAFBAAFBAAAA)) 
    \state[3]_i_4 
       (.I0(rx_error),
        .I1(\state[3]_i_10_n_0 ),
        .I2(\state[3]_i_11_n_0 ),
        .I3(\reply_index[15]_i_4_n_0 ),
        .I4(\state_reg_n_0_[1] ),
        .I5(\state_reg_n_0_[0] ),
        .O(\state[3]_i_4_n_0 ));
  LUT5 #(
    .INIT(32'h5955A6AA)) 
    \state[3]_i_40 
       (.I0(\reply_len_reg_n_0_[9] ),
        .I1(\reply_index_reg_n_0_[7] ),
        .I2(\reply_index[9]_i_2_n_0 ),
        .I3(\reply_index_reg_n_0_[8] ),
        .I4(\reply_index_reg_n_0_[9] ),
        .O(\state[3]_i_40_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair1" *) 
  LUT5 #(
    .INIT(32'h6AAAAAAA)) 
    \state[3]_i_41 
       (.I0(\reply_index_reg_n_0_[8] ),
        .I1(\reply_index_reg_n_0_[7] ),
        .I2(\reply_index_reg_n_0_[5] ),
        .I3(\reply_index_reg_n_0_[6] ),
        .I4(\reply_index[6]_i_2_n_0 ),
        .O(\state[3]_i_41_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair1" *) 
  LUT4 #(
    .INIT(16'h6AAA)) 
    \state[3]_i_42 
       (.I0(\reply_index_reg_n_0_[7] ),
        .I1(\reply_index[6]_i_2_n_0 ),
        .I2(\reply_index_reg_n_0_[6] ),
        .I3(\reply_index_reg_n_0_[5] ),
        .O(\state[3]_i_42_n_0 ));
  LUT6 #(
    .INIT(64'h6AAAAAAAAAAAAAAA)) 
    \state[3]_i_43 
       (.I0(\reply_index_reg_n_0_[6] ),
        .I1(\reply_index_reg_n_0_[4] ),
        .I2(\reply_index_reg_n_0_[2] ),
        .I3(\reply_index_reg_n_0_[3] ),
        .I4(reply_mem_reg_0_i_57_n_0),
        .I5(\reply_index_reg_n_0_[5] ),
        .O(\state[3]_i_43_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair36" *) 
  LUT5 #(
    .INIT(32'h69999999)) 
    \state[3]_i_44 
       (.I0(p_0_in[3]),
        .I1(\reply_index_reg_n_0_[3] ),
        .I2(\reply_index_reg_n_0_[1] ),
        .I3(\reply_index_reg_n_0_[0] ),
        .I4(\reply_index_reg_n_0_[2] ),
        .O(\state[3]_i_44_n_0 ));
  LUT6 #(
    .INIT(64'h000E0E0E000E000E)) 
    \state[3]_i_5 
       (.I0(\fast_error[2]_i_3_n_0 ),
        .I1(reply_mem_reg_0_i_50_n_0),
        .I2(\state[3]_i_8_n_0 ),
        .I3(\state[3]_i_12_n_0 ),
        .I4(state1),
        .I5(\cmd_index[6]_i_2_n_0 ),
        .O(\state[3]_i_5_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair61" *) 
  LUT4 #(
    .INIT(16'h00EA)) 
    \state[3]_i_6 
       (.I0(\state_reg_n_0_[1] ),
        .I1(\state[3]_i_13_n_0 ),
        .I2(\state_reg_n_0_[2] ),
        .I3(\state_reg_n_0_[3] ),
        .O(\state[3]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h0000004055555555)) 
    \state[3]_i_7 
       (.I0(\state_reg_n_0_[2] ),
        .I1(\state[1]_i_6_n_0 ),
        .I2(rx_valid),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[3] ),
        .I5(\state[3]_i_14_n_0 ),
        .O(\state[3]_i_7_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair22" *) 
  LUT5 #(
    .INIT(32'h0000B000)) 
    \state[3]_i_8 
       (.I0(\state[3]_i_15_n_0 ),
        .I1(\reply_len[15]_i_8_n_0 ),
        .I2(state2),
        .I3(fast_reply_valid),
        .I4(fast_reply_ready_INST_0_i_1_n_0),
        .O(\state[3]_i_8_n_0 ));
  FDRE \state_reg[0] 
       (.C(clk),
        .CE(\state[2]_i_1_n_0 ),
        .D(\state[0]_i_1_n_0 ),
        .Q(\state_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \state_reg[1] 
       (.C(clk),
        .CE(\state[3]_i_2_n_0 ),
        .D(\state[1]_i_1_n_0 ),
        .Q(\state_reg_n_0_[1] ),
        .R(\state[3]_i_1_n_0 ));
  CARRY8 \state_reg[1]_i_3 
       (.CI(1'b1),
        .CI_TOP(1'b0),
        .CO({\NLW_state_reg[1]_i_3_CO_UNCONNECTED [7:6],\state_reg[1]_i_3_n_2 ,\state_reg[1]_i_3_n_3 ,\state_reg[1]_i_3_n_4 ,\state_reg[1]_i_3_n_5 ,\state_reg[1]_i_3_n_6 ,\state_reg[1]_i_3_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(\NLW_state_reg[1]_i_3_O_UNCONNECTED [7:0]),
        .S({1'b0,1'b0,\state[1]_i_7_n_0 ,\state[1]_i_8_n_0 ,\state[1]_i_9_n_0 ,\state[1]_i_10_n_0 ,\state[1]_i_11_n_0 ,\state[1]_i_12_n_0 }));
  FDRE \state_reg[2] 
       (.C(clk),
        .CE(\state[2]_i_1_n_0 ),
        .D(\state[2]_i_2_n_0 ),
        .Q(\state_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \state_reg[3] 
       (.C(clk),
        .CE(\state[3]_i_2_n_0 ),
        .D(\state[3]_i_3_n_0 ),
        .Q(\state_reg_n_0_[3] ),
        .R(\state[3]_i_1_n_0 ));
  CARRY8 \state_reg[3]_i_16 
       (.CI(1'b1),
        .CI_TOP(1'b0),
        .CO({\NLW_state_reg[3]_i_16_CO_UNCONNECTED [7:6],state2,\state_reg[3]_i_16_n_3 ,\state_reg[3]_i_16_n_4 ,\state_reg[3]_i_16_n_5 ,\state_reg[3]_i_16_n_6 ,\state_reg[3]_i_16_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(\NLW_state_reg[3]_i_16_O_UNCONNECTED [7:0]),
        .S({1'b0,1'b0,\state[3]_i_25_n_0 ,\state[3]_i_26_n_0 ,\state[3]_i_27_n_0 ,\state[3]_i_28_n_0 ,\state[3]_i_29_n_0 ,\state[3]_i_30_n_0 }));
  CARRY8 \state_reg[3]_i_9 
       (.CI(1'b1),
        .CI_TOP(1'b0),
        .CO({\NLW_state_reg[3]_i_9_CO_UNCONNECTED [7:6],state1,\state_reg[3]_i_9_n_3 ,\state_reg[3]_i_9_n_4 ,\state_reg[3]_i_9_n_5 ,\state_reg[3]_i_9_n_6 ,\state_reg[3]_i_9_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(\NLW_state_reg[3]_i_9_O_UNCONNECTED [7:0]),
        .S({1'b0,1'b0,\state[3]_i_17_n_0 ,\state[3]_i_18_n_0 ,\state[3]_i_19_n_0 ,\state[3]_i_20_n_0 ,\state[3]_i_21_n_0 ,\state[3]_i_22_n_0 }));
  MUXF8 \tx_data[0]_INST_0 
       (.I0(\tx_data[0]_INST_0_i_1_n_0 ),
        .I1(\tx_data[0]_INST_0_i_2_n_0 ),
        .O(tx_data[0]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[0]_INST_0_i_1 
       (.I0(\tx_data[0]_INST_0_i_3_n_0 ),
        .I1(\tx_data[0]_INST_0_i_4_n_0 ),
        .O(\tx_data[0]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[0]_INST_0_i_2 
       (.I0(\tx_data[0]_INST_0_i_5_n_0 ),
        .I1(\tx_data[0]_INST_0_i_6_n_0 ),
        .O(\tx_data[0]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[0]_INST_0_i_3 
       (.I0(data3[0]),
        .I1(data2[0]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[0]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[0]),
        .O(\tx_data[0]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[0]_INST_0_i_4 
       (.I0(data7[0]),
        .I1(data6[0]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[0]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[0]),
        .O(\tx_data[0]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[0]_INST_0_i_5 
       (.I0(data11[0]),
        .I1(data10[0]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[0]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[0]),
        .O(\tx_data[0]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[0]_INST_0_i_6 
       (.I0(data15[0]),
        .I1(data14[0]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[0]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[0]),
        .O(\tx_data[0]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[1]_INST_0 
       (.I0(\tx_data[1]_INST_0_i_1_n_0 ),
        .I1(\tx_data[1]_INST_0_i_2_n_0 ),
        .O(tx_data[1]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[1]_INST_0_i_1 
       (.I0(\tx_data[1]_INST_0_i_3_n_0 ),
        .I1(\tx_data[1]_INST_0_i_4_n_0 ),
        .O(\tx_data[1]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[1]_INST_0_i_2 
       (.I0(\tx_data[1]_INST_0_i_5_n_0 ),
        .I1(\tx_data[1]_INST_0_i_6_n_0 ),
        .O(\tx_data[1]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[1]_INST_0_i_3 
       (.I0(data3[1]),
        .I1(data2[1]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[1]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[1]),
        .O(\tx_data[1]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[1]_INST_0_i_4 
       (.I0(data7[1]),
        .I1(data6[1]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[1]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[1]),
        .O(\tx_data[1]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[1]_INST_0_i_5 
       (.I0(data11[1]),
        .I1(data10[1]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[1]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[1]),
        .O(\tx_data[1]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[1]_INST_0_i_6 
       (.I0(data15[1]),
        .I1(data14[1]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[1]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[1]),
        .O(\tx_data[1]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[2]_INST_0 
       (.I0(\tx_data[2]_INST_0_i_1_n_0 ),
        .I1(\tx_data[2]_INST_0_i_2_n_0 ),
        .O(tx_data[2]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[2]_INST_0_i_1 
       (.I0(\tx_data[2]_INST_0_i_3_n_0 ),
        .I1(\tx_data[2]_INST_0_i_4_n_0 ),
        .O(\tx_data[2]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[2]_INST_0_i_2 
       (.I0(\tx_data[2]_INST_0_i_5_n_0 ),
        .I1(\tx_data[2]_INST_0_i_6_n_0 ),
        .O(\tx_data[2]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[2]_INST_0_i_3 
       (.I0(data3[2]),
        .I1(data2[2]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[2]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[2]),
        .O(\tx_data[2]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[2]_INST_0_i_4 
       (.I0(data7[2]),
        .I1(data6[2]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[2]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[2]),
        .O(\tx_data[2]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[2]_INST_0_i_5 
       (.I0(data11[2]),
        .I1(data10[2]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[2]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[2]),
        .O(\tx_data[2]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[2]_INST_0_i_6 
       (.I0(data15[2]),
        .I1(data14[2]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[2]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[2]),
        .O(\tx_data[2]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[3]_INST_0 
       (.I0(\tx_data[3]_INST_0_i_1_n_0 ),
        .I1(\tx_data[3]_INST_0_i_2_n_0 ),
        .O(tx_data[3]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[3]_INST_0_i_1 
       (.I0(\tx_data[3]_INST_0_i_3_n_0 ),
        .I1(\tx_data[3]_INST_0_i_4_n_0 ),
        .O(\tx_data[3]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[3]_INST_0_i_2 
       (.I0(\tx_data[3]_INST_0_i_5_n_0 ),
        .I1(\tx_data[3]_INST_0_i_6_n_0 ),
        .O(\tx_data[3]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[3]_INST_0_i_3 
       (.I0(data3[3]),
        .I1(data2[3]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[3]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[3]),
        .O(\tx_data[3]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[3]_INST_0_i_4 
       (.I0(data7[3]),
        .I1(data6[3]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[3]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[3]),
        .O(\tx_data[3]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[3]_INST_0_i_5 
       (.I0(data11[3]),
        .I1(data10[3]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[3]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[3]),
        .O(\tx_data[3]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[3]_INST_0_i_6 
       (.I0(data15[3]),
        .I1(data14[3]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[3]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[3]),
        .O(\tx_data[3]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[4]_INST_0 
       (.I0(\tx_data[4]_INST_0_i_1_n_0 ),
        .I1(\tx_data[4]_INST_0_i_2_n_0 ),
        .O(tx_data[4]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[4]_INST_0_i_1 
       (.I0(\tx_data[4]_INST_0_i_3_n_0 ),
        .I1(\tx_data[4]_INST_0_i_4_n_0 ),
        .O(\tx_data[4]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[4]_INST_0_i_2 
       (.I0(\tx_data[4]_INST_0_i_5_n_0 ),
        .I1(\tx_data[4]_INST_0_i_6_n_0 ),
        .O(\tx_data[4]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[4]_INST_0_i_3 
       (.I0(data3[4]),
        .I1(data2[4]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[4]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[4]),
        .O(\tx_data[4]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[4]_INST_0_i_4 
       (.I0(data7[4]),
        .I1(data6[4]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[4]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[4]),
        .O(\tx_data[4]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[4]_INST_0_i_5 
       (.I0(data11[4]),
        .I1(data10[4]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[4]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[4]),
        .O(\tx_data[4]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[4]_INST_0_i_6 
       (.I0(data15[4]),
        .I1(data14[4]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[4]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[4]),
        .O(\tx_data[4]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[5]_INST_0 
       (.I0(\tx_data[5]_INST_0_i_1_n_0 ),
        .I1(\tx_data[5]_INST_0_i_2_n_0 ),
        .O(tx_data[5]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[5]_INST_0_i_1 
       (.I0(\tx_data[5]_INST_0_i_3_n_0 ),
        .I1(\tx_data[5]_INST_0_i_4_n_0 ),
        .O(\tx_data[5]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[5]_INST_0_i_2 
       (.I0(\tx_data[5]_INST_0_i_5_n_0 ),
        .I1(\tx_data[5]_INST_0_i_6_n_0 ),
        .O(\tx_data[5]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[5]_INST_0_i_3 
       (.I0(data3[5]),
        .I1(data2[5]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[5]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[5]),
        .O(\tx_data[5]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[5]_INST_0_i_4 
       (.I0(data7[5]),
        .I1(data6[5]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[5]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[5]),
        .O(\tx_data[5]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[5]_INST_0_i_5 
       (.I0(data11[5]),
        .I1(data10[5]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[5]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[5]),
        .O(\tx_data[5]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[5]_INST_0_i_6 
       (.I0(data15[5]),
        .I1(data14[5]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[5]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[5]),
        .O(\tx_data[5]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[6]_INST_0 
       (.I0(\tx_data[6]_INST_0_i_1_n_0 ),
        .I1(\tx_data[6]_INST_0_i_2_n_0 ),
        .O(tx_data[6]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[6]_INST_0_i_1 
       (.I0(\tx_data[6]_INST_0_i_3_n_0 ),
        .I1(\tx_data[6]_INST_0_i_4_n_0 ),
        .O(\tx_data[6]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[6]_INST_0_i_2 
       (.I0(\tx_data[6]_INST_0_i_5_n_0 ),
        .I1(\tx_data[6]_INST_0_i_6_n_0 ),
        .O(\tx_data[6]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[6]_INST_0_i_3 
       (.I0(data3[6]),
        .I1(data2[6]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[6]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[6]),
        .O(\tx_data[6]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[6]_INST_0_i_4 
       (.I0(data7[6]),
        .I1(data6[6]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[6]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[6]),
        .O(\tx_data[6]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[6]_INST_0_i_5 
       (.I0(data11[6]),
        .I1(data10[6]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[6]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[6]),
        .O(\tx_data[6]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[6]_INST_0_i_6 
       (.I0(data15[6]),
        .I1(data14[6]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[6]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[6]),
        .O(\tx_data[6]_INST_0_i_6_n_0 ));
  MUXF8 \tx_data[7]_INST_0 
       (.I0(\tx_data[7]_INST_0_i_1_n_0 ),
        .I1(\tx_data[7]_INST_0_i_2_n_0 ),
        .O(tx_data[7]),
        .S(\tx_index_reg_n_0_[3] ));
  MUXF7 \tx_data[7]_INST_0_i_1 
       (.I0(\tx_data[7]_INST_0_i_3_n_0 ),
        .I1(\tx_data[7]_INST_0_i_4_n_0 ),
        .O(\tx_data[7]_INST_0_i_1_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  MUXF7 \tx_data[7]_INST_0_i_2 
       (.I0(\tx_data[7]_INST_0_i_5_n_0 ),
        .I1(\tx_data[7]_INST_0_i_6_n_0 ),
        .O(\tx_data[7]_INST_0_i_2_n_0 ),
        .S(\tx_index_reg_n_0_[2] ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[7]_INST_0_i_3 
       (.I0(data3[7]),
        .I1(data2[7]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data1[7]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(reply_q[7]),
        .O(\tx_data[7]_INST_0_i_3_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[7]_INST_0_i_4 
       (.I0(data7[7]),
        .I1(data6[7]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data5[7]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data4[7]),
        .O(\tx_data[7]_INST_0_i_4_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[7]_INST_0_i_5 
       (.I0(data11[7]),
        .I1(data10[7]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data9[7]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data8[7]),
        .O(\tx_data[7]_INST_0_i_5_n_0 ));
  LUT6 #(
    .INIT(64'hAFA0CFCFAFA0C0C0)) 
    \tx_data[7]_INST_0_i_6 
       (.I0(data15[7]),
        .I1(data14[7]),
        .I2(\tx_index_reg_n_0_[1] ),
        .I3(data13[7]),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(data12[7]),
        .O(\tx_data[7]_INST_0_i_6_n_0 ));
  LUT6 #(
    .INIT(64'hAAA2AAAAAAAAAAAA)) 
    \tx_index[0]_i_1 
       (.I0(\tx_index[13]_i_2_n_0 ),
        .I1(\tx_index_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[2] ),
        .I5(tx_ready),
        .O(tx_index__0[0]));
  LUT6 #(
    .INIT(64'h3030033022222222)) 
    \tx_index[10]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[10] ),
        .I3(\tx_index_reg_n_0_[9] ),
        .I4(\tx_index[11]_i_2_n_0 ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[10]));
  LUT6 #(
    .INIT(64'h88288888AAAAAAAA)) 
    \tx_index[11]_i_1 
       (.I0(\tx_index[13]_i_2_n_0 ),
        .I1(\tx_index_reg_n_0_[11] ),
        .I2(\tx_index_reg_n_0_[10] ),
        .I3(\tx_index[11]_i_2_n_0 ),
        .I4(\tx_index_reg_n_0_[9] ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index__0[11]));
  LUT6 #(
    .INIT(64'h7FFFFFFFFFFFFFFF)) 
    \tx_index[11]_i_2 
       (.I0(\tx_index_reg_n_0_[7] ),
        .I1(\tx_index_reg_n_0_[5] ),
        .I2(\tx_index_reg_n_0_[4] ),
        .I3(\tx_index[4]_i_2_n_0 ),
        .I4(\tx_index_reg_n_0_[6] ),
        .I5(\tx_index_reg_n_0_[8] ),
        .O(\tx_index[11]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h3202320202323202)) 
    \tx_index[12]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index[15]_i_3_n_0 ),
        .I3(\tx_index_reg_n_0_[12] ),
        .I4(\tx_index_reg_n_0_[11] ),
        .I5(\tx_index[13]_i_3_n_0 ),
        .O(tx_index__0[12]));
  LUT6 #(
    .INIT(64'hA2A22AA2A2A2A2A2)) 
    \tx_index[13]_i_1 
       (.I0(\tx_index[13]_i_2_n_0 ),
        .I1(\tx_index[15]_i_3_n_0 ),
        .I2(\tx_index_reg_n_0_[13] ),
        .I3(\tx_index_reg_n_0_[12] ),
        .I4(\tx_index[13]_i_3_n_0 ),
        .I5(\tx_index_reg_n_0_[11] ),
        .O(tx_index__0[13]));
  LUT6 #(
    .INIT(64'h4445444444444444)) 
    \tx_index[13]_i_2 
       (.I0(\state_reg_n_0_[3] ),
        .I1(\reply_index[15]_i_2_n_0 ),
        .I2(\state_reg_n_0_[1] ),
        .I3(\state_reg_n_0_[0] ),
        .I4(\state_reg_n_0_[2] ),
        .I5(tx_ready),
        .O(\tx_index[13]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hF7FFFFFFFFFFFFFF)) 
    \tx_index[13]_i_3 
       (.I0(\tx_index_reg_n_0_[9] ),
        .I1(\tx_index_reg_n_0_[7] ),
        .I2(\tx_index[7]_i_2_n_0 ),
        .I3(\tx_index_reg_n_0_[6] ),
        .I4(\tx_index_reg_n_0_[8] ),
        .I5(\tx_index_reg_n_0_[10] ),
        .O(\tx_index[13]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'h02323202)) 
    \tx_index[14]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index[15]_i_3_n_0 ),
        .I3(\tx_index_reg_n_0_[14] ),
        .I4(\tx_index[15]_i_6_n_0 ),
        .O(tx_index__0[14]));
  LUT5 #(
    .INIT(32'hFFF2F2F2)) 
    \tx_index[15]_i_1 
       (.I0(\tx_index[15]_i_3_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\last_cycles[31]_i_1_n_0 ),
        .I3(\tx_index[15]_i_4_n_0 ),
        .I4(\tx_index[15]_i_5_n_0 ),
        .O(\tx_index[15]_i_1_n_0 ));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \tx_index[15]_i_10 
       (.I0(\tx_index[15]_i_17_n_0 ),
        .I1(\s_axi_bresp[1]_i_15_n_0 ),
        .I2(wd[9]),
        .I3(wd[4]),
        .I4(wd[5]),
        .O(\tx_index[15]_i_10_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \tx_index[15]_i_11 
       (.I0(p_0_in[6]),
        .I1(p_0_in[7]),
        .I2(\reply_len_reg_n_0_[10] ),
        .I3(\reply_len_reg_n_0_[9] ),
        .I4(\reply_len_reg_n_0_[11] ),
        .I5(\reply_len_reg_n_0_[12] ),
        .O(\tx_index[15]_i_11_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \tx_index[15]_i_12 
       (.I0(\reply_len_reg_n_0_[14] ),
        .I1(\reply_len_reg_n_0_[13] ),
        .I2(\reply_len_reg_n_0_[15] ),
        .I3(p_0_in[5]),
        .I4(p_0_in[4]),
        .I5(\reply_len_reg_n_0_[8] ),
        .O(\tx_index[15]_i_12_n_0 ));
  LUT5 #(
    .INIT(32'hFFEFFFFF)) 
    \tx_index[15]_i_13 
       (.I0(\reply_len_reg_n_0_[12] ),
        .I1(\reply_len_reg_n_0_[11] ),
        .I2(aw[4]),
        .I3(aw[3]),
        .I4(aw[2]),
        .O(\tx_index[15]_i_13_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFF8)) 
    \tx_index[15]_i_14 
       (.I0(p_0_in[0]),
        .I1(p_0_in[1]),
        .I2(p_0_in[3]),
        .I3(p_0_in[7]),
        .I4(p_0_in[2]),
        .I5(p_0_in[4]),
        .O(\tx_index[15]_i_14_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair133" *) 
  LUT2 #(
    .INIT(4'hE)) 
    \tx_index[15]_i_15 
       (.I0(p_0_in[5]),
        .I1(p_0_in[7]),
        .O(\tx_index[15]_i_15_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair133" *) 
  LUT2 #(
    .INIT(4'h1)) 
    \tx_index[15]_i_16 
       (.I0(p_0_in[7]),
        .I1(p_0_in[6]),
        .O(\tx_index[15]_i_16_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair26" *) 
  LUT4 #(
    .INIT(16'hFFEF)) 
    \tx_index[15]_i_17 
       (.I0(wd[3]),
        .I1(wd[2]),
        .I2(wd[0]),
        .I3(wd[1]),
        .O(\tx_index[15]_i_17_n_0 ));
  LUT6 #(
    .INIT(64'h0330303022222222)) 
    \tx_index[15]_i_2 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[15] ),
        .I3(\tx_index_reg_n_0_[14] ),
        .I4(\tx_index[15]_i_6_n_0 ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index__0[15]));
  (* SOFT_HLUTNM = "soft_lutpair60" *) 
  LUT4 #(
    .INIT(16'h1000)) 
    \tx_index[15]_i_3 
       (.I0(\state_reg_n_0_[1] ),
        .I1(\state_reg_n_0_[0] ),
        .I2(\state_reg_n_0_[2] ),
        .I3(tx_ready),
        .O(\tx_index[15]_i_3_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \tx_index[15]_i_4 
       (.I0(\tx_index[15]_i_7_n_0 ),
        .I1(\s_axi_bresp[1]_i_8_n_0 ),
        .I2(\tx_index[15]_i_8_n_0 ),
        .I3(\tx_index[15]_i_9_n_0 ),
        .I4(\s_axi_bresp[1]_i_11_n_0 ),
        .I5(\tx_index[15]_i_10_n_0 ),
        .O(\tx_index[15]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair128" *) 
  LUT2 #(
    .INIT(4'h2)) 
    \tx_index[15]_i_5 
       (.I0(\s_axi_bresp[1]_i_3_n_0 ),
        .I1(\reply_len[15]_i_5_n_0 ),
        .O(\tx_index[15]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h0080000000000000)) 
    \tx_index[15]_i_6 
       (.I0(\tx_index_reg_n_0_[13] ),
        .I1(\tx_index_reg_n_0_[12] ),
        .I2(\tx_index_reg_n_0_[10] ),
        .I3(\tx_index[11]_i_2_n_0 ),
        .I4(\tx_index_reg_n_0_[9] ),
        .I5(\tx_index_reg_n_0_[11] ),
        .O(\tx_index[15]_i_6_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair39" *) 
  LUT5 #(
    .INIT(32'h00022222)) 
    \tx_index[15]_i_7 
       (.I0(\tx_index[15]_i_11_n_0 ),
        .I1(\tx_index[15]_i_12_n_0 ),
        .I2(p_0_in[1]),
        .I3(p_0_in[2]),
        .I4(p_0_in[3]),
        .O(\tx_index[15]_i_7_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \tx_index[15]_i_8 
       (.I0(\s_axi_bresp[1]_i_14_n_0 ),
        .I1(\reply_index[15]_i_5_n_0 ),
        .I2(\tx_index[15]_i_13_n_0 ),
        .I3(\reply_len_reg_n_0_[15] ),
        .I4(\reply_len_reg_n_0_[13] ),
        .I5(\reply_len_reg_n_0_[14] ),
        .O(\tx_index[15]_i_8_n_0 ));
  LUT6 #(
    .INIT(64'hAAAAAAAA00008000)) 
    \tx_index[15]_i_9 
       (.I0(\reply_len_reg_n_0_[10] ),
        .I1(\tx_index[15]_i_14_n_0 ),
        .I2(\reply_len_reg_n_0_[8] ),
        .I3(\tx_index[15]_i_15_n_0 ),
        .I4(\tx_index[15]_i_16_n_0 ),
        .I5(\reply_len_reg_n_0_[9] ),
        .O(\tx_index[15]_i_9_n_0 ));
  LUT5 #(
    .INIT(32'h02323202)) 
    \tx_index[1]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index[15]_i_3_n_0 ),
        .I3(\tx_index_reg_n_0_[0] ),
        .I4(\tx_index_reg_n_0_[1] ),
        .O(tx_index__0[1]));
  LUT6 #(
    .INIT(64'h0330303022222222)) 
    \tx_index[2]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[2] ),
        .I3(\tx_index_reg_n_0_[1] ),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index__0[2]));
  LUT6 #(
    .INIT(64'h2AA2A2A2A2A2A2A2)) 
    \tx_index[3]_i_1 
       (.I0(\tx_index[13]_i_2_n_0 ),
        .I1(\tx_index[15]_i_3_n_0 ),
        .I2(\tx_index_reg_n_0_[3] ),
        .I3(\tx_index_reg_n_0_[2] ),
        .I4(\tx_index_reg_n_0_[0] ),
        .I5(\tx_index_reg_n_0_[1] ),
        .O(tx_index__0[3]));
  LUT5 #(
    .INIT(32'h03302222)) 
    \tx_index[4]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[4] ),
        .I3(\tx_index[4]_i_2_n_0 ),
        .I4(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[4]));
  (* SOFT_HLUTNM = "soft_lutpair3" *) 
  LUT4 #(
    .INIT(16'h8000)) 
    \tx_index[4]_i_2 
       (.I0(\tx_index_reg_n_0_[3] ),
        .I1(\tx_index_reg_n_0_[2] ),
        .I2(\tx_index_reg_n_0_[0] ),
        .I3(\tx_index_reg_n_0_[1] ),
        .O(\tx_index[4]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0330303022222222)) 
    \tx_index[5]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[5] ),
        .I3(\tx_index[4]_i_2_n_0 ),
        .I4(\tx_index_reg_n_0_[4] ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[5]));
  LUT6 #(
    .INIT(64'h28888888AAAAAAAA)) 
    \tx_index[6]_i_1 
       (.I0(\tx_index[13]_i_2_n_0 ),
        .I1(\tx_index_reg_n_0_[6] ),
        .I2(\tx_index_reg_n_0_[5] ),
        .I3(\tx_index_reg_n_0_[4] ),
        .I4(\tx_index[4]_i_2_n_0 ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[6]));
  LUT6 #(
    .INIT(64'h3030033022222222)) 
    \tx_index[7]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[7] ),
        .I3(\tx_index_reg_n_0_[6] ),
        .I4(\tx_index[7]_i_2_n_0 ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[7]));
  LUT6 #(
    .INIT(64'h7FFFFFFFFFFFFFFF)) 
    \tx_index[7]_i_2 
       (.I0(\tx_index_reg_n_0_[3] ),
        .I1(\tx_index_reg_n_0_[2] ),
        .I2(\tx_index_reg_n_0_[0] ),
        .I3(\tx_index_reg_n_0_[1] ),
        .I4(\tx_index_reg_n_0_[4] ),
        .I5(\tx_index_reg_n_0_[5] ),
        .O(\tx_index[7]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h88288888AAAAAAAA)) 
    \tx_index[8]_i_1 
       (.I0(\tx_index[13]_i_2_n_0 ),
        .I1(\tx_index_reg_n_0_[8] ),
        .I2(\tx_index_reg_n_0_[7] ),
        .I3(\tx_index[7]_i_2_n_0 ),
        .I4(\tx_index_reg_n_0_[6] ),
        .I5(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[8]));
  LUT5 #(
    .INIT(32'h30032222)) 
    \tx_index[9]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\state_reg_n_0_[3] ),
        .I2(\tx_index_reg_n_0_[9] ),
        .I3(\tx_index[11]_i_2_n_0 ),
        .I4(\tx_index[15]_i_3_n_0 ),
        .O(tx_index[9]));
  FDRE \tx_index_reg[0] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[0]),
        .Q(\tx_index_reg_n_0_[0] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[10] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[10]),
        .Q(\tx_index_reg_n_0_[10] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[11] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[11]),
        .Q(\tx_index_reg_n_0_[11] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[12] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[12]),
        .Q(\tx_index_reg_n_0_[12] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[13] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[13]),
        .Q(\tx_index_reg_n_0_[13] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[14] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[14]),
        .Q(\tx_index_reg_n_0_[14] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[15] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[15]),
        .Q(\tx_index_reg_n_0_[15] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[1] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[1]),
        .Q(\tx_index_reg_n_0_[1] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[2] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[2]),
        .Q(\tx_index_reg_n_0_[2] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[3] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index__0[3]),
        .Q(\tx_index_reg_n_0_[3] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[4] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[4]),
        .Q(\tx_index_reg_n_0_[4] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[5] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[5]),
        .Q(\tx_index_reg_n_0_[5] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[6] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[6]),
        .Q(\tx_index_reg_n_0_[6] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[7] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[7]),
        .Q(\tx_index_reg_n_0_[7] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[8] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[8]),
        .Q(\tx_index_reg_n_0_[8] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \tx_index_reg[9] 
       (.C(clk),
        .CE(\tx_index[15]_i_1_n_0 ),
        .D(tx_index[9]),
        .Q(\tx_index_reg_n_0_[9] ),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair17" *) 
  LUT4 #(
    .INIT(16'h0004)) 
    tx_valid_INST_0
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[2] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[1] ),
        .O(tx_valid));
  (* SOFT_HLUTNM = "soft_lutpair85" *) 
  LUT3 #(
    .INIT(8'hF4)) 
    w_full_i_1
       (.I0(s_axi_bvalid_reg_0),
        .I1(s_axi_wvalid),
        .I2(w_full_reg_n_0),
        .O(w_full_i_1_n_0));
  FDRE w_full_reg
       (.C(clk),
        .CE(1'b1),
        .D(w_full_i_1_n_0),
        .Q(w_full_reg_n_0),
        .R(aw_full_i_1_n_0));
  (* SOFT_HLUTNM = "soft_lutpair101" *) 
  LUT3 #(
    .INIT(8'hAB)) 
    \watchdog[0]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog[0]),
        .O(\watchdog[0]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair96" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[10]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[10]),
        .O(\watchdog[10]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair96" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[11]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[11]),
        .O(\watchdog[11]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair95" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[12]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[12]),
        .O(\watchdog[12]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair95" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[13]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[13]),
        .O(\watchdog[13]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair94" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[14]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[14]),
        .O(\watchdog[14]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair94" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[15]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[15]),
        .O(\watchdog[15]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair93" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[16]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[16]),
        .O(\watchdog[16]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair93" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[17]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[17]),
        .O(\watchdog[17]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair92" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[18]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[18]),
        .O(\watchdog[18]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair92" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[19]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[19]),
        .O(\watchdog[19]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair101" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[1]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[1]),
        .O(\watchdog[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair91" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[20]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[20]),
        .O(\watchdog[20]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair91" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[21]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[21]),
        .O(\watchdog[21]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair90" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[22]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[22]),
        .O(\watchdog[22]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair90" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[23]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[23]),
        .O(\watchdog[23]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair89" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[24]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[24]),
        .O(\watchdog[24]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair89" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[25]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[25]),
        .O(\watchdog[25]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair88" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[26]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[26]),
        .O(\watchdog[26]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair88" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[27]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[27]),
        .O(\watchdog[27]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair87" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[28]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[28]),
        .O(\watchdog[28]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair87" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[29]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[29]),
        .O(\watchdog[29]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair100" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[2]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[2]),
        .O(\watchdog[2]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair86" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[30]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[30]),
        .O(\watchdog[30]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h888888FF88FF88F8)) 
    \watchdog[31]_i_1 
       (.I0(\tx_index[15]_i_5_n_0 ),
        .I1(\cmd_index[15]_i_3_n_0 ),
        .I2(state1),
        .I3(\reply_index[15]_i_4_n_0 ),
        .I4(\state_reg_n_0_[0] ),
        .I5(\state_reg_n_0_[1] ),
        .O(\watchdog[31]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair86" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[31]_i_2 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[31]),
        .O(\watchdog[31]_i_2_n_0 ));
  LUT5 #(
    .INIT(32'hFF9FFFFF)) 
    \watchdog[31]_i_3 
       (.I0(\state_reg_n_0_[0] ),
        .I1(\state_reg_n_0_[1] ),
        .I2(\state_reg_n_0_[3] ),
        .I3(\state_reg_n_0_[2] ),
        .I4(reply_mem_reg_0_i_50_n_0),
        .O(\watchdog[31]_i_3_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair100" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[3]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[3]),
        .O(\watchdog[3]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair99" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[4]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[4]),
        .O(\watchdog[4]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair99" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[5]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[5]),
        .O(\watchdog[5]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair98" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[6]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[6]),
        .O(\watchdog[6]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair98" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[7]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[7]),
        .O(\watchdog[7]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair97" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[8]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[8]),
        .O(\watchdog[8]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair97" *) 
  LUT3 #(
    .INIT(8'hBA)) 
    \watchdog[9]_i_1 
       (.I0(\reply_index[15]_i_2_n_0 ),
        .I1(\watchdog[31]_i_3_n_0 ),
        .I2(watchdog0[9]),
        .O(\watchdog[9]_i_1_n_0 ));
  FDRE \watchdog_reg[0] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[0]_i_1_n_0 ),
        .Q(watchdog[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[10] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[10]_i_1_n_0 ),
        .Q(watchdog[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[11] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[11]_i_1_n_0 ),
        .Q(watchdog[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[12] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[12]_i_1_n_0 ),
        .Q(watchdog[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[13] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[13]_i_1_n_0 ),
        .Q(watchdog[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[14] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[14]_i_1_n_0 ),
        .Q(watchdog[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[15] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[15]_i_1_n_0 ),
        .Q(watchdog[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[16] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[16]_i_1_n_0 ),
        .Q(watchdog[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \watchdog_reg[16]_i_2 
       (.CI(\watchdog_reg[8]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\watchdog_reg[16]_i_2_n_0 ,\watchdog_reg[16]_i_2_n_1 ,\watchdog_reg[16]_i_2_n_2 ,\watchdog_reg[16]_i_2_n_3 ,\watchdog_reg[16]_i_2_n_4 ,\watchdog_reg[16]_i_2_n_5 ,\watchdog_reg[16]_i_2_n_6 ,\watchdog_reg[16]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(watchdog0[16:9]),
        .S(watchdog[16:9]));
  FDRE \watchdog_reg[17] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[17]_i_1_n_0 ),
        .Q(watchdog[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[18] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[18]_i_1_n_0 ),
        .Q(watchdog[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[19] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[19]_i_1_n_0 ),
        .Q(watchdog[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[1] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[1]_i_1_n_0 ),
        .Q(watchdog[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[20] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[20]_i_1_n_0 ),
        .Q(watchdog[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[21] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[21]_i_1_n_0 ),
        .Q(watchdog[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[22] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[22]_i_1_n_0 ),
        .Q(watchdog[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[23] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[23]_i_1_n_0 ),
        .Q(watchdog[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[24] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[24]_i_1_n_0 ),
        .Q(watchdog[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \watchdog_reg[24]_i_2 
       (.CI(\watchdog_reg[16]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\watchdog_reg[24]_i_2_n_0 ,\watchdog_reg[24]_i_2_n_1 ,\watchdog_reg[24]_i_2_n_2 ,\watchdog_reg[24]_i_2_n_3 ,\watchdog_reg[24]_i_2_n_4 ,\watchdog_reg[24]_i_2_n_5 ,\watchdog_reg[24]_i_2_n_6 ,\watchdog_reg[24]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(watchdog0[24:17]),
        .S(watchdog[24:17]));
  FDRE \watchdog_reg[25] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[25]_i_1_n_0 ),
        .Q(watchdog[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[26] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[26]_i_1_n_0 ),
        .Q(watchdog[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[27] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[27]_i_1_n_0 ),
        .Q(watchdog[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[28] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[28]_i_1_n_0 ),
        .Q(watchdog[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[29] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[29]_i_1_n_0 ),
        .Q(watchdog[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[2] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[2]_i_1_n_0 ),
        .Q(watchdog[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[30] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[30]_i_1_n_0 ),
        .Q(watchdog[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[31] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[31]_i_2_n_0 ),
        .Q(watchdog[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \watchdog_reg[31]_i_4 
       (.CI(\watchdog_reg[24]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_watchdog_reg[31]_i_4_CO_UNCONNECTED [7:6],\watchdog_reg[31]_i_4_n_2 ,\watchdog_reg[31]_i_4_n_3 ,\watchdog_reg[31]_i_4_n_4 ,\watchdog_reg[31]_i_4_n_5 ,\watchdog_reg[31]_i_4_n_6 ,\watchdog_reg[31]_i_4_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\NLW_watchdog_reg[31]_i_4_O_UNCONNECTED [7],watchdog0[31:25]}),
        .S({1'b0,watchdog[31:25]}));
  FDRE \watchdog_reg[3] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[3]_i_1_n_0 ),
        .Q(watchdog[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[4] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[4]_i_1_n_0 ),
        .Q(watchdog[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[5] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[5]_i_1_n_0 ),
        .Q(watchdog[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[6] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[6]_i_1_n_0 ),
        .Q(watchdog[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[7] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[7]_i_1_n_0 ),
        .Q(watchdog[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \watchdog_reg[8] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[8]_i_1_n_0 ),
        .Q(watchdog[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 \watchdog_reg[8]_i_2 
       (.CI(watchdog[0]),
        .CI_TOP(1'b0),
        .CO({\watchdog_reg[8]_i_2_n_0 ,\watchdog_reg[8]_i_2_n_1 ,\watchdog_reg[8]_i_2_n_2 ,\watchdog_reg[8]_i_2_n_3 ,\watchdog_reg[8]_i_2_n_4 ,\watchdog_reg[8]_i_2_n_5 ,\watchdog_reg[8]_i_2_n_6 ,\watchdog_reg[8]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(watchdog0[8:1]),
        .S(watchdog[8:1]));
  FDRE \watchdog_reg[9] 
       (.C(clk),
        .CE(\watchdog[31]_i_1_n_0 ),
        .D(\watchdog[9]_i_1_n_0 ),
        .Q(watchdog[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  LUT3 #(
    .INIT(8'h02)) 
    \wd[31]_i_1 
       (.I0(s_axi_wvalid),
        .I1(s_axi_bvalid_reg_0),
        .I2(w_full_reg_n_0),
        .O(w_full0));
  FDRE \wd_reg[0] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[0]),
        .Q(wd[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[10] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[10]),
        .Q(wd[10]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[11] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[11]),
        .Q(wd[11]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[12] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[12]),
        .Q(wd[12]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[13] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[13]),
        .Q(wd[13]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[14] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[14]),
        .Q(wd[14]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[15] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[15]),
        .Q(wd[15]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[16] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[16]),
        .Q(wd[16]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[17] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[17]),
        .Q(wd[17]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[18] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[18]),
        .Q(wd[18]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[19] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[19]),
        .Q(wd[19]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[1] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[1]),
        .Q(wd[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[20] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[20]),
        .Q(wd[20]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[21] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[21]),
        .Q(wd[21]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[22] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[22]),
        .Q(wd[22]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[23] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[23]),
        .Q(wd[23]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[24] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[24]),
        .Q(wd[24]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[25] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[25]),
        .Q(wd[25]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[26] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[26]),
        .Q(wd[26]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[27] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[27]),
        .Q(wd[27]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[28] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[28]),
        .Q(wd[28]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[29] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[29]),
        .Q(wd[29]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[2] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[2]),
        .Q(wd[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[30] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[30]),
        .Q(wd[30]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[31] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[31]),
        .Q(wd[31]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[3] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[3]),
        .Q(wd[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[4] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[4]),
        .Q(wd[4]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[5] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[5]),
        .Q(wd[5]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[6] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[6]),
        .Q(wd[6]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[7] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[7]),
        .Q(wd[7]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[8] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[8]),
        .Q(wd[8]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \wd_reg[9] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wdata[9]),
        .Q(wd[9]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \ws_reg[0] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wstrb[0]),
        .Q(ws[0]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \ws_reg[1] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wstrb[1]),
        .Q(ws[1]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \ws_reg[2] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wstrb[2]),
        .Q(ws[2]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
  FDRE \ws_reg[3] 
       (.C(clk),
        .CE(w_full0),
        .D(s_axi_wstrb[3]),
        .Q(ws[3]),
        .R(\s_axi_bresp[1]_i_1_n_0 ));
endmodule
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
