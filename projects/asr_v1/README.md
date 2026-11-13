# ASR v1 — AXU15EGB 原生编码器发布候选

本次对外版本名为 v1，工作分支 asr-v1-release。工程来源是已实测的 ASR V0.24 原生 PS/PL 编码器；为保持可追溯性，原 work/v024_* 路径、RTL 模块名、镜像号 0xA51A2493 和历史报告标题保留。此次整理没有改变阵列、PE、算法或数值格式，也没有重新综合或上板。

## 2026-11-13 文件恢复补丁

请先读 [文件恢复与启动说明](DEPLOYMENT_V1.md)。**源码 ZIP 不包含位流、ELF 和权重**；另行下载 [v1 的 asr_v1_assets.zip](https://github.com/bit-digital-logic-lab/npu4conformer/releases/download/v1/asr_v1_assets.zip)，再双击本目录 `restore_assets.cmd` 选择附件，恢复并校验全部 68 个文件。

此分支补齐恢复工具和冷启动编排，修复部署脚本读取归档实现记录的路径。默认识别入口为 `mode=hybrid`，已经通过 `native_host → native_ps` 接入板端，无需设置可选插件的 `ASR_RESIDENT_ADAPTER`。当前板卡凭据由 `cold_start.cmd` 在原始读回校验通过后生成，不随源码分发，不从历史 evidence 复制。补丁离线验证见 `repair_validation.json`；新编排尚未实板复测。

`snapshot_manifest.json` 与 `package_validation.json` 保留为原 `v1` 标签的历史清单；当前补丁新增和覆盖的文件以 `repair_manifest.json` 为准，未列出的旧文件仍沿用原清单。

已发布的 `v1` 标签及原附件保持不变。获取补丁请下载 **asr-v1-release** 分支的最新源码；旧标签自动生成的源码 ZIP 仍是原始快照。

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

在源码的 `projects/` 目录内解压附件，将 ZIP 顶层 `asr_v1/` 与现有项目文件夹合并，也可以使用上面的恢复工具。校验 SHA-256 后再使用。部分工具路径、JTAG 串号及历史回执仍绑定原电脑；正式迁移须配置路径并执行一次新的冷启动验收。历史综合驱动还绑定具体完成记录，不是通用一键构建器。原 ACTIVE_BOARD_WEIGHTS.json 和 active_qualification.json 仅归档在 evidence，未放在活动运行位置。

原有 start.cmd 依赖项目内的 ASR/environment/envs/ASR 环境；本源码包未附该数 GB 环境。当前电脑原工作树不受影响，新位置需要按环境说明配置，不能因为文件已上传就宣称已能在新电脑直接识别。

## 验证及提交状态

2026-11-04 的打包阶段完成离线复核，随后源码与 v1 Release 已发布。原父综合 63 项输入、位流、DDR 权重与记录哈希一致；其他固定回归输入也按清单核对，并使用保存的原始矩阵读回进行独立数值校验。历史检查结果见 package_validation.json；2026-11-13 补丁的检查另见 repair_validation.json。两次打包修复均没有进行新的上板测量。

同条件优化前后基线、干净环境重建、实物照片及完整许可核对仍待补齐。现有报告的已验证结果、工程推断与待完成事项分别列出。2026-11-13 核查时仓库已公开；本补丁不改变可见性，也不为原工程或 AMD IP、第三方模型和数据授予新许可证。模型、ESPnet、数据和生成 IP 分别遵守其上游许可，原许可证和归属记录随包保留。
