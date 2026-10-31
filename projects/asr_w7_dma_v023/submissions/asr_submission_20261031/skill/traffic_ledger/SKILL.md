---
name: traffic-ledger
description: 为 Python 推理、硬件周期模型或 RTL 握手建立张量搬运账本与资源时间轴，分析搬运原因、区域重复、带宽利用率、等待和空闲归因；用于 FPGA/NPU/DDR/DMA 数据流优化。保留特殊量化及数值顺序，区分模型、软件测量与真实硬件证据。
---

# 张量搬运账本与周期归因

交付可复跑的原始 trace、逐张量搬运表、逐资源时间轴和证据边界，回答：什么时间搬什么、为什么搬、重复了多少、总线忙什么、空闲时在等谁。

## 先确定观测范围

1. 确认任务区间、数据预装是否排除、全模型还是子图，记录输入、源码和配置哈希。
2. 列出真实资源：独立 AXI R/W 通道、共享 DDR 服务资源、片上读写端口、计算阵列。不要把独立通道强行当半双工，也不要把多个 master 峰值相加作为共享端口峰值。
3. 为每个资源确定时间基准：周期及域频率，或单调时钟纳秒。禁止把 Python 执行时间换算为 DMA 周期；多时钟域先取得频率、相位/同步锚点，再做跨域重叠统计。
4. 选择接入模式，按需读 [接入方法](references/instrumentation.md)：Python 分配/拷贝及调度入口、周期模型每次 tick、或 RTL `valid && ready` 监视器。不要把 NumPy 算子调用当物理搬运。

## 记录合同

详见 [事件格式](references/schema.md)。采用 JSONL，metadata 定义资源与区间，transfer 定义张量搬运，interval 定义资源状态。

- 每笔搬运有唯一 ID、算子/阶段、张量及版本、源/目标、格式、逻辑区域、有效/实际字节、原因、起止及所在域。地址重用不等于同一张量版本；动态重解释格式必须新建 format。
- 资源状态区间使用半开 `[start,end)`，同资源互斥；不同资源允许并行。未知时间必须保留 `unknown`，不能自动归到空闲。
- `payload` 仅代表已握手的数据；命令、等待响应、下游反压、缺输入、FIFO满、bank冲突、读写切换、计算依赖、尾部排空分别记录。将 DMA busy 与有效传输分开。
- 等待区间附 `blocked_by` 和因果证据。一次只能选择一个主归因；多原因可作辅助标签，不重复加时间。没有证据就 unknown。
- 读数据按 R 握手计、写数据按 W 握手计，有效写字节按 WSTRB；发 AR/AW 不是搬完，B 也不计额外数据字节。记录 request/first-data/last-data/completion，分别计算排队、首拍延迟和排空。

## 执行与产物

1. 插桩应新增独立 wrapper/监视器，保留原始数值实现，先在小例对比无插桩版本输出。主机 profile 不宣称周期精确。
2. 用 `scripts/ledger.py` 的 `Ledger` 写 metadata/transfer/interval；`python_call` 仅计主机同步调用的墙钟跨度，异步设备调用需设备完成事件，不计成实际 DMA。
3. 执行 `python3 scripts/analyze.py TRACE.jsonl --out REPORT_DIR`，生成 `summary.json`、`transfers.csv`、`resources.csv`、`intervals.csv`、`timeline.html`、`REPORT.md`。脚本为标准库实现。
4. 逐资源核对：分类时长和等于窗口，`payload≤observed≤window`，握手字节对账，容量不超界，量纲一致。脚本拒绝状态重叠和显式超容量；未覆盖区间补 unknown。
5. 重复统计仅限同张量版本、格式、源/目标和明确逻辑字节范围，计算区域并集及累计交集，支持部分重叠；只输出“重复候选字节”，不能直接扣成可省流量。驱逐重载、不同消费者、重算/布局转换、版本改变须独立解释。矩形/跨步切片先展开为真实行区间，不能按外包围地址误算。
6. 分别给出算法唯一字节、调度流量、模型 AXI 握手流量、实际硬件计数；未采集的层级标未测。有效带宽按有效字节/全窗口时间，busy带宽另列，明确B/s与GB/s，峰值只用实际端口配置。
7. 给出带宽匹配 PE 数 `P≤B_eff·I/f_compute`，其中 I 的读/写、布局/QDQ、补零、C重载和参数预装口径一致；物理 DDR 共享读写调度需单独建模。依赖阶段分段求和，可重叠段才取 max，不能直接全图套 max。

## 必须展示的结果

- 时间轴：R、W、DDR、片上端口、阵列各一行，显示张量、阶段及等待原因；缺采样覆盖可见。
- 搬运Top表：按算子/张量列唯一区域、累计流量、重复候选、填充/对齐及原因。
- 空闲与等待Top表：时间范围、主原因、阻塞源、证据、可实施改进。
- 优化前后用相同输入、数值合同、窗口及资源模型；报告真实握手并发，不以 prefetch 名称或 busy 标志作证。

运行 `python3 scripts/selftest.py` 验证工具自身。工具的示例和自测不等于被分析工程已完成接入，不自动授权修改工程或运行板卡。

## Roofline 与忙状态口径

展示性能或定位瓶颈时，先区分 `busy`、FSM处于计算阶段和逐PE有效MAC。旧trace若把busy采样命名为compute，分析器会依据明确busy证据标为busy，并保留original_state；不能由busy或FSM阶段时长推导有效MAC利用率。

Roofline使用同一次任务的有用运算N、同一命名存储边界的实际读写总字节Q和完整完成窗口T，计算I=N/Q、P=N/T。量化矩阵可约定1 MAC=2整数运算，不能称FP FLOPS。分块补齐与有用运算分别保留。

带宽上限必须来自端口合同或独立带宽基准，不能使用Q/T反推roof。共享读写通道不相加；独立通道需保留方向限制。明确逻辑模型与板级测量、理论峰值与持续带宽。无可靠频率时使用OP/cycle和B/cycle，不补造MHz。

traffic-ledger负责Q、重复候选及字节对账；module-activity-waveform负责T与等待/排空归因。有逐PE有效事件时才能报告有效计算重叠。Roofline之下的空隙不能仅凭点位断言全由带宽造成。

已明确上述合同后，可用 `python3 scripts/roofline.py spec.json --out roofline.json` 核算。spec包含scope、memory_boundary、peak_source、bandwidth_source、bandwidth_basis（interface_contract或independent_benchmark）、clock_relation（same_cycle_domain）、traffic_basis（bus_bytes或valid_bytes_equal_bus_bytes）、peak_ops_per_cycle、bandwidth_bytes_per_cycle；cases逐项提供M/N/K、read_bytes、write_bytes、cycles、source。工具只计算有用GEMM的2MNK，不把不同算子操作数混在一起；共享或全双工限制应先在spec中正确确定。

Roofline的Q还须声明字节口径：默认使用命名接口的实际bus/wire字节，包括补齐或无效字节占用；有效数据字节另列。只有已验证valid_bytes等于bus_bytes时可直接互用，不能用较小的逻辑数据量搭配较大的物理峰值伪造计算强度。
