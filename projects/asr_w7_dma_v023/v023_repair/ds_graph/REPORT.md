# REPORT — 全图 PL 自主编译（V023 candidate，逻辑仿真）

日期：2026-10-29  
任务：`v023_repair/ds_graph`  
范围：逻辑仿真 / 离线编译；**不综合、不 Vivado、不上板、不 VNC、不 push**。  
本报告不修改 `work/`、旧竞赛仓库、ZIP 或其他 worker 目录。

## 1. 一句话结论

在现有只读材料中，**外层 591 个矩阵队列的“台账”可以恢复**（形状、参数 ID/地址、C 地址、实测周期），但**原 ONNX 图、Tensor 名依赖边、host executor 不在本机**，因此不能诚实地重建“完整模型张量 DAG”。本任务完成了：

1. 68 个闭合程序的**真实边界张量全局分配**（68 个输入 + 68 个输出，全部唯一地址）；
2. 591 条台账任务的**唯一 A/C 地址分配**，并用 host 顺序回放做控制级验证；
3. 一个 1024 节点、1024-bit 依赖掩码的 WCPG v2 控制器：一次 START → PL 取 header/nodes/payload → 按依赖发射 → 引擎 DMA → 一次 DONE/IRQ；
4. 根节点输入出处检查、输出保持、分配器冲突负例、坏 hash/前向依赖/无输出负例；
5. 一个小真实算子图（IN→LAY copy→VEC ADD→VEC MUL）用 sealed `ddr_layout_axi`/`ddr_vector_axi`/`asr_fp32_alu` 跑通，64/64 word 与 Python float32 golden 一致；
6. 68 节点控制计划和 591 节点台账回放计划各一次 START、一次 DONE，全部节点完成。

**没有**声称：完整 CASE0000、完整 591 真数据流、矩阵算术、FMA/op17、整机加速、600 MHz、板级 DDR 绕过。详见 §8。

## 2. 只读输入与缺失输入

### 2.1 实际找到的材料

| 材料 | 位置 | 用途 |
|---|---|---|
| sealed V022 ZIP | `项目/model_a_v0_22(1).zip` PRG | 板级结果、参数镜像、68 program manifest |
| `parameters002` | ZIP / `work/assets/parameters002` | 173,715,968 B 镜像，SHA `fc36806a…` |
| 68 program manifest | ZIP member / `tasks/ds_pl_autonomy/assets/manifest_v022.json` | 45,055 instructions、6,231 matrix descriptors、tensor 名/QDQ 边界 |
| 板级 case0000 结果 | ZIP member `reports/case0000_board001/result.json` | **591 task ledger**：m/k/n、param_id/param_B_address、cbase/cbytes、queue cycles |
| 70 个旧 RTL | `work/rtl/` | 只读复用 `axi_dma_v019`、`ddr_vector_axi/engine`、`ddr_layout_axi/engine`、`asr_fp32_alu`、`u16_divmod` |
| `ds_pl_autonomy` 候选 | `tasks/ds_pl_autonomy/` | 只读参考 128 节点 WCPL v1 控制器、68 program 分析、BFM |

`analysis/source_ledger.json` 记录 ZIP、manifest、result member 的 SHA-256。  
`SOURCE_SHA.json` 记录只读源与本地新增文件的 SHA-256。

### 2.2 仍未找到的输入（不能虚构）

有界本地搜索（`software4npu`、`当前工程文件`、`项目`，排除 venv/site-packages，未下载/未远控）没有找到：

* `lowbit_executor.py`（host 图执行器/Tensor 类）
* `profiled_backend.py`（591 queue 的 host 调度来源）
* `vm_abi.py`
* 可用的原模型 ONNX（唯一 `.onnx` 是 ESPnet 第三方 `silero_vad.onnx`，与本模型无关）
* 板级结果里记录的 `D:\program\python\ASR-ONNX\software4npu\temp\model_a_fpga_vectors\...`（本机无 D 盘）

因此：

