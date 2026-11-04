# ASR：统一的语音识别工程

**用 PyCharm 打开本 ASR 文件夹。** 所需模型、LibriSpeech 数据、random200、LayerNorm 实验、ESPnet 可编辑源码和专用 Conda 环境均放在这里。外部旧工程和 ASR_chip 环境已于 2026-09-23 按要求删除；必要历史资料与备份集中在本工程 history 内。

## 已完成的迁移验证

新环境依赖检查通过；225 项主工程测试和 74 项 LayerNorm 测试通过。迁移前后固定样本的文本及中间数值一致。详见 [迁移验证记录](docs/MIGRATION_ASR.md)。完整 test-clean 和完整 LayerNorm WER 本次没有重跑。

## 第一次运行

1. 在 PyCharm 的 Settings → Python Interpreter → Add Interpreter → Add Local Interpreter 中选择 Select existing。
2. Type 选择 Python，指定下面的 python.exe；也可选择 Conda 的 ASR 环境。

```text
C:\Academic_Work\CIM_learning\ASR\environment\envs\ASR\python.exe
```

3. 右键运行 pycharm_runs/01_check_environment.py，检查环境和工程内 ESPnet 加载路径。
4. 右键运行 pycharm_runs/02_recognize_one_audio.py，对同一音频执行 FP32 和 INT16 权重版识别。

无需填写 Parameters 或 Working directory。新运行结果写入 results/runs 的时间戳目录。

## 各入口

| 文件 | 功能 |
|---|---|
| pycharm_runs/01_check_environment.py | 环境、GPU、模型和源码位置检查 |
| pycharm_runs/02_recognize_one_audio.py | 单条真实音频，两种权重版本识别 |
| pycharm_runs/03_reproduce_layernorm.py | 原生/移位 LayerNorm 数值与真实语音实验，约十几分钟 |
| pycharm_runs/04_reproduce_random200.py | random200 全部 200 组 FP32/INT16 数值对照；不是 WER |
| pycharm_runs/05_reproduce_full_test_clean.py | 新冻结协议下完整 2620 条 test-clean 对照，约两小时 |

每次使用新输出目录。耗时为此前本机估计，不是固定保证；保持接通电源。

## 文件放在哪里

| 目录 | 用途 |
|---|---|
| asr_chip | 项目自己的数据、推理、量化和评估代码；包名保留以兼容已有接口 |
| third_party/espnet | **实际运行的网络源码**，可修改 encoder/decoder/attention 等实现；下一次启动生效 |
| configs | 当前基线配置及保留的历史研究配置，主配置为 asr_chip_baseline.json |
| artifacts | 原始预训练权重、INT16 权重及自动生成的当前运行配置 |
| data/LibriSpeech | dev-clean、test-clean 音频及转录 |
| data/manifests | 相对路径数据清单和音频校验信息 |
| data/random200 | random200_v1.zip，合成特征测试包 |
| experiments/layernorm_shift | 完整 LayerNorm 实验源码、测试和说明 |
| environment/envs/ASR | **Conda 环境本身**，不要手工移动、编辑包或删除 |
| environment | 依赖清单、安装/迁移记录和环境重建入口 |
| results/runs | 新执行的识别与比较结果 |
| results/migration | 本次整理后的验证记录 |
| history | 原始版本、原 README、迁移前结果和旧环境清单 |
| scripts、tests | 辅助脚本和自动化测试；部分 scripts 为保留的历史研究入口 |
| docs、licenses | 使用说明、历史报告、第三方许可证 |

model_source_original 仍是历史阅读副本，实际修改请到 third_party/espnet。legacy_script_notes、model_a_preexperiment、report_assets、streaming_fastconformer_validation_2026-08-25 为历史研究资料，不是当前 ASR 主流程。

## 命令行

在 Anaconda Prompt 中：

```bat
conda activate ASR
cd /d C:\Academic_Work\CIM_learning\ASR
python pycharm_runs\01_check_environment.py
python pycharm_runs\02_recognize_one_audio.py
python -B -m pytest tests -q -p no:cacheprovider
```

独立 LayerNorm 单元测试：

```bat
cd /d C:\Academic_Work\CIM_learning\ASR\experiments\layernorm_shift
python -B -m pytest tests -q -p no:cacheprovider
```

## 模型和数值边界

固定 Model A：12 层 Conformer encoder + 6 层 Transformer decoder，英语、16 kHz 单声道、离线整句。INT16 是权重存储，加载后继续使用 FP32 运算；没有 INT8 或新增训练。此次迁移不缩小网络，也不改变预训练权重和解码方式。

原软件完整 test-clean 的 WER 2.678028% 等历史成绩保存在 history，不能把复制文件视作新环境完整测试已经通过。当前迁移检查以 results/migration 和 docs/MIGRATION_ASR.md 为准。

## 环境与可迁移性

Conda 环境名 ASR，实际目录也在本工程。已将 environment/envs 加到当前用户 Conda 搜索路径，原 Conda 搜索路径保留，旧 ASR_chip 环境已删除。Python/PyTorch/ESPnet 来自固定旧环境与固定来源；ESPnet 以可编辑方式安装在工程内。

PyCharm、Conda 管理器、Windows 和 NVIDIA 驱动属于电脑软件，不打包到工程。Conda 环境含绝对路径；移动整个文件夹或换电脑后，必须重建环境并重新安装本地 ESPnet，不能当作任意拖动即用的绿色软件。

历史 docs 中的旧路径/环境名表示当时运行条件；当前运行以本 README 为准。旧 Docker/requirements.txt 属于历史流程，当前依赖以 environment/README.md 为准。
