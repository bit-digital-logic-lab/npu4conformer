# 2026年10月31日ASR封存资料发布入口

目标仓库为组织bit-digital-logic-lab下的npu4conformer，要求保持Private。

[完整目录](../projects/asr_w7_dma_v023/submissions/asr_submission_20261031/readme.md)包含源码、测试输入与日志、修复后的技能、Roofline图、设计报告、约104秒讲稿及无封面PPT。整改方案待实施，不作为当前代码收益。

封存目录逐文件保留原始字节与manifest_sha256.json。目录内archive_status中的github_pushed=false描述的是推送前的封存时点，不是仓库发布状态。发布状态以GitHub提交与本发布入口为准。原有工程与冻结版本不覆盖。

本次资料包验证为22项技能自测、分析重算通过；11项统一小图RTL命令返回0且独立判定通过。这不证明完整ASR模型或板级性能。仓库既有Python与RTL门禁另行执行，不将它们当成专用性能点的新测量。

提交目录中的build为复现入口，日志为精选证据，故显式纳入版本控制；编译二进制、模型权重、位流和虚拟环境不上传。冻结历史RTL与自动生成SVG保留原始空白，避免修改其校验值。
