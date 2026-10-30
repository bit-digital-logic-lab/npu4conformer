# INTERFACE — WCPG v2 全图控制计划 / 全局 tensor map

本文件是 `ds_graph` 新增模块的集成契约。只读的 V022 RTL/参数/数值语义不在此修改。

## 1. 新增文件

| 文件 | 作用 |
|---|---|
| `rtl/wc_graph_ctrl.sv` | 1024 节点 WCPG v2 控制器：header/node/payload fetch、1024-bit 依赖、IN/MAT/VEC/LAY/SEQ 发射、root provenance、output retention、drain、单 DONE/IRQ |
| `rtl/wc_graph_top.sv` | 控制器 + fetch DMA + 真实 `ddr_vector_axi`/`ddr_layout_axi` + 外部 matrix/SEQ handshake |
| `tb/wc_graph_bfm.sv` | 独立 AXI128 逻辑 BFM（scratch/intermediate/external/param 四个窗口；param 写致命） |
| `tb/tb_wc_graph_ctrl.sv` | 控制级测试：68 计划、591 台账、负例、输出保持；引擎是 stub |
| `tb/tb_wc_graph_real.sv` | 真实 LAY→ADD→MUL 算术链；使用 sealed 引擎 |
| `scripts/explore_sources.py` | 从 sealed ZIP/manifest/result 恢复 68 + 591 台账 + 缺失输入清单 |
| `scripts/allocator.py` | 全局生命周期/地址分配、共享 temp 策略、负例 |
| `scripts/compile_graph.py` | 生成 `whole68_global.bin`、`ledger591.bin`、`small_real.bin` 及负例 |
| `scripts/verify_graph.py` | 独立 plan/依赖/root/output/alloc 交叉验证 |
| `scripts/check_alloc.py` | 独立分配检查 + 冲突负例 |
| `scripts/make_fixtures.py` | BFM 1 MiB 稀疏镜像与真实链 golden |
| `scripts/run_all.py` | 顺序复跑全部测试，写 `reports/run_all/` |

## 2. 物理 DDR 边界

逻辑模型中 DDR 是独立 AXI slave（`wc_graph_bfm`），不是板级 DDR 时序模型。  
实际板级 V022 仍经 `ps/S_AXI_HP0_FPD`（PS hard DDR controller）；本任务：

* **PS CPU 不参与运行期数据流**（计划/输入预装后，控制器自主 fetch/dispatch）；
* **没有绕过 PS 硬 DDR 控制器**，也没有 MIG/external DDR 适配；
* 不声称 250/300/600 MHz 或板级带宽。

## 3. WCPG v2 二进制格式

所有 word 为 little-endian 32-bit。

### 3.1 Header：64 B / 16 words

| word | 字段 | 要求 |
|---:|---|---|
| 0 | magic `0x57435047` (`WCPG`) | 精确 |
| 1 | version `0x00020001` | 精确 |
| 2 | node_count | 1..1024 |
| 3 | flags | bit0 param-RO，bit1 generation，bit2 要求 root provenance，bit3 要求至少一个 output |
| 4 | param_end | `<= 0x40000000`；plan/payload 必须在 `[PARAM_BASE,param_end)` 或 external 窗口 |
| 5 | plan_bytes | `64 + 192*node_count` |
| 6 | generation | 0=忽略；否则必须等于运行期 generation |
| 7 | hash | FNV-1a，覆盖 header words 0..6,8..15 和所有 node words |
| 8 | input window base | 当前为 `0x08000000` |
| 9 | input window limit | 当前为 `0x10000000` |
| 10..15 | reserved | 0 |

hash 是完整性检查，不是签名。

### 3.2 Node：192 B / 48 words

