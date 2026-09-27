# 整理后的检查记录

日期：2026-09-27。以下检查在整理后的本地源码目录运行，没有打开 FPGA 网口、串口或 JTAG。

| 检查 | 执行入口 | 本次结果 |
|---|---|---|
| V5 传输协议与报告判定 | `tools/run_checks.py --suite python` | 34 项原有单元测试通过 |
| 独立黄金比较器的合成数组正反例 | 同上 | 5 项通过；未把合成数组作为模型黄金值 |
| 单头原模型与整数参考 | `tools/run_checks.py --suite head` | 10 项原有测试通过，原参数输入镜像及 C 仿真输出一致性检查通过 |
| UDP 命令桥 RTL | `tools/run_checks.py --suite rtl` | 38 项检查通过，使用真实冻结 V2 引擎 |
| UDP 接收保护 RTL | 同上 | 13 项检查通过 |
| KSZ9031 初始化 RTL | 同上 | 非默认 PHY 地址、11 次配置写入和无 PHY 失败路径通过 |
| ARP 直连 RTL | 同上 | 11 项检查通过，使用实际 verilog-ethernet 模块 |
| Python 语法、设计输入、依赖文件与文件身份 | `tools/check_repository.py` | 上传前核对当前清单与保留的冻结文件 |

离线协议测试因冻结执行器导入依赖，使用临时目录中的 ONNX 1.23.0 与 ml_dtypes 0.6.0；没有运行 ONNX 模型推理或生成新黄金值。单头测试使用当前 PyTorch 环境及经原 manifest 哈希核对的本地资产。模型和参数镜像均被 Git 忽略。

此次没有重新运行 Vivado/Vitis HLS、AMD FMA IP XSIM 或实板模型推理。原包中的 HLS/实板/时序证据仅以历史记录方式保留。V5 case_0001 的 Decoder 17/5,000 超差仍是当前已知失败；离线回归通过不改变其模型验收结论。

根目录 CI 执行文件检查、协议/比较器测试和上述四个 RTL testbench；完整单头参考测试需要外部权重与镜像，因此不在无资产的 CI 中自动执行。
