`timescale 1ns/1ps
// 参数化 AXI128 共享 DDR 逻辑模型（不是板级 DDR 时序模型）
// - PORTS 个 AXI4 从端口共享一份存储和一条数据通道
// - 可配置读/写延迟、每拍随机 gap、命令背压、每端口有限 outstanding
// - DUPLEX=0: 读/写数据共享一条 128bit/cycle 通道；DUPLEX=1: 读写各一条
// - 严格检查 16B 对齐、INCR、<=16 beat、不跨 4KiB、地址范围
// - 计数器区分 read/write beats、命令突发、busy/idle、队列满停顿
// v5 adds cfg_b_extra so a test can hold BVALID for a long, explicit AXI write
// response delay independently of read latency.  With cfg_b_extra=0 the
// behaviour is byte-for-byte the v4 model.
module axi128_ddr_bfm #(
 parameter integer PORTS=2,
 parameter integer BASE=40'h04000000,
 parameter integer MEM_BYTES=262144,
 parameter integer MAX_RD_OUT=8,
 parameter integer MAX_WR_OUT=8,
 parameter integer DUPLEX=0,
 parameter integer QDEPTH=16
)(
 input wire [31:0] cfg_lat_min,cfg_lat_max,cfg_bp_pct,cfg_seed,
 input wire [31:0] cfg_long_mode,cfg_long_period,cfg_long_len,
 input wire [31:0] cfg_b_extra,
 input wire clk,rst_n,
 input wire [PORTS*40-1:0] araddr,input wire [PORTS*8-1:0] arlen,
 input wire [PORTS*3-1:0] arsize,input wire [PORTS*2-1:0] arburst,
 input wire [PORTS-1:0] arvalid,output wire [PORTS-1:0] arready,
 output wire [PORTS*128-1:0] rdata,output wire [PORTS*2-1:0] rresp,
 output wire [PORTS-1:0] rlast,rvalid,input wire [PORTS-1:0] rready,
 input wire [PORTS*40-1:0] awaddr,input wire [PORTS*8-1:0] awlen,
 input wire [PORTS*3-1:0] awsize,input wire [PORTS*2-1:0] awburst,
 input wire [PORTS-1:0] awvalid,output wire [PORTS-1:0] awready,
 input wire [PORTS*128-1:0] wdata,input wire [PORTS*16-1:0] wstrb,
 input wire [PORTS-1:0] wlast,wvalid,output wire [PORTS-1:0] wready,
 output wire [PORTS*2-1:0] bresp,output wire [PORTS-1:0] bvalid,input wire [PORTS-1:0] bready,
 input wire inject_read_error,inject_write_error,
 output reg [63:0] total_cycles,busy_cycles,read_busy_cycles,write_busy_cycles,
 output reg [63:0] read_beats,write_beats,read_bursts,write_bursts,
 output reg [63:0] read_wait_cycles,write_wait_cycles,
 output reg [63:0] ar_full_stalls,aw_full_stalls,cmd_stalls,
 output reg [31:0] max_rd_outstanding,max_wr_outstanding
);
 wire [31:0] lat_min=cfg_lat_min,lat_max=cfg_lat_max,bp_pct=cfg_bp_pct,seed=cfg_seed,
             long_mode=cfg_long_mode,long_period=cfg_long_period,long_len=cfg_long_len,
             b_extra=cfg_b_extra;

 localparam integer MEMW=MEM_BYTES/16; // 16B words
 reg [127:0] mem[0:MEMW-1];

 // 每端口 AR/AW 环形队列；R/W 数据每个端口至多一个突发在流。
 reg [39:0] ar_addr[0:PORTS*QDEPTH-1];
 reg [7:0]  ar_beats[0:PORTS*QDEPTH-1];
 reg [15:0] ar_lat[0:PORTS*QDEPTH-1];
 reg [15:0] ar_cnt[0:PORTS-1];
 reg [4:0]  ar_head[0:PORTS-1],ar_tail[0:PORTS-1];
 reg        rd_active[0:PORTS-1];
 reg [7:0]  rd_idx[0:PORTS-1];
 reg [15:0] rd_gap[0:PORTS-1];
 reg [127:0] rd_data_q[0:PORTS-1];

 reg [39:0] aw_addr[0:PORTS*QDEPTH-1];
 reg [7:0]  aw_beats[0:PORTS*QDEPTH-1];
 reg [15:0] aw_cnt[0:PORTS-1];
 reg [4:0]  aw_head[0:PORTS-1],aw_tail[0:PORTS-1];
 reg        wr_active[0:PORTS-1];
 reg [7:0]  wr_idx[0:PORTS-1];
 reg [15:0] wr_gap[0:PORTS-1];

 reg [39:0] b_addr[0:PORTS*QDEPTH-1];
 reg [7:0]  b_beats[0:PORTS*QDEPTH-1];
 reg [15:0] b_lat[0:PORTS*QDEPTH-1];
 reg [15:0] b_cnt[0:PORTS-1];
 reg [4:0]  b_head[0:PORTS-1],b_tail[0:PORTS-1];

 reg [31:0] lfsr;
 reg [31:0] long_cnt;
 reg rr_dir; // 共享通道仲裁方向
 reg [31:0] rr_port;
 reg r_lock,w_lock;
 reg [31:0] r_lock_port,w_lock_port;

 // 每端口当前读/写数据请求（组合）
 reg [PORTS-1:0] r_req,w_req,r_gnt,w_gnt;
 wire [PORTS-1:0] ar_push,ar_pop,aw_push,aw_pop,b_push,b_pop;
 reg [31:0] r_sel,w_sel;
 always @* begin
  r_req=0;w_req=0;r_gnt=0;w_gnt=0;r_sel=0;w_sel=0;
  for(integer p=0;p<PORTS;p=p+1)begin
   if(rd_active[p]&&ar_cnt[p]!=0&&ar_lat[p*QDEPTH+ar_head[p]]==0&&rd_gap[p]==0)r_req[p]=1;
   if(wr_active[p]&&aw_cnt[p]!=0&&wr_gap[p]==0)w_req[p]=1;
  end
  if(DUPLEX!=0)begin
   for(integer k=0;k<PORTS;k=k+1)begin
    integer p; p=(rr_port+k)%PORTS;
    if(r_gnt==0&&r_req[p])begin r_gnt[p]=1;r_sel=p;end
    if(w_gnt==0&&w_req[p])begin w_gnt[p]=1;w_sel=p;end
   end
  end else if(rr_dir==0)begin
   for(integer k=0;k<PORTS;k=k+1)begin
    integer p; p=(rr_port+k)%PORTS;
    if(r_gnt==0&&r_req[p])begin r_gnt[p]=1;r_sel=p;end
   end
   if(r_gnt==0)for(integer k=0;k<PORTS;k=k+1)begin
    integer p; p=(rr_port+k)%PORTS;
    if(w_gnt==0&&w_req[p])begin w_gnt[p]=1;w_sel=p;end
   end
  end else begin
   for(integer k=0;k<PORTS;k=k+1)begin
    integer p; p=(rr_port+k)%PORTS;
    if(w_gnt==0&&w_req[p])begin w_gnt[p]=1;w_sel=p;end
   end
   if(w_gnt==0)for(integer k=0;k<PORTS;k=k+1)begin
    integer p; p=(rr_port+k)%PORTS;
    if(r_gnt==0&&r_req[p])begin r_gnt[p]=1;r_sel=p;end
   end
  end
  // 锁定端口优先，避免 RREADY 低时撤销 RVALID
  if(r_lock)begin r_gnt=0;if(r_req[r_lock_port])begin r_gnt[r_lock_port]=1;r_sel=r_lock_port;end end
  if(w_lock)begin w_gnt=0;if(w_req[w_lock_port])begin w_gnt[w_lock_port]=1;w_sel=w_lock_port;end end
 end

 generate for(genvar p=0;p<PORTS;p=p+1)begin:g
  assign ar_push[p]=arvalid[p]&&arready[p];
  assign ar_pop[p]=rvalid[p]&&rready[p]&&rlast[p];
  assign aw_push[p]=awvalid[p]&&awready[p];
  assign aw_pop[p]=wvalid[p]&&wready[p]&&wlast[p];
  assign b_push[p]=aw_pop[p];
  assign b_pop[p]=bvalid[p]&&bready[p];
  wire [39:0] ra=ar_addr[p*QDEPTH+ar_head[p]];
  wire [39:0] wa=aw_addr[p*QDEPTH+aw_head[p]];
  wire [31:0] roff=(ra-BASE)>>4;
  assign arready[p]=rst_n&&(ar_cnt[p]<MAX_RD_OUT)&&(lfsr[7:5]!=3);
  assign awready[p]=rst_n&&(aw_cnt[p]<MAX_WR_OUT)&&(b_cnt[p]<QDEPTH)&&(lfsr[7:5]!=3);
  assign rvalid[p]=rst_n&&rd_active[p]&&ar_cnt[p]!=0&&ar_lat[p*QDEPTH+ar_head[p]]==0&&rd_gap[p]==0&&r_gnt[p];
  assign rdata[p*128+:128]=rd_data_q[p];
  assign rlast[p]=rd_active[p]&&(rd_idx[p]+1==ar_beats[p*QDEPTH+ar_head[p]]);
  assign rresp[p*2+:2]=(inject_read_error&&rvalid[p])?2'b10:2'b00;
  assign wready[p]=rst_n&&wr_active[p]&&aw_cnt[p]!=0&&wr_gap[p]==0&&w_gnt[p];
  assign bvalid[p]=rst_n&&b_cnt[p]!=0&&b_lat[p*QDEPTH+b_head[p]]==0;
  assign bresp[p*2+:2]=(inject_write_error&&bvalid[p])?2'b10:2'b00;
 end endgenerate
 wire r_hs=|(rvalid&rready);
 wire w_hs=|(wvalid&wready);
 // periodic long stalls: assert command backpressure during the window and
 // insert a long data gap after the next completed beat of that direction.
 wire long_stall_r = ((long_mode & 1) != 0) && (long_cnt >= (long_period-long_len));
 wire long_stall_w = ((long_mode & 2) != 0) && (long_cnt >= (long_period-long_len));

 // 读数据：组合取存储，握手时锁存到输出寄存器（同步宏读的保守近似）
 always @(posedge clk)begin
  if(!rst_n)begin
   total_cycles<=0;busy_cycles<=0;read_busy_cycles<=0;write_busy_cycles<=0;
   read_beats<=0;write_beats<=0;read_bursts<=0;write_bursts<=0;
   read_wait_cycles<=0;write_wait_cycles<=0;ar_full_stalls<=0;aw_full_stalls<=0;cmd_stalls<=0;
   max_rd_outstanding<=0;max_wr_outstanding<=0;lfsr<=seed[31:0];rr_dir<=0;rr_port<=0;long_cnt<=0;
   r_lock<=0;w_lock<=0;r_lock_port<=0;w_lock_port<=0;
   for(integer p=0;p<PORTS;p=p+1)begin
    ar_cnt[p]<=0;ar_head[p]<=0;ar_tail[p]<=0;rd_active[p]<=0;rd_idx[p]<=0;rd_gap[p]<=0;rd_data_q[p]<=0;
    aw_cnt[p]<=0;aw_head[p]<=0;aw_tail[p]<=0;wr_active[p]<=0;wr_idx[p]<=0;wr_gap[p]<=0;
    b_cnt[p]<=0;b_head[p]<=0;b_tail[p]<=0;
   end
  end else begin
   total_cycles<=total_cycles+1;
   lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
   if (long_mode != 0) long_cnt <= (long_cnt >= (long_period-1)) ? 0 : (long_cnt + 1);
   if(|r_gnt||r_hs)read_busy_cycles<=read_busy_cycles+1;
   if(|w_gnt||w_hs)write_busy_cycles<=write_busy_cycles+1;
   if(|r_gnt|||w_gnt)busy_cycles<=busy_cycles+1;
   if(r_hs)rr_dir<=1;
   if(w_hs)rr_dir<=0;
   if(r_hs)rr_port<=(r_sel+1)%PORTS;
   if(w_hs)rr_port<=(w_sel+1)%PORTS;
   if(|r_gnt&&!rready[r_sel])begin r_lock<=1;r_lock_port<=r_sel;end
   else if(r_hs||(r_lock&&!r_req[r_lock_port]))r_lock<=0;
   if(|w_gnt&&!wready[w_sel])begin w_lock<=1;w_lock_port<=w_sel;end
   else if(w_hs||(w_lock&&!w_req[w_lock_port]))w_lock<=0;

   for(integer p=0;p<PORTS;p=p+1)begin
    // ---- AR 接收 ----
    if(arvalid[p]&&arready[p])begin
     if(!valid_addr(araddr[p*40+:40],arlen[p*8+:8]+1)||arsize[p*3+:3]!=4||arburst[p*2+:2]!=1||arlen[p*8+:8]>15||
        ((araddr[p*40+:12])+((arlen[p*8+:8]+1)*16))>4096)
      $fatal(1,"AXI AR framing/range violation");
     ar_addr[p*QDEPTH+ar_tail[p]]<=araddr[p*40+:40];
     ar_beats[p*QDEPTH+ar_tail[p]]<=arlen[p*8+:8]+1;
     ar_lat[p*QDEPTH+ar_tail[p]]<=lat_min+((lat_max>lat_min)?(lfsr%(lat_max-lat_min+1)):0);
     ar_tail[p]<= (ar_tail[p]+1)%QDEPTH; read_bursts<=read_bursts+1;
    end else if(arvalid[p]&&!arready[p])ar_full_stalls<=ar_full_stalls+1;
    // ---- 读延迟倒计时 ----
    for(integer k=0;k<QDEPTH;k=k+1)begin
     if(ar_cnt[p]!=0&&ar_lat[p*QDEPTH+((ar_head[p]+k)%QDEPTH)]!=0)
      ar_lat[p*QDEPTH+((ar_head[p]+k)%QDEPTH)]<=ar_lat[p*QDEPTH+((ar_head[p]+k)%QDEPTH)]-1;
    end
    if(!rd_active[p]&&ar_cnt[p]!=0&&ar_lat[p*QDEPTH+ar_head[p]]==0)begin
     rd_active[p]<=1;rd_idx[p]<=0;rd_data_q[p]<=mem[((ar_addr[p*QDEPTH+ar_head[p]]-BASE)>>4)];
    end
    if(rd_active[p]&&!r_gnt[p])read_wait_cycles<=read_wait_cycles+1;
    // ---- R 握手 ----
    if(rvalid[p]&&rready[p])begin
     read_beats<=read_beats+1;
     if(rlast[p])begin
      ar_head[p]<=(ar_head[p]+1)%QDEPTH;rd_active[p]<=0;
     end else begin
      rd_idx[p]<=rd_idx[p]+1;
      rd_data_q[p]<=mem[((ar_addr[p*QDEPTH+ar_head[p]]-BASE)>>4)+rd_idx[p]+1];
     end
     if(long_stall_r) rd_gap[p]<=long_len;
     else if(bp_pct>0)rd_gap[p]<=(lfsr%100<bp_pct)?(1+(lfsr%7)):0;
    end
    if(rd_gap[p]!=0)rd_gap[p]<=rd_gap[p]-1;

    // ---- AW 接收 ----
    if(awvalid[p]&&awready[p])begin
     if(!valid_addr(awaddr[p*40+:40],awlen[p*8+:8]+1)||awsize[p*3+:3]!=4||awburst[p*2+:2]!=1||awlen[p*8+:8]>15||
        ((awaddr[p*40+:12])+((awlen[p*8+:8]+1)*16))>4096)
      $fatal(1,"AXI AW framing/range violation");
     aw_addr[p*QDEPTH+aw_tail[p]]<=awaddr[p*40+:40];
     aw_beats[p*QDEPTH+aw_tail[p]]<=awlen[p*8+:8]+1;
     aw_tail[p]<=(aw_tail[p]+1)%QDEPTH;write_bursts<=write_bursts+1;
    end else if(awvalid[p]&&!awready[p])aw_full_stalls<=aw_full_stalls+1;
    if(!wr_active[p]&&aw_cnt[p]!=0)begin wr_active[p]<=1;wr_idx[p]<=0;end
    if(wr_active[p]&&!w_gnt[p])write_wait_cycles<=write_wait_cycles+1;
    // ---- W 握手 ----
    if(wvalid[p]&&wready[p])begin
     if(wlast[p]!=(wr_idx[p]+1==aw_beats[p*QDEPTH+aw_head[p]]))$fatal(1,"AXI WLAST mismatch");
     for(integer lane=0;lane<16;lane=lane+1)
      if(wstrb[p*16+lane])mem[((aw_addr[p*QDEPTH+aw_head[p]]-BASE)>>4)+wr_idx[p]][lane*8+:8]<=wdata[p*128+lane*8+:8];
     write_beats<=write_beats+1;
     if(wlast[p])begin
      b_addr[p*QDEPTH+b_tail[p]]<=aw_addr[p*QDEPTH+aw_head[p]];
      b_beats[p*QDEPTH+b_tail[p]]<=aw_beats[p*QDEPTH+aw_head[p]];
      b_lat[p*QDEPTH+b_tail[p]]<=lat_min+((lat_max>lat_min)?(lfsr%(lat_max-lat_min+1)):0)+b_extra;
      b_tail[p]<=(b_tail[p]+1)%QDEPTH;
      aw_head[p]<=(aw_head[p]+1)%QDEPTH;wr_active[p]<=0;
      if(long_stall_w) wr_gap[p]<=long_len;
      else if(bp_pct>0)wr_gap[p]<=(lfsr%100<bp_pct)?(1+(lfsr%7)):0;
     end else wr_idx[p]<=wr_idx[p]+1;
    end
    if(wr_gap[p]!=0)wr_gap[p]<=wr_gap[p]-1;
    // ---- B 响应 ----
    for(integer k=0;k<QDEPTH;k=k+1)begin
     if(b_cnt[p]!=0&&b_lat[p*QDEPTH+((b_head[p]+k)%QDEPTH)]!=0)
      b_lat[p*QDEPTH+((b_head[p]+k)%QDEPTH)]<=b_lat[p*QDEPTH+((b_head[p]+k)%QDEPTH)]-1;
    end
    if(bvalid[p]&&bready[p])begin
     b_head[p]<=(b_head[p]+1)%QDEPTH;
    end
    ar_cnt[p]<=ar_cnt[p]+(ar_push[p]?1:0)-(ar_pop[p]?1:0);
    aw_cnt[p]<=aw_cnt[p]+(aw_push[p]?1:0)-(aw_pop[p]?1:0);
    b_cnt[p]<=b_cnt[p]+(b_push[p]?1:0)-(b_pop[p]?1:0);
    if(ar_cnt[p]+(ar_push[p]?1:0)-(ar_pop[p]?1:0)>max_rd_outstanding)max_rd_outstanding<=ar_cnt[p]+(ar_push[p]?1:0)-(ar_pop[p]?1:0);
    if((aw_cnt[p]+(aw_push[p]?1:0)-(aw_pop[p]?1:0)+b_cnt[p]+(b_push[p]?1:0)-(b_pop[p]?1:0))>max_wr_outstanding)max_wr_outstanding<=aw_cnt[p]+(aw_push[p]?1:0)-(aw_pop[p]?1:0)+b_cnt[p]+(b_push[p]?1:0)-(b_pop[p]?1:0);
   end
  end
 end

 function automatic valid_addr(input [39:0] a,input [7:0] beats);
  reg [63:0] enda;
  begin
   enda={24'd0,a}+({56'd0,beats}<<4);
   valid_addr=(a>=BASE)&&(a[3:0]==0)&&(enda<=BASE+MEM_BYTES);
  end
 endfunction
endmodule
