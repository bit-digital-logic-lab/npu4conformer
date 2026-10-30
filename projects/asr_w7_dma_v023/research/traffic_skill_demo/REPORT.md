# 搬运与时间归因

synthetic cycle example; not project measurement

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_r|cycle|100.0%|30.0%|24|0|
|axi_w|cycle|10.0%|10.0%|6|0|

## 重复搬运候选

- X / v1 / DDR→Abank：累计 16 B，已知区域并集 12 B，重复候选 4 B；原因 {'first_load': 8, 'capacity_reload': 8}。
- X / v2 / DDR→Abank：累计 8 B，已知区域并集 8 B，重复候选 0 B；原因 {'first_load': 8}。
- Y / v1 / Cbank→DDR：累计 6 B，已知区域并集 6 B，重复候选 0 B；原因 {'result': 6}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。