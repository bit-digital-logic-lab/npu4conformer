# 采集合同

输入是JSONL。首行metadata，其余使用interval；transfer事件可以保留，渲染器不把transfer整个跨度当busy。

```json
{"type":"metadata","schema":1,"scope":"RTL BFM only, not board","resources":{"dut.dma":{"unit":"cycle","clock_hz":100000000,"timebase":"tb_clk","start":0,"end":100,"kind":"module","evidence":"RTL FSM+handshake"},"dut.dma.busy":{"unit":"cycle","clock_hz":100000000,"timebase":"tb_clk","start":0,"end":100,"kind":"signal"}}}
{"type":"interval","resource":"dut.dma","start":0,"end":20,"state":"wait_memory","reason":"read outstanding and RVALID low","blocked_by":"memory BFM","tensor":"W","op":"ffn1","descriptor_id":4,"evidence":"posedge monitor"}
{"type":"interval","resource":"dut.dma.busy","start":0,"end":20,"state":"1","evidence":"sampled busy register"}
```

start/end为半开区间。一个模块只代表互斥FSM状态时，用module lane；多个子单元并发时各自lane。动态module实例或模型调用要有唯一实例ID，不能把并行调用重叠塞同一lane。

Python：阶段scope用perf_counter_ns相对同一origin记录，unit=ns、timebase=同一进程单调计时器ID；线程/异步设备单独lane。异步enqueue不代表GPU/FPGA执行时间。若同一线程有嵌套scope，用不同lane避免重叠；perf_counter采集开销单独说明。

周期模型：固定在tick的哪个阶段采样，采集FSM、握手、inflight和阻塞条件。每tick恰一个主状态，未知原因不能猜。模块即使没有外部请求，也可能在清零/排空，不是idle。

RTL：在同一个时钟沿捕获输入握手与FSM旧状态，具体约定写README。验证`valid&&ready`、首末拍、done和drain事件的对齐。多域的本地cycle计数不要使用同一timebase；即使时钟频率一样，也不代表相位与epoch一致。本工具只接受明确已对齐的输入，不负责CDC证明。

状态日志按同一(resource,state,reason,tensor,op,descriptor_id,blocked_by)合并；bytes需相加，不能保留第一拍bytes冒充全区间。信号高低必须由采样记录，组合X/Z如实保留。关键单拍脉冲不能去掉。

集成时建议lane：执行计划fetch/dispatch、DMA读、DMA写、DDR服务、A/W预取bank0/1、计算阵列、C48打包写回、layout、vector；每个只在真实可观测时添加。模块依赖箭头是因果主张，必须关联实际token或descriptor，不能仅因时间相邻就画。
