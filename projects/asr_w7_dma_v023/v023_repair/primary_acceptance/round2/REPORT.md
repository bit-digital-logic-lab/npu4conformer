# 第二轮主复测

主独立复跑更新：primary_acceptance/round2/中FMA8734零失配、approx15168通过（DIV最大0.1114666%，SQRT5.78e-6、RSQRT5.72e-6，5拍II1）。新stream接新FMA BP2的tag/重复/数据已通过，但stream_param_port仍113失配，子项pass=false而run_suite整体rc0，禁止仅看exitcode。stream_reconfig通过。请核查param使能/参考契约，修脚本汇总使任一失败非零。流式仍不得最终PASS。

系统整合尚无最终通过结果。脚本退出码为0并不足以判定所有子项通过；已逐项读取JSON。
