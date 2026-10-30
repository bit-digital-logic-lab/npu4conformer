# 最新同步状态

同步时间（北京时间）：2026-10-30T19:12:20+08:00

本次同步包含已完成的清洁导出：[final_export](v024_opt/ds_final_organize/final_export/README.md)。51个选定RTL源文件，唯一filelist；矩阵、DMA、memory、vector、layout、graph、epilogue按目录组织，仿真与分析脚本分开。此导出对应小图逻辑验证候选，不是全部专项优化已合并、不是完整模型或板卡验收。

统一受测小图18,724拍，按125MHz换算149.792微秒；旧约150秒完整模型的新运行时间未知。文件的GitHub时间表示其最后内容提交，较旧文件不会因别处更新而刷新；本文件与新导出记录本次实际同步。

根据用户明确要求，仓库的Offline engineering checks自动workflow已设置disabled_manually；保留检查脚本和已有成功/失败历史，不删除或伪造检查结果。仓库继续私密。

入口：

```bash
cd projects/asr_w7_dma_v023/v024_opt/ds_final_organize/final_export
bash scripts/sim/run_export_all.sh
```

大模型/生成镜像/编译缓存不入库，按资产清单恢复或运行fixture生成器。根目录README及历史PUBLISH_STATUS是阶段记录，以本同步入口和final_export/README为当前目录说明。
