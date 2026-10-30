`timescale 1ns/1ps
// Wiring-only top: three coarse CSR writes submit a DDR task queue.
// Define V020_COLLECT4 to select the separately generated candidate core.
module queued_v020_board(
 input wire clk,rst_n,
 input wire plan_lock,plan_matrix_valid,
 input wire [31:0] plan_matrix_base,plan_matrix_count,
 output wire plan_matrix_ready,plan_matrix_done,plan_matrix_fault,
 output wire parameter_ready,output wire [31:0] parameter_generation,parameter_end,
 output wire [63:0] plan_matrix_cycles,plan_matrix_pe_cycles,
 input wire [7:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
 output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,
 input wire [7:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,
 output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,output wire s_axi_rvalid,input wire s_axi_rready,
 output wire irq,
 output wire [39:0] m_axi_araddr,output wire [7:0] m_axi_arlen,
 output wire [2:0] m_axi_arsize,output wire [1:0] m_axi_arburst,
 output wire [3:0] m_axi_arcache,output wire [2:0] m_axi_arprot,
 output wire m_axi_arvalid,input wire m_axi_arready,
 input wire [127:0] m_axi_rdata,input wire [1:0] m_axi_rresp,
 input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready,
 output wire [39:0] m_axi_awaddr,output wire [7:0] m_axi_awlen,
 output wire [2:0] m_axi_awsize,output wire [1:0] m_axi_awburst,
 output wire [3:0] m_axi_awcache,output wire [2:0] m_axi_awprot,
 output wire m_axi_awvalid,input wire m_axi_awready,
 output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
 output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
 input wire [1:0] m_axi_bresp,input wire m_axi_bvalid,output wire m_axi_bready
);
 wire legacy_start,start,busy,done,fault,completion_valid,completion_ready;
 wire [31:0] legacy_base,legacy_count;reg [31:0] epoch_bias;
 assign plan_matrix_ready=plan_lock&&!busy&&!legacy_start;
 assign start=legacy_start||(plan_matrix_valid&&plan_matrix_ready);
 assign queue_base=plan_lock?plan_matrix_base:legacy_base;
 assign queue_count=plan_lock?plan_matrix_count:legacy_count;
 assign plan_matrix_done=done;assign plan_matrix_fault=fault;
 assign parameter_end=param_end;
 always @(posedge clk)if(!rst_n)epoch_bias<=0;else if(start&&!busy)epoch_bias<=plan_lock?control.last_cookie:0;
 wire [31:0] param_end;
 wire [31:0] queue_base,queue_count,completed_tasks,current_index,rejected_starts;
 wire [7:0] error_code,completion_error;
 wire [63:0] queue_cycles,fetch_cycles,engine_wait_cycles,retire_wait_cycles,completion_cycles;
 wire [31:0] completion_index,completion_cookie,dma_read_bytes,dma_write_bytes,dma_read_bursts,dma_write_bursts;
 wire [63:0] total_compute_cycles;
 assign plan_matrix_cycles=queue_cycles;assign plan_matrix_pe_cycles=total_compute_cycles;
 wire [31:0] last_core_compute,last_core_reads,last_core_writes,last_core_hits,last_core_misses;
 queue_submit_csr_board control(.start(legacy_start),.queue_base(legacy_base),.queue_count(legacy_count),.parameter_ready_out(parameter_ready),.param_generation_out(parameter_generation),.*);
 queued_v020_monitored compute(.*);
endmodule
