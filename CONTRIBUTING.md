# 工程修改约定

1. 按项目提交修改，写明影响的是硬件设计、主机软件、仿真还是黄金验收。
2. 修改前后执行 `python tools/check_repository.py` 和相应的离线回归。V5 数值路径修改还需要实际 FMA IP 仿真和原案例实板验证。
3. `releases/v2_20260922_pre_golden/` 保持冻结源文件原样。新增实现放在工作目录，不覆盖历史证据。
4. 报告区分 CPU/GPU 参考、RTL/HLS 仿真和实板运行。保留失败结果，并明确尺寸、输入、容差和是否使用 FPGA 实际 Encoder 输出。
5. 新输出使用被 `.gitignore` 排除的 `reports/local_*`、`build/` 或 `artifacts/`。只有能支撑结论的报告才进入版本控制。

整理后的文件身份清单位于 `docs/repository-manifest.json`。修改后先检查差异，再使用 `python tools/check_repository.py --refresh` 更新清单。
