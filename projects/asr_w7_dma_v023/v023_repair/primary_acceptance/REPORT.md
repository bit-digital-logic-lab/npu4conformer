# 主验收：暂不通过整体验收

日期：2026-10-29。仅本地 RTL 逻辑范围；未综合、未上板。

## 已独立复跑
- 控制修复：复制交付件到 primary_acceptance/control，run_all.sh 重跑成功，SUMMARY fails=0；覆盖 CSR snapshot、watchdog、DMA 地址溢出与 WSTRB、ready scan、地址流水及 storage 握手。详见 control_rerun.log。只接受该模块测试范围。
- 近似数学：隔离副本 test_approx_suite.py 重跑退出0，但该脚本末尾无条件打印 ALL VERIFICATION CHECKS PASSED，不能以这句话验收。实测 DIV 最大相对误差0.1080%，SQRT/RSQRT约0.0006%；所构造量化用例 LayerNorm最大1LSB、Softmax最大14LSB。这是合成输入映射，未证明当前完整模型精度。
- 融合算术反例：tb_fma_probe.sv 实测 0x3f800001 × 0x3fc00000 返回3fc00001，正确最近偶数舍入为3fc00002。ROUNDING_FAIL。功能乘法截断且乘加分开，不是真正单次舍入FMA。用户仅放宽除法/开根，不能据此放宽融合乘加。

## 阻断与整改
1. gemini_epilogue/epilogue_fma_stage.sv 用截断乘法+加法冒充FMA，非原数值契约；随机 stress 使用 cfg_fma_mode=0，只覆盖转换旁路，不能支持完整融合通过。须替换为可信数值实现或明确接原IP并使用独立golden覆盖非平凡scale/bias。
2. gemini_approx/rtl/approx_div_sqrt.sv 的 LATENCY、II 参数未用于流水结构；TIER仅区分0与非0，TIER2无第二次NR，固定四组时序寄存器。报告2/4/7拍三档不成立。修实现或收窄为真实单档；去掉未经STA的300/600MHz及<2.4ns承诺。
3. ds_vector 当前 result.json passed=false，add_tail5/add_tail7/a48_tail3/f32_to_i16_tail7输出不一致，仍在运行。长向量add/sub/mul1001当前已gold一致，但不能抵消尾包错误。
4. ds_layout仍在修C48跨缓存行；ds_matrix仍未最终交付。不得引用早期review的PASS当最终代码验收。
5. ds_graph坦诚仅部分交付：591为synthetic host-order chain、矩阵stub；原ONNX及外层执行器缺失。小真实图可作为局部证据，不能称完整CASE0000完成或全图纯PL已验收。
6. ds_integration仍waiting_modules，暂无整合版验收结果。

## 结论
控制修复模块在复跑范围内通过；其余按上述整改，整体暂不通过。性能改善不得先于字节正确性，逻辑仿真不能证明物理300/600MHz。
