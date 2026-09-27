# 复现入口

## 不接触硬件的检查

在仓库根目录执行：

```bash
python -m pip install -r requirements-checks.txt
python tools/check_repository.py
python tools/run_checks.py --suite python
python tools/run_checks.py --suite rtl
```

Python 回归检查 V5 传输协议、冒烟报告判定与独立比较器的合成数组正反例。RTL 回归需要 `iverilog`、`vvp`，实际执行四个原 testbench：UDP 桥、UDP 接收保护、PHY 初始化与 ARP 直连。

## 单头项目的完整离线软件验证

```bash
python tools/prepare_local_assets.py --archive-dir /path/to/解压归档 --project head
python tools/run_checks.py --suite head
```

该步骤恢复原 `.pth` 权重、参数输入镜像及参考 `.pt` 到被忽略的本地目录，核对原包 manifest 中的 SHA-256。`--suite head` 使用已安装的 PyTorch 执行原有单元测试，不下载新权重，也不访问 FPGA。原运行环境版本见项目 `requirements.txt`；运行此检查不等同于重跑实板。

## Vivado / Vitis HLS

单头项目的目标是 `xc7a35tfgg484-1`、50 MHz，原工具记录为 2025.2。保留生成 RTL，可直接用 Vivado 构建；修改 HLS 源码后需重新综合。

```bash
python tools/build.py --project head --action build --vivado /path/to/vivado
python tools/build.py --project head --action hls --vitis-run /path/to/vitis-run
python tools/build.py --project head --action cosim --vitis-run /path/to/vitis-run
```

ASR V5 的原设计使用 `xc7a35tfgg484-2`、50 MHz。-1 与 -2 来自两份不同工程的原配置，不应自动统一；根据实际器件核实速度档。先生成 AMD FMA IP，再进行新的实现：

```bash
python tools/build.py --project asr --action fma --vivado /path/to/vivado
python tools/build.py --project asr --action build --run board_rebuild_001 --vivado /path/to/vivado
```

入口为 Vivado 设置当前 Python 路径，避免依赖原电脑的 `D:/app/...`。硬件烧写保留各项目原脚本，需根据实际 JTAG、串口、网卡与工具安装位置配置。

V5 数值 XSIM 需先用 `diagnostics/rtl_numeric_vectors.py` 生成向量，然后调用项目 `scripts/simulate_numeric.tcl`，最后再次运行向量脚本检查输出。该步骤需要 V2 软件依赖和 AMD FMA IP，本次没有在缺少 Vivado 的环境中重新执行。

## V5 原模型黄金验收

外部资产包括原 encoder/decoder ONNX、完整 `random200_v1` 黄金案例目录、V2 冻结清单内的其余文件，以及实际部署位流。恢复当前归档所含 V2 文件：

```bash
python tools/prepare_local_assets.py --archive-dir /path/to/解压归档 --project asr
```

该命令只恢复 V2 清单内的本地文件，不代表整个模型验收资产已齐备。随后安装与原验收匹配的 ONNX/ORT 环境，在 `projects/asr_qdq_fpga/v5/` 显式传入路径：

```bash
python scripts/run_golden_ethernet.py --validate-only \
  --case-dir /path/to/random200_v1/cases/case_0000 \
  --model-dir /path/to/int16_qdq_fix01
```

实板运行还需 `--allow-hardware`、新输出目录、位流身份文件及实际主机/FPGA IP。所有验收仍使用原容差；第二例已知失败不会因为整理、编译或协议单元测试通过而消失。

历史 Windows PowerShell 包装脚本保留供原环境参考；跨平台离线回归和构建优先使用仓库根 `tools/`。
