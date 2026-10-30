# 板卡与链路查证 (BOARD FINDINGS)

## 1. 器件与板卡候选确认
- **器件型号**: 确认原工程及位流配置均为 **XCZU15EG-2FFVB1156I**。
- **板名候选**: ALINX AXU15EG (ACU15EG 核心板) 与原工程 `board_pins.xdc` 中约束的差分时钟引脚 `AL8/AL7` (`clk200_p`/`clk200_n`)、RGMII 以太网 PHY 引脚 (`V3/V4/AC9/AB9/AA7/AA6/U4/U5/Y9/Y10/M10/L10/R9`) 完全一致。
- **归因边界**: 虽引脚高度吻合，但工程内未出现板卡名称文本或原理图锚点，因此严格遵从证据原则：**仅作为最高优先级候选板卡，不得在无板卡硬件实测证据前直接断定**。

## 2. 真实 DDR4 物理参数与带宽核定
- **参数来源**: 原 ZIP 包内 `model_a_v0_22/soc_full/build/full002/ps_properties.txt`。
- **存储配置**: DDR4、64-bit 物理总线位宽、4 颗 16-bit 8Gb DRAM 颗粒，物理总容量 4 GBytes (高低地址各 2GB，`DDR_LOW: 0x0..0x7FFFFFFF`, `DDR_HIGH: 0x800000000..0x87FFFFFFF`)。
- **时钟频率**: `CONFIG.PSU__ACT_DDR_FREQ_MHZ = 799.992004` (~800 MHz，对应 DDR4-1600 MT/s 双沿速率)。
- **Speed Bin**: 标称 `DDR4_2400P`（颗粒级别，当前实际以 800MHz 运行）。
- **物理理论带宽**: 64-bit / 8 × 1600 MT/s = **12.8 GB/s**。

## 3. PL 通路瓶颈与 6 Master 汇聚拓扑
- **拓扑结构**: PL 侧 6 个 AXI 主机 (`accelerator/m_axi`, `plans/read_axi`, `plans/write_axi`, `plans/fetch_axi`, `plans/layout_read_axi`, `plans/layout_write_axi`) 汇聚接入一个 SmartConnect (`ddr_connect`, NUM_SI=6, NUM_MI=1)，单一输出连接 PS 的 `S_AXI_HP0_FPD` 端口。
- **接口时钟与带宽**: HP0 配置为 128-bit，时钟为 125 MHz，**接口理论峰值仅为 2.0 GB/s**。
- **关键结论**: 6 个 Master 共享单一 2.0 GB/s 端口，并非 6 × 2 GB/s = 12 GB/s！外部 DDR4 的 12.8 GB/s 物理带宽被 PL 侧 2.0 GB/s 接口严重卡死。
- **PL 独立 DDR4 连接证据**: 若硬件确认具备 AXU15EG 的 PL 端 2GB DDR4，其为 32-bit 物理总线，但原工程 `board_pins.xdc` 中未约束任何 PL DDR4 引脚，亦未例化 MIG IP。在无板卡不操作引脚的约束下，目前仅做逻辑层架构建议与模拟。
