# 第二例结果：Encoder 通过，Decoder 未通过原容差

2026-09-23，使用原 `case_0001` 完整执行一次 FPGA Encoder→Decoder。01:09:54 开始，01:42:22 完成，耗时 **32 分 28 秒**。进程因黄金验收失败返回退出码 1，不是 DLL 崩溃。测试已停止，板卡空闲。

## 两例独立复核

| 指标 | case_0000（上一例） | case_0001（本例） |
|---|---:|---:|
| 完整前向耗时 | 1947.081 秒 | 1947.938 秒 |
| Encoder 15,872 个浮点值 | 全部逐位一致 | 全部逐位一致 |
| Encoder 长度输出 | 精确一致 | 精确一致 |
| Decoder 超差数 / 5,000 | 0 | **17** |
| Decoder 最大绝对误差 | 0.00432395935 | **0.01969432831** |
| Decoder 均方根误差 | 0.00075973335 | 0.00468901275 |
| 全链路原标准验收 | 通过 | **不通过** |

标准未改变：每个浮点值满足 `abs(actual-golden) <= 0.001 + 0.001*abs(golden)`，整数精确相等，并检查形状、dtype 和有限值。本例 4,983/5,000 个 Decoder 元素在容差内，但不能以 99.66% 元素通过代替逐元素全部通过。

两例最高分 token 均与各自黄金结果相同（ID 4999），也不能据此宣布所有 logits 或完整语音识别已经正确。验收对象是 128 帧、16 tokens 的 Encoder→Decoder 单次前向，不是全长音频解码或识别准确率测试。

独立比较器直接读取用户原 `expected.npz`，固定其 SHA256，逐个用 Python float64 判断，不导入部署比较器。它与物理运行的失败判定一致。第二例所有 10,240 个特征元素和 15/16 个 token 与第一例不同；不是重命名复跑第一例。

## 离线定位证据

- 原 ONNX 模型和原始黄金数据未变；独立 CPU ONNX 诊断的 Encoder、Decoder 最终输出均与原黄金逐位一致。
- 本例实际 FPGA Encoder 输出直接进入 Decoder，没有替换成黄金 memory，没有 CPU 动态数值回填。
- Encoder 保存的 93 个检查点：92 个逐位一致，1 个 Softmax 检查点有 581 个极小值差异，最大 `1.084028797458878e-38`，均在容差内；最终 Encoder 完全一致。
- Decoder 保存的 52 个检查点：8 个逐位一致，18 个检查点存在超差元素。
- 保存检查点中最早的数值差异出现在 `/decoders.0/src_attn/linear_k/MatMul`，最大绝对误差约 `3.34e-6`，当时仍在容差内。
- 保存检查点中最早的超差出现在 `/decoders.1/norm3/LayerNormalization`（第 2 层），8,192 个值中 10 个超差，最大绝对误差约 `0.00193806`。

上述“最早”只针对已经保存的稀疏检查点，不代表已经找到整个计算图的第一个错误算子，也不能直接断言 LayerNorm 本身就是根因。现有证据把问题范围缩小到仍使用旧数值路径的 Decoder；优先下一步应检查它的矩阵乘、累计/舍入顺序、QDQ 边界及误差传播。暂不改动已冻结实现，也未开始新版本或第二次物理复跑。

## 通信、冻结状态与 DLL

- 本例 1,649,389 次 UDP 收发匹配，重传、丢弃均为零，会话正常 CLOSE。
- 结束后的只读 UART 显示：1G，engine_busy=false，累计收/发均 3,307,624，较开始增加的包数与本例主机计数完全一致；坏帧、FCS、溢出、下溢、ARP 失败均为零。
- 再次校验 1,665 个 V5 冻结文件、29 个当前实现文件，全部一致。没有重新下载比特流、没有写 Flash，没有修改模型或容差。
- 本轮发现的系统应用事件为先前 Widgets 崩溃，以及运行期间 Office SDX Helper 关闭失败、SearchFilterHost 的 .NET 探查器初始化失败。未发现本次 Python 崩溃记录；需要的数值库加载及离线 ONNX 诊断成功。
- 用户所见具体 DLL 弹窗仍未确定，不能宣称已经修复，也没有证据把本次数值偏差归因于它。未安装或替换 DLL、未更新驱动、未重启系统。

`post_run_audit.json` 的 `pass_audit=true` 仅表示冻结/板卡空闲/通信检查通过，**不是模型黄金验收通过**。黄金验收明确为 false。

## 主要证据文件

- `independent_two_case_report.json`：两例独立逐元素复核，`pass_all=false`。
- `runs/case_0001_full_chain_001/result.json`：物理运行原始记录，`completed=true`，`acceptance_pass=false`。
- `runs/case_0001_full_chain_001/hardware_outputs.npz`：本例实际输出。
- `diagnostics/encoder_final_001/diagnostic_report.json`、`diagnostics/decoder_final_001/diagnostic_report.json`：中间输出诊断。
- `post_run_audit.json`：冻结哈希、7 项比较器单元测试及只读 UART 记录。
- `system_before.json`、`system_mid_001.json`、`system_mid_002.json`、`system_after.json`、`DLL_NOTES_zh.md`：系统事件调查。

本例输出 SHA256：`85594af4b905dd935cb670eefc1dc7eeacbd984d13283a0327bde9c7eefae8dd`。

本例物理结果 JSON SHA256：`99bb5906893839ccc926d24f4a6d51724229555f2cd0a4230601d348008e1d67`。

结论：增加第二例是有必要的；它证实 Encoder 在两个不同输入上逐位符合黄金，同时暴露出第一例通过并未覆盖的 Decoder 数值偏差。目前不能把 V5 标记为“两例全链路通过”。
