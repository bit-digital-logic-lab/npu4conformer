# ds_storage_write — V0.24 Matrix C48 写合并 + 地址校验寄存级

本目录只写本任务。`v023_repair/`、`work/`、ZIP 和其他 worker 目录全部只读。
仅逻辑仿真：未综合、未 Vivado/STA、未上板、未 VNC、未 push；不承诺频率或
整模型秒数。

## 任务

基于 `v023_repair/ds_matrix` 的 `block_storage_stream_v2` / `axi_dma_v020_multi_v2`：

1. 多角度复现 `long_wait`（48 拍存储响应）下的矩阵反向退化与 `COLLECT` 气泡；
2. 合法连续 C48 段写合并：每次写请求 ≤16 beat、不跨 4 KiB、按行 stride 识别，
   非该布局保留 generic 路径；
3. 让 `cseg` 与首拍 `cval` 同拍接收（或 metadata FIFO），减少每 16 个 C 值一次
   的命令气泡；
4. 把 `ld_expected = base + row*ncols*block_bytes + col*block_bytes` 的宽乘加、
   64-bit 比较拆成寄存器级流水，不是只打拍输入；
5. metadata 对齐、背压无丢包，计 cmd/beats/B credits/collect stall；
6. 新旧 RTL 使用同一 BFM、同一输入、同一完成/排空边界；旧 C、多 K、多 N、
   byte 有效 mask、fault/abort 契约都要过；独立 gold，失败非零。

## 快速复跑

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_storage_write
bash scripts/run_all.sh          # 每个仿真有 timeout watchdog；失败即非零
python3 scripts/collect_metrics.py
```

## 目录

```text
rtl/                 候选 RTL + 未改动参考模块（SHA 见 REFERENCE_SHA256.json）
tests/               testbench / 独立 gold 生成器 / BFM
fixtures/            冻结的引擎输入与独立整数 gold
scripts/             run_all.sh、collect_metrics.py
logs/                本次运行日志、commands.log、metrics.txt
reports/             长等待复现的分角度原始 CSV/JSON
REPORT.md            最终报告
result.json          机器可读结果（rc/SHA/测了什么/未完）
filelist.txt         候选唯一编译 filelist
```
