# Conformer 单注意力头 FPGA 实现

本项目来自 `modelA_conformer_head_full_fpga.zip`，命名为 `conformer_attention_head`，明确范围为一个注意力头。HDL 的模块名和 Vivado 内部工程名保持原样。

## 硬件边界

输入是 Model A 编码器第 0 层 `norm_mha` 后的 `[1,T,512]`，T=1..8，选取 head=0、维度 64。FPGA 完成原 FP32 输入解析、动态 INT16 量化、Q/K/V/P 投影、位置偏置、mask、Softmax、PV、输出投影及 FP32 输出转换。累加为 INT64，INT16 表示矩阵操作数位宽。

前置 LayerNorm、另外 7 个 head、卷积/FFN 与完整语音编码器不在该模块边界内。主机传输客户端只负责数据和 CRC；模型参考计算仅在离线验证端使用。

## 软件 / 仿真 / 硬件

| 目录 | 角色 |
|---|---|
| `src_hls/` | 当前 C++ HLS 硬件算法、查表常量和 C testbench |
| `rtl/` | UART 数据桥、顶层；`generated/` 是实际 Vivado 构建所需的 HLS 导出 RTL/ROM |
| `constraints/` | AX7035 引脚与时序约束 |
| `host/` | 通信软件、参数镜像导出、整数/模型参考及原有单元测试 |
| `scripts/` | HLS 仿真/综合/协同仿真和 Vivado 实现/烧写 |
| `vendor/` | 原参考模型所需的 ESPnet 源码副本 |
| `reports/` | 从原包精选的仿真、实现和实板结果 |

## 已归档的验证

[validation_summary.json](reports/validation_summary.json) 记录 T=1/4/8 三次实板测试：14,225 个输出全部与独立整数参考逐位一致。相对原 PyTorch 浮点模型，context 和输出投影的相对 L2 误差最大约 0.067%；不能把“与整数参考逐位一致”解释为“与浮点模型零误差”。

原报告记录 50 MHz、11,567 LUT、33.5 BRAM、9 DSP，setup WNS 2.265 ns。HLS 协同仿真是 3,905,841 周期，理想计算延迟约 78.12 ms；串口传输和实物端到端耗时另见 `reports/verified_t*/transport.json`。

## 运行入口

从仓库根使用 [复现说明](../../docs/reproduction.md) 中的 `tools/build.py`、`tools/run_checks.py`。当前目录下的软件调用仍使用 `python -m host.transport`。

模型权重、`fixtures/input.bin` 参数镜像和参考 `.pt` 不入 Git。可用 `tools/prepare_local_assets.py` 从完整解压包恢复并核对哈希。原环境版本见 [requirements.txt](requirements.txt)，原使用细节见 [使用说明](docs/全FPGA单头使用说明.md)；说明中的旧本机路径仅代表原环境。
