# ASR v1 文件恢复与启动

2026-11-13 补充。针对固定的 AXU15EGB、JTAG 串号 `210512180081`、镜像 `0xA51A2493`。
这些补丁没有改变 RTL、阵列、数值格式、位流、权重或 ELF，也没有重新综合。

## 先取得完整文件

1. 在仓库网页切换到 **asr-v1-release** 分支，使用 **Code → Download ZIP**，解压后打开 `projects/asr_v1`。原 `v1` 标签保留 2026-11-04 的快照，自动生成的旧版 Source code ZIP 不包含此次补丁。
2. 打开 [v1 Release](https://github.com/bit-digital-logic-lab/npu4conformer/releases/tag/v1)，下载 **asr_v1_assets.zip**。它与页面自动生成的 Source code ZIP 是两个不同文件。
3. 在 `projects/asr_v1` 中双击 **restore_assets.cmd**，点击“选择 ZIP 并恢复”。需要已安装 Python 3.10 或更高版本及 Tk；Windows Python Launcher 可自动寻找解释器。此工具不需要 PyTorch 或 Vivado，也不访问开发板。
4. 工具核对 ZIP 大小、整体 SHA-256 和 68 个成员文件的大小与哈希，并按原目录恢复。已有相同文件会跳过，已有不同内容会停止，不覆盖。也可点击“检查本地附件”复查。

不用工具时，用资源管理器打开 ZIP，把里面唯一的 `asr_v1` 文件夹与源码的 `projects/asr_v1` 合并。不要解压成 `projects/asr_v1/asr_v1`；只有源码没有附件无法部署。

附件精确大小：1,249,045,103 字节。SHA-256：
`e10392a684b04bf869dbc94c5ed0edcbe32db8d58901b7febdfd66de038c3153`。

截图中提到的三个文件都在附件内，路径相对于 `projects/asr_v1`：

| 文件 | 精确大小 | 正确位置 |
|---|---:|---|
| 位流 | 20,511,274 B | `work/v024_ddr_resident/physical_native/physical/build/candidate_A51A2493.bit` |
| DDR 权重 | 84,994,048 B | `work/v024_ddr_resident/native_model/weights.bin` |
| 基线 PS 固件 | 169,984 B | `work/v024_ddr_resident/native_ps/build/encoder.elf` |

不要使用 `perf_candidate/generated/` 下的同名实验 ELF 替代基线。模型原始资源、PS 初始化 Tcl、矩阵固件源码和主机端驱动也已打包；PS 初始化 Tcl 在源码中，原始模型在附件中。

## 哪个才是实际驱动

当前页面使用以下调用路径，完整 Conformer 编码器在板上执行：

```text
operator_ui/server.py  mode=hybrid
  → native_host/backend.py  NativeHybrid
  → native_ps/resident_host.py  BoardEncoder
  → native_ps/resident_host.tcl  XSDB / PSU-DAP
  → encoder.elf（PS）+ candidate_A51A2493.bit（PL）
```

`ASR_RESIDENT_ADAPTER` 只属于 `mode=board` 的可选外部插件接口。正常 v1 UI 不需要设置这个变量；`_native_command()` 的缺省报错不表示本项目的板端驱动不存在。默认 HTTP 请求和启动链接现已明确指向 `mode=hybrid`。

## 环境与板卡准备

1. 使用 Vivado/XSDB **2025.2**。默认工具路径是 `C:/Academic_Application/Vivado/2025.2/Vivado/bin`。安装位置不同时，在 Windows“编辑账户的环境变量”中新建 `ASR_VIVADO_BIN`，值填本机实际的 `Vivado/bin` 文件夹；重开启动窗口。
2. 默认 ASR Python 位于 `projects/asr_v1/ASR/environment/envs/ASR/python.exe`。若使用另一个已配好的同版本环境，在同一设置页新建 `ASR_PYTHON`，值填该环境 `python.exe` 的完整路径。只安装普通 Python 只能恢复文件，不能运行语音前端；ASR 依赖见 `ASR/environment/requirements-ASR-lock.txt`。已安装的数 GB Python 环境没有打包。
3. 关闭其他使用本板的 UI/调试器，连接电源和 JTAG。冷启动要求 APU 仍在复位，不能同时从 SD 卡启动操作系统。本流程不自动重置正在运行的 A53。型号相同但 JTAG 串号不同的板，仍需适配并重新验收，不能只改一个配置就假定兼容。

## 生成本机凭据

准备完成后双击 **cold_start.cmd**。日志保存在 `work/v024_ddr_resident/cold_start_runs/<本次时间与编号>/`。它顺序执行现有步骤：

1. 离线核对附件和静态实现记录；实现记录可从 `evidence/` 读取，仍校验位流、综合输入和实现脚本哈希及已通过的时序报告。
2. 独占指定板卡，归档并撤下旧活动指针；初始化 PS DDR，确认 APU 复位。
3. 烧入固定 2493 位流并读取真实镜像号；冷启动允许空白 `USR_ACCESS`，其他未知镜像仍拒绝。
4. 采集冷启动首个七节点图的 8,192 个输出字，调用原独立校验器。
5. 下载固定基线 `encoder.elf`；执行 boot、A53 自检、PL 矩阵测试，按原始 mailbox/output 再校验。
6. 加载权重到 `0x10100000`，完整读回并比较 SHA-256。只有全部通过才生成下表中的活动文件。

| 活动文件 | 来源 |
|---|---|
| `board_test/active_qualification.json` | 指向本次七节点图的独立验证结果 |
| `native_model/ACTIVE_BOARD_WEIGHTS.json` | 本次固件启动、自检及完整权重读回结果 |
| `native_ps/runs/<本次编号>/{boot,selftest,pltest}/verified.json` | 本次原始邮箱、矩阵输出的独立校验 |

这些不是遗漏的发行文件；复制 `evidence/` 下的旧活动 JSON 会错误冒充当前硬件状态。断电后须重新运行冷启动。若脚本失败，查看本次 `result.json` 和对应日志，保留现场，不手写 `passed: true`。

## 打开识别界面

冷启动输出 `COLD_START_PASS` 后，双击 `work/v024_ddr_resident/operator_ui/start.cmd`。打开的是 `http://127.0.0.1:8765/?mode=hybrid`。点击“初始化实板”，建立常驻 XSDB 会话并加载电脑端 CPU 前处理/CTC，然后录音。

冷启动检查和一次性权重读回不计入热识别用时；后续每次录音只发送特征并接收编码结果，不反复加载全模型。网页的“初始化实板”只建立识别会话，不代替上面的板卡烧写与冷启动验收。

## 此次补丁验证范围

附件完整性、恢复工具的成功/缺失/损坏/冲突/越界路径行为、离线实现验收、启动失败时撤下旧活动指针、现有原始读回数据的校验可以离线验证。修复记录见 `repair_validation.json`。

此次补丁没有执行新的硬件冷启动，也没有在全新电脑从零安装 Python 环境。新冷启动编排和空白镜像分支仍需实板验证；历史板测结果不计作本轮成功。原 `package_validation.json` 是 2026-11-04 打包时的记录。
