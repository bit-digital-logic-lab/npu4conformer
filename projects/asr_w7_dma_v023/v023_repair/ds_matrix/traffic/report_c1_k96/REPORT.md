# 搬运与时间归因

RTL logic simulation: matrix P2 cluster K96 C=1, AXI128 BFM; not board DDR

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_r|cycle|100.0%|22.0%|30720|0|
|axi_w|cycle|100.0%|8.8%|12288|0|
|ddr_bfm|cycle|100.0%|30.9%|43008|-43008|
|compute|cycle|100.0%|0.0%|0|0|
|c_cache_rd|cycle|100.0%|17.6%|0|0|
|c_cache_wr|cycle|100.0%|23.5%|0|0|
|packer|cycle|100.0%|5.9%|0|0|

## 重复搬运候选

- A / epoch3 / DDR→Abank：累计 12288 B，已知区域并集 12288 B，重复候选 0 B；原因 {'block_load': 12288}。
- W / epoch3 / DDR→Wbank：累计 6144 B，已知区域并集 3072 B，重复候选 3072 B；原因 {'block_load': 6144}。
- Cpartial / epoch3 / DDR→Ccache：累计 12288 B，已知区域并集 12288 B，重复候选 0 B；原因 {'block_load': 12288}。
- C / epoch3 / Ccache→DDR：累计 12288 B，已知区域并集 12288 B，重复候选 0 B；原因 {'result_stream': 12288}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。