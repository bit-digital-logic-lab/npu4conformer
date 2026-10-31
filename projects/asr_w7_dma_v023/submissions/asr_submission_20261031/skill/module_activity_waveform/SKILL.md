---
name: module-activity-waveform
description: 将硬件 module、Python 模型阶段或周期模型资源活动记录展示为交互式多泳道波形，查看某周期各模块忙闲、等待原因及 valid/ready/busy/done 数字信号；用于 FPGA/NPU/DMA 调度、数据流与流水可视化。支持 traffic-ledger JSONL，不把未采样当空闲，不虚构时钟域对齐。
---

# 模块活动波形

把模块的真实观测事件放到可缩放、可搜索、可悬停和游标检查的时间轴，回答“什么时候哪个模块在做什么”。若用户的 model 指机器学习模型而非硬件 module，lane 改用模型/算子实例，保留证据层级与时间规则。

## 接入

1. 先确认每一行代表模块、接口还是信号。名称使用稳定层级路径，另带 tensor、op、descriptor_id、reason、blocked_by、evidence，不能只画一个笼统 busy。
2. 观测方式与数据格式见 [采集合同](references/instrumentation.md)。优先直接读取已有 `traffic-ledger` 的 metadata/interval；也可新增只读 RTL 监视器或周期模型 recorder，禁止为了画图改变 ready/valid。
3. 同步采样边沿、半开区间、任务窗口固定。模块状态区间互斥，不同模块允许并行；未覆盖区间为 unknown。同模块的计算与传输若真并发要拆子资源 lane，不能强行覆盖。
4. 只有 `timebase` 完全相同且 unit、clock_hz、`origin_ns` 一致的资源才共用一条坐标轴。未提供 timebase 默认每资源独立，不根据频率相同就猜同步。异步域需要外部同步锚点转换后的输入；本工具不自动换域。
5. 用下列命令生成离线 HTML，无网络依赖：

```bash
python3 scripts/render.py trace.jsonl --out activity.html --title '模块活动波形'
```

支持滚轮围绕游标缩放、按钮平移、搜索模块、点击锁定游标、选时间域；游标下面列出当前各模块状态及原因，悬停显示事件详情。二进制信号 interval 的 state 使用 `0`、`1`、`X`、`Z`，资源 `kind: signal`；普通module lane使用 compute、payload、wait_memory、backpressure、idle_no_work 等状态。

## 状态的含义

- active/compute：真实发射/有效累加或模块FSM在执行，不等同于忙标志为1。
- payload：valid&&ready，字节/拍和tensor关联由流量账本证明。
- wait_memory、starved_input、fifo_full、bank_conflict、backpressure、drain：各自观测依据要带出；无法确定原因用 wait_unknown。
- idle_no_work：明确没有待处理工作；忙但等响应不能归入idle。
- unknown：缺观测/无法辨认，与idle使用不同颜色。
- `busy/valid/ready/done`是独立数字信号lane，不能只由busy推断compute或payload。

## 验收与交付

先运行 `python3 scripts/selftest.py`，再对实际trace核对窗口、总字节/周期、状态覆盖、首尾事件和同拍并发。脚本拒绝同lane重叠、越界和混用timebase。输出HTML及同名 `.summary.json`，保留原trace、采集命令、源码hash。报告明确软件墙钟、模型周期、RTL/BFM、板测哪一层。

大trace先在采集侧合并同状态、同工作ID、同原因的相邻区间，或按目标窗口裁剪；不要把单拍done脉冲平均成活跃百分比。画面中很窄的事件通过放大和游标确认，不能仅凭全局截图判断不存在。

若当前只采集DMA，就只展示DMA，不凭估算补出PE、缓存等活动。示例/演示数据要显著标为合成，不称为项目实测。`traffic-ledger`用于流量和重复数据分析，本skill用于活动波形；需要两者时读取对应skill再执行。

## Roofline 与忙状态口径

展示性能或定位瓶颈时，先区分 `busy`、FSM处于计算阶段和逐PE有效MAC。旧trace若把busy采样命名为compute，分析器会依据明确busy证据标为busy，并保留original_state；不能由busy或FSM阶段时长推导有效MAC利用率。

Roofline使用同一次任务的有用运算N、同一命名存储边界的实际读写总字节Q和完整完成窗口T，计算I=N/Q、P=N/T。量化矩阵可约定1 MAC=2整数运算，不能称FP FLOPS。分块补齐与有用运算分别保留。

带宽上限必须来自端口合同或独立带宽基准，不能使用Q/T反推roof。共享读写通道不相加；独立通道需保留方向限制。明确逻辑模型与板级测量、理论峰值与持续带宽。无可靠频率时使用OP/cycle和B/cycle，不补造MHz。

traffic-ledger负责Q、重复候选及字节对账；module-activity-waveform负责T与等待/排空归因。有逐PE有效事件时才能报告有效计算重叠。Roofline之下的空隙不能仅凭点位断言全由带宽造成。

Roofline的Q还须声明字节口径：默认使用命名接口的实际bus/wire字节，包括补齐或无效字节占用；有效数据字节另列。只有已验证valid_bytes等于bus_bytes时可直接互用，不能用较小的逻辑数据量搭配较大的物理峰值伪造计算强度。