* **591 台账的 shape/参数出处是完整的**（111 条有精确 `param_name`；480 条动态 MatMul 没有静态参数，只能按 host 顺序/邻居层归属到 20 个 owner 组）；
* **591 的 Tensor 级依赖边不完整**，本任务不把它称为 DAG；
* 68 个 program 的输入全部是“外部边界张量”（68 个不同 tensor 名，但旧 host 只用了 4 个重复地址），不是 68 内部互相生产；
* 完整 CASE0000 的 host 控制流仍无法从本机材料下降。

## 3. 外层 591 队列与非矩阵算子的来源

### 3.1 591 台账结构

`analysis/outer591_ledger.json` 逐条保存：

```
index, m,k,n, mt,nt,kt,
queue_base, queue_count, cbase, cbytes,
param_id, param_B_address, param_name, param_shape,
a_bytes_q16 = m*k*2, c48_bytes = cbytes,
queue_cycles, compute_cycles, dma_read_bytes, dma_write_bytes
```

`analysis/outer591_groups.json` 按 `param_name` 的前缀得到 20 个 owner 组：

| owner | 任务数 | 说明 |
|---|---:|---|
| `encoder//encoder/embed` | 1 | subsampling 输出投影 |
| `encoder//encoder/encoders.0..11` | 12 × 29 = 348 | 每层 29 个队列 |
| `decoder//decoders.0..5` | 6 × 40 = 240 | 每层 40 个队列 |
| `decoder//decoder/output_layer` | 2 | 输出 Gemm |
| **合计** | **591** | 与板级 `native_matrix_queues=591` 一致；`queue_count` 合计 593 descriptors |

每层 29/40 是**从参数名与 host 记录顺序得到的结构归属**，不是从 ONNX 边恢复的依赖。  
`analysis/outer591_ledger.json` 的 `inferred_owner` 字段对 480 条动态任务只声明“属于哪一层”，不声明它的 A 来自哪个 tensor。

### 3.2 非矩阵算子

板级 result 的 stage 计数（原样引用，未从 ONNX 重算）：

| 算子 | encoder | decoder |
|---|---:|---:|
| MatMul | 97 | 72 |
| LayerNormalization | 61 | 19 |
| Softmax | 12 | 12 |
| Div | 25 | 12 |
| Sigmoid | 24 | 0 |
| Add | 159 | 67 |
| Mul | 74 | 1 |
| Q/DQ | 646/646 | 272/272 |
| V211Subgraph | 62 | 6 |
| 动态执行节点 | 2,601 | 1,016 |
| 静态折叠节点 | 1,879 | 727 |

`analysis/nonmatrix_tensor_names.json` 从 manifest directory 的 static/QDQ tensor 名中抽取了这些算子的可见 tensor 名示例（仅名字，不造边）。  
这些非矩阵算子当前仍在 host/legacy DAG；本任务没有把它们全部下降成 PL 节点，也没有声称完成。

## 4. 全局张量、版本、生命周期、地址分配

### 4.1 分配对象

`analysis/global_alloc.json` 共 **1,318** 个 tensor：

| 类 | 数量 | 地址区域 | 说明 |
|---|---:|---|---|
| 68 program 输入（Q16） | 68 | external `0x08000000..0x10000000` | 全部唯一 |
| 68 program 输出（FP32） | 68 | external | 全部唯一 |
| 591 台账 A（Q16） | 591 | arena `0x03000000..0x08000000` | 全部唯一 |
| 591 台账 C48 | 591 | arena | 全部唯一 |
| 68 program 临时区 | 1 个共享 extent | arena | **scheduler-exclusive** |

结果：

