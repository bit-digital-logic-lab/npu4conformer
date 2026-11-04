# 复现说明与当前验证边界

## 固定平台

本版实测：ALINX AXU15EGB，XCZU15EG-FFVB1156-2-I，Vivado/XSDB 2025.2，A53裸机固件，PL周期20.625ns，镜像A51A2493。模型pyf98/librispeech_conformer固定修订b74448c3b089eceea913735bd59a76d5252d8eec，12层、512维、8头；135个静态W7矩阵，参数84994048字节。电脑仅CPU前处理及greedyCTC，不使用GPU。该硬件与工具属于指南3.3允许范围。

## 离线复核

1. 保存本包，确认Python>=3.10。运行skill/README.md中的compare及partition命令，成功退出码0。
2. 原工程项目根下可重新核对既有原始数据，以下命令是离线校验，不访问开发板：

       python work/v024_ddr_resident/native_ps/verify_receipt.py pltest work/v024_ddr_resident/native_ps/runs/20261102_215234/pltest
       python work/v024_ddr_resident/native_pl/verify_selftest.py work/v024_ddr_resident/native_ps/runs/20261102_215234/pltest/matrix_output.bin

## 从构建到上板的顺序

1. 安装Vivado/XSDB 2025.2及目标器件支持、AArch64裸机工具链，按ASR/environment中的环境记录准备CPU前端和CTC依赖，获取固定版本模型与LibriSpeech样本并核对哈希。
2. 从冻结RTL、IP和约束重新构建PS壳、父模块与16x16叶模块，连接后实现，检查资源、时钟、WNS/WHS及DRC。现有入口physical_native/run_parent.py、run_shell.py与run_join_fast.py绑定历史清单/路径，不能把它们直接视为已验证的通用一键构建器。
3. 板卡独占且APU复位后，按prepare_ddr.tcl初始化DDR，按program_resident.tcl载入已验收位流，读回镜像号。入口均保留门禁，不应跳过错误。它们也含当前板卡的JTAG串号；迁移设备须在发布配置中显式调整。
4. 先导出并校验native_model/weights.bin与model_index.h，再执行 python work/v024_ddr_resident/native_ps/build.py --encoder 编译固件。工具路径在build.py中配置，本版不是自动安装器。
5. 使用XSDB运行native_ps/run_xsdb.tcl的boot、自检和pltest；boot只接受复位中的目标，已有固件运行时不可盲目重载。按其用法传入新的结果目录与ELF路径。
6. native_model/load_weights.tcl接收weights.bin与新的输出目录，写入参数并完整读回；校验大小、SHA-256和会话一致后才生成本轮有效驻留记录，不能复制旧ACTIVE_BOARD_WEIGHTS记录伪装本轮验收。
7. 启动operator_ui/start.cmd，初始化常驻会话，打开localhost:8765。录音满10秒提交首段、20秒提交第二段；提前停止提交尾段。两段应顺序执行，错误保留已确认文字。核对原始响应的序号、输出形状、PL调用与GPU未使用。
8. 冷启动时间、单段服务时间、板内时间和录音墙钟时间分别统计。相同模型、输入哈希、量化、解码方式、工具/器件/时钟下再做优化前后性能和资源对比。

## 尚未闭合

本轮未在空白电脑、全新目录或第二块板上重新完成构建与部署。当前构建入口依赖历史验收记录，工具路径、模型缓存、串号、冻结IP与环境依赖需要进一步整理。因此本说明提供了已核对的步骤和入口，但不能证明陌生队伍现已能够从零一次复现。正式提交包还应含完整源码/IP许可、模型获取方式、环境锁定、原始输出和基线对照，并完成一次干净环境验收。不要用报告整理完成代替工程包完成。
