# AXU15EGB PL ETH 现有代码复用评估

日期：2026-11-01。范围：只读检查本地解压源码与当前 V024 平台；没有连接硬件、打开网口、配置网卡、运行旧网关或启动编译。当前没有本轮 V024 经 PL ETH 完成 ARP、UDP HELLO、RAM 上传或计算回读的真实通信证据。旧工程的报告和注释不能替代本次验证。

**结论：已有 UDP 收发与可靠会话代码值得复用，但本包没有可直接接入当前 V024 的完整 ZU15 网口工程。最小后续工作是补齐 ZU15 物理接口依赖，保留已有 V4/V2 报文格式，在旧命令字节流之后增加一个面向现有四个 PL 地址区的 AXI32 访问端点。当前 JTAG 工具与核心不需要因此改成旧 PS 网关架构。**

## 1. 已有模块分别负责什么

| 源码 | 已核实的职责 | 对 PS 的依赖 | 当前复用判断 |
|---|---|---|---|
| `work/rtl/asr_eth_board_zu15.sv` | RGMII 引脚、时钟、MAC FIFO、Ethernet/ARP/IPv4/UDP、目的地址与分片过滤；对应用输出 UDP 首部与 8-bit AXI-Stream | 此模块本身没有 PS、DDR 或 AXI 内存端口 | 可作为 ZU15 网口前端依据，依赖未闭合，不能直接投入构建 |
| `v5/rtl/asr_udp_command_bridge.sv` | UDP 49152、`ASR4` 会话、顺序号、CRC16、完整批次预检查、最近请求/回复缓存、相同请求重传去重 | 不依赖 PS；后端是 `engine_rx_valid/data` 与 `engine_tx_valid/data/ready` 字节流 | 可保留传输层逻辑；它不是 AXI 主设备，也不解析 V024 CSR |
| `v5/host/ethernet_transport.py` 的 `EthernetLink` | HELLO/EXEC/CLOSE、同报文重试、回复 CRC/顺序号/长度检查、不确定会话终止 | PC 侧 Python，不依赖板上 PS | 可作为主机报文层，目标 IP 必须显式设置 |
| 同文件的 `EthernetBackend` | 继承冻结 V2 数值后端，16-bit SRAM 字索引、32768 字容量、旧运算命令 | 对应旧 V2 命令引擎，并非 V024 | 不能直接把它的 `write_words(0x04000000, ...)` 当 AXI 地址访问 |
| `work/ps/gateway_async.c` 及其 include | A53 处理旧虚拟命令、参数装载 CRC、DDR 读写、旧矩阵队列和计划启动；通过 PL 邮箱交换请求/回复 | 明确依赖 A53、OCM、PS 可见 DDR/AXI、旧邮箱及旧 CSR | 不能在当前 PL-only 平台直接运行；只适合参考已有命令语义 |

“接 PL ETH”与“旧网关使用 A53”并不矛盾：以太网物理口可以在 PL，应用命令再交由 PS 邮箱软件处理。本包中的 `gateway_main_async.c` 访问邮箱 `0xA4000000`，并不调用 PS GEM 或 lwIP。旧完整顶层与继承的构建工程缺失，因此这里只能依据源码接口和地址映射重建该路径，不能声称已逐线验证旧完整网表。

主要源码入口：

- [ZU15 网口前端](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023/work/rtl/asr_eth_board_zu15.sv:5)
- [UDP 命令桥](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_qdq_fpga/v5/rtl/asr_udp_command_bridge.sv:4)
- [PC EthernetLink](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_qdq_fpga/v5/host/ethernet_transport.py:263)
- [旧 PS 网关](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023/work/ps/gateway_async.c:1)、[邮箱主循环](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023/work/ps/gateway_main_async.c:4)

## 2. 源依赖是否完整