* arena 使用 56,570,880 B，剩余 27,315,200 B；
* external 使用 15,545,344 B；
* **同时活跃的地址冲突 = 0**（`check_alloc.py` 独立检查）；
* 旧地址中“同 base 但不同 tensor”的对数 = 225,310（含 591 A 共用旧 queue_base）；其中 live 区间同时重叠的 = 2,413。这些正是局部 arena 复用造成的假冲突来源。
* 旧 68 程序之间的 WAW/RAW/WAR 对数为 **2,278 / 2,278**（只读引用 `ds_pl_autonomy` 的分析），本任务通过唯一边界地址 + 共享 temp 的串行所有权消除了“地址重叠但语义不冲突”的混淆。

### 4.2 为什么不给 68 个程序各分一份 temp

68 个程序的 temp extent 合计 **126,382,080 B**；单份最大 **30,277,632 B**。  
80 MiB arena（83,886,080 B）连两份最大 temp + 591 A/C（26,287,872 B）都放不下：

```
2 * 30,277,632 + 26,287,872 = 86,843,136 B > 83,886,080 B
```

所以“给每个子图一个唯一 temp_base”只是把冲突搬到地址上，并不能让 68 路并行成立。本任务的正确做法是：

* 边界 tensor 全局唯一；
* 68 个 SEQ program 由**一个 SEQ 引擎**串行拥有共享 temp；
* 若未来要并行，需要片上 residency / 更大 arena / 真正分块，而不是改地址。

这是一个**负结果**，已写入 `analysis/global_alloc.json` 的 `shared_temp` 和 `FINDINGS.md`。

### 4.3 版本与生命周期

每个 tensor 记录 `live=(start,end)`、`version`、`owner`、`old_addr`、`base/bytes`。  
68 输入 live `[0,i+1]`，输出 live `[i+1,68]`；591 A live `[i,i+1]`，C live `[i+1,i+2]`。  
`analysis/tensor_map.json` 是 trace/fusion 使用的 tid→地址/大小/生命周期/版本表；  
`analysis/descriptor_map.json` 是 plan node→tid/依赖/地址的映射；  
`analysis/relocation_map.json` 记录 old→new 边界与 temp 偏移，并明确：

> sealed V022 plan 内部的 `0x03000000` queue/A/C 指针没有在本任务重写；  
> 新全局地址用于 WCPG 控制图和集成期 re-lowering，直接把旧 payload 搬到新地址执行会是数据破坏 bug。

## 5. WCPG v2 控制器与一次 START/DONE

### 5.1 格式

`rtl/wc_graph_ctrl.sv`，header 64 B + N×192 B node，N≤1024：

* header：magic `WCPG`、version `0x00020001`、node_count、flags、param_end、plan_bytes、generation、FNV-1a hash、input window；
* node：magic `WCGN`、type `{MAT,VEC,LAY,SEQ,IN}`、id、flags（root/output/external/retained/synthetic-order）、base/count、input_tid/output_tid、input/output base/bytes、version、epoch、**32 word / 1024-bit predecessor mask**；
* 只允许指向更低编号的前驱；forward dependency 在 fetch 时拒绝。

### 5.2 行为

1. 一次 `START`，校验 plan 边界/对齐/parameter_ready/generation；
2. PL 通过 fetch DMA 读 header（4 beat）和每个 node（12 beat）；
3. 校验 magic/id/reserved/forward-dep/FNV hash；
4. 根节点必须 `dep_mask==0` 且 `input_base/input_bytes` 落在 param/arena/external 可读窗口；
5. 有 output flag 的节点必须有非零 `output_tid` 和可读 `output_base`；
6. 每周期扫描一个 node（不是 1024 路组合 scan），依赖满足后按类型发射到 SEQ/MAT/VEC/LAY；IN 节点在 scan 中直接完成；
7. VEC/LAY 先 PL fetch payload（4/8 beat），做 ACL/overlap 检查，再交给真实引擎；
8. 错误时停止新发射，排空已接受引擎，再给一次 DONE/IRQ；
9. DONE 后**不清 done_mask、不清输出存储**；`output_retained`、`last_output_tid/base/bytes` 保持。

### 5.3 集成 top

`rtl/wc_graph_top.sv`：

