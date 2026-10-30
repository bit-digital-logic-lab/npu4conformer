# ds_layout — V0.23 Layout 步进与突发

本目录是 `v023_repair` 批次的 Layout worker 交付。只做逻辑仿真；不综合、
不 Vivado、不上板、不 push。原 `work/` 与旧任务目录只读。

> **整体验收仍为 NOT PASS**（见 `../primary_acceptance/REPORT.md`）。本目录
> 只给 Layout 模块级证据，不沿用早期 PASS，也不代表整机/全模型通过。主验收
> 第 4 项“C48 跨缓存行”已在本目录定位、修复并给出负对照（REPORT §5.1）。

## 交付物

- `rtl/ddr_layout_engine_v023.sv` — 阶段 A：增量步进/stride 预计算，去运行期
  `u16_divmod`，仍 1-beat I/O（用于单独证明步进正确）。
- `rtl/ddr_layout_engine_v023_burst.sv` — **集成候选**：阶段 A + 16-beat
  posted 写突发 + 有界顺序读预取；新增参数 `MAX_PREFETCH`（默认 16，1=关闭）。
- `INTERFACE.md` — 端口、延迟、计数器语义、共享 DMA 契约、集成检查项。
- `REPORT.md` — 方法、结果表、II、4 KiB/边界/错误、未完成项。
- `FINDINGS.md` — 关键实测事实与限制。
- `result.json` / `progress.json` — 机器可读结果与阶段状态。
- `scripts/run_all.sh` — 一键复跑（顺序编译，避免抢资源）。

## 快速结果

| 套件 | 用例 | 结果 |
|---|---:|---|
| 官方 8 fixture | 8 | 8/8 逐字节；周期 671,563 → 397,315（0.592×） |
| 官方错误/ACL/lifecycle | 12 | 12/12 同结果 |
| 描述符 fuzz | 57 | 57/57 功能一致 |
| 独立 Python golden | 32 | 32/32 逐字节 |
| 随机合法 shape | 100 | 100/100 逐字节（周期 0.608×） |

官方合计写请求 11,890 → 746，读写 beat/字节数不变。读预取在某些
reuse-heavy im2col 会多读连续行（随机 9/100 例，最坏 +168 beat），已实测
报告；`MAX_PREFETCH=1` 可消除额外读（采样中读 beat 与原版逐项相等），周期
仍约 0.60×。

## 复跑

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_layout
./scripts/run_all.sh
```

结果汇总：`logs/FINAL_SUMMARY.txt`；每套件：`logs/official_table.log`、
`logs/layout_fuzz.log`、`logs/gold_table.log`、`logs/random_fuzz.log`、
`logs/prefetch_policy.log`。

## 边界

- 无 STA，因此不声称 Fmax/600 MHz；无 CDC。
- 共享 DMA 只给接口契约，仲裁器未实现/未联仿。
- 未跑完整 CASE0000；不宣称全模型时间或精度。
- Layout 不含浮点除/开根；W7p8/A16/C48/QDQ/clip 未改。
