# 原模型 W16A16 ASR：共享 Encoder / Decoder RTL

## 2026-09-22 板级更新（优先于下文早期实施记录）

照片及原厂引脚表已核对为ALINX AX7035老版布局，实际USB-UART接口为Mini USB。
第一代50MHz/115200已成功JTAG下载、8项实板测试通过，冻结在
`releases/v1_20260922_board_verified`（61个文件SHA256核验一致）。
第一代RTL和冻结文件不再修改。

第二代位于`v2/`，已下载并通过20项实板测试：128KiB BRAM、批量向量/归约、
矩阵分块、片上QDQ/Softmax/Sigmoid/LayerNorm。BRAM占64%，LUT约32%。
921600波特UART通过4MiB随机回环；各实测算子比第一代快约41–128倍。
最新结果与限制见`v2/README.md`和`v2/reports/board_acceptance.json`。

14:12:27起，完整原模型的7帧/1token新短输入推理在COM8后台运行，未缩层/缩权重，
原case0000未替换。最终状态以`v2/reports/full_micro7x1_20260922/result.json`为准；
在该文件出现并核对数值前，不宣称整网推理通过。当前所有下载仅易失配置，未写Flash。

下文保留第一代离线开发阶段的架构和命令背景；其中“未下载/未核实引脚”描述已被上述实测更新取代。

本目录是在 `D:\fpga\fproject\adder_16` 中新增的独立 ASR 实现。原有 `adder_16.xpr`、加法器源码和 `software4npu/temp` 下模型/向量均未修改。不裁层、不缩宽、不换词表；不包含 CTC、音频前端特征提取、beam search 或文本后处理。

目标器件采用现有工程的 `xc7a35tfgg484-2`，系统时钟暂按用户给出的 **50 MHz**，UART 默认 **115200，8N1**。实际板卡型号、时钟与引脚尚未确认，不能直接生成/下载可用 bitstream。

## 当前架构

```text
电脑：原 ONNX 权重、全部中间张量、图调度、形状/索引/掩码选择
       │ USB-Type-C 所承载的 UART，CRC + 停等协议
       ▼
FPGA：UART → 命令控制器 → 一套共享算术核心
                         ├ INT16 × INT16，signed48 累加
                         ├ FP32 标量：Q/DQ scale、LN/BN、Softmax、激活
                         └ 可选整数重定标（不擅自替换原图 QDQ）
```

Encoder 和 Decoder 的算术共用同一套 RTL，不在 FPGA 内驻留全部模型，也不需要 DDR。片内只保存最大 1024 字节命令包、状态及累加器。长点积可跨任意多个包保留 48 位部分和；原模型最大 K=9728 已验证。主机可以准备静态常量子图，但硬件模式下动态神经算术没有 CPU 回退。

## “INT16 原模型”的精度边界

所选原始模型本身是 **W16A16 QDQ**，并非所有节点均为整数。其量化权重、量化乘法输入仍为 signed INT16；scale、偏置、残差、LayerNorm/BatchNorm、Sigmoid/Softmax 等保留 FP32 标量语义，并在 FPGA 计算。这里没有把主要矩阵计算改回浮点，也没有把非线性偷偷放回 CPU。

矩阵/卷积采用精确 `sum(int16 * int16)` → signed48 → FP32 → scale。此运算顺序与 ONNX Runtime 的“先 DQ 成 float，再浮点归约”并非逐 bit 相同。FP 标量基础算术采用 RNE；subnormal 输入/输出冲零；EXP/LOG 使用多项式近似。不能宣称与原运行时 bit-exact，也不能把软件参考或小算子仿真当作整网 RTL 验收。

静态折叠不会删除网络层：38 个 Conv、Encoder 的 145 个 MatMul、Decoder 的 84 个 MatMul 和 1 个 Gemm 都保留为动态运算。

锁定原模型目录：

`D:\program\python\ASR-ONNX\software4npu\temp\model_a_int16_runs\run01\int16_qdq_fix01`

模型审计拒绝 SHA256 不匹配、非对称/非 INT16 QDQ、非 opset 21 和未实现算子。

| 项目 | 保留配置 |
| --- | --- |
| Encoder | 12 层，D=512，8 heads，FFN=2048，Conformer 卷积核31 |
| Decoder | 6 层，D=512，8 heads，FFN=2048 |
| 词表 | 5000 |
| 模型和缓冲 | 上位机保存，串行传输，允许极慢运行 |

## 文件入口

- `rtl/asr_uart_top.sv`：板级顶层 `clk, rst_n, uart_rx, uart_tx`。
- `rtl/asr_command_engine.sv`：完整校验报文后执行、CRC、跨包累加、错误状态。
- `rtl/asr_i16_mac.sv`、`asr_requant.sv`、`asr_fp32_alu.sv`：共享算术模块。
- `host/model_a.py`：原 Encoder → Decoder 图执行入口。
- `host/onnx_executor.py`：原图调度、QDQ 来源检查、算子展开。
- `host/transport.py`：Windows 原生串口后端，不依赖 pyserial，不自动重发有状态命令。
- `host/rtl_sim.py`：相同协议连接真实 RTL 仿真，不冒充物理 FPGA。
- `host/smoke.py`：同一组有界算子冒烟测试，可显式选择真实串口或默认RTL仿真。
- `host/profile_model.py`：完整 case 的 UART 流量及主机控制节点审计。
- `sim/`、`tests/`：模块、UART、协议、主机以及实际 RTL 算子联调测试。
- `PROTOCOL.md`：协议及数值命令定义。

