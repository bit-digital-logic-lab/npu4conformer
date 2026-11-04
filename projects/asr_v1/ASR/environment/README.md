# ASR 环境

环境名：ASR。

解释器：`C:/Academic_Work/CIM_learning/ASR/environment/envs/ASR/python.exe`。

本环境从已验证的 ASR_chip 复制，所有实际 Python 包均在本工程中；旧 ASR_chip 环境已于 2026-09-23 按要求删除。ESPnet 使用同一固定版本源码，执行 `python -m pip install --no-deps --no-build-isolation -e third_party/espnet` 后，实际代码位于工程内。

- `ASR-conda-explicit.txt`：Conda 包精确清单。
- `ASR-pip-freeze.txt`：新环境原始 pip 快照，其中 ESPnet 路径指向本工程。
- `requirements-ASR-lock.txt`：重建用 pip 清单，ESPnet 本地关联由重建脚本单独执行。
- `recreate.ps1`：在新位置/新电脑重建环境，拒绝覆盖现有环境。需要联网下载依赖，可能数 GB；只有明确需要重建时才运行。本次没有运行它。
- `migration/`：克隆日志、来源与文件校验、Conda 配置备份和安装日志。

正常使用不需重新安装。PyCharm 中选择现有环境的 python.exe 即可。

ASR 已注册到当前用户的 Conda 环境搜索目录；可用 `conda activate ASR`。如果在新的 Anaconda Prompt 中找不到名字，可用完整环境目录激活，或添加本工程 environment/envs 到 envs_dirs。

迁移记录保留安装前配置；本次只增加新的环境搜索目录，不删除原目录。若移除此工程，先从用户 .condarc 移除对应 envs_dirs 条目；不要覆盖你后来新增的其他配置。
