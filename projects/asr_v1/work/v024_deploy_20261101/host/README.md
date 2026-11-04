# V0.24 板上小图验收工具

仅用于 `AXU15EGB / XCZU15EG` 上的 V024、128 节点容量控制器、七节点 fused 测试图。两块 64 KiB BRAM 替代仿真 BFM 的 arena/parameter 区域；此结果不代表完整 ASR、DDR 带宽或识别精度验证。

## 入口

由主部署流程完成目标板识别、比特流下载和 Hardware Manager 连接，并对唯一的 JTAG AXI master 执行 AMD 要求的 `reset_hw_axi`。随后在同一个已连接的 Vivado Tcl 会话中调用：

```tcl
source C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/host/load_run_verify.tcl
v024_board_verify hw_axi_1 C:/Academic_Work/CIM_learning/work/v024_deploy_20261101/hardware/run_001 60000
```

可把第一个参数换成主流程识别的唯一 `hw_axi` 名称。最后一个参数为 START 之后的轮询超时（毫秒）。输出目录必须不存在，避免覆盖历史证据。`source` 只定义函数；本脚本不连接服务器、不下载比特流、不复位 PS，也不访问任何 PS 寄存器。

本机 Vivado 2025.2 的 `run_hw_axi` 没有逐事务超时参数；60 秒期限约束正常返回的轮询。主流程必须为整个 Vivado 子进程设置 600–1200 秒 watchdog，覆盖硬件总线调用卡住的情况。工具不使用会吞掉内部错误的 `-quiet`，不执行无限轮询。

