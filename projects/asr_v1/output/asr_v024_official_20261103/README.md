# ASR V0.24 官方指南修订材料

对应2026 AMD选题指南3.3自主选题高级组。目录包含修改后的汇报材料及随附的协作、技能和复现说明，不是完整可独立上板的工程发行包。RTL、位流、固件、模型参数及原始数据仍位于原工程中；完整提交包和干净环境从零复现尚待整理验证。正文可以使用中文；本轮新增业务文件使用英文小写名称。README.md按指南列出的文件名保留。

## 目录

- asr_v024_presentation_official.pptx 汇报演示稿
- asr_v024_design_report_official.docx 按技术模板整理的设计报告
- skill/ 可复用证据审计工具及已验证的输入样例
- report/ai_collaboration_excerpt.md 可见协作原始消息选摘
- report/skill_validation.json 离线技能验证结果
- report/reproduce.md 已核对入口、前置条件和待完成的复现工作
- report/requirements_alignment.md 指南条目、材料位置与当前缺口

## 与推荐工程目录的对照

指南 src/ 对应原工程 native_pl、native_ps、physical_native/rtl及冻结RTL目录；sim/ 对应既有regression和独立校验记录；build/ 对应physical_native及综合实现报告；board/ 对应board_test与部署脚本；data/ 对应native_model及测试数据；skill/为本包同名目录；report/为本包报告和协作材料。以上是当前目录映射，不表示已复制完整工程。发布副本仍需统一英文命名和相对路径并检验构建引用。

不在本轮修改或发布公共仓库，不替已有代码、模型及第三方IP擅自授予新许可证。指南强烈要求开源与可再分发协议，正式提交前应完成公开可达性和逐项许可核对。决赛英文A4海报须另用AMD官方附件模板，本材料不替代该海报。
