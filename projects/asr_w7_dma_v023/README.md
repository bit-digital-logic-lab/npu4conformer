# ASR FPGA：W7p8 / A16 / C48、PL 自主 DMA

本工程基于 Model A V0.22，研究 Conformer/Transformer ASR 的 FPGA 数据流、DDR 搬运、矩阵流水和算子融合。目标是主机启动前一次性预装输入、权重和执行计划，此后由 PL 调度器和 DMA 完成运行，不由 PS CPU 逐算子搬运或回主机计算。

**当前是多个可复跑的逻辑候选，尚未合成一个完整模型验收通过的发布版本。** 本轮没有运行 Vivado、综合、布线或上板；300/600 MHz 是目标，没有时序达标证据。历史约150秒是旧平台完整推理时间，下面局部周期不能换算为新的整模型秒数。

## 最新 V0.24 快照

[发布状态与整体时间口径](v024_opt/PUBLISH_STATUS.md)：统一受测小图18,724拍，按125MHz换算约150微秒；完整模型新时间未知。重点融合测试通过，完整安全回归仍9项未通过，不能称最终整机版。

## 架构与数值约定

- 矩阵路径：16×16 阵列、A16、特殊 W7p8 编码（保留 positions/clip/parity 语义）、C48 累加。W7p8 在 DDR 中按字节存放，不能按7bit理论容量计算带宽。
- 主机只预装一次；图控制器从 DDR 读取描述符，驱动 matrix / vector / layout，最终 DONE/错误出口。
- 共享存储接口为 AXI128 逻辑模型。原平台使用 Zynq PS 硬 DDR 控制器：PS CPU 不参与运行期控制，不等于绕过 PS 硬 DDR 控制器。
- FMA 保持单次舍入；转换与量化保留约定的 RNE/饱和边界。DIV/SQRT/RSQRT 允许近似，误差必须单独量测。
- 当前模型为512维 ASR（12 encoder + 6 decoder），不是旧 IC 竞赛的 KWT-1；不能套用旧64维/99元素的精度范围。

## 已测结果及边界

| 对照 | 基线→候选 | 证据范围 |
|---|---:|---|
| 32×32×32矩阵＋后处理小链，默认 | 53,015→21,121拍（约少60%） | 启动至完成并排空；控制方式不同，仅对应受测小链 |
| 同小链，随机背压 | 55,014→23,744拍（约少57%） | 最终I16与C48核对通过 |
| 同小链，长存储等待 | 87,973→33,660拍（约少62%） | 单时钟存储BFM，无物理DDR时间模型 |
| FMA→DIV→SQRT数值计划 | 45,785→16,589拍（约少64%） | 精确/近似同计划；FMA 2048例零失配，DIV最大相对误差约0.111% |
| A16流式输出改进 | 18组同负载约少20%～33% | 256/1024/4096 beat，转换/FMA、不同背压；独立输出/tag核对 |
| 矩阵片上融合初步日志 | 默认4,397→2,122拍；随机6,013→2,405拍 | 每个1024元素结果消除6144B C48写入＋6144B读回；待主验收 |

这些收益来自不同实验，**不能相加或相乘当作全模型收益**。融合任务生成了23项通过报告，但智能体进程退出1，原始状态保留，最终验收尚未关闭。安全任务已报告26项通过，数值/安全/融合仍是独立快照，尚未统一为一个最终配置。

主 agent 亲修的 stream 候选完成65项独立回归：修复参数有效位、禁止忙时改参数、避免等待控制请求堵住旧burst，A16与packed独立缓冲/tag；修正测试漏传参数、失败退出码与旧结果残留。它只有两词广播参数（addr0 scale、addr1 bias），没有逐通道参数或FP32 spill。

## 目录与优先阅读顺序

