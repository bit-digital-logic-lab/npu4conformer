# 接入与因果归因

## Python

只对统一后端的 read_tensor/write_tensor/load_tile/evict/convert_layout/submit_dma 插桩，不重写数值核。使用tensor的稳定ID、版本和格式；记录为何触发缓存失效、是否写脏、下次消费者。Python数组视图不是一次外存搬运，numpy.matmul不是AXI流量。显式copy只能证明软件内存请求，CPU缓存/真实DRAM另需硬件计数。

```python
from ledger import Ledger
with Ledger("trace.jsonl", metadata) as log:
    with log.python_call("host", "prepare_layout", tensor="X", version="input0"):
        result = prepare_layout(x)
    log.transfer(id="r0", resource="axi_r", start=100, end=140,
                 tensor="X", version="input0", format="A16", src="DDR", dst="Abank0",
                 op="conv0", phase="load", reason="first_load", logical_offset=0,
                 logical_bytes=256, valid_bytes=256, bus_bytes=256)
```

Python同步调用跨度仅记主机资源的python_call interval，不写虚构DMA有效字节。异步enqueue耗时不是设备执行耗时；只在真实设备时间戳/完成同步证据存在时建立设备跨度。微小调用的插桩开销可显著影响耗时，需要开关A/B测量并报告。

## 周期模型

每tick先处理已接受事务的推进，再收集通道实际握手（约定在README固定），更新独立的AR/R/AW/W/B计数及队列占用。按模型**真正有的状态**归因。对资源每拍恰记一种主状态，连续同状态且同transfer可压缩为interval，压缩后的bytes是总和。

优先级例：R握手→payload；RVALID&&!RREADY→backpressure；pending>0&&!RVALID→wait_memory；pending==0且compute缺数据→starved_input或调度间隙；无法判断→unknown。RREADY=0且RVALID=0不能仅由这两个信号推出反压。WVALID&&!WREADY可判下游反压；WVALID=0时有未完成AW还要区分pack缺数/FIFO无数据与等待命令。

DDR读写共享状态必须由仲裁器或存储模型采样，不能从AXI R/W的同时活动反推DDR物理同时读写。需要bank/rank调度、刷新和读写切换时另设模型，声明参数和假设。

## RTL / BFM

监视器只读，不改变ready/valid或payload。数据只在valid&&ready时计数；在途数=accepted_commands-completed_responses，并检查上下界/复位。写入字节=popcount(WSTRB)，总线承载字节=握手拍数×数据位宽/8。WLAST并不代表B已成功；task_done不得早于最后正确响应。异常只记录已握手字节，未接受请求不计实际流量。

先用可手算小例校验：单拍、跨4KiB、partial strobe、两笔重叠读、下游反压、无任务空闲、错误排空。再跑真实输入，关联descriptor_id→tensor/slice→transfer_id。握手trace若只有VCD时间，要记录timescale和时钟域，不按文件名猜频率。

## 结果解释

- 端口busy但payload低：查命令等待、单在途、响应气泡或反压，不能直接“DDR满”。
- payload高但有效字节低：查padding、尾拍和稀疏格式开销。
- AXI忙但PE饿：查局部带宽/布局/bank冲突、prefetch信用和FIFO容量。
- 相同数据重复：先确认容量/一致性/消费者需求，再用候选调度重放验证可省。
- 写一个“去重字节”估算不是性能优化完成；需要保持数值/依赖的实际候选及公平before/after。
