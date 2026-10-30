# 主agent亲自修复：流式模块与验收工具

## 结果
主候选在5种背压模式（无背压、双路随机、仅packed随机、仅A16随机、长周期停顿）下65项全部通过；每次均重新编译真实RTL，使用DS独立参考。还检查valid/payload在stall期间稳定、忙时参数不可写、控制请求等待期间数据继续排空。负对照旧版失败且退出1。Gemini第二版scale预装在修正测试台后通过，但bias-only会激活未初始化scale产生X，返回非零，主版不再有该问题。

## 亲自修改的RTL
- 参数由虚设的256词表收窄为2个有真实用途的广播寄存器：地址0 scale、地址1 bias。有效位独立，单独写bias不会读取未初始化scale。地址2..255不接收；不宣称per-channel参数支持。
- 参数仅在engine完全idle时接受，配置请求优先。控制valid在busy期间等待时不阻止剩余输入排空，避免互等。
- 配置就绪前不接受数据；配置/参数真正握手的当拍不接收新数据，避免使用旧配置。
- A16增加一个elastic输出寄存器；与128位packer作为两个独立输出，消除共享tag和重复握手。packed tag新增独立a16_packed_tag端口，禁止继续用a16_tag读取packed标签。
- packed旧数据消费与新数据装入可同拍发生，消除互斥空泡。

## 亲自修正的测试
- run_suite.py实际传PARAM_EN/PARAM_ADDR/PARAM_DATA给vvp。此前113失配是测试漏传参数，不能据此断言第二版scale口仍然失效；原始旧版端口确实未实现。
- 任一子项失败使用sys.exit(1)，负对照确认为非零。回归启动前删除旧result，执行失败不得读旧PASS。
- 按parameter用例区分日志文件名，避免覆盖；新增bias-only预装、pending cfg/param请求、稳定性断言、第三/第四背压模式。packed标签在新接口上独立验证。

## 同负载测量
256个C48 beat（4lane/beat）、转换旁路、两消费者始终ready：
- Gemini版：A16第11..393拍（256次），packed第13..394拍（128次）。
- 主版：A16第12..267拍（256次），packed第13..267拍（128次）。
最后packed输出提前127拍；A16稳态每拍一组。以上是testbench周期，不是板卡主频或全模型收益。

## 范围与接入
仅本地逻辑仿真；未综合/STA/上板，不声称300/600MHz。整合DS另行处理地址重定位、共享AXI、异常排空和完整图。
两个输出都产生数据：仅用packed时a16_ready必须置1以丢弃旁路；仅用A16时packed_ready也需置1以排空。cfg_ready等待两路排空。预装值在之后配置中覆盖对应cfg值，直到reset/abort清除有效位或写新值。共享4lane广播，per-channel索引仍未实现。cfg_spill_fp32仍是旧接口预留项，未实现/未验收，本回归固定0；C48 spill已经测试。
FMA/转换来自gemini_fma_round2，数学证明仅限已有独立向量集；没有全模型WER/CER证据。

复跑：`python3 run_regression.py`。每次预计约一分钟。lint.log中仍有宽度/未用信号警告；无LATCH/MULTIDRIVEN/UNOPTFLAT或致命错误，lint不能替代STA。