```text
work/                         V0.22基线源码、主机软件、测试与历史材料
v023_repair/
  primary_stream_fix/         主 agent 亲修stream，65项回归与独立tag接口
  integrated/                 原9节点精确小链，可运行但不含最新融合/数值/安全全部补丁
  ds_closeout_numeric/        真实FMA/approx接入共享AXI图路径，含abort/reset测试
  ds_closeout_safety/         SEQ互斥、watchdog、故障隔离、计数修复
  ds_closeout_fusion/         matrix→片上FMA→A16→AXI写回候选
  ds_cycle_chain_compare/     三种存储条件的小链周期对照
  ds_cycle_stream_compare/    18组stream同负载对照
  primary_acceptance/         主验收历史；旧失败应结合后续修复结果阅读
  ds_numeric_adversarial/     独立参考与对抗测试，原失败证据保留
  ...                        各阶段独立候选、审查和报告
skills/                       搬运账本与模块活动波形工具
research/                     板卡/带宽资料与理论下界
analysis/                     实际RTL搬运采样实验
timing_baseline/               旧V0.22布线报告，不是新版时序
SOURCE_MANIFEST.json           本次归档文件及SHA
EXTERNAL_ASSETS.json           未上传的大资产路径、大小与SHA
```

内部相对目录暂保留，避免破坏已有脚本依赖。各候选的 `REPORT.md` / `INTERFACE.md` / `result.json` 才是其具体受测范围；早期PASS不是当前整机PASS。根目录 `EXECUTION_CONTRACT.md` 记录当时的运行范围，后续用户明确允许的发布操作不受旧“禁止push”任务文本限制。

## 复跑

依赖：Python 3（部分参考脚本需要 NumPy）、Icarus Verilog（iverilog/vvp）、部分检查使用 Verilator、bash/timeout。发布时未再次运行全部RTL回归，表格来自保留的运行证据。

历史脚本包含原机器绝对路径；先生成本地工作副本（不改归档原件）：

```bash
python3 tools/materialize.py /tmp/asr-v023-local
cd /tmp/asr-v023-local
# 准备独立参考依赖：python3 -m pip install numpy
cd v023_repair/primary_stream_fix
python3 run_regression.py
```

其他候选分别运行，不表示统一系统已验收：

```bash
cd /tmp/asr-v023-local/v023_repair/ds_closeout_numeric
bash run_all.sh
cd /tmp/asr-v023-local/v023_repair/ds_closeout_safety
bash scripts/run_safety.sh
cd /tmp/asr-v023-local/v023_repair/ds_closeout_fusion
bash scripts/run_all.sh
cd /tmp/asr-v023-local/v023_repair/ds_cycle_chain_compare
bash run_all.sh
cd /tmp/asr-v023-local/v023_repair/ds_cycle_stream_compare
bash run_all.sh
```

完整源码/可生成小型fixtures优先保留。原ZIP、权重bin、大型输入/黄金镜像、编译缓存和智能体原始对话不入库。受影响运行需按 `EXTERNAL_ASSETS.json` 恢复对应资产，或用该候选生成脚本重建小fixture；缺失原模型不能由小fixture替代。`materialize.py` 只改代码中的原机器路径，不保证补足缺失资产。

## 尚未完成

1. 数值、安全、融合合并到唯一最终顶层并做独立回归；核查融合任务退出1的原因。
2. sealed payload仍有旧地址，需重新生成/重定位；完整591真实数据依赖、原ONNX与部分host executor缺失，未证明完整CASE0000纯PL执行。
3. 全模型WER/CER与量化精度；不能用旧KWT范围代替本模型标定。
4. 存储地址检查、FMA宽移位/加法/规格化仍有长组合锥；没有新版综合/STA，未知实际最长路径与Fmax。
5. 真实板卡DDR、CDC、多时钟与300/600MHz未验收。旧报告实际主时钟125MHz，最差setup裕量0.055ns，不代表新版。

## 来源与发布

基线来自本地 `model_a_v0_22(1).zip`；原始解包清单见 `EXTRACT_MANIFEST.json`，外部大包SHA见资产清单。原始源码与第三方声明保留；本次没有额外授予源码开源许可证。代码仅推送到组织私密仓库。