已找到的可复用部分包括 `eth_mac_1g_rgmii_fifo.v`、`eth_axis_rx.v`、`eth_axis_tx.v`、`udp_complete.v`、`sync_reset.v`、AXIS FIFO 源，以及 V5 的 UDP bridge/guard。主机 `frozen_imports.py` 要求的四份冻结 transport/executor 文件也都存在；但该模块在导入时会加载旧数值后端和 NumPy，不能把单个 `ethernet_transport.py` 脱离目录结构复制后就视为独立可运行工具。本轮没有执行这些导入。

明确缺口如下：

| 缺口 | 本地证据与影响 |
|---|---|
| `rgmii_rx_delay` 缺失 | ZU15 前端第 63 行实例化；在本解压项目的 RTL 中未找到该模块定义。接收延迟及 `delay_ready` 无法闭合 |
| ZU15 I/O DDR 分支不匹配 | 前端第 70 行指定 `IODDR_STYLE("IODDRE1")`；随包 vendor 的 `iddr.v`、`oddr.v` 在 `TARGET=="XILINX"` 下仅有 `IODDR`、`IODDR2` 分支。直接组合时不会实例化相应收发寄存器，输出无驱动，不能当作兼容版本 |
| 旧完整构建依赖缺失 | `work/scripts/build_full.tcl` 打开 `asr_w7_dma_v023/model_a_lowbit_v13/soc_full/build.tcl`，该路径不存在；大量旧 RTL 也从此继承根目录读取 |
| 旧 PS 运行依赖缺失 | `resident.h`、`macro.h`、`v13_ps_mailbox` 模块、`v9_command_router` 模块未在本包源码中找到；`work/scripts/build_gateway.ps1` 不存在。`derive_runtime_v022.py` 引用的旧 sibling 工程也不在当前预期路径 |
| ZU15 网口约束没有完整来源链 | 未找到旧 `board_pins.xdc` 或独立的 ZU15 RGMII 约束文件；旧报告提及引脚与 placement locks，但这不等于可复用约束。V5 的 `ax7035_eth.xdc` 明确用于 AX7035/KSZ9031，不能给 AXU15EGB 使用 |
| 协议说明文件缺失 | Python 注释引用 `PROTOCOL_V4.md`，本包未找到该文件；当前合同应以实际 bridge/transport 源码及现有仿真用例为准 |

[IDD R 实际分支](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_qdq_fpga/v5/vendor/verilog-ethernet/rtl/iddr.v:72)、[ODDR 实际分支](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_qdq_fpga/v5/vendor/verilog-ethernet/rtl/oddr.v:72)、[旧完整构建入口](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_w7_dma_v023/work/scripts/build_full.tcl:4)、[错误板型约束的明确说明](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_qdq_fpga/v5/constraints/ax7035_eth.xdc:1)。

