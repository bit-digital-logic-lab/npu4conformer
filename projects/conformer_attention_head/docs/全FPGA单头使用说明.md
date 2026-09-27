# Model A Conformer 单头全 FPGA 工程使用说明

## 1. 本次实现的边界

本工程把 Model A encoder 中一个相对位置自注意力 head 的全部推理运算放进 FPGA。默认选择第 1 个 Conformer 层的第 1 个 head，即 layer=0、head=0。

| 参数 | 当前实现 |
|---|---|
| FPGA / Vivado Part | XC7A35TFGG484-1 / xc7a35tfgg484-1 |
| 输入 | norm_mha 之后的 FP32 张量 X，形状 [1,T,512] |
| 序列长度 T | 运行时可选 1～8 |
| 一个 head 的维度 | 64；原模型共有 8 个 head |
| 矩阵操作数 | FPGA 动态量化的有符号 INT16 |
| 内部工作数 / 累加 | INT64，工作格式含 20 个小数位 |
| 输出 | FPGA 完成 IEEE754 FP32 转换；主机直接接收 |
| 推理模式 | eval；不启用训练时 dropout |
| 时钟 / UART | 50 MHz / 115200，8 data bits，No parity，1 stop bit，No flow control |

模块输入从原模型 norm_mha 的输出开始。norm_mha 之前的 Macaron FFN、LayerNorm 本身、卷积模块、其他 head、后续残差及完整 encoder 都属于这个 head 之外的模块。默认输入是固定随机残差通过真实训练好的 norm_mha 参数形成的测试夹具；实物执行时直接读取已保存的 X 字节，不现场调用 LayerNorm。

整个 head 的运算包括 Q/K/V、位置投影、偏置 u/v、相对位置项、mask、Softmax、PV 和该 head 对输出投影的贡献。FPGA 没有 MicroBlaze、RISC-V 或其他软件处理器。

## 2. 数据从哪里来，计算在哪里发生

~~~mermaid
flowchart LR
    PC["电脑：原始 FP32 输入/权重字节"] --> UART["FPGA UART + CRC 数据桥"]
    subgraph FPGA["FPGA 内部"]
      UART --> Quant["FP32 解析与 INT16 量化"]
      Quant --> Proj["Q/K/V/P 投影与偏置"]
      ROM["片上相对位置 ROM"] --> Proj
      Proj --> Score["AC + 相对位置 BD + mask"]
      Score --> Soft["减最大值、指数 ROM、归一化除法"]
      Soft --> Out["PV、输出投影、共享 bias"]
      Out --> Float["FP32 输出转换"]
    end
    Float --> Result["电脑：保存结果字节"]
~~~

主机发送的权重是原始 FP32 位模式。每个输出通道的最大值、量化 shift、INT16 权重和投影结果都由 FPGA 计算。主机不传预计算 Q/K/V、Softmax 或输出投影。

单个 head 的 5 组矩阵各含 512×64 个权重，总共 163,840 个数；即使以 INT16 整体常驻也需要 2,621,440 bits，超过这颗芯片的 50 个 36 Kb BRAM。因此本实现逐输出通道流式接收原始权重，复用运算单元与存储。主机按固定 512-word 分包顺序搬运数据，FPGA 内的状态机自行推进运算，不向主机返回中间张量求下一步结果。

## 3. 和原模型的对应关系

权重按 PyTorch Linear 的 [out_features,in_features] 排列。head h 对应切片 h×64:(h+1)×64：

~~~text
Q = X @ Wq_h.T + bq_h
K = X @ Wk_h.T + bk_h
V = X @ Wv_h.T + bv_h
P = relative_position @ Wpos_h.T

AC[i,j] = (Q[i] + u_h) @ K[j]
BD[i,j] = (Q[i] + v_h) @ P[T-1-i+j]
scores = (AC + BD) / sqrt(64)
probability = masked_softmax(scores)
context = probability @ V
contribution = context @ Wout[:, h*64:(h+1)*64].T
with_output_bias = contribution + shared_output_bias
~~~

