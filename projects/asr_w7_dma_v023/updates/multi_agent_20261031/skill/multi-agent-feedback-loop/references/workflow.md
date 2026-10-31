# 协作合同与反馈记录

| 角色 | 任务 | 交付或反馈 |
|---|---|---|
| GPT | 拆分、分发、整合、判断下一轮 | 子任务合同与候选版本 |
| DeepSeek | 实现与数据整理 | 差异、运行命令和证据路径 |
| Gemini 3.8 Flash | 并行实现与辅助分析 | 独立工作产物与范围说明 |
| Gemini 4 Argon | 架构、数据流和证据范围复核 | 问题位置、影响与验证条件 |
| Claude | 代码、数值及测试口径交叉复核 | 可复现问题与验收条件 |

每次事件至少记录task_id、round、event、source_sha、input_hash、artifact_paths、command_exit_code、review_status、issues和time。只有该候选SHA的所有必要测试与独立复核通过，才能触发acceptance_passed。没有调用返回与日志时，模型角色状态为未执行。

默认最大3轮是建议的有界流程设置，可按任务成本调整，不代表实际模型调用预算。钩子事件是设计接口，不是已经安装的自动服务。
