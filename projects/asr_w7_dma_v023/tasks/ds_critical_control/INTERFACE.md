# INTERFACE — 交给主 agent 的集成契约

## 1. 文件与模块名

| 候选 | 文件 | 模块名 | 替换关系 |
|---|---|---|---|
| Storage | `candidate/rtl/block_storage_dma_wide4_pipe_v1.sv` | `block_storage_dma_wide4` | 可直接替换 `work/rtl/block_storage_dma_prefetch.sv` |
| Layout | `candidate/rtl/ddr_layout_engine_pipe_v1.sv` | `ddr_layout_engine` | 可直接替换 `work/rtl/ddr_layout_engine.sv` |

两者端口名、方向、位宽与参数均未改变；`work/` 和 ZIP 未修改。

## 2. Storage 接口/延迟契约

### 2.1 端口

与 `work/rtl/block_storage_dma_prefetch.sv` 完全一致：

- 请求：`req_valid/req_ready/req_write/req_address/req_epoch/req_layer/req_matrix/req_block_row/req_block_col/req_allowed_ops/req_completed_ops/req_encoding/req_block_valid/req_in_operation`
- Header：`header_valid/header_ready/header_exists/header_block_valid/header_in_operation/header_epoch/header_layer/header_matrix/header_block_row/header_block_col/header_allowed_ops/header_completed_ops/header_encoding`
- 数据：`data_valid/data_ready/data_in[191:0]/data_index/data_last`（读）
- 写回：`out_valid/out_ready/out_data[47:0]/out_index/out_last`（写）
- DMA：`dma_request_valid/ready/write/address/beats`、`dma_read_*`、`dma_write_*`、`dma_done/error`
- 状态/计数：`idle/transactions/read_blocks/write_blocks/error_transactions/read_wait_cycles/write_wait_cycles/scalar_cycles`

`req_ready` 仍为 `idle && rst_n`；请求接受语义不变（`req_valid && req_ready` 在时钟沿接受）。

### 2.2 延迟变化（必须让上层知道）

- 接受请求后，descriptor validator 走 7 个寄存阶段（V1..V7）。
- **读**：
  - 坏 descriptor / C 不存在：接受后约 **8 拍** 进入 `HEADER`（不再发 DMA）。
  - 好 descriptor：约 8 拍后进入 `RREQ`，之后 DMA 时序与原模块相同；`HEADER` 在 DMA 排空后出现。
  - 因此 `req -> header` 比原来多约 8 拍；`req -> first data` 也相应后移。`req_ready` 的接受带宽不变（一次一个 block）。
- **写**：
  - 接受后仍立即进入 `WSCALAR` 并开始接收 1024 个 `out_*` 字；validator 与打包并行。
  - 1024 字结束后经 `WVAL` 等 `v_done`（正常已提前完成），再进 `WREQ`；比原来多 **1 拍** 才发 DMA 写请求。
  - `write_ack` 仍只在 DMA 写响应/错误排空后出现；错误码/`error_transactions` 语义不变。
- `read_wait_cycles`/`write_wait_cycles` 仍只统计原 `RREQ/RDMA`、`WREQ/WDMA`，新增校验拍不计入；`scalar_cycles` 仍只统计 `RSCALAR/WSCALAR`。

### 2.3 顺序/错误/ACL/abort

必须保持以下不变量（候选已按此实现）：

1. 坏 descriptor 不发任何 AXI 读/写；只通过 `HEADER`（读）或 `WACK`（写）报告。
2. 合法地址仍由 `ARENA_BASE/ARENA_END`、`PARAM_BASE/PARAM_END/param_end`、`req_address[5:0]==0`、row/col<nrows/ncols、`expected_address==req_address` 检查；参数窗口仍只允许 **读 + encoding==1**。
3. `header_exists == header_block_valid == exists`；`header_in_operation == bad`；`completed` 仍按 `encoding==2 && cfg_c_valid ? cfg_c_completed : 0` 生成。
4. 读 AXI 错误必须先排空已接受 beat，再给 `HEADER`；写错误在 `WACK` 报告；不取消已接受事务。
5. `abort_scalar` 仍只在 `HEADER/RPRE/RSCALAR` 生效；VWAIT 不新增 abort 语义（与原模块在 RREQ/RDMA 期间忽略 abort 保持一致）。
6. 数据通路、C48 打包、A16/W7 位宽、奇偶校验、tail strobe、ACL 均未改；W7A16C48/QDQ 数值合同未动。

