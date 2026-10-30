# 项目 Skills

这里集中保存本项目可复用的技能、脚本及格式说明。

| Skill | 用途 | 入口 |
|---|---|---|
| traffic-ledger | 张量搬运、时间/周期、重复流量、忙闲归因 | [SKILL.md](traffic-ledger/SKILL.md) |
| module-activity-waveform | 模块活动与valid/ready/busy/done交互波形 | [SKILL.md](module-activity-waveform/SKILL.md) |

每个skill自带scripts/和references/；报告及运行产物放项目analysis/，不混入技能源码。当前目录是全局已安装技能的项目快照，不是软链接；以后项目内修改不会自动同步全局版本。全局版本位于/home/yang/.codex/skills/，供Codex发现和调用。文件哈希见MANIFEST.json。

## 快速运行

```bash
python3 skills/traffic-ledger/scripts/analyze.py TRACE.jsonl --out analysis/traffic
python3 skills/module-activity-waveform/scripts/render.py TRACE.jsonl --out analysis/activity.html
```

两个工具使用相同metadata/interval格式；多模块放同timebase前需证实采样域和epoch一致。缺观测标unknown，不当成idle。
