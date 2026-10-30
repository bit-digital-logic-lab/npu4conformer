# JSONL 事件格式 v1

所有事件使用单一 JSON 对象。第一行必须 metadata。每行 `type` 必填；无未声明字段语义时不可猜测。

```json
{"type":"metadata","schema":1,"scope":"example tile; preload excluded","resources":{"axi_r":{"unit":"cycle","clock_hz":125000000,"start":0,"end":1000,"capacity_bytes_per_tick":16,"evidence":"cycle_model"},"host":{"unit":"ns","start":0,"end":100000000,"evidence":"python_wall"}}}
```

资源unit为cycle或ns；周期资源clock_hz缺失时只输出B/cycle，不编造B/s。start/end是观测窗口，不能从第一条传输到最后一条传输推断整个任务时长。capacity可选，必须是单资源实际峰值。主机ns是相对当前记录器单调时钟起点，不能与设备cycle直接对齐。跨域映射放项目单独sidecar记录。

```json
{"type":"transfer","id":"rd7","resource":"axi_r","start":20,"end":45,"tensor":"W","version":"layer3:immutable","format":"W7p8","src":"DDR","dst":"Wbank0","op":"ffn1","phase":"prefetch","reason":"first_load","logical_offset":0,"logical_bytes":256,"valid_bytes":256,"bus_bytes":256,"request":18,"first_data":20,"last_data":44,"completion":45,"cache":"miss_compulsory","descriptor_id":7}
{"type":"interval","resource":"axi_r","start":20,"end":21,"state":"payload","bytes":16,"wire_bytes":16,"transfer_id":"rd7","reason":"weight_read","evidence":"RVALID&&RREADY"}
{"type":"interval","resource":"axi_r","start":21,"end":26,"state":"wait_memory","bytes":0,"blocked_by":"DDR","reason":"outstanding_nonzero_rvalid_low","evidence":"model queue state"}
```

transfer是账本，**不是总线占用区间**。多笔在途的transfer跨度可以交叠；interval才是每个资源的互斥时间分区。不要把跨度全部记payload。总线统计从interval算，transfer只做张量流量/重复账本，两者不能相加。transfer各资源账本对总线字节的覆盖差值会输出，非零须解释；命令/响应跨范围、预装、未标记事务或模型错误均可能产生差异。

状态不限定硬编码枚举，建议：payload、command、wait_memory、backpressure、starved_input、fifo_full、bank_conflict、rw_turnaround、compute_dependency、drain、idle_no_work、compute、unknown。状态必须有观测依据；command计时间不计data字节；compute/idle等不加payload字节。

logical_offset/logical_bytes是同格式张量序列化后的有效逻辑字节半开区间，不能为空洞跨度的外包围盒。重复候选按(tensor,version,format,src,dst)分组，资源不改变逻辑身份；跨不同dst的重用机会需要另作消费者分析。多维slice另附slice字段并为每行发子记录，避免重叠计数。版本和地址映射的证明由调用者负责，默认不根据地址猜张量。

同一大DMA请求包含多个张量时，要用子transfer拆分，保证字节不双计；同一transfer跨多个资源时建立显式hop ID与parent_id，资源账本只在各hop内对齐，不能将所有hop累加为DDR流量。

传输起止、request/first_data/last_data/completion必须属于同一声明资源的时间域。last_data是最后一拍起点，end/completion是半开完成边界。记录失败status和已接受/已完成字节，不能把计划字节当成功搬运字节。重复只在显式成功且实际有完整逻辑区间的记录上计算；失败/部分完成若区域未知要标unknown并排除重复推断。
