# 第三方来源、版本与归属

记录日期：2026-09-18。本文件记录本轮 `ASR_chip` 软件路径的主要直接依赖、原模型和测试数据。版本以实际安装元数据、固定下载 revision 和数据包内声明为依据；没有将外部模型未经说明替换为新网络。

`licenses/PROVENANCE.json` 保存本地复制原文的来源路径、版本和 SHA-256。复制的许可文件及模型卡保持原始字节。软件库、模型权重和音频数据各自使用其上游许可；本文件没有为整个工程重新指定许可证。

## 1. ESPnet 模型实现

- 来源：[ESPnet](https://github.com/espnet/espnet/tree/2d9a6c37c8eef710debc903d86132f1ad9a40c9f)。
- 当前运行 commit：`2d9a6c37c8eef710debc903d86132f1ad9a40c9f`。
- 已安装 distribution 版本：`202604`。`direct_url.json` 指向上述 commit 的 GitHub ZIP；版本标签不能代替 commit 身份。
- 许可证：Apache-2.0；本地原文为 `licenses/ESPnet-LICENSE.txt`。
- 引入理由：复用项目已有 Conformer、Transformer decoder、CTC/attention beam search、音频特征和 BPE 推理接口，保留 Model A 结构与权重。
- 工程中的 `model_source_original/espnet2` 是此前保留的阅读副本；新推理入口加载专用环境的固定 ESPnet 包，不把该不完整阅读目录当作可安装替代品。
- 本轮增加的是外部资源路径配置、校验、评估和量化包装；没有为此次任务重新训练或替换整套网络。

模型卡的原训练环境使用 ESPnet `0.10.7a1`、commit `c3569453a408fd4ff4173d9c1d2062c88d1fc060`。这与当前兼容运行 commit 不同，必须通过当前工程的真实音频测试验证兼容性；原模型卡成绩不能直接当成本机成绩。

## 2. Model A 权重、配置和分词资源

- 模型：[pyf98/librispeech_conformer](https://huggingface.co/pyf98/librispeech_conformer/tree/b74448c3b089eceea913735bd59a76d5252d8eec)。
- 作者/训练者：模型卡署名 **Yifan Peng**。
- 固定 revision：`b74448c3b089eceea913735bd59a76d5252d8eec`。
- 模型卡许可声明：**CC-BY-4.0**，不是由 ESPnet 的 Apache-2.0 推断出来的。
- 原模型卡副本：`licenses/ModelA-model-card.md`；其中包含上游训练环境、配置和上游结果，仅作来源记录。
- 获取内容：checkpoint、模型配置、global-MVN 统计、BPE 模型和元数据；身份及预期哈希定义在 `asr_chip/assets.py`。
- checkpoint SHA-256：`8e94fe626aefaec3662a101cba7e112fd108de4871602c34852c27b09384b21b`。
- 引入理由：继续使用项目已有英语 LibriSpeech ASR 基线，避免引入新的识别任务或训练过程。
- 本轮派生变化：按记录的 per-axis 对称规则将选定权重保存为 INT16，加载时恢复为 FP32 执行；保留原浮点权重作为参考。导出包记录原模型身份、量化规则及张量哈希。

[CC BY 4.0 官方许可说明](https://creativecommons.org/licenses/by/4.0/)；再分发时保留作者、来源、许可链接和修改说明。软件量化包并未取消原模型的归属信息。

## 3. LibriSpeech 数据

- 来源：[OpenSLR LibriSpeech ASR corpus，资源 12](https://www.openslr.org/12)。
- 本轮使用：`dev-clean.tar.gz`、`test-clean.tar.gz`，分别用于开发验证和最终评价；不下载训练集，也不训练模型。
- 数据包内署名：**LibriSpeech (c) 2014 by Vassil Panayotov**。
- 数据包内许可证声明：CC-BY-4.0。
- 本地原件：`data/LibriSpeech/LICENSE.TXT`；工程副本：`licenses/LibriSpeech-LICENSE.txt`。
- 官方 MD5：dev-clean 为 `42e2234ba48799c1f50f24a7926300a1`，test-clean 为 `32fa31d27d2e1cad72775fee3f4849a9`；下载过程另记录实际 SHA-256。
- 引入理由：与原英语模型一致的公开音频及转录，能够固定清单、校验数据、计算 WER 并保证两种权重版本使用同一评价条件。
- 处理说明：保留原始 FLAC 与完整转录；生成 manifest、哈希及识别结果，不改写数据包原始音频。

## 4. 主要 Python 依赖

| 组件与版本 | 来源 | 许可证与本地证据 | 引入理由 |
|---|---|---|---|
| PyTorch 2.8.0+cu128 | [pytorch/pytorch](https://github.com/pytorch/pytorch/tree/v2.8.0) | BSD-3-Clause；`licenses/PyTorch-LICENSE.txt`，同时保留包内附带组件说明 | FP32 张量计算、CUDA、权重加载 |
| torchaudio 2.8.0+cu128 | [pytorch/audio](https://github.com/pytorch/audio/tree/v2.8.0) | BSD-2-Clause；`licenses/torchaudio-LICENSE.txt` | 与 PyTorch 版本配对，满足 ESPnet 音频依赖 |
| NumPy 2.3.5 | [NumPy](https://numpy.org/) | NumPy 为 BSD-3-Clause；wheel 附带库另列于 `licenses/NumPy-LICENSE.txt` | FP32 波形及数值数组 |
| SoundFile 0.13.1 | [python-soundfile](https://github.com/bastibe/python-soundfile) | BSD-3-Clause；`licenses/SoundFile-LICENSE.txt` | WAV/FLAC 读取、音频元数据 |
| wheel 附带 libsndfile | 随 SoundFile 0.13.1 安装 | 附带 LGPL-2.1 原文：`licenses/libsndfile-COPYING.txt` | 实际音频容器解码；许可与 Python 包分开记录 |
| jiwer 4.0.0 | [jitsi/jiwer](https://github.com/jitsi/jiwer) | Apache-2.0；`licenses/jiwer-LICENSE.txt` | 独立核对纯 Python WER 实现 |
| PyYAML 6.0.3 | [PyYAML](https://github.com/yaml/pyyaml) | MIT；`licenses/PyYAML-LICENSE.txt` | 原 ESPnet YAML 配置加载 |
| SentencePiece 0.2.1 | [google/sentencepiece](https://github.com/google/sentencepiece/tree/v0.2.1) | Apache-2.0；[该版本官方 LICENSE](https://github.com/google/sentencepiece/blob/v0.2.1/LICENSE) | 使用原模型的 BPE 词表进行分词/转录恢复 |
| loralib 0.1.2 | [Microsoft LoRA](https://github.com/microsoft/LoRA) | MIT，Microsoft Corporation；`licenses/LoRA-LICENSE.txt` | 保留既有 LoRA 实验兼容性和依赖；本轮新基线不训练、不加载 adapter |
| pytest 8.3.5 | [pytest](https://github.com/pytest-dev/pytest/tree/8.3.5) | MIT；`licenses/pytest-LICENSE.txt` | 自动化测试工具；测试也可通过 unittest 入口运行 |

本表覆盖主要直接依赖，不宣称已穷举 ESPnet、CUDA、BLAS 等所有传递依赖。实际环境中各 distribution 的许可文件、依赖锁定记录和 wheel 附带声明仍需随对应环境保留。将来若打包分发整个运行环境，应按实际打包内容补齐清单。

## 5. 历史分支与本轮新增实现

工程原有 Model B、FastConformer、LoRA 搜索脚本及报告继续保留。本轮新 `asr_chip` 路径不以它们替换 Model A，也不把它们的既有成绩当作新 FP32/INT16 对照成绩。其资源与依赖不在本轮运行范围内。

本轮数据清单、WER、固定协议、量化存储和资源校验代码为项目新增包装，未复制另一套 ASR 网络。失效的 `model_a_preexperiment` 符号链接占位文件已转换为包装脚本或配置副本，原件保存在 `audit/2026-09-18/originals/`。

本项目当前未引入需要在 FPGA/ASIC 中实例化的外部 RTL、标准单元库或存储宏。这里的软件许可证清单不能代替下一阶段具体工艺库和硬件 IP 的来源说明。
