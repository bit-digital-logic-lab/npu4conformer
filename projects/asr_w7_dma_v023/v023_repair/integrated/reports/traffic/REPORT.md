# 搬运与时间归因

V0.23 integrated single-clock logic simulation; shared AXI128 BFM, not board DDR

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_r|cycle|100.0%|7.7%|29248|0|
|axi_w|cycle|100.0%|6.7%|25600|0|
|ddr_bfm|cycle|100.0%|13.5%|54848|-54848|
|graph|cycle|100.0%|0.0%|0|0|
|matrix|cycle|100.0%|0.0%|0|0|
|vector|cycle|100.0%|0.0%|0|0|
|layout|cycle|100.0%|0.0%|0|0|

## 重复搬运候选

- plan / run1 / DDR→graph_fetch_bank：累计 1792 B，已知区域并集 1792 B，重复候选 0 B；原因 {'burst_load': 1792}。
- payloads / run1 / DDR→graph_fetch_bank：累计 640 B，已知区域并集 640 B，重复候选 0 B；原因 {'burst_load': 640}。
- A16_param / run1 / DDR→layout_bank：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'burst_load': 2048}。
- A16 / run1 / layout_bank→DDR：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'burst_store': 2048}。
- W7_param / run1 / DDR→layout_bank：累计 1024 B，已知区域并集 1024 B，重复候选 0 B；原因 {'burst_load': 1024}。
- W7 / run1 / layout_bank→DDR：累计 1024 B，已知区域并集 1024 B，重复候选 0 B；原因 {'burst_store': 1024}。
- queue / run1 / DDR→matrix_queue_bank：累计 64 B，已知区域并集 64 B，重复候选 0 B；原因 {'burst_load': 64}。
- A16 / run1 / DDR→matrix_bank：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'burst_load': 2048}。
- W7 / run1 / DDR→matrix_bank：累计 1024 B，已知区域并集 1024 B，重复候选 0 B；原因 {'burst_load': 1024}。
- C48 / run1 / matrix_bank→DDR：累计 6144 B，已知区域并集 6144 B，重复候选 0 B；原因 {'burst_store': 6144}。
- C48 / run1 / DDR→vector_bank：累计 6144 B，已知区域并集 6144 B，重复候选 0 B；原因 {'burst_load': 6144}。
- F32_conv / run1 / vector_bank→DDR：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'burst_store': 4096}。
- F32_conv / run1 / DDR→vector_bank：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'burst_load': 4096}。
- scalars / run1 / DDR→vector_bank：累计 128 B，已知区域并集 16 B，重复候选 112 B；原因 {'burst_load': 128}。
- F32_scale / run1 / vector_bank→DDR：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'burst_store': 4096}。
- F32_scale / run1 / DDR→vector_bank：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'burst_load': 4096}。
- F32_bias / run1 / vector_bank→DDR：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'burst_store': 4096}。
- F32_bias / run1 / DDR→vector_bank：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'burst_load': 4096}。
- A16_out / run1 / vector_bank→DDR：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'burst_store': 2048}。
- A16_out / run1 / DDR→layout_bank：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'burst_load': 2048}。
- final / run1 / layout_bank→DDR：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'burst_store': 2048}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。