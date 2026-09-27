# 来源与许可证

## 项目源码

源码来自用户提供的四个 ZIP，文件映射和原始 SHA-256 见 [source-provenance.json](docs/source-provenance.json)。本次只做筛选、命名、文档和工程入口整理，没有给项目自有源码授予新的开源许可证。

## ESPnet

`projects/conformer_attention_head/vendor/` 包含原始源码阅读副本中实际使用的 Python 文件与模型配置，保留原版权头。原包声明 Apache-2.0，标准许可证文本位于该目录的 `LICENSE`。原模型权重来源为 `pyf98/librispeech_conformer`，仓库不包含权重或含权重的 `fixtures/input.bin`。

## verilog-ethernet / verilog-axis

`projects/asr_qdq_fpga/v5/vendor/verilog-ethernet/` 保留实际 Vivado 构建引用的 Ethernet 与 AXIS 文件，以及原 `COPYING`、`AUTHORS`。来源提交为 `77320a9471d19c7dd383914bc049e02d9f4f1ffb`，详情见项目 `vendor/SOURCE.json`。未打包整个上游仓库和未使用的板卡示例。

## ONNX Runtime

V5 的数值顺序参照 ORT 提交 `f2c39fe`。本仓库仅保留其 `SOURCE_MANIFEST.json` 来源清单与原 `LICENSE`，参考实现副本可通过项目 `scripts/fetch_ort_sources.py` 获取；它不等同于运行时版本要求。
