# ds_critical_control

只读逻辑仿真任务：切断 `block_engine state_reg[3] -> storage/bad_reg` 的宽乘加+边界比较同拍锥，并分级 `ddr_layout_engine` 的非 2 幂 stride 地址链。

先读：

- `REPORT.md`：完整结论、证据、延迟/周期代价、理论下界修正。
- `FINDINGS.md`：关键路径逐级证据与候选分级。
- `INTERFACE.md`：交给主 agent 的端口/延迟/顺序/traffic-ledger 监视点契约。
- `result.json`：通过计数、哈希、限制。
- `BOUNDS.md` / `BOUNDS.json`：按读写拆分、DAG 依赖修正、PE/带宽匹配。
- `logs/`：真实复跑日志（storage 71-case 原/候选/diff、layout 20+51 case、block 集成、编译/lint）。

复跑：

```bash
./scripts/run_all_tests.sh
```

边界：未综合/未 Vivado/未 STA/未上板/未 push；`work/`、ZIP、其他任务目录只读；不声称任何频率已达到。Storage 候选优先集成；layout 候选有约 +10.7…+15.1% 元素周期代价，仅在更高频点/局部域收益能覆盖时使用。