| word | 字段 | 说明 |
|---:|---|---|
| 0 | magic `0x5743474e` (`WCGN`) | 精确 |
| 1 | type | 1 MAT, 2 VEC, 3 LAY, 4 SEQ, 5 IN |
| 2 | node_id | 等于数组下标 |
| 3 | flags | bit0 root, bit1 output, bit2 external, bit3 retained, bit4 synthetic-order |
| 4 | base | MAT: queue base；SEQ: V022 plan base；VEC/LAY: payload；IN: data base |
| 5 | count | MAT: queue count；SEQ: instruction count；VEC/LAY: 0 |
| 6 | input_tid | 全局 tensor id（provenance/trace） |
| 7 | output_tid | 全局 tensor id；output 节点必须非 0 |
| 8 | input_base | 根节点输入出处；必须可读 |
| 9 | input_bytes | 非 0 |
| 10 | output_base | output 节点必须可读 |
| 11 | output_bytes | 非 0 |
| 12 | version | tensor 版本（当前 1） |
| 13 | epoch | 信息字段 |
| 14..15 | reserved | 0 |
| 16..47 | predecessor mask | 1024 bit；bit i = node i；只允许更低编号 |

### 3.3 依赖/root 规则

* 只允许 `dep_mask & ~((1<<id)-1) == 0`；前向边/环在 fetch 时拒绝（`0x04`）。
* 根节点必须 `dep_mask==0` 且 `input_base/input_bytes` 可读（param/arena/external）。
* IN 节点必须是 root，`output_base/output_bytes` 可读。
* output 节点必须有 `output_tid!=0` 且 `output_base/output_bytes` 可读。
* 非根节点必须有前驱；没有前驱且非 IN 会被拒绝。
* DONE 后不清 `done_mask`，不清输出存储；`output_retained/last_output_*` 保持到下次 START。

### 3.4 错误码

| code | 含义 |
|---:|---|
| 0x01 | START/plan 边界/对齐/parameter 未 ready |
| 0x02 | parameter_ready 丢失或 generation 变化 |
| 0x03 | fetch DMA 错误 / beat 数不符 |
| 0x04 | magic/id/type/reserved/前向依赖/hash 错误 |
| 0x05 | 子引擎 fault 无错误码 |
| 0x07 | VEC/LAY payload ACL/overlap 失败 |
| 0x08 | root provenance / root 有前驱 / IN 缺 root |
| 0x09 | fetch/operation watchdog（保留） |
| 0x0A | 要求 output 但没有 output 或 output 未保持 |
| 0xFF | 非法状态 |
| 子引擎码 | 原样传播 |

## 4. `wc_graph_ctrl` 端口

时钟/复位：`clk`, active-low `rst_n`。`start` 单周期脉冲。

| 组 | 信号 | 说明 |
|---|---|---|
| identity | `start, plan_base[31:0], param_end[31:0], parameter_ready, generation[31:0]` | plan_base 64 B 对齐；一次 START |
| status | `busy, done(pulse), fault(level), error_code[7:0], completed, node_count, rejected_starts, last_node` | `done` 只在子引擎 drain 后 |
| scoreboard | `done_mask[1023:0]` | DONE 后保持 |
| counters | `cycles, fetch_cycles, operator_cycles, drain_cycles[63:0], drain_timeout` | 只状态，不用于加速声明 |
| output | `output_retained, output_count, last_output_tid/base/bytes` | 保持 |
| fetch | `fetch_req_valid/ready, fetch_address[31:0], fetch_beats[7:0], fetch_read_valid/ready, fetch_read_data[127:0], fetch_read_index[7:0], fetch_done, fetch_error` | 单 outstanding 128-bit |
| SEQ | `seq_valid/ready, seq_base[31:0], seq_count[31:0], seq_done, seq_fault, seq_error[7:0]` | 可接 V022 或 stub |
| MAT | `mat_valid/ready, mat_base[31:0], mat_count[31:0], mat_done, mat_fault, mat_error[7:0]` | 外部 matrix engine |
| VEC | `vec_valid/ready, vec_descriptor[511:0], vec_done, vec_fault, vec_error[7:0]` | 控制器先取 payload 并 ACL |
| LAY | `lay_valid/ready, lay_descriptor[1023:0], lay_done, lay_fault, lay_error[7:0]` | 同上 |
| misc | `direct_idle` | 无直接 MAT/VEC/LAY 活动 |

