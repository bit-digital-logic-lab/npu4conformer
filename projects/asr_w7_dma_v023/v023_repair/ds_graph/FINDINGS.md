# FINDINGS — ds_graph（全图 PL 自主编译）

1. **591 台账可恢复，但真 Tensor 边不可恢复。**  
   sealed `case0000_board001/result.json` 有 591 条 `native_matrix_tasks`（m/k/n、param_id/param_B_address、cbase/cbytes、queue/compute cycles）。  
   但原 ONNX、`lowbit_executor.py`、`profiled_backend.py`、`vm_abi.py` 均不在本机；480 条动态 MatMul 没有静态参数名，只能按 host 顺序归到 owner 层。  
   证据：`analysis/source_ledger.json`、`analysis/outer591_ledger.json`。

2. **591 的层结构是 12×29 + 6×40 + 1 + 2 = 591。**  
   12 个 encoder 层各 29 条，6 个 decoder 层各 40 条，embed 1 条，output layer 2 条。  
   这是参数名前缀 + host 顺序的结构归属，不是 ONNX 依赖。  
   证据：`analysis/outer591_groups.json`。

3. **68 个闭合程序的边界地址在旧 host 中大量复用。**  
   68 个不同输入 tensor 只落到 4 个旧地址；68 个不同输出 tensor 只落到 6 个旧地址。  
   全局分配把它们变成 68+68 个唯一地址；旧地址同 base 的对数 225,310，其中 live 同时重叠 2,413。  
   证据：`analysis/global_alloc.json`、`analysis/relocation_map.json`。

4. **“给每个子图唯一 temp_base”不能解决 68 并行。**  
   68 个 temp extent 合计 126,382,080 B；单份最大 30,277,632 B；80 MiB arena 连两份最大 temp + 591 A/C（26,287,872 B）都放不下（86,843,136 B > 83,886,080 B）。  
   正确做法是单 SEQ 引擎独占共享 temp（本任务），或片上 residency/更大 arena/真正分块；不是改地址。  
   证据：`analysis/global_alloc.json.shared_temp`、`REPORT.md §4.2`。

5. **ds_pl_autonomy 的 WCPL v1（128 节点/128-bit mask）不够。**  
   591 台账 + 68 program 需要 >128 节点；本任务用 WCPG v2：1024 节点、每节点 192 B、1024-bit 依赖 mask、IN 类型、root provenance、output retention。  
   证据：`rtl/wc_graph_ctrl.sv`、`INTERFACE.md §3`。

6. **68 控制计划是 136 节点（68 IN + 68 SEQ），不是 68 串行。**  
   每个 SEQ 只依赖自己的 IN；一次 START、4,556 cycles、136/136、一次 DONE、68 个 output。  
   但只有一个 SEQ 引擎，所以执行仍串行；没有声称 68 路并行。  
   证据：`reports/run_all/run_ctrl_mode1.log`。

7. **591 控制回放是 host-order synthetic chain。**  
   591 个 MAT 节点、590 条 synthetic 边、一次 START/DONE、591/591、367,846 cycles。  
   这不是恢复的 tensor DAG；`flags.bit4` 和 `descriptor_map.json` 都标注 synthetic-order。  
   证据：`reports/run_all/run_ctrl_mode2.log`、`analysis/descriptor_map.json`。

8. **root provenance / output retention / 负例都过。**  
   root 无输入出处 → `0x08`；无 output → `0x0A`；bad hash → `0x04`；forward dep → `0x04`；输出地址在 DONE 后保持；child fault `0x55` 时停止新发射并 drain 后一次 DONE。  
   证据：control modes 3..8。

9. **小真实图 64/64 word 与 Python float32 golden 一致。**  
   IN(param 0x10001000) → real layout COPY → real vector ADD 1.0 → real vector MUL 2.0。  
   4/4、2,357 cycles、lay 790 / vec 1,381 cycles、读写 DMA burst 均发生；没有 FMA/op17。  
   证据：`reports/run_all/run_real_mode10.log`、`tests/fixtures/gold_small.hex`。

10. **非矩阵算子仍在 host/legacy DAG。**  
    板级 stage 计数：encoder 动态执行 2,601 节点、decoder 1,016；MatMul 97+72、LayerNorm 61+19、Softmax 12+12、Div 25+12 等。  
    本任务没有把它们全部下降；`nonmatrix_tensor_names.json` 只是 tensor 名示例。  
    证据：`analysis/source_ledger.json.nonmatrix_ops`。

11. **旧 host 控制残留在板级结果中是量化的。**  
    361,388 UDP batches、591 native queues/593 tasks、3 MMIO writes/queue、host→DDR 19,814,464 B、DDR→host 34,086,912 B。  
    这些是 sealed result 的原样引用，不是本任务重新跑板。  
    证据：`analysis/source_ledger.json.host_residual`。

12. **本任务没有越过逻辑边界。**  
    没有综合/Vivado/bitstream/板卡/VNC/push；没有 STA，所以不声明 300/600 MHz；没有 MIG，所以不声称绕过 PS hard DDR controller；没有完整 CASE0000，所以不声明整机加速。

13. **sealed V022 内部指针未重写。**  
    全局 map 用于 WCPG 控制图和集成期 re-lowering；直接把旧 payload 搬到新地址执行会是数据破坏 bug。  
    证据：`analysis/relocation_map.json` 的 `note`。

14. **分配器负例是主动构造并被拒绝的。**  
    正常分配 0 live conflict；人为把两个 live 输出放同一 base，`check_alloc.py` 报 `live tensors share base`。  
    证据：`analysis/alloc_check.json`。
