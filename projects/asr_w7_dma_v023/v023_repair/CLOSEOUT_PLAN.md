# 本地逻辑收尾

1. 第二轮数值核接入系统真实AXI图测试。
2. matrix->stream fusion->A16真实片上链与对照。
3. 异常排空/隔离/复位恢复与统一计数。
4. 主agent冻结合格SHA、统一filelist并独立回归。

全模型150秒对照另需原版ONNX、真实591依赖及profiled_backend/lowbit_executor/vm_abi等，目前缺失；不能把小链结果外推成全模型秒数。没有板卡/Vivado/STA范围。
