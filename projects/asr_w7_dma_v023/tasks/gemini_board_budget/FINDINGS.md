# FINDINGS: 板卡审计、官方文献对齐、下界重算与 PE 带宽反推

## 1. 硬件配置与板卡证据审计

1. **器件确认**:
   - 原工程工程脚本 (`build_full.tcl`, `ps_properties.txt`) 明确器件型号为 **XCZU15EG-2FFVB1156I**（Zynq UltraScale+ MPSoC，-2 速度等级，工业级）。
2. **板卡型号归因边界**:
   - `board_pins.xdc` 中约束的差分时钟引脚 `AL8/AL7` (`clk200_p`/`clk200_n`)、RGMII 以太网 PHY 引脚 (`V3/V4/AC9/AB9/AA7/AA6/U4/U5/Y9/Y10/M10/L10/R9`) 与 ALINX AXU15EG (ACU15EG 核心板) 原理图引脚完全一致。
   - **严格证据约束**: 虽引脚与器件完全匹配 ALINX AXU15EG，但由于原代码库与报告中无直接板卡名称字符串或官方原理图标注，因此 ALINX AXU15EG **仅列为最高优先级候选板卡**，不得在未经实物证据前假定为唯一用户板。
3. **PS DDR4 物理配置**:
   - `ps_properties.txt` 明确配置：64-bit 数据位宽、4 颗 16-bit 8Gb 颗粒（总容量 4 GBytes，高低地址各 2GB）。
   - 配置频率 `ACT_DDR_FREQ_MHZ = 799.992 MHz`（~800 MHz 时钟，对应 DDR4-1600 MT/s 双沿传输）。
   - Speed Bin 标称 `DDR4_2400P`（这是颗粒等级，非当前实际运行频率）。
   - **物理理论带宽**: 64-bit / 8 × 1600 MT/s = **12.8 GB/s**。
4. **PL 侧外存通路瓶颈**:
   - PL 侧 6 个 AXI 主机 (`accelerator/m_axi`, `plans/read_axi`, `plans/write_axi`, `plans/fetch_axi`, `plans/layout_read_axi`, `plans/layout_write_axi`) 通过 SmartConnect IP (`ddr_connect`, NUM_SI=6, NUM_MI=1) **单一汇聚**至 PS 的 `S_AXI_HP0_FPD` 端口。
   - HP0 端口配置为 128-bit，挂载于 125 MHz 时钟（`CONFIG.PSU__S_AXI_GP2__FREQMHZ=125.0`）。
   - **HP0 接口理论峰值仅为 2.0 GB/s** (128-bit / 8 × 125 MHz)。6 个 master 共同争抢此 2.0 GB/s 管道，绝非 6 × 2 GB/s = 12 GB/s！

---

## 2. AMD 官方权威文献对齐

1. **UG1085 & HP Traffic Shaping (突发长度与在途深度)**:
   - UltraScale+ MPSoC 的 AXI FIFO Interface (AFI) 内部架构以 AXI3 为基础，突发长度本质受限于 16 beats。AXI4 的 >16 beats 事务会在互连中被拆分。
   - 官方 HP 调优最佳实践明确推荐 **128-bit 16-beat 突发**。因此，16-beat 本身绝非设计缺陷！
   - 真正的延迟暴露瓶颈在于 **单在途事务 (Single Outstanding, Depth=1)**：每一突发都要承受 50-100 拍往返延迟，总线利用率跌落至 20%-35%。引入多在途流水 (Depth 4-8) 方能彻底隐藏往返延迟，将总线效率推至 90% 以上。
2. **DS925 (PS-PL AXI 频率上限)**:
   - 数据手册表 49 规定：-2 速度等级下，`S_AXI_HP{0-3}_FPD` 接口最大标称频率为 **333 MHz**。
   - 600 MHz 仅可作为 PL 内部局部计算域（DSP 阵列与短连线流水），绝对无法在 PS AXI 接口域运行。
3. **UG949 & UG579 (时钟域与算力结构)**:
   - 计算域 (300/600 MHz) 与接口域 (125/250/333 MHz) 必须跨越严格的时钟域交叉 (CDC) 边界，使用异步 FIFO（XPM_FIFO_ASYNC）隔离。
   - DSP48E2 标称最高频率 ~741 MHz，在考虑高扇出控制网络和布线延迟后，300 MHz 为稳健目标，600 MHz 需深度流水与寄存器复制（UG949 high-fanout optimization）。

---

## 3. 工作量核算与理论最快时间重算