本次优先检查了仓库已固定的 GitHub 实现，没有替换网络库。[vendor/SOURCE.json](C:/Academic_Work/CIM_learning/v0.24/npu4conformer-main/npu4conformer-main/projects/asr_qdq_fpga/v5/vendor/SOURCE.json:1) 记录上游为 [alexforencich/verilog-ethernet](https://github.com/alexforencich/verilog-ethernet)，固定提交 `77320a9471d19c7dd383914bc049e02d9f4f1ffb`，并记录其已由 taxi 接续维护；这是本包保存的来源记录，本轮未刷新远端维护状态。MIT 授权原文在本地 `COPYING` 和各 RTL 文件头中存在，复用应保留。已有固定源码的接入成本主要在 ZU15 I/O、约束和 V024 地址端点，不在重新选择协议栈。

## 3. 与当前 V024 的关键差异

| 项目 | 旧网络工程/网关 | 当前 V024 平台 |
|---|---|---|
| 应用数据接口 | UDP 首部 + 8-bit payload；后续是 V2 命令字节流 | SmartConnect 上的 AXI32 主机入口；核心 AXI128 数据端口 |
| 主机地址含义 | V2 SRAM 的 16-bit 字索引；旧 PS 另用 E000/E100 虚拟命令设置 32-bit 游标/搬数据 | 字节地址：arena `0x04000000`、params `0x10000000`，各 64 KiB |
| 核心控制 | 旧 resident `0xA0000000`，matrix `0xA8000000`，plans `0xA9000000`，mailbox `0xA4000000` | 原 V024 CSR `0xA0000000`，板控 `0xA1000000`；没有旧 mailbox/matrix CSR |
| `0xA0000000` 身份 | 旧网关期望 `A51A1001` | 当前 V024 为 `A51A22D0`；地址相同不代表 ABI 相同 |
| 参数合同 | 参数 DDR 窗 `0x10000000..0x40000000`；镜像加载/CRC/READY/generation 状态机 | params 实际只有 64 KiB；另需板控 `+0x100..+0x1FC` 预装 64 个 scale/bias 字 |
| 图启动 | E200/E400 转译为旧队列、旧 plan 及 A53 调度 | CSR `+0x08=0x10008000`、`+0x0C=1`、`+0x10=1` |
| 完成判断 | 旧 ABI 的运行状态/软件 ticket | 原 CSR `+0x04` 的粘滞 DONE；板控 done 只是一个时钟脉冲 |
| 平台组成 | 旧 full 构建明确加入 PS、HP0 DDR 路径、邮箱 | 当前仅 PL 时钟、JTAG AXI、核心、板控、两块 BRAM；没有 Ethernet 引脚或 MAC |

因此，仅把网线插入 PL ETH 或改 Python 的目标 IP，不会使当前比特流新增网络功能。旧 C 网关使用 AArch64 `dsb/mrs/msr`、OCM `0xFFFE0000`，并在入口处理 `SCTLR_EL3`/I-cache，绝不是可在 PC 上执行的普通 UDP 服务。其“无 CPU 神经运算”注释也不等于“无 PS 依赖”。

## 4. 时钟、PHY 与主机参数的细节

ZU15 前端的注释和信号名写有“100 MHz / clk100”，但实际参数是 `200 MHz × 5 ÷ 8 = 125 MHz`；MAC 与应用两个输出均为 125 MHz，校准时钟为 `200 MHz × 5 ÷ 3 ≈ 333.333 MHz`。当前平台应用时钟为 50 MHz，不能把旧 `core_clk` 直接接到现有逻辑后还保留 50 MHz 计数口径。

最小接入宜保持 V024/UDP bridge/新 AXI32 端点在当前 50 MHz 域，保留 MAC 所需 125 MHz；MAC FIFO 已有 `gtx_clk` 与 `logic_clk` 的跨域接口。时钟输入应在一个板级顶层统一处理，不能让旧前端和当前 Clock Wizard 各自重复接管同一组 200 MHz 差分输入。RGMII 接收延迟、IDELAY 校准、PHY TX 内部延迟和约束仍需补齐并实际验证；不能仅凭上述时钟规划宣布接口可用。

旧前端默认 MAC 为 `02:00:00:00:15:06`，IP 为 `169.254.15.6/16`；其 `GATEWAY_IP=LOCAL_IP` 用于直接网线的 ARP 子网判断。它固定 `phy_reset_n=1`、`phy_mdc=0`、`phy_mdio=Z`，注释假设 JL2121 B 板 strap；这不能证明当前实物 PHY/延迟模式已经读出或核验。

V5 `open_link()` 默认目标却是 `169.254.35.4`，本地绑定 `169.254.147.66`。旧 W7 运行脚本显式覆盖为 `169.254.15.6`。未来应从实际网卡与固件配置确认地址后显式传参；本轮没有检查或修改电脑网卡。

## 5. 最小后续接入路径（评估建议，尚未实现）

```text
PC EthernetLink
  → 现有 ASR4 UDP 会话 / CRC / 去重
  → PL RGMII MAC + UDP + guard + command bridge
  → V2 命令字节流到 AXI32 的小端点
  → 当前 SmartConnect 的新增主机入口
  → arena / params / V024 CSR / 板控
```

1. **先补齐板级前端依赖。** 优先找回旧 ZU15 版本的 `rgmii_rx_delay`、带 IODDRE1 支持的 I/O wrapper、RGMII 约束及原顶层来源；若拿不到，按已有 ALINX 官方资料与 AMD 原语重新适配这部分。不要用本包 AX7035 引脚表替代，也不要把不同 vendor 版本直接混接。
2. **保留现有报文格式，只做端点适配。** 旧 PS 已有 `0x41 + E000` 设置 32-bit 游标、`0x41/0x42 + E100` 顺序写/读的语义，可作为现有语义的复用候选；新端点将实际访问限定到上述四个 PL 区域及已定义 CSR，不沿用旧 DDR 范围、READY 镜像或 A53 宏执行。无需因此另起 UDP 包格式或引入新运算协议。本轮没有实现或冻结这个端点合同。
3. **把 AXI 完成边界保留下来。** 原 bridge 的 `engine_rx` 没有 `ready`，不能直接将每个字节接到可能反压的 AXI 总线；端点应先接收有界完整命令，再进行 AXI 读写。写回复应等待实际 B 响应，读回复应包含实际 R 数据和严格长度；错误/超时必须结束当前会话，不能伪造成功。保留已有相同 session/sequence/报文的去重缓存，避免丢包重试重复执行 START 或递增游标。
4. **`engine_busy` 表示命令端点忙，不能直接接图的 busy。** START 的命令响应应在控制写入被接受后返回；图在运行时仍需要允许查询 CSR。若直接用图 busy 阻止 bridge 接收命令，会把状态轮询也挡住。运行时拒绝 RAM 改写、参数改写及新 START，保留只读诊断。
5. **主机使用 EthernetLink 的报文层，另做 V024 访问包装。** 不实例化旧数值 `EthernetBackend` 去执行 V2 运算。保持已有 `MAX_BODY=1382` 和内层 1024-byte 上限；采用已有 E100 合同的最多 255 个 32-bit 字一批即可分批搬运每个 64 KiB 区域，禁止跨映射边界。64 个 per-channel 字仍通过板控实际握手完成。
6. **保持现有验收顺序和证据。** magic/cap → 核心保持复位 → 写完两个 64 KiB 区域 → 两区完整读回与哈希/逐字核验 → 释放复位 → 写并读回 64 参数 → 设置计划并 START → 原 CSR 粘滞 DONE/FAULT 轮询 → 32 KiB 输出完整读回 → A16/copy 精确比对和 DIV/SQRT 容差验收。既有冻结输入与数值比较规则可复用；网络运行应另存明确的 UDP receipt，不得给它贴上 `physical_board_jtag_axi` 标签，也不改写已验证的 JTAG 工具证据。

其中 SmartConnect 从当前两个主机入口扩为三个，保留 JTAG 便于独立比较；新入口的地址解码仍对应现有两块独立 BRAM 和两个 CSR。50 MHz 核心域与 125 MHz MAC 域的边界、网络复位与核心复位的边界应清楚：保持核心复位时网络端点必须仍能装载 RAM。

## 6. 下一次怎样证明网口确实可用

先在核心保持复位时取得实际 ARP/UDP HELLO/PING 与两项 magic 读回，再做非对称字形往返和两个完整 64 KiB 图像的交叉读回。随后执行同一七节点图，核对全部 8192 个输出字的数量及四段结果。可以用 JTAG 对同一 RAM 作独立读取，排除网络写读同时错序仍相互抵消。

只有这些实际回包、内容、终态及结果文件都齐全，才能记录“当前 V024 的 PL ETH 上传/控制/回读通过”。链路灯、网卡显示已连接、旧报告中的 UDP 性能或本次源码存在，都不够证明这件事。上传时间、图运行周期与输出回读时间应分别记录。

本轮交付仅此评估文件；没有修改 `load_run_verify.tcl`、`verify_v024.py`、平台 RTL 或任何网络配置。