* 一个 fetch DMA；
* 真实 `ddr_vector_axi` + `ddr_layout_axi`；
* 外部 matrix handshake；
* 外部 SEQ handshake（便于接 sealed `pl_execution_plan_v022` 或控制 stub）；
* 没有第二份算术；没有隐藏 host 逐算子控制。

## 6. 测试与证据

所有日志：`reports/run_all/`；汇总：`reports/run_all/run_all.json`。  
`run_all.py` 顺序执行，无并行编译；Verilator 仅 `-j 1` lint，不做综合/STA。

### 6.1 26/26 通过

| # | 测试 | 结果 |
|---:|---|---|
| 1–5 | 恢复 591 台账 / 分配 / 编译 / fixture / allocator 检查 | rc=0 |
| 6–8 | 68 计划 / 591 计划 / small real 计划静态验证 | rc=0 |
| 9–12 | bad root / no output / bad hash / forward dep **拒绝** | rc=0（预期拒绝） |
| 13–14 | Icarus 编译 control / real | rc=0 |
| 15–23 | control mode 0..8（含 child fault drain） | rc=0 |
| 24 | real mode 10 | rc=0 |
| 25–26 | Verilator lint ctrl/top | rc=0 |

### 6.2 控制级（stub engine，**不是算术**）

| mode | 负载 | 结果 |
|---:|---|---|
| 0 | 4-node IN→LAY→VEC→VEC（stub） | 4/4，193 cycles，1 DONE，out_ret=1 |
| 1 | **68 真实 program 的全局控制计划**：68 IN + 68 SEQ = 136 nodes | 136/136，4,556 cycles，1 DONE，68 outputs |
| 2 | **591 台账 host-order replay** | 591/591，367,846 cycles，1 DONE，1 output |
| 3 | root 无输入出处 | fault `0x08`，0 dispatch |
| 4 | 无 output | 4/4 后 fault `0x0A` |
| 5 | bad hash | fault `0x04`，0 dispatch |
| 6 | forward dependency | fault `0x04`，0 dispatch |
| 7 | 输出保持 | 完成后 `0x04002000` 的 `0xdeadbeef` 未被清除，`last_output_base/bytes` 保持 |
| 8 | child fault + drain | LAY stub 报 `0x55`；控制器停止发射、排空后一次 DONE，`drain_cycles=2` |

mode 1 的 68 个 SEQ 节点是**68 个独立根**（每个依赖自己的 IN），不是“68 串行冒充完整”；但引擎只有一个 SEQ，所以执行仍串行。  
mode 2 的 590 条边是 **synthetic host order**，不是恢复的 tensor 依赖；报告和 `descriptor_map.json` 都标注了这一点。

### 6.3 真实算术链（sealed RTL）

mode 10：

```
IN (param 0x10001000, 64 word float32)
  -> real ddr_layout_axi COPY -> arena 0x04000000
  -> real ddr_vector_axi ADD 1.0 -> 0x04001000
  -> real ddr_vector_axi MUL 2.0 -> 0x04002000
```

结果：`WC_GRAPH_REAL_PASS`，4/4，2,357 cycles，64/64 word 与 Python float32 golden 一致；  
真实 layout/vector 引擎均被激活（lay 790 cycles，vec 1,381 cycles），数据 DMA 有读写 burst；DONE 后从 `0x04002000` 读回 64 word 校验。  
没有使用 FMA/op17；FMA 仍是 forbidden stub，且未被调用。

### 6.4 分配器负例

`analysis/alloc_check.json`：

* 正常分配：0 live conflict；
* 人为把两个 live 输出放到同一 base：`negative_detected=true`，检查器报 `live tensors share base`；
* 因此“所有冲突都被消除”不是只看正常样本得出的。

## 7. 与旧候选/接口的复用

