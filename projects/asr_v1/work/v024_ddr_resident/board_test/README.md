# AXU15EGB DDR 首图验收

该实验使用同一块 210512180081 板上的 0xA51A2493。通过 XSDB 的 PSU/DAP 写入两个 64 KiB DDR 窗口和 64 个系数，PL 经 HP0 执行原有七节点图。A53 可保持复位。需要 Vivado 2025.2 的 XSDB、本机 Python 3 及原工程中的冻结输入和校验器。

先由部署流程完成 PS DDR 初始化、烧入本轮位流并读取 USR_ACCESS。它要把本次读回保存为文本，三行分别为 usr_access=0xA51A2493、part=xczu15、serial=210512180081。保持算子复位，不要运行其他图。以下命令的输出目录必须尚不存在。

    & $xsdb "$boardTest/run_once.tcl" --capture-live $newRun $liveIdentity $python release

release 使用本设计生成的 PS 文件执行两项 PS/PL 隔离解除及复位释放操作。如果部署已经完成这些操作，传 already-released。两者都先检查板控默认的核心复位仍然有效，再允许加载和执行首图。板卡验收期间需要独占该板。

output_raw.bin 是从 DDR 物理地址 0x04004000 读出的 32,768 个字节。csr.tsv 记录寄存器、硬件计数器、输入地址测试和第一次 START。verification.json 给出 8,192 字的独立比较结果，分别覆盖 A16、复制、DIV、SQRT 和未改写区。独立 PS/DAP 读写检测覆盖三个定点区域。七节点算例本身验证工作窗口中的 PL/HP0 数据路径。时间换算使用实现约束的 20.625 ns 时钟周期，同时要求板上 PL0_REF_CTRL 的有效位与该配置吻合。可针对同一份采集重新进行离线校验。

    & $python "$boardTest/verify_ddr.py" verify $newRun
