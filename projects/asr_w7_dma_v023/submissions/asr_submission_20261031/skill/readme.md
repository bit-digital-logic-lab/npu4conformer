# 技能包与Roofline分析

traffic_ledger记录真实搬运并计算总读写Q、唯一区域及重复候选。module_activity_waveform展示同时间域的模块状态与任务窗口T；配合已核实的矩阵运算数N，计算Roofline点I=N/Q、P=N/T。

本次修复：旧trace中compute若明确来自busy标志，分析时归为busy并保留original_state，波形使用独立颜色；不修改原始trace。新增roofline.py要求独立带宽来源、同周期域、读加写字节与明确源记录，拒绝以任务Q/T反推roof及超过屋顶的矛盾点。

测试：搬运账本10项，活动波形8项，Roofline核算4项；另用真实trace核查busy分类及已知点位。两个技能各保留标准入口SKILL.md，这是技能运行规范所需；其他提交路径使用英文小写。

## 复现

在提交根目录执行：

```bash
bash build/reproduce_analysis.sh
```

工具自测不表示硬件性能或板级验证通过。当前Roofline是RTL/BFM矩阵局部测试与接口理论屋顶，不是完整ASR性能，也不是实测持续DDR带宽屋顶。