1. **68 闭合计划算力核算**:
   - 数学有用 MAC: **3,461,011,968** (3.461e9)。
   - 硬件填充 MAC: **3,991,404,544** (3.991e9，由于 32×32 块化填充，填充比 1.153×，共 121,808 个 3D Tile)。
   - 矩阵算力下界 (256 PE):
     - 125 MHz: 有用 108.16 ms / 填充 124.73 ms
     - 150 MHz: 有用 90.13 ms / 填充 103.94 ms
     - 300 MHz: 有用 45.07 ms / 填充 51.97 ms
     - 600 MHz: 有用 22.53 ms / 25.99 ms
   - **重要断言**: 以上时间仅为矩阵纯计算下界，不含 Vector 算术、Layout 转置、QDQ 和内存交互。
2. **非矩阵算子与整模型落差**:
   - 68 计划中包含 82.95M 个 Vector 元素和 16.78M 个 Layout 元素，在 125 MHz 实测消耗 6.816s (Vector) + 3.353s (Layout) = 10.169s（占闭合计划 12.487s 的 81.4%！）。
   - 整模型板测墙钟时间为 154.824s，68 计划仅占 12.487s，存在 **142.337s 的巨大落差**。落差由未融合算子、主机 UDP 轮询、CPU MMIO 搬运和网络边界交互造成。单纯优化 68 计划无法自动消除外层 142s 耗时。
3. **数据搬运量与真实下界校正**:
   - 实测 68 计划总搬运量: **933,028,896 B** (Vector/Layout 读 452.3MB + 写 355.6MB + Matrix DMA 125.1MB)。
   - 读写分解: 读通道 577.5 MB (61.9%)，写通道 355.6 MB (38.1%)。
   - 若在串行共享单通道 (2.0 GB/s) 下需 0.467s；若在读写并发全双工下，时间受限于读通道 0.289s。
   - **张量生命周期必须下界 (Compulsory Bound)**:
     - 唯一权重: 81,007,616 B
     - 边界输入: 4,539,392 B
     - 边界输出: 16,508,928 B
     - 唯一中间量张量空间: 12,592,128 B
     - **全片内驻留下界**: 102,055,936 B (102.06 MB，比当前 933MB 小 9.14 倍！)。
     - **全外存粗下界**: 127,240,192 B (127.24 MB，比当前 933MB 小 7.33 倍！)。
     - 实测 Vector/Layout 产生 807.9 MB DDR 流量，相对 12.6 MB 真实张量产生了 64.2 倍的放大，揭示出极大的片上算子融合优化空间。

---

## 4. PE 阵列规格与外存带宽反推 (PE Bandwidth Matching)

1. **反推公式**: $P_{\text{equiv}} \le \frac{B \times I}{f_c}$。
2. **关键参数与单位口径**:
   - 外存操作数: W7p8 占 1B (DDR4 存储格式)，A16 占 2B，C48 占 6B。
   - 算术强度 $I$ 单位为 **MAC/Byte**；若按浮点计算/OP 统计，则 $1\text{ MAC} = 2\text{ OPs}$，对应 $2I\text{ OP/Byte}$。
3. **Tile 规模对等效 PE 的决定性制约**:
   - 在 2.0 GB/s (HP0 @ 125MHz) 且计算时钟为 300 MHz 下:
     - Tile [16, 16, 32] ($I = 2.67\text{ MAC/B}$): 仅能支撑 **17.8 等效 PE**！
     - Tile [32, 32, 32] ($I = 3.56\text{ MAC/B}$): 仅能支撑 **23.7 等效 PE**！256 PE 利用率仅 9.3%！
     - Tile [32, 32, 256] ($I = 8.53\text{ MAC/B}$): 可支撑 **56.9 等效 PE**。
     - Tile [64, 128, 256] ($I = 18.29\text{ MAC/B}$): 可支撑 **121.9 等效 PE**。
4. **PE 选型与阵列匹配建议**:
   - 在当前 2.0 GB/s 内存通路下，配置 256 PE 严重内存受限。
   - 若不增加外存带宽，采用 **32 PE (4×8 或 8×4)** 或 **64 PE (8×8 或 4×16)** 是算力与带宽平衡的最优解；
   - 若要让 256 PE 在 300 MHz 下达到 100% 满载，所需算术强度必须达到 $I \ge \frac{256 \times 300\text{e6}}{2.0\text{e9}} = 38.4\text{ MAC/B}$（需要巨大的片上 BRAM/URAM 缓存 Tile），或者将 DDR 带宽提升至 8~12 GB/s（通过多 HP 端口或独立 PL DDR4）。
5. **内部边界供数 (On-chip Feeding)**:
   - 脉动阵列每拍内部供数需求为 $2R + C$ Bytes/cycle。
   - 对于 $16 \times 16$ 阵列，每拍需 48 Bytes = 384 bits，在 300 MHz 下内部供数带宽为 14.4 GB/s。此供数由片上 BRAM/URAM 分布式多端口提供，不占用外部 DDR。
