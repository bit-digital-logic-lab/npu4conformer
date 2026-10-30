# ds_ddr 交付索引

- `REPORT.md`：最终报告（baseline、DMA before/after、ping-pong、下界、整机自主、诚实边界）。
- `result.json`：机器可读汇总 + 输入/候选源码 SHA-256。
- `HISTORICAL_OPTIONS.md`：只读 Git 历史方案（commit/ref、文件、机制、采用/拒绝）。
- `docs/PL_AUTONOMY.md`：host/PS 依赖逐项迁移、节点表、graph runner、未实现项。
- `candidate/`：v020 多 outstanding DMA、A/W ping-pong、vector/layout v020 wrapper、graph runner 骨架。
- `INTERFACE.md`：DMA/ping-pong/BFM 端口、信用、错误排空、300/600MHz 寄存化建议与集成清单。
- `bench/bfm/axi128_ddr_bfm_ds.sv`：钉住的共享 AXI128 BFM 修正副本（shared 文件由外部维护，二者不混用）。
- `bench/`：BFM、TB、复跑脚本、日志；`bench/reports/` 为 JSON/BOUNDS 报告。

一键复跑（只读输入，不综合/不板卡/不联网）：

```bash
cd /home/yang/Desktop/项目/tasks/ds_ddr
bash bench/run_all.sh
```
