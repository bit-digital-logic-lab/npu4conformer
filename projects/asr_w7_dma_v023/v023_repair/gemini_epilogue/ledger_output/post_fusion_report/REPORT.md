# 搬运与时间归因

Post-Fusion Candidate: 1024 elements with on-chip epilogue streaming

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_w|cycle|100.0%|21.3%|2048|0|
|axi_r|cycle|100.0%|0.0%|0|0|

## 重复搬运候选

- A16_out / v1 / Epilogue_Engine→DDR：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'fused_output_stream': 2048}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。