位置表包含从 T−1 到 −(T−1) 的 2T−1 个位置。直接访问 P[T−1−i+j] 与该模型的 rel_shift 操作等价。mask 的 1/True 表示可见，0/False 表示屏蔽。一个 query 的所有 key 都屏蔽时，该行概率、context 和 contribution 都是 0；with_output_bias 则等于共享输出偏置经 Q20 舍入后的值。

FPGA 返回四个数组：

| 字段 | 形状 | 用途 |
|---|---|---|
| context | [1,T,64] | 单头输出，在合并多个 head 前使用 |
| contribution | [1,T,512] | 单头经过自己那部分输出权重后的贡献 |
| with_output_bias | [1,T,512] | 单头贡献加一次共享输出偏置，便于本次独立测试 |
| probability | [1,T,T] | Softmax 的 Q30 结果转换为 FP32，便于观察 |

将来组合 8 个 head 时，应把 8 个 contribution 相加，再加一次共享 bias。不能把 8 个 with_output_bias 直接相加，否则会把 bias 加 8 次。概率输出是 Q30 精度；PV 运算还会把它舍入为 Q15 INT16，因此用返回的 FP32 probability 重新相乘不会逐位复现 PV 的量化过程。

## 4. INT16 量化规则

### 4.1 原始输入转换

FPGA 解析 IEEE754 FP32 位模式并转换为有符号 INT64 工作数：

~~~text
fixed = round_to_nearest_even(real_value × 2^20)
~~~

支持范围：X 的绝对值不超过 64；矩阵权重不超过 16；各 bias、u、v 不超过 4096。NaN、Inf、越界值会使 FPGA 返回非零错误计数，主机不会把它作为有效输出保存。Q20 分辨率以下的小值可能舍入成 0。

### 4.2 动态尺度全部由 FPGA 计算

对一个 token 的激活，或者一个输出通道的权重，扫描最大绝对值。选择最小非负整数 shift，使舍入后的值落在 [-32767,32767]：

~~~text
q = round_to_nearest_even(fixed / 2^shift)
real_approx = q × 2^(shift-20)
~~~

采用对称零点 0、2 的幂尺度。X、K、V、P、context 按 token/位置确定尺度；权重按输出通道确定尺度；Q+u 与 Q+v 分别确定尺度。bias 和两路 attention 分数在 Q20 工作格式中相加。尺度随每次输入及权重在板上重新计算。

主乘法操作数为 INT16，单次乘积为 INT32，求和及尺度调整为 INT64。这样既保持 INT16 数据路径，也给 512 项累加、注意力分数及偏置留出范围。不能将本工程理解为每一个中间寄存器都只有 16 bit。

### 4.3 FPGA Softmax

1. 忽略屏蔽 key，求可见分数最大值。
2. 计算与最大值的差 delta。
3. 读取 4097 项 Q30 指数表，表间隔为 1/256，并进行线性插值。
4. delta≥16 时指数设为 0。
5. 对指数求和，再用片上逐位恢复除法完成归一化。
6. Q30 概率舍入为 Q15 INT16 后用于 PV；数值 1 被表示为 32767/32768。
7. 全屏蔽行的和为 0，概率定义为全 0。

这些步骤都在 src_hls/conformer_head.cpp 中，综合后成为 RTL。src_hls/tables.h 是编译时 ROM 数据；运行时没有 CPU exp、softmax、除法、scale 或偏置处理。

## 5. 工程文件

~~~text
modelA_conformer_head_full_fpga/
  README_zh.md
  docs/                       中文使用说明与最终测试报告
  src_hls/conformer_head.cpp   完整 head 算法，中文注释
  src_hls/tables.h             相对位置及指数 ROM
  src_hls/testbench.cpp        HLS 仿真输入输出
  rtl/ax7035_top.sv            UART/CRC/复位/调度数据桥
  rtl/uart_rx.sv, uart_tx.sv   UART 接收发送
  rtl/generated/              HLS 生成的 .v/.dat 及文件清单
  constraints/ax7035.xdc       板卡引脚与 50 MHz 时序约束
  host/transport.py           纯字节传输客户端，实物推理入口
  host/export_image.py        离线打包原始权重与 X
  host/make_reference.py      离线生成原始 PyTorch 基准
  host/integer_reference.py   测试专用独立整数模型
  host/verify.py              测试专用结果比较
  host/test_full_head.py      舍入、mask、CRC 等单元测试
  scripts/                    环境安装、HLS、Vivado、下载脚本
  vendor/                     用户压缩包中的原始模型阅读源码
  weights/layer_0.pth         真实第 1 层原始 FP32 参数
  fixtures/                   T=4 默认样本，另含 t1/ 和 t8_masks/
  artifacts/ax7035_top.bit    已构建、已上板验证的最终位流
  artifacts/verified_t*/      最终三组实物结果和验证 JSON
  manifest.json              交付文件大小与 SHA256
