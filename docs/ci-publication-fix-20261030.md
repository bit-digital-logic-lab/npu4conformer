# 2026-10-30 发布检查修复

三次 ASR 快照提交已上传，但 `Offline engineering checks` 在文件清单检查失败，Python/RTL后续步骤被跳过。故障原因是新增项目与README后未同步 `docs/repository-manifest.json`；本地可复现 `File inventory differs`。

本次核对并保留新增文件，更新完整清单；不禁用workflow、不缩小检查范围、不把生成失败证据改成PASS。新增 `tools/verify_before_push.py` 复用现有门禁，清单仍须人工审查后显式刷新。GitHub 远端提交存在与CI通过是两件需要分别核验的事。

测试结果以本次提交对应的云端 Actions 和本地控制台为准。这个发布修复不改变RTL数值行为，不代表完整模型、所有优化分支、时序或板卡已验收。仓库继续私密。
