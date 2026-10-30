# 搬运与时间归因

RTL logic simulation: matrix P2 cluster K32, AXI128 BFM; not board DDR

|资源|时间单位|已知覆盖率|传数据占比|有效字节|账本差值|
|---|---|---:|---:|---:|---:|
|axi_r|cycle|100.0%|7.1%|3072|0|
|axi_w|cycle|100.0%|14.2%|6144|0|
|ddr_bfm|cycle|100.0%|21.3%|9216|-9216|
|compute|cycle|100.0%|0.0%|0|0|
|c_cache_rd|cycle|100.0%|9.5%|0|0|
|c_cache_wr|cycle|100.0%|9.5%|0|0|
|packer|cycle|100.0%|9.5%|0|0|

## 重复搬运候选

- A / epoch3 / DDR→Abank：累计 2048 B，已知区域并集 2048 B，重复候选 0 B；原因 {'block_load': 2048}。
- W / epoch3 / DDR→Wbank：累计 1024 B，已知区域并集 1024 B，重复候选 0 B；原因 {'block_load': 1024}。
- C / epoch3 / Ccache→DDR：累计 6144 B，已知区域并集 6144 B，重复候选 0 B；原因 {'result_stream': 6144}。

等待原因、时间范围、blocked_by和证据见 intervals.csv；unknown不能解释成空闲。账本差值非零需要解释，不能自动判总线错误。

重复字节是候选，不是可省流量证明；跨域时间未对齐；未采样区间是unknown。