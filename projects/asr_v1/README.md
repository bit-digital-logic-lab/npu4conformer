# ASR v1 — AXU15EGB 原生编码器发布候选

本次对外版本名为 v1，工作分支 asr-v1-release。工程来源是已实测的 ASR V0.24 原生 PS/PL 编码器；为保持可追溯性，原 work/v024_* 路径、RTL 模块名、镜像号 0xA51A2493 和历史报告标题保留。此次整理没有改变阵列、PE、算法或数值格式，也没有重新综合或上板。

## 已有实测范围

AXU15EGB / XCZU15EG-FFVB1156-2-I；Vivado/XSDB 2025.2；16×16 物理阵列，W7p8 / A16 / C48；实际 PL 时钟 48.484848 MHz。12 层 Conformer 编码器在 PS 与 PL 执行，电脑只承担 CPU log-Mel 与 greedy CTC，无 GPU 编码器。当前传输是 JTAG/DAP。电脑仍会接收编码特征执行 CTC；网口识别、300 MHz、实时识别、完整语料 WER 和陌生环境从零复现均未验收。

已有冷复位首个 7 节点算例：8192 个原始输出字独立校验通过，18833 周期，按实际时钟约 0.388431 ms；此数不代表完整语音耗时。2.68 秒原始短句的板内编码约 10.290 秒；20 秒双窗口演示是由两条已知短句与静音组成，尚未实时。详细口径见随附报告和原始记录。

## 目录与内容

| 路径 | 内容 |
|---|---|
| work/v024_ddr_resident/ | 原生 PS/PL 控制、固件、模型导出、CPU 前端/CTC、浏览器录音 UI |
| work/v024_deploy_20261101/ | 启动汇编、独立校验器、冻结 RTL/IP/仿真参考、当前父综合所用依赖 |
| ASR/asr_chip/ | 固定模型获取及软件包装源码 |
| ASR/third_party/espnet/ | 已使用版本的 espnet2、espnet3 Python 包源码及上游许可；当前前端使用 espnet2 |
| ASR/environment/ | 重建环境所需清单与说明；不含安装好的 Python 环境 |
| ASR/licenses/ | 既有第三方许可和来源记录 |
| evidence/ | 原始日志、读回及验收记录的归档，包含历史尝试；不能用来冒充本轮冷启动验收 |
| output/asr_v024_official_20261103/ | 原样保留的 PPT、DOCX、技能包、协作消息摘录与比赛要求对照 |
| release_assets.json | 另行上传到 GitHub Release 的二进制/模型附件清单与 SHA-256 |
| snapshot_manifest.json | 本源码快照的文件及原始来源对应关系 |

## 二进制与复现边界

asr_v1_assets.zip 与源码一起组成此次发布候选。附件包含已验收位流、已有 ELF、DDR 权重、原模型固定资源、综合/布线检查点及大型原始数据；附件内容清单见 release_assets.json。它不是可双击安装的 Python/Vivado 环境。该 ZIP 应作为 GitHub Release 附件上传，不能当普通源码提交。

在 projects 目录旁解压 ZIP 时，其顶层 asr_v1/ 与源码项目文件夹同名，文件按保存的相对路径合并。校验 SHA-256 后再使用。原文件均原样保留，因此部分工具路径、JTAG 串号及历史回执仍绑定原电脑；正式迁移须配置这些路径并执行一次新的冷启动验收。历史综合驱动还绑定具体完成记录，不是通用一键构建器。原 ACTIVE_BOARD_WEIGHTS.json 和 active_qualification.json 仅归档在 evidence，未放在活动运行位置。

原有 start.cmd 依赖项目内的 ASR/environment/envs/ASR 环境；本源码包未附该数 GB 环境。当前电脑原工作树不受影响，新位置需要按环境说明配置，不能因为文件已上传就宣称已能在新电脑直接识别。

## 验证及提交状态

本次只做本地打包和离线复核，没有写 GitHub，没有改变工作分支或进行 commit/push，没有操作开发板。当前父综合 63 项输入、位流、DDR 权重与原记录哈希一致；其他固定回归输入也按清单核对。使用保存的原始矩阵读回进行独立数值校验。检查结果见 package_validation.json。

同条件优化前后基线、干净环境重建、实物照片及完整许可核对仍待补齐。现有报告的已验证结果、工程推断与待完成事项分别列出。当前目标仓库为私有；本次不为原工程或 AMD IP、第三方模型和数据授予新许可证，也不改变仓库可见性。模型、ESPnet、数据和生成 IP 分别遵守其上游许可，公开前需核对再分发条件。原许可证和归属记录随包保留。
