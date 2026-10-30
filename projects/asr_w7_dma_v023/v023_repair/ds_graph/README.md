# ds_graph — 全图 PL 自主编译候选

本目录是 V023 整改批次中 `ds_graph` worker 的隔离工作区。只读输入在
`../../work/`、`../../model_a_v0_22(1).zip`、`../../tasks/`；本目录所有文件都是新增。

## 快速结论

* 68 个闭合 CONV/FFN program 的边界 tensor 已做全局唯一地址分配；
* 591 条外层矩阵队列的台账（shape/param/cbase/cycles）已从 sealed 板级 result 恢复；
* 但原 ONNX / host executor / 591 真 Tensor 边不在本机，**不声称完整全图**；
* WCPG v2 控制器支持 1024 节点、1024-bit 依赖、一次 START/DONE、root provenance、输出保持；
* 68 控制计划 136/136、591 台账回放 591/591、小真实 LAY→ADD→MUL 64/64 word 通过；
* 仅逻辑仿真；不综合、不 Vivado、不上板、不 VNC、不 push。

## 目录

```
rtl/        wc_graph_ctrl.sv, wc_graph_top.sv
tb/         wc_graph_bfm.sv, tb_wc_graph_ctrl.sv, tb_wc_graph_real.sv
scripts/    source recovery, allocator, compiler, verifier, fixtures, run_all
analysis/   plans (.bin), tensor/descriptor/alloc maps, source ledger
tests/      mem_graph.hex, gold_small.hex
reports/    run_all logs + run_all.json
REPORT.md   详细结果、边界、非声明
INTERFACE.md WCPG v2 格式/端口/集成契约
FINDINGS.md 14 条发现
result.json 机器可读摘要
SOURCE_SHA.json 只读源与产物 SHA
```

## 复现

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_graph
python3 scripts/run_all.py
```

`run_all.py` 顺序执行 26 项检查/编译/仿真，无总超时；Verilator 只做 `-j 1` lint。

## 关键非声明

* 68/591 计划里的 SEQ/MAT 是控制 stub，不是算术证据；
* sealed V022 内部 queue/A/C 指针没有重写，不能直接把旧 payload 搬到新地址执行；
* 没有 591 真 DAG，没有完整 CASE0000，没有整机加速；
* 没有 STA/频率/板级 DDR 绕过声明；
* 没有实现除法/开根近似（用户已授权，但本任务未改 `asr_fp32_alu`）。