## 复现

在本目录运行。当前机器可用的 Python 环境已含 numpy/onnx：

```powershell
$asrPython = 'D:\app\ananconda\envs\asronnx312_int16\python.exe'
& $asrPython -B scripts/run_tests.py
& $asrPython -B -m host.smoke --simulation-build build/smoke --report reports/smoke_rtl.json
& $asrPython -B -m host.model_a inspect --report reports/model_a_manifest.json
& $asrPython -B -m host.model_a run --backend software --isolated-decoder --report reports/model_a_software_case0000.json --output-npz reports/model_a_software_case0000.npz
& $asrPython -B -m host.profile_model --report reports/model_a_uart_estimate.json
```

`run_tests.py` 需要 Icarus 的 `iverilog` / `vvp`；可通过同名参数指定绝对路径。扩大 FP 随机测试：`--scalar-count 20000`。测试不连接串口，不烧录板卡。

最终离线回归（`--scalar-count 20000`）通过：MAC 10,198个结果、整数重定标535例、命令引擎71包回复、UART全部256种字节及完整顶层PING、FP标量324,726例、标量流水/长运算复位31例、52项Python/真实RTL联调测试，以及持久仿真桥。完整命令输出和RTL文件SHA256记录在 `build/tests/test_report.json`，标量结果在 `build/tests/scalar/scalar_report.json`。EXP/LOG在这批样本最大误差分别1/3 ULP，不是全域误差证明。

Vivado 综合与无板级引脚的 OOC 布局布线：

```powershell
./scripts/run_vivado.ps1 -Mode synth
./scripts/run_vivado.ps1 -Mode create_project
```

第二条生成 `build/vivado_project/asr_int16.xpr`，不覆盖现有加法器工程。启动脚本只给当前进程指定 Vivado 自带 TclStore，不改全局安装文件。默认 Vivado 路径可用 `-Vivado` 参数覆盖。综合报告在 `build/synth/`；OOC 报告不等价于板级时序验收。

### 2026-09-22 实测 Vivado OOC 结果

Vivado 2025.2、`xc7a35tfgg484-2`、20 ns时钟、完成布局布线：

| 资源/指标 | 结果 |
| --- | --- |
| LUT | 5349 / 20800 = 25.72%（含192 LUTRAM） |
| FF | 1636 / 41600 = 3.93% |
| DSP48 | 3 / 90 = 3.33% |
| BRAM | 0 / 50 |
| 建立 WNS / TNS | +0.188 ns / 0 |
| 保持 WHS / THS | +0.092 ns / 0 |
| 锁存器 / 无时钟寄存器 / 未约束内部端点 | 0 / 0 / 0 |

报告以 `build/synth/utilization_route.rpt`、`timing_route.rpt` 为准。实现没有用算术 false path 或 multicycle 放宽掩盖失败；加法器采用真实分级寄存流水。50MHz OOC约束已满足，但裕量较小，真实板级时钟树、I/O、配置电压仍需重新约束和验收。OOC参考时钟使用器件内可用BUFG站点，并非板卡引脚声明。

DRC仍有配置电压未知、DSP流水优化建议、OOC输出无可布线负载等 Warning；不宣称板级DRC全部通过。当前是串行正确性核，没有为了达到此前“60%–80%”目标而人为占满资源；余量可以用于后续片上tile缓存、批量算术和并行度，需另行衡量吞吐与资源。

真实串口仅在完成正确引脚约束、bitstream、板卡时钟确认后使用：

```powershell
# COM号必须替换为实物端口；本轮没有执行以下硬件命令。
& $asrPython -B -m host.transport --port COMx --baud 115200
& $asrPython -B -m host.smoke --backend hardware --port COMx --baud 115200 --report reports/smoke_hardware.json
& $asrPython -B -m host.model_a run --backend hardware --port COMx --baud 115200 --report reports/hardware_case0000.json
```

先做 PING、标量/短点积、真实维度算子和单层验收，再启动完整模型。串口错误必须显式复位/重启任务，禁止盲目重传会重复累加的包。

## 验证范围与性能限制

已完成模块仿真、完整 UART 顶层握手、真实 RTL 的 D=512 LayerNorm、分组 Conv、MatMul/Gemm、QDQ、Softmax/LogSoftmax、Swish 和注意力片段联调。小片段只是测试夹具，原模型执行入口未被它们替代。

原 `case_0000` 完整软件参考已运行：输入 `[1,128,80]`、token前缀 `[1,16]`，Encoder输出 `[1,31,512]`，Decoder输出 `[1,5000]`。相对已有 QDQ expected，Encoder最大绝对误差约0.0045513，Decoder全链约0.0050392；均非 bit-exact。详见 `reports/model_a_software_case0000.json`。该报告明确 `hardware_executed=false`，不表示整网 RTL 通过。

当前逐 dot / scalar 协议的上述 case 约44.76亿 MAC，串口往返 **23.40 GB**。115200 8N1 的理想线速下限约 **564小时（23.5天）**，921600约70.5小时，尚未计算停等、USB延迟和算术时间。921600只是估算，不代表该板卡已验证支持。这里优先验证计算正确性，尚未做 tile缓存/批量标量优化；这些优化可在不改模型的条件下逐步加入。

未完成的验收：物理板卡引脚/晶振核对、bitstream 下载、板上数值测试，以及完整原模型 RTL 对比与识别精度评估。不能用软件全链测试替代这些步骤。
