# LayerNorm GPU 软件实验摘要

原包 `layernorm_results_before_migration.zip` 主要包含 600 份 `.npz` 数值样本和运行记录。实验标记 `fpga_executed=false`，运行设备为 GPU；不属于 RTL 仿真或实板硬件验证。

`summary.json` 从原 `run_20260919/comparison.json` 及其分组比较记录提取聚合指标，不包含逐条语音文本和原始张量。它显式标为派生摘要，并记录主要来源文件 SHA-256。

200 条音频的原记录：native WER 为 2.464704%，pow2 WER 为 3.996171%，增加约 1.531467 个百分点。该结果说明此 pow2 替代在这些样本上的精度变化，不证明 FPGA 实现或全量数据集性能。

原包没有实验驱动的完整源码，因此这里只作为研究结果归档。完整原始数据留在仓库外的解压归档中。