~~~

解压包不包含 .venv、Vivado 临时工程、HLS 编译缓存及 465 MB 完整 checkpoint。它包含构建所需的 RTL/ROM、单层权重、默认输入、位流与测试证据。vendor/README.md 内的旧相对路径属于原始阅读副本，实际运行路径以本说明为准。

## 6. 板卡连接与英文 Windows 界面

1. 板卡接正常电源。
2. 接板卡的 USB-UART 接口，Windows Device Manager → Ports (COM & LPT) 中应出现 Silicon Labs CP210x USB to UART Bridge (COMx)。本次实测为 COM3。
3. JTAG 用于下载位流，UART 用于输入和结果；需要同时确认两个连接。USB Serial Converter 的名字不能单独确定 UART COM 号。
4. 在 Vivado 中选择 xc7a35tfgg484-1。已测试的 JTAG target 是 Digilent/210512180081，设备 xc7a35t_0。
5. 关闭串口助手等占用 COM 口的程序，再运行客户端。

| 信号 | FPGA 球位 | 说明 |
|---|---|---|
| sys_clk | Y18 | 50 MHz |
| sys_rst_n | F20 | 普通 RESET，低有效 |
| uart_rxd | G15 | FPGA RX，接 CP210x TX |
| uart_txd | G16 | FPGA TX，接 CP210x RX |
| led[0:3] | F19 / E21 / D20 / C20 | 低电平点亮 |

led[0] 是心跳，led[1] 表示忙，led[2] 表示最近一次传输完成，led[3] 记录本轮遇到的传输错误。错误重传恢复后 led[3] 仍可能亮，以主机最终 CRC、FPGA 错误计数及验证报告为准。

## 7. 首次建立环境

在 PowerShell 中进入工程目录。当前电脑已经完成此步骤；换电脑或解压到新目录时再执行：

~~~powershell
cd C:\Academic_Work\CIM_learning\modelA_conformer_head_full_fpga
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup.ps1 -Python C:\Academic_Application\Anaconda\python.exe
~~~

本次使用 Python 3.13.9、PyTorch 2.14.0+cpu、pyserial 3.5、NumPy 2.5.2。安装脚本在工程内创建 .venv，不替换系统 Python。只有传输客户端时仅依赖 pyserial；PyTorch 与 NumPy 用于离线数据准备及验证。

## 8. 直接下载位流并运行

包内已有已验证的位流，无需先运行 HLS 或重新综合：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Program
.\.venv\Scripts\python.exe -m host.transport --port COM3 --output artifacts\my_run
~~~

客户端打印 INPUT_PROGRESS，约 1 分钟后显示 FPGA_TRANSFER_PASS。默认 T=4，接收 4368 个 FP32 值。结果文件：

- fpga_output.bin：3 个 uint32 元信息加 FPGA 原样返回的 FP32 字节。
- fpga_output.json：同一字节流直接解包后的四个数组，行优先排列。
- transport.json：耗时、包数、重试、主机端位流文件 SHA256。

下载使用 JTAG 写入 FPGA SRAM；断电后需重新执行 Program。旧 GEMM/混合 head 客户端与这个完整 head 协议不兼容，请使用此目录的 host.transport。

Vivado 安装位置不同时：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Program -Vivado "D:\Xilinx\Vivado\2025.2\bin\vivado.bat"
~~~

若传输中途被终止，先按板卡普通 RESET 再重新运行完整输入。收到的最终结果 CRC 出错时，客户端报错退出，应 RESET 后重跑整次推理。

## 9. 用原始 PyTorch 独立核对

先完成上面的实物运行，再执行：

~~~powershell
.\.venv\Scripts\python.exe -m host.verify --output artifacts\my_run
~~~

