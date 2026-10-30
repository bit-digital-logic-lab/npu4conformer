# 搬运与时间归因

candidate V1 M=64 N=32 K=96 C=0; preload excluded; window=engine busy cycles; Verilator logic simulation

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_r|cycle|100.0%|19.5%|18432|0|
|axi_w|cycle|100.0%|13.0%|12288|0|
|compute|cycle|100.0%|0.0%|0|0|

## 重复搬运候选

- A / epoch3:blocks00-01:kb0-2 / DDR→A_stage_banks：累计 12288 B，已知区域并集 12288 B，重复候选 0 B；原因 {'first_load': 12288}。
- W / epoch3:immutable:kb0-2 / DDR→W_stage_banks：累计 6144 B，已知区域并集 6144 B，重复候选 0 B；原因 {'first_load': 6144}。
- C / epoch3:blocks00-01:final / C_cache→DDR：累计 12288 B，已知区域并集 12288 B，重复候选 0 B；原因 {'c_result_write': 12288}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。