# 搬运与时间归因

Pre-Fusion Baseline: 1024 elements through DDR roundtrips

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_w|cycle|100.0%|36.6%|20480|0|
|axi_r|cycle|100.0%|32.9%|18432|0|

## 重复搬运候选

- C48_tile / v1 / C_Cache→DDR：累计 6144 B，已知区域并集 6144 B，重复候选 0 B；原因 {'unfused_c48_evict': 6144}。
- C48_tile / v1 / DDR→Vector_LPRE：累计 6144 B，已知区域并集 6144 B，重复候选 0 B；原因 {'read_c48_for_conversion': 6144}。
- FP32_raw / v1 / Vector_ALU→DDR：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'intermediate_spill': 4096}。
- FP32_raw / v1 / DDR→Vector_ALU：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'read_fp32_scale': 4096}。
- FP32_scaled / v1 / Vector_ALU→DDR：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'intermediate_spill': 4096}。
- FP32_scaled / v1 / DDR→Vector_ALU：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'read_fp32_bias': 4096}。
- FP32_biased / v1 / Vector_ALU→DDR：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'intermediate_spill': 4096}。
- FP32_biased / v1 / DDR→Vector_ALU：累计 4096 B，已知区域并集 4096 B，重复候选 0 B；原因 {'read_fp32_quant': 4096}。
- A16_out / v1 / Vector_ALU→DDR：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'final_output': 2048}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。