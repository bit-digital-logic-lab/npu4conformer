# 最新检查

整合任务正在编写 integrated/rtl/v023_integrated_top.sv；暂无最终联仿结果。


## 最新主检查：禁止采用未经复核的FMA PASS
ds_numeric_adversarial已产生真实失败：result_fma_repair.json 8734向量/137 mismatch（mode1），x=3f800003 scale=3fc00000 bias=0，got3fc00005 expected3fc00004；流式bp2b 预期256拍却402拍，tag和数据不一致。approx_repair 15168例中3个signed-zero RSQRT特殊值不一致。请读这些结果、复核TB协议与参考，锁定SHA后再修复，不得忽略这些失败直接整合报PASS。近似大误差须区分FTZ/范围策略与实际普通值错误。

控制/向量/Layout/矩阵模块交付已完成，但不是系统验收。FMA此前只证明单一反例已修，不能推出完整正确。