## 5. `wc_graph_top` 端口/集成

`wc_graph_top` 在控制器上接：

* 1 个 fetch AXI master（`sf_*`）；
* 真实 vector 2 个 AXI master（`vr_*`, `vw_*`）；
* 真实 layout 2 个 AXI master（`lr_*`, `lw_*`）；
* 外部 matrix handshake；
* 外部 SEQ handshake（`seq_*`）。

没有第二份 vector/layout 算术。SEQ 未在本 top 内实例化；集成时可接：

```
pl_execution_plan_v022  -> seq_valid/ready/base/count/done/fault/error
```

或控制 stub。

AXI 地址宽度 40 bit，数据 128 bit，burst INCR，size=4（16 B/beat）。fetch 单 outstanding；未实现多在途 DMA。

## 6. 全局 tensor / descriptor map

| 文件 | 内容 |
|---|---|
| `analysis/tensor_map.json` | 1318 个 tensor：tid、name、kind、base、bytes、live、version、owner、old_addr、region |
| `analysis/descriptor_map.json` | 每个 plan 的 node→type/base/count/tids/input/output/deps/version |
| `analysis/relocation_map.json` | 68 边界 old→new、temp delta；591 cbase→new C；并标注 sealed V022 内部指针未重写 |
| `analysis/global_alloc.json` | arena/external 使用量、shared temp 策略、负例 |
| `analysis/outer591_groups.json` | 20 个 owner 组（12×29 encoder + 6×40 decoder + 1 + 2） |
| `analysis/nonmatrix_tensor_names.json` | 非矩阵算子的可见 tensor 名示例（不造边） |

地址区域：

```
matrix scratch  0x03000000..0x04000000   (保留，未改 sealed 布局)
intermediate    0x04000000..0x08000000   = arena
external I/O    0x08000000..0x10000000   (host boundary / 全局输入输出)
parameter/plan  0x10000000..0x40000000   (只读)
```

本任务生成的计划放在 `0x10008000 / 0x10010000 / 0x10020000`（都在 param 窗口，启动前由 host 预装）。  
小真实图的输入放在 `0x10001000`，因为 sealed `ddr_layout_axi` 的 ACL 只接受 param/arena 源；external 源在控制器 ACL 中允许，但真实 layout 引擎尚未扩展。集成时若要从 external 直接读，需要扩展 layout ACL 或先 DMA 到 arena。

## 7. 集成顺序（建议）

1. 用 `global_alloc.json` + `relocation_map.json` 对 sealed V022 plan 做真正的 re-lowering（queue/A/C/temp 绝对地址）。
2. 用 `wc_graph_ctrl` 替掉 `wc_superplan_ctrl`（128 节点）作为图级控制器；WCPG v2 支持 591+。
3. 接 `pl_execution_plan_v022` 作为 SEQ；保持其单 START/DONE/错误 drain。
4. 矩阵队列仍由现有 accelerator 拥有；控制器只检查 queue base/count。
5. 在集成前用 `verify_graph.py` 做 plan/hash/root/output/alloc 门禁；`run_all.py` 的负例必须保持拒绝。
6. 若要并行 68，先解决 temp residency（见 REPORT §4.2），不要只改地址。
7. 找到原 ONNX/executor 后，重建 591 真边；当前 `ledger591.bin` 的 590 条边是 synthetic host order，不能当数据流 DAG。

## 8. 数值/范围

* 未改 W7p8/A16/C48、最低 bit 位置、clip、QDQ、FP32 FTZ/RNE/FMA 顺序。
* 未实现除法/开根近似；用户授权允许近似，但本任务没有改 `asr_fp32_alu`，所以不声明近似误差。
* 未执行 FMA/op17；`fma_forbidden_stub` 只用于编译，且测试没有调用 op17。
* 未执行矩阵算术；591/68 的 MAT/SEQ 是控制 stub。
* 未实现/未验证 CDC 或异步 FIFO；本接口没有假设它们存在。
* 只做了小真实 LAY/VEC 数据链，64/64 word 对 Python float32 golden 一致。
