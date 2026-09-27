# V5 第二个原始黄金案例验证

最终状态：已完成一次物理运行，Encoder 逐位通过，Decoder 有 17/5,000 个元素超出原容差，整体不通过。详见 `RESULT_zh.md`。没有修改冻结实现或启动修复版本。

本目录只增加验证脚本和报告。冻结的 V5 RTL、主机数值实现、已部署比特流、原始 ONNX 和原始黄金文件均不改动；不操作 Flash，不重新配置 FPGA，不安装或替换任何系统 DLL。

## 固定实验条件

- 案例：原 `random200_v1/cases/case_0001`，128 帧、16 tokens，与第一例尺寸相同、输入不同。
- 原始输入 SHA256：`0c416a25d6bf1b8c6f0537c77e25020e2ebec5cfb8fd70d32bcf7c16dbba08a3`。
- 原始黄金 NPZ SHA256：`947fe5090bd97a097c0b3f0ba42541c3bb39ac5a0d9626cd999255634421641d`。
- 沿用通过第一例的 V5，比特流文件 SHA256：`e07da6cad366c43947f358432d0fccc482f4020462cfb8663508602e1119aab5`。这是文件身份记录，不宣称完成了配置存储器逐位读回。
- 完整 Encoder→Decoder 单次前向调用；Decoder 使用本轮实际 FPGA Encoder 输出。
- 原模型 INT16 QDQ 保持不变；量化图内原有浮点节点按已冻结 V5 实现执行，不宣称全部运算为纯 INT16。
- 所有浮点输出逐元素要求 `abs(actual-golden) <= 0.001 + 0.001*abs(golden)`，整数精确一致，形状、dtype、有限值必须符合。不得为第二例放宽容差。
- 不重新生成验收用黄金输出，不将 CPU 动态计算回填进 FPGA 推理链路。

## 文件说明

- `run_case0001.py` / `golden_case0001.py`：从第一例的验收工具复制，仅绑定第二例及独立输出目录，复用未修改的 V5 主机实现。
- `runs/case_0001_full_chain_001/`：本次物理运行、进度、中间输出、最终输出与黄金比较。
- `verify_two_cases.py`：独立逐元素比较，固定两例原始黄金哈希，不导入部署比较函数，不接触 FPGA；同时核对相同模型、相同主机实现和相同比特流记录。
- `test_independent_verifier.py`：比较器正反例、非有限值、形状/dtype、整数精确性测试；人工构造的测试数组只用于测试比较器，绝不是模型黄金数据。
- `compare_encoder_checkpoints.py`：仅诊断用途，使用原模型在内存中增加观察输出，与保存的 FPGA 中间量比较；诊断输出不作为新的黄金验收数据。只覆盖已保存的抽样检查点，不声称覆盖全部节点。
- `compare_decoder_checkpoints.py`：同样只做离线诊断；使用实际 FPGA Encoder 输出，并先确认其与原黄金逐位一致。
- `finish_audit.py`：运行结束后核验冻结文件、比较器测试、只读 UART；其审计通过不等于黄金测试通过。
- `verify_frozen_v5.py`：重算原 V5 冻结包及当前 RTL/host/constraints/bitstream 文件哈希。
- `collect_system_events.ps1` / `system_*.json`：只读系统日志快照，不执行 DLL 修复。

## 开始前已确认

- 1665 个冻结文件、29 个当前实现文件哈希通过。
- 板卡空闲，1G 链路，已有 UART 诊断中的帧错误/FCS/溢出/下溢/ARP 失败为零。
- 隔离 Python 进程可导入 NumPy、ONNX、ONNX Runtime，CPU INT16 QDQ 探针通过。
- 独立比较器包含正反例及第一例结果复核，并直接确认两例输入数组不同，而非仅依赖 ZIP 文件哈希不同。

本文件是实验说明，最终成功与否以完整物理运行 `result.json` 和独立双案例复核报告为准。