### 2.4 关键 ABI 提醒

原 block engine 的 `req_in_operation` 语义是“该 slot 正在操作”：

- 读请求：`req_in_operation=1`、`req_completed_ops=0` 才是合法；
- 写请求：`req_in_operation=0`、`req_completed_ops=1` 才是合法。

候选按原 `request_bad` 的完全相同表达式实现；集成时不要把该字段按字面意思反转。

## 3. Layout 接口/延迟契约

端口/参数与 `work/rtl/ddr_layout_engine.sv` 完全一致。

- 地址形成由原 `CALC -> ADDRESS` 变为 `CALC -> ADDR1 -> ADDRESS`。
- 每个元素多 **1 拍**；`processed_elements`、cache tag、读写数据、错误码/ACL 不变。
- 实测 fixture 周期代价约 +10.7%…+15.1%（见 FINDINGS.md）。
- 若主 agent 仍在 125 MHz 运行，建议优先只集成 storage；layout 候选作为“更高频点/局部域”备选，或在后续用预计算步进进一步摊薄这 1 拍。

## 4. 供 traffic-ledger 接入的监视点（不改变功能 ready/valid）

按 `/home/yang/.codex/skills/traffic-ledger/SKILL.md`，后续可在独立 wrapper/monitor 中采集；本任务未改功能握手，也未宣称已完成 ledger 接入。

### Storage

- 事件字段：`descriptor_id`、`tensor`（A/B/C）、`tensor_version`（`epoch` + `layer` + `matrix` + block row/col）、`format`（encoding 0/1/2）、`logical_slice`（block row/col + beat range）、`reason`、`request/first_data/last_data/completion`。
- 资源：`ddr_r`、`ddr_w`；片上 `l1_bank`/`c_cache` 可另立资源。
- reason 建议：`A_PREFETCH`、`B_PREFETCH`、`C_RELOAD`、`C_WRITEBACK`、`EVICT`、`FLUSH`、`DESCRIPTOR_CHECK`、`HEADER`、`SCALAR_REPACK`。
- 关键监视点：
  - `req_valid && req_ready`：接受 descriptor；
  - `state==VWAIT`：descriptor check（不要归到 idle 或 DDR wait）；
  - `dma_request_valid && dma_request_ready`：DMA 请求发出；
  - `dma_read_valid && dma_read_ready`：R payload；
  - `dma_write_valid && dma_write_ready`：W payload（有效字节按 `dma_write_strobe`，本模块为全 16 字节）；
  - `header_valid && header_ready`：读 header 完成；
  - `write_ack`：写完成/错误出口；
  - `state==WVAL`：写 descriptor verdict 等待（正常隐藏）。
- 未知原因保留 `unknown`；`VWAIT/WVAL` 不应被猜成 DDR 延迟。

### Layout

- 事件字段：`descriptor_id`、`tensor`（source/destination）、`version`（`cfg` 快照 + descriptor 序号）、`format`（mode 0..4 + bytes）、`logical_slice`（mode/通道/行/列/kernel 坐标）、`reason`（`COPY`、`PACK`、`IM2COL`、`UNPACK`、`LAYOUT_CACHE_HIT/MISS`）。
- 资源：`ddr_r`、`ddr_w`；`layout_cache` 可另立资源。
- 监视点：`RREQ/RDATA`、`WREQ/WDATA/WWAIT`、`LOOKUP/CACHE_SELECT/CACHE_READ`、`CALC/ADDR1/ADDRESS`。
- `ADDR1/ADDRESS` 是地址形成，不是 DDR wait；不要把它们归入 `wait_memory`。
- 未采集的层级标 `unknown`/未测，不能用 `busy` 或 `prefetch` 名称代替真实握手。

## 5. 集成建议

1. 先集成 storage 候选：它直接切断已证实的 7.745 ns 路径，且对 125 MHz 现有数据流只增加约 1.3% 仿真周期（主要是校验等待）。
2. layout 候选默认不强行替换；先用主 agent 的 STA/实现判断 125 MHz 之外的频点是否值得 +13% 左右元素周期。
3. 任何频率/吞吐结论都必须来自新的综合/STA/板测；本任务只提供逻辑等价和结构分级。