verify 在电脑上执行测试参考，不参与 FPGA 推理。它先把 FPGA 的完整结果字节与独立整数参考比较，再与由原始 ESPnet/PyTorch 类生成的浮点基准比较。成功时生成 verification.json，包含：

- status: PASS
- all_fpga_outputs_bit_exact: true
- context、contribution、with_output_bias、probability 的误差
- 输入和输出 SHA256

通过标准：完整输出与整数参考逐位一致；前三类输出相对 PyTorch 的 max_abs≤0.1 且 relative_l2≤0.005（0.5%）。probability 的浮点误差单独记录，仍执行整数参考逐位比较。INT16 量化模型与浮点模型之间的差异在报告中明确列出。

## 10. 复现实物边界测试

~~~powershell
.\.venv\Scripts\python.exe -m host.transport --port COM3 --input fixtures\t1\input.bin --output artifacts\my_t1 --inject-crc-at 2 --duplicate-at 7
.\.venv\Scripts\python.exe -m host.verify --fixtures fixtures\t1 --output artifacts\my_t1

.\.venv\Scripts\python.exe -m host.transport --port COM3 --input fixtures\t8_masks\input.bin --output artifacts\my_t8
.\.venv\Scripts\python.exe -m host.verify --fixtures fixtures\t8_masks --output artifacts\my_t8

.\.venv\Scripts\python.exe -m host.test_full_head -v
~~~

T=1 的诊断故意破坏编号 2 的包 CRC，检查正确重传；重复发送编号 7 的包，检查 FPGA 只确认而不重复运算。T=8 屏蔽最后一个 key，并把 query 索引 2 的整行屏蔽。二者均已在最终位流上执行。

## 11. 重新构建 Vivado 工程

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Create
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Build
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Program
~~~

Create 生成 build/vivado/modelA_conformer_head_full_fpga.xpr。Build 执行综合、实现、时序检查及位流输出；失败时停止并返回错误。

英文 GUI 操作：

1. File → Open Project，打开上述 .xpr；或运行 run.ps1 -Action Open。
2. Flow Navigator → Synthesis → Run Synthesis。
3. Implementation → Run Implementation。
4. Program and Debug → Generate Bitstream。
5. Open Hardware Manager → Open Target → Auto Connect。
6. 选择 xc7a35t_0 → Program Device。
7. Bitstream file 选择 artifacts/ax7035_top.bit。

源码已经包含 rtl/generated 的 Verilog 与 .dat ROM 初始化文件，普通 Vivado 构建不需要安装 Vitis HLS。sources.txt 控制生成文件清单，重新 HLS 后 Create 会更新工程引用。

## 12. 修改算法及 HLS 验证

算法入口是 src_hls/conformer_head.cpp。修改后需要重新生成 RTL、构建并重新上板验证：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Hls
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Cosim
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Build
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run.ps1 -Action Program
~~~

Hls 使用 Vitis HLS 2025.2 的 vitis-run --mode hls --tcl 接口，先运行 C 仿真再综合，并复制 .v/.dat 到 rtl/generated。Cosim 用 xsim 执行 C/RTL 联合仿真。

脚本把 HLS 工程放在根目录的 core_hls。该路径结构已经在 Windows 2025.2 实测，保留它可避免嵌套 HLS 工程对源文件相对路径的解析问题。

修改 T 上限需要一起调整存储、位置 ROM、输入帧格式、主机长度检查和测试。当前已交付位流支持 T=1..8；不支持直接通过参数运行更长序列或改变到其他量化位宽。

## 13. 换输入或选择同层的其他 head

将实际的 norm_mha 输出保存为 tensor-only 文件，例如 my_x.pt，里面包含：

~~~python
{"x": x, "mask": mask}
# x: CPU torch.float32 [1,T,512]
# mask: [1,1,T] 或 [1,T,T]，1/True 表示可见
~~~

按原始 FP32 位模式打包并上板：

~~~powershell
.\.venv\Scripts\python.exe -m host.export_image --x my_x.pt --head 0 --output fixtures\custom
.\.venv\Scripts\python.exe -m host.transport --port COM3 --input fixtures\custom\input.bin --output artifacts\custom_run
~~~

离线生成对应的原始浮点基准并核对：

