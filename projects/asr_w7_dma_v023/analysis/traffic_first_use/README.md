# traffic-ledger 首次工程接入

这是原DMA与候选DMA真实RTL/AXI BFM握手微基准，不是合成skill示例，不是整模型/真实DDR/物理频率签核。仿真周期域100MHz（TB10ns），报告不声称达到100MHz硬件Fmax。读写各256beat=4KiB，同seed7/固定32拍BFM延迟/无额外随机背压/8在途上限/共享半双工BFM。窗口从第一请求接受到最后done拍末，读写同一窗口。

|项目|原DMA|候选DMA|
|---|---:|---:|
|总拍数|821|538|
|读payload拍|256|256|
|写payload拍|256|256|
|共享模型数据利用率|62.36%|95.17%|
|读等待数据拍|528|263|
|写下游反压拍|16|228|

同一拍R/W同时握手为0，依据BFM DUPLEX=0而非AXI天然半双工。读等待包括共享仲裁，不能直接等同物理DDR延迟。写dispatch_or_drain尚未细分AW等待/B响应/调度：保留合并标签，不能猜原因。原与候选各8192有效字节逐项对账，状态覆盖率100%，有效/实际字节一致，无重复候选；这里的tensor仅标BFM_operand/BFM_result，不能宣称真实矩阵不重复。

每版本report/有时间轴、CSV和summary，signals.csv是逐拍原始证据，trace.jsonl为skill格式。run.log有原有数据golden PASS；commands.json、源码hash见result.json。复跑python3 analysis/traffic_first_use/run.py。不改变work或worker候选。

下一阶段：待全系统候选完成后，接入descriptor→真实tensor/version/slice/reason映射，记录A/W预取、C48驻留/回写、layout/QDQ和计算区间，用同一账本查部分重复/空闲因果。没有整模型流量证明前不对重复作性能承诺。
