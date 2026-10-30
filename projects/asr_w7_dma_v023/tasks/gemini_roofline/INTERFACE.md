# INTERFACE CONTRACT: `matrix_prefetch_dma_engine`

## 1. 模块定位与职责

- **模块名称**: `matrix_prefetch_dma_engine`
- **源文件**: [`rtl/matrix_prefetch_dma_engine.sv`](file:///home/yang/Desktop/项目/tasks/gemini_roofline/rtl/matrix_prefetch_dma_engine.sv)
- **职责**: 解决 V0.22 矩阵计算队列中 88.57% 的非计算残差（DMA等待/串行阻塞）瓶颈。提供 A/W 双缓冲乒乓预取通道与 C 累加结果异步投递写回（Posted Writeback），支持在计算当前 Tile 的同时通过独立 AXI DMA 预取下一 Tile 的输入数据，实现计算与内存搬运完全重叠。

---

## 2. 端口定义与总线契约

```systemverilog
module matrix_prefetch_dma_engine #(
    parameter DATA_WIDTH   = 128,   // AXI 数据总线位宽 (128-bit 或 64-bit)
    parameter ADDR_WIDTH   = 32,    // 物理地址位宽
    parameter TILE_A_BYTES = 2048,  // 单个 32x32 A 块字节数 (A16)
    parameter TILE_W_BYTES = 1024,  // 单个 32x32 W 块字节数 (W7 + parity)
    parameter TILE_C_BYTES = 6144   // 单个 32x32 C 块字节数 (C48)
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // 控制与状态
    input  wire                   start,
    input  wire                   mode_overlap, // 0 = 串行基线(Before), 1 = 乒乓重叠预取(After)
    input  wire [15:0]            num_tiles,
    output reg                    busy,
    output reg                    done,

    // 内存基地址
    input  wire [ADDR_WIDTH-1:0]  a_base_addr,
    input  wire [ADDR_WIDTH-1:0]  w_base_addr,
    input  wire [ADDR_WIDTH-1:0]  c_base_addr,

    // 硬件性能监控计数器
    output reg [31:0]             cnt_total_cycles,
    output reg [31:0]             cnt_compute_cycles,
    output reg [31:0]             cnt_dma_wait_cycles,

    // AXI 读通道 (DMA Fetch)
    output reg                    m_axi_arvalid,
    input  wire                   m_axi_arready,
    output reg [ADDR_WIDTH-1:0]   m_axi_araddr,
    output reg [7:0]              m_axi_arlen,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready,
    input  wire [DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire                   m_axi_rlast,

    // AXI 写通道 (Posted C Writeback)
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

    // PE 阵列计算核握手
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
```

---

## 3. 握手与流水契约

1. **双缓冲乒乓机制**:
   - `core_page` 指示当前 PE 核心应读取的物理 Bank 页号（0 或 1）。
   - DMA 控制器在 `core_page` 被 PE 占用计算期间，自主使用 `~core_page` 从 DDR 预取下一 Tile 的 A 和 W 操作数。
   - PE 阵列完成当前 Tile 后拉高 `core_done` 单拍；若下一 Tile 预取已完成，引擎在下一拍拉高 `core_start` 并切换 `core_page`，实现计算流水零气泡（0 bubble）。

2. **异步 C 结果投递（Posted Writeback）**:
   - 当 PE 核心产生 48-bit 累加和 `core_c_data` 并写入局部写缓冲时，DMA 写引擎自主申请 AXI AW/W/B 事务。
   - 写通道与下一 Tile 计算完全解耦并行，计算无需等待 DDR 写响应。

3. **数值一致性**:
   - 保持严格 W7(S/J/M)/positions/clip、A16、C48 累加精度不变。
   - 数据通路无零点截断、无模型容差放宽。