~~~powershell
.\.venv\Scripts\python.exe -m host.make_reference --fixtures fixtures\custom --head 0
.\.venv\Scripts\python.exe -m host.verify --fixtures fixtures\custom --output artifacts\custom_run
~~~

--head 可选 0～7，选择 weights/layer_0.pth 中同一层的权重切片；make_reference 必须使用相同 head。默认位流通用地读取这些原始权重，测试证据覆盖的是 head=0。

重建默认 T=4 固定随机测试输入：

~~~powershell
.\.venv\Scripts\python.exe -m host.export_image --seq-len 4 --mask-last-key --output fixtures\regenerated
.\.venv\Scripts\python.exe -m host.make_reference --fixtures fixtures\regenerated --head 0
~~~

T=1 省略 --mask-last-key；T=8 使用 --seq-len 8 --mask-last-key --all-masked-row 2。导出工具不做量化；无 --x 时才生成离线测试 X。实际运行只消费保存好的 input.bin。

## 14. 数据协议与恢复行为

所有多字节字段为 little endian。

### 原始推理数据

1. uint32 magic=0x48454144。
2. uint32 T。
3. 固定 8 个 uint32 mask 行，每行低 T 位有效。
4. T×512 个原始 FP32 X。
5. Q、K、V、P、Out 五阶段，按输出通道发送该通道的全部原始 FP32 权重，接着发送该通道 bias。
6. Q 阶段每个通道的 bias 后还发送该通道 u、v。P 无 bias，发送 0 占位。

总长度为 4×(10+512×T+164736) 字节。主机按 2048 字节切包，不读取或计算 Q/K/V 等中间结果。

### 输入包

~~~text
A5 C3
command:uint8 = 0x41
tag:uint16
word_count:uint16 = 1..512
flags:uint8 = 最后一包 bit0 为 1
payload:word_count×4 bytes
crc32:uint32
~~~

CRC 覆盖 command 到 payload，算法与 zlib.crc32 相同。FPGA 收齐且 CRC 正确后才提交数据。

ACK 为 5A C4 + status:uint8 + tag:uint16 + crc32:uint32，CRC 覆盖 status/tag：

- status=0：成功。
- status=1：输入 CRC 错误。
- status=2：UART framing error 或收包超时。
- status=3：格式/序号错误。

主机最多尝试 3 次。重复的上一包只回复 ACK，不重复提交。重复诊断目前用于非最后包。不会以 CPU 计算作为通信失败时的替代路径。

### 最终结果

~~~text
5A C5
magic:uint32 = 0x46504741
FPGA_error_count:uint32
output_count:uint32 = T*64 + 2*T*512 + T*T
context / contribution / with_output_bias / probability 的 FP32 字节
crc32:uint32
~~~

结果 CRC 覆盖 magic 到全部输出。transport.json 中 wire_attempts 包含正常发送和重试，不包含专门重复包诊断额外发送的 1 包。bitstream_sha256 是主机端下载文件的哈希；它不表示执行过 FPGA 配置存储器回读。

## 15. 测试证据与来源

最终测试、资源利用和限制见 [测试报告](测试报告.md)。检查代码时可从以下位置开始：

- 原模型：vendor/espnet2/legacy/nets/pytorch_backend/transformer/attention.py。
- 原 encoder 边界：vendor/espnet2/legacy/nets/pytorch_backend/conformer/encoder_layer.py。
- 全部片上算法：src_hls/conformer_head.cpp。
- 主机纯传输：host/transport.py。
- 独立测试整数实现：host/integer_reference.py。

真实 checkpoint 来自 [pyf98/librispeech_conformer](https://huggingface.co/pyf98/librispeech_conformer/tree/b74448c3b089eceea913735bd59a76d5252d8eec)，固定 revision 为 b74448c3b089eceea913735bd59a76d5252d8eec。完整 checkpoint SHA256、所含单层参数 SHA256、用户压缩包和原始源码哈希记录在 artifacts/source_provenance.json。THIRD_PARTY_NOTICES.md 保留原源码及权重来源说明。

测试使用真实权重与合成激活，结论是该 head 的功能、量化误差、RTL 和实物通信验证通过；没有进行真实语音数据集评估，也没有报告整个 ASR 模型的 WER。
