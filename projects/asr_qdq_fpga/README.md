# INT16 QDQ 模型的 FPGA 执行研究

本项目来自 `v5_xc7a35t_frozen.zip`。使用原 Model A INT16 QDQ ONNX，主机调度图节点、保存张量并做布局/静态常量准备，动态数值通过 FPGA 命令执行。Encoder 使用 V5 浮点兼容路径，Decoder 保留 V2 数值路径。

## 当前正确性状态

| 指标 | case_0000 | case_0001 |
|---|---:|---:|
| Encoder 15,872 个 float32 值 | 全部逐位一致 | 全部逐位一致 |
| Decoder 超差数 / 5,000 | 0 | **17** |
| Decoder 最大绝对误差 | 0.00432395935 | 0.01969432831 |
| 全链路原容差验收 | 通过 | **未通过** |
| 归档耗时 | 1947.081 s | 1947.938 s |

浮点标准固定为 `abs(actual-golden) <= 0.001 + 0.001*abs(golden)`，整数、形状及 dtype 精确匹配，并要求有限值。两例均使用实际 FPGA Encoder 输出进入 Decoder；第二例不能以最高分 token 相同或 99.66% 元素通过代替全部通过。

详见 [第一例结果](v5/RESULT_20260923_zh.md)、[第二例失败与定位](v5/validation_case0001/RESULT_zh.md) 和 [双案例独立复核](v5/validation_case0001/independent_two_case_report.json)。当前是研究基线，不能宣布完整模型一般性正确。

## 目录与依赖

| 路径 | 作用 |
|---|---|
| `v5/rtl/`、`v5/constraints/` | 硬件命令引擎、RGMII/UDP、PHY 初始化和板级约束 |
| `v5/host/` | 传输、调度和 FPGA 数值命令适配 |
| `v5/diagnostics/` | CPU 参考、命令引擎仿真及检查点诊断 |
| `v5/sim/` | RTL testbench；数值仿真需要 AMD FMA IP |
| `v5/tests/` | 用内存模拟端点执行的协议与报告判定测试 |
| `v5/validation_case0001/` | 原第二例运行工具、独立比较器及失败报告 |
| `releases/v2_20260922_pre_golden/` | 当前 V5 引用的冻结数值 RTL、执行器与黄金读取器 |
| `golden_validation/scripts/` | 从归档恢复的第一例验收辅助脚本 |
| `v5/vendor/` | 固定版本的必要 Ethernet/AXIS 依赖及原许可证 |

SRAM 为 128 KiB，无 DDR，节点间张量仍保存在主机。QDQ 图本身包含反量化后的浮点运算，V5 包含 FP32 FMA 和专用 LayerNorm 数值顺序；项目名称不意味着“全程纯 INT16 算术”。

原目标是 `xc7a35tfgg484-2`、50 MHz；器件速度档须按实际板卡核对。历史顶层与位流名仍带 `v4`，保持协议和构建兼容，以 V5 路径与 `USR_ACCESS=A5160005` 区分。

## 复现与后续工作

统一入口见 [复现说明](../../docs/reproduction.md)。黄金模型/案例、位流和冻结清单中的二进制资产通过本地资产准备恢复；本目录的源码精选版不是完整不可变冻结包。

第二例失败已定位到旧 Decoder 数值路径相关误差传播；保存检查点中最早超差位于第二层 LayerNorm，但不能直接据此认定该算子是根因。继续研究应核对 MatMul 累加/舍入顺序及 QDQ 边界，保持原模型和容差。

本项目只覆盖 Encoder→Decoder 单次前向，不含 CTC、特征提取或完整自回归解码循环。`v5/docs/README_original.md` 保留首例历史说明，当前状态以上表为准。
