# npu4conformer

面向 Conformer 的 FPGA 实现与数值验证工程。仓库包含一个单注意力头硬件示例、一个 Encoder→Decoder FPGA 执行研究版本，以及一组独立的 LayerNorm GPU 实验摘要。

## 工程与状态

| 工程 | 类型 | 目标与边界 | 原包记录的结果 |
|---|---|---|---|
| [conformer_attention_head](projects/conformer_attention_head/README.md) | HLS + RTL 硬件，Python 配套 | Model A 第 0 层、第 0 个注意力头；T=1..8，维度 64 | T=1/4/8 的 14,225 个实板输出与整数参考逐位一致 |
| [asr_qdq_fpga](projects/asr_qdq_fpga/README.md) | RTL 硬件 + 主机调度 + 仿真 | INT16 QDQ 模型的 Encoder→Decoder 单次前向；128 帧、16 tokens | 第一例全链路通过；第二例 Decoder 有 17/5,000 个值超差，整体未通过 |
| [layernorm_gpu_study](results/layernorm_gpu_study/README.md) | GPU 软件实验 | native / manual_exact / pow2 LayerNorm 比较 | native WER 2.4647%，pow2 WER 3.9962%；没有 FPGA 执行 |

这些是归档中的历史结果。工程整理后的离线回归见 [检查记录](docs/check-results.md)；没有把历史实板运行当成此次重新执行的结果。

## 目录

```text
projects/
  conformer_attention_head/       # HLS 单注意力头项目
    src_hls/                     # 可修改的 C++ 算法与 HLS testbench
    rtl/                         # UART 顶层和 HLS 导出 RTL/ROM
    constraints/                 # 引脚与时钟约束
    host/                        # 通信、模型导出、参考计算及单元测试
    scripts/                     # Vivado / HLS 构建入口
    vendor/                      # 离线参考所需的 ESPnet 源码和许可证
    reports/                     # 精选仿真、时序、资源与实板证据
  asr_qdq_fpga/
    v5/                          # 当前 V5 RTL、主机端、仿真及失败案例诊断
    releases/                    # V5 仍引用的 V2 冻结源码
    golden_validation/           # 从首例运行副本恢复的黄金验收工具
results/layernorm_gpu_study/      # 软件实验的汇总数据
docs/                            # 分类、筛选、复现和来源清单
tools/                           # 统一构建及离线检查工具
```

保留每个项目的内部相对路径与 HDL 模块名，避免按文件后缀拆散依赖。C++ `src_hls/` 是待综合硬件算法；SystemVerilog `sim/` 中的 testbench 是仿真；Python `host/` 同时包含通信软件与离线参考，具体分类见 [工程分类](docs/engineering-classification.md)。

## 快速检查

```bash
python tools/check_repository.py
python -m pip install -r requirements-checks.txt
python tools/run_checks.py --suite python
# 安装 Icarus Verilog，使 iverilog 与 vvp 在 PATH 中
python tools/run_checks.py --suite rtl
```

以上入口不打开串口、网口或 JTAG。Vivado/Vitis HLS 构建及外部模型资产的准备见 [复现说明](docs/reproduction.md)。

## 使用范围

Conformer 单头示例不包含完整多头注意力、前置 LayerNorm、卷积、FFN 或整个语音编码器。ASR V5 采用量化模型中的浮点数值路径，包含 FP32 FMA；不能称作全程纯 INT16 运算。它不含 CTC、音频特征提取或完整自回归识别循环，也未证明 200 例全链路通过。

源码、必要的第三方依赖和摘要证据优先入库。模型、含权重的输入镜像、黄金张量、虚拟环境、位流和构建缓存通过外部资产方式准备，见 [筛选依据](docs/selection.md)。第三方文件保留原许可证；未替项目自有源码指定新的开源许可证，见 [来源与许可证](THIRD_PARTY_NOTICES.md)。
