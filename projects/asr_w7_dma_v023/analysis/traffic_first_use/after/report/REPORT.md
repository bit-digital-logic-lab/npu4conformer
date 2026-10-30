# 搬运与时间归因

actual AXI handshakes of RTL DMA BFM microbenchmark, 256 beats each direction; not full model; no matrix IDs inferred

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_r|cycle|100.0%|47.6%|4096|0|
|axi_w|cycle|100.0%|47.6%|4096|0|

## 重复搬运候选

- BFM_operand / fixture_seed7 / DDR_model→DMA_read_sink：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'test_fixture_transfer_not_model_tensor': 4096}。
- BFM_result / fixture_seed7 / DMA_write_source→DDR_model：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'test_fixture_transfer_not_model_tensor': 4096}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。