Vivado 会设置自己的 Python 库环境；脚本通过 bundled Python 的 `-I` 隔离模式忽略这些变量，避免不同 Python 版本混用引起 `SRE module mismatch`。这是进程内调用参数，不更改系统环境。[Python 官方选项说明](https://docs.python.org/3.12/using/cmdline.html#cmdoption-I)

## 顺序与验收

1. Python 核验 10 个冻结参考文件，固定 fused 图、gold A16 和 JSON 参考的 SHA256；Windows 文本仅允许 CRLF→LF 规范化。三份输入二进制必须与冻结 BFM 图相同，长度必须为 65536、65536、256 字节。
2. 核对 board magic `A51A2480`、capacity `128`，先检查无 busy 和未完成事务，再把核心保持复位。
3. 使用 arena 尾部临时区的非对称字形，分别做“单字写→突发读”及“突发写→单字读”，独立确定读、写的 DATA 字序；该区随后被完整输入覆盖。
4. 先完整写入两个 64 KiB 区域，再分别完整读回比对，防止两地址窗错误别名到同一块 RAM。写突发最大 256 beats，读回采用 127 beats，同时限制不跨 4 KiB 边界。
5. 释放核心复位；核对原 CSR magic `A51A22D0`；逐个写 64 个 scale/bias 字，再逐字读取 board-control shadow。写响应必须在核心参数握手之后出现。
6. `PLAN_BASE @ +0x08 = 0x10008000`、`PLAN_COUNT @ +0x0c = 1`，读回核对后写 `START @ +0x10 = 1`。
7. 有界轮询原核心 CSR `+0x04` 的 `done_latched`，保存终态与从 `0x04004000` 开始的完整 32768 字节输出。核心 `done` / board-control 状态 bit1 只持续一个时钟，作为瞬时诊断，不能用来轮询完成。通过或失败都保留核心状态，不自动重启。
8. Python 独立检查 status、pending、completed、计数器、每份全量回读和全部数值。必须原 CSR 的 DONE=1、busy/fault/requires_reset=0、quiesced/fused=1、completed=7、三个 pending=0、C48外存字节=0、A16字节=2048；board status bit1 被掩码，其余位严格要求 `0x30`。last_node 必须在 0–6 内并保留诊断值，按依赖并发的完成次序随 AXI 延迟而变，不硬编码仿真的 last=6。board-control 与原 CSR 均连接同一 cycles 信号，在 DONE 后要求一致，周期数必须正数，不预设与仿真 TB 周期相等。

| 输出 | dump 内 32-bit 字偏移 | 精确数量 | 比对规则 |
|---|---:|---:|---|
| A16 | 0 | 512 packed words / 1024 INT16 | 逐字完全相同 |
| DIV | 1536 | 1024 FP32 | 相对误差 ≤ 0.0012 |
| SQRT | 2560 | 1024 FP32 | 相对误差 ≤ 0.000006 |
| A16 copy | 3584 | 512 packed words / 1024 INT16 | 逐字完全相同 |

所有结果和参考数组均先检查长度；任何 NaN/Inf、缺字、多字、尾项错误均失败。参考值为零时误差分母采用 1，遵循冻结参考规则。输出窗口其余 5120 字与已验证的冻结 arena 初始窗口逐字比较，要求保持不变。

## 证据文件

- `board_receipt.json`：板上状态、传输计数、读写字序、阶段与失败原因；字段为字符串。
- `axi_transactions.tsv`：每次调用的 BEGIN/END、地址、beat 数、原始 DATA、暴露的 transaction/master 属性；卡住时最后一条 BEGIN 定位边界。
- `arena_readback.hex`、`param_readback.hex`、`pc_readback.hex`：完整读回，按递增地址逐行 32-bit 十六进制。
- `output.hex` / `output.bin`：完整 8192 字 / 32768 字节输出；bin 为 little-endian。
- `verification.json`：严格验收结论、计数、误差、周期数与输入/输出哈希。
- `prepared/provenance.json`：准备时的冻结输入来源；验收时再次校验。

上传+回读时间与 START 至结束的主机观察时间单独记录；二者均不能冒充硬件算子周期或完整语音识别时延。实际时钟频率和时序收敛由主部署流程另行证明。

单独重验已保存结果：

```powershell
& 'C:\Users\liuka\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  'C:\Academic_Work\CIM_learning\work\v024_deploy_20261101\host\verify_v024.py' verify `
  --run 'C:\Academic_Work\CIM_learning\work\v024_deploy_20261101\hardware\run_001'
```

`tests/verifier_selftest.json` 为数值验收器的故障注入自测；`tests/tcl_mock/result.json` 为纯内存 Tcl transport 模拟的四种读写字序、全 64 KiB 地址顺序与越界拦截测试；`tests/flow_test_result.json` 为流程串联及模拟证据拒绝测试；`tests/flow_alias_test_result.json` 验证两内存窗别名时在释放核心复位前拒绝。它们都没有硬件访问，不能作为板验成果。

## 命令依据

- 本机安装的 Vivado 2025.2 帮助已保存于 `installed_vivado_help.log`，通过只加载 labtools 帮助模块取得。
- [AMD PG174 JTAG to AXI Master](https://docs.amd.com/api/khub/documents/LqQTk0RcZiVWPLA84Eji0A/content)：INCR burst 为 1–256 beats。
- [AMD UG835 create_hw_axi_txn](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/create_hw_axi_txn)：DATA、len 与 hw_axi 对象调用方式。
- [AMD UG908 write transaction](https://docs.amd.com/r/2023.2-English/ug908-vivado-programming-debugging/Creating-and-Running-a-Write-Transaction)：DATA 方向文字与常见示例有歧义，因此运行时必须做上述独立字序校准。

已检索 GitHub 通用 [JTAG_TO_AXI](https://github.com/jimaandro/JTAG_TO_AXI) 和 [dump 示例](https://gist.github.com/wipeseals/8300710204c4c766132151611a1cf44b)。它们提供通用事务思路，未证明本项目的长度、冻结参考、参数握手和终态验收合同，因此本工具按 AMD 原生命令实现，没有引入其代码或额外依赖。

计时字段补充：`input_upload_ms` 为两块输入RAM上传，`input_readback_verify_ms` 为两块完整读回校验，`output_readback_and_save_ms` 为输出32KiB读回与保存；均为主机墙钟毫秒，不能当成纯总线传输或核心计算时间。新增字段通过纯模拟流程检查，仍待实板采集。
