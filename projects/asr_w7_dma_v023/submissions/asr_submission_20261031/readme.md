# ASR FPGA矩阵架构与Roofline分析封存资料

本仓库固定W7p8/A16/C48、16×16脉动阵列及电脑与FPGA协作框架。包括当前可复跑的统一小图RTL候选、独立性能记录、已修复技能、设计报告和短视频取材。整改方案另列，尚未修改硬件。

## 目录与选题指南对照

```text
asr_submission/
  readme.md
  src/unified/             固定的统一RTL小图与原路径依赖
  sim/                     分析复现脚本与新运行日志
  build/                   分析与RTL构建入口
  board/                   板级状态说明
  data/                    trace 量化记录 Roofline合同与源哈希
  skill/                   搬运账本与模块活动波形技能
  report/                  七部分设计报告 协作记录 整改方案
    images/                PNG及SVG母版
    slides/                无封面的短讲PPT
```

遵循指南3.3.5.3的七项报告内容。目录按3.3.5.4建立：由于统一RTL测试依赖原相对路径，其测试源与fixtures保留在src/unified/sim，原脚本保留在src/unified/scripts；build/run_rtl.sh为统一入口，将新日志汇入sim/unified_run。build/status.md和board/status.md明确无新的综合实现和上板结果，不用空目录暗示已完成。

路径均使用英文、数字、下划线或连字符。技能入口SKILL.md保留工具规范的固定名称；其余交付文件使用小写。源代码正文、报告与注释允许中文。

## 从零复现

### 1 准备依赖

Linux主机需Python 3、bash、timeout、Icarus Verilog与vvp。绘图需要NumPy、Matplotlib与Noto CJK字体（Debian/Ubuntu字体包fonts-noto-cjk）。示例环境准备：

```bash
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install numpy matplotlib
# Debian或Ubuntu可通过系统包管理器安装iverilog
# 安装后检查：iverilog -V；vvp -V
```

本次实际验证所用工具版本见sim/environment.txt。未固定包版本的平台应先核对该文件，再建立同版本环境。

### 2 重算原始分析与图

```bash
bash build/reproduce_analysis.sh
```

生成data/roofline_recomputed.json、sim/ledger_fixed、report/activity_fixed.html和report/images/roofline.png及svg。用原始trace验证busy分类，重算N/Q与N/T；不重新运行原V023专用性能试验。

### 3 重新运行统一小图RTL

```bash
bash build/run_rtl.sh
```

串行编译与仿真，重新生成独立gold。执行融合、回退、多消费者、错误标志、写响应故障及基线小图回归；正常完成要求写响应排空。总运行时间取决于机器，脚本对各测试设置超时。输出日志在sim/unified_run，失败返回非零。

### 4 阅读并使用

report/design_report.md为七部分正式报告；report/remediation_plan.md为R0至R3整改方案；report/narration.md为约104秒讲稿；report/slides/architecture_roofline.pptx仅放图片和图名。片头另留8至12秒。图片与讲稿分开，历史量化不含LoRA。

## 证据边界

Roofline用共享128位读写BFM的16 B/周期与256 PE每周期1 MAC的512 OP/周期理论上限。图上点是M64 N32 K96局部矩阵RTL测试，不代入300/600MHz，不以Q/T自证带宽屋顶。复用A/B为独立候选，未合入统一小图。统一RTL新回归不能证明这三个历史性能点已在统一顶层重现。

完整591张量ASR、板级DDR、bitstream、综合STA、物理资源与功耗不在本次复现范围。原工程保持原状。GitHub远端尚未推送；后续应以本封存目录作为待审提交，不上传大体积模型及无关用户数据。