* 复用 `ds_pl_autonomy` 的 68 program 分析、sealed V022 plan 指针、真实 vector/layout 引擎接法；
* **没有直接复制** 128 节点 WCPL v1 控制器：591 需要 1024 节点/1024-bit mask，v1 的 128-bit mask 和 128-entry 寄存器文件不够；
* 复用 `axi_dma_v019`，保留其单 outstanding/≤16 beat 行为；本任务不声称多在途 DMA；
* W7p8/A16/C48、低 bit 位置、clip、QDQ 边界、FP32 FTZ/RNE/FMA 顺序均未改；
* 已读本目录 `USER_UPDATES.md`（用户允许除法/开根近似）。本任务没有改 `asr_fp32_alu`，因此没有实现近似版本、没有误差实测数据；旧精确除法/开根只作为基线，未把差异判成 bug，也不声明任何精度门槛通过。

## 8. 明确未完成 / 非声明

| 项 | 状态 |
|---|---|
| 原 ONNX / host executor / profiled backend | **缺失**，未下载/未远控 |
| 591 真 tensor 依赖 DAG | **未恢复**；只有 owner 组 + host 顺序 |
| 591 矩阵算术 / W7+A16+C48 | **未执行**；MAT 是控制 stub |
| 68 V022 真实 payload 在新全局地址下执行 | **未执行**；只做控制计划，未 re-lower sealed payload |
| FMA/op17 / 严格 ONNX 输出 | **未测试**（netlist 缺失，stub 禁止） |
| 完整 CASE0000 / 整机加速 | **未运行/未声明** |
| 300/600 MHz / STA / 综合 / 板卡 | **未运行/未声明** |
| PS 硬 DDR 控制器真正绕过 | **未实现**；逻辑模型是独立 AXI slave；板级仍经 PS HP 端口 |
| CDC / 异步 FIFO 独立验证 | **未实现**；本任务没有假设异步 FIFO 存在 |
| 16-beat 本身 | 不当作问题；没有以“16 beat 必差”为前提 |
| 600 MHz 局部域 | 只是一个未来目标；本任务无 STA，不声称可达 |

## 9. 复现

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_graph
python3 scripts/run_all.py
```

单独跑：

```bash
python3 scripts/explore_sources.py
python3 scripts/allocator.py
python3 scripts/compile_graph.py
python3 scripts/make_fixtures.py
python3 scripts/check_alloc.py
python3 scripts/verify_graph.py --plan analysis/whole68_global.bin \
  --alloc analysis/global_alloc.json
python3 scripts/verify_graph.py --plan analysis/ledger591.bin \
  --alloc analysis/global_alloc.json
python3 scripts/verify_graph.py --plan analysis/small_real.bin
iverilog -g2012 -s tb_wc_graph_ctrl -o /tmp/ctrl.vvp \
  rtl/wc_graph_ctrl.sv ../../work/rtl/axi_dma_v019.sv \
  tb/wc_graph_bfm.sv tb/tb_wc_graph_ctrl.sv
vvp /tmp/ctrl.vvp +mode=1 +memfile=tests/fixtures/mem_graph.hex +seed=7
vvp /tmp/ctrl.vvp +mode=2 +memfile=tests/fixtures/mem_graph.hex +seed=7
```

`run_all.py` 不设总超时；所有编译/仿真顺序执行；Verilator 仅 `-j 1` lint。

## 10. 集成建议（下一阶段）

1. 找到原 ONNX / executor 后，用同一 WCPG v2 格式重建 591 真边；不要沿用 synthetic host order。
2. 若要让 68 并行，先解决 temp residency（当前 2×30.3 MB 已超 80 MiB），不要只改地址。
3. 把 sealed V022 plan 做一次真正的 re-lowering：把 queue/A/C/temp 绝对地址映射到 `global_alloc.json`，再执行矩阵算术；本任务没有做这一步。
4. 接 `pl_execution_plan_v022` 作为 SEQ 引擎时，保持其单 START/单 DONE/错误 drain 语义；WCPG 只负责图级调度。
5. 若未来要 250–600 MHz，先对 1024-bit 依赖检查和 fetch/hash 做寄存/分bank；本任务没有 STA，不能声称频率。
