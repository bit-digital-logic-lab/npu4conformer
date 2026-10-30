# REPORT — ds_repair_fmaflush（AR-001 最小握手整改）

状态：**完成；本地逻辑仿真 gate rc=0，32 个用例 0 失败。**
范围：仅本地 RTL 逻辑仿真。**未做**综合 / Vivado / STA / 上板 / VNC / push。
工作目录：`/home/yang/Desktop/项目/v024_opt/ds_repair_fmaflush`
原始 `ds_fma_deep`、`ds_adversarial_review`、v023、`work/` 全部只读，未修改。

---

## 1. 冻结输入与修复结果

| 项 | SHA-256 |
|---|---|
| 基线 7 级核 `ds_fma_deep/candidate/fp32_fma_pipe.sv` | `b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82` |
| 修复后 `rtl/fp32_fma_pipe.sv` | `3c1114bc40078fd357bb968e8daecc53e68ad4da25a6ae586ce658b4d2a5e0c5` |
| 原 `epilogue_fma_stage.sv`（未改） | `34b55dc340b33ee570c540453662404579a77b2f8e2b166dbb2563ab3740c00b` |
| 原 `asr_fma_ip.sv`（未改） | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` |
| 冻结 8734 向量 | `6bb7a8bc1dd36f0dae38957fcbc89310048adcc4404b82748159f1146445a874` |
| 冻结 251 向量 | `cddd08a6d0f0205742e2bed6cf95e533a35b3b761dc3a2a4908df04a483b3fa6` |
| 新生成 2000 向量（独立 gold） | `d78c2869a5e9cc26df616cf0f117bc7334cf762611bd57ac53cb078d8338b7c0` |

完整清单见 `SHA256SUMS`、`reports/frozen_shas.json`；逐行 diff 见
`reports/rtl_diff.patch`。修复只改了 2 条 assignment（加注释）：

```diff
-    assign in_ready  = s1_ready;
-    assign out_valid = s7_valid;
+    assign in_ready  = rst_n && !flush && s1_ready;
+    assign out_valid = rst_n && !flush && s7_valid;
```

算术、S1..S7 寄存器划分、tag/last、129 位累加器、舍入/FTZ/特殊值逻辑一行未动。

## 2. 明确的握手契约

1. `in_valid && in_ready` 在上升沿才构成一次传输。
2. `flush=1` 时 `in_ready=0`：上游在 flush 期间给的数据**没有被传输**，
   必须保持/重发；没有隐藏接收，也没有 drain 握手。
3. `flush=1` 时 `out_valid=0`：**flush 当前拍取消输出传输**，即使
   `out_ready=1` 也不会交付；S7 中已停放的结果同样被取消。下游把 flush
   当作 error abort。
4. `flush` 同步生效：采样到 flush 的上升沿清 S1..S7；撤销后的新 epoch
   重新是 7 拍延迟。
5. `rst_n=0` 同样是屏障：`in_ready=0`、`out_valid=0`，reset 期间不识别
   传输。触发器 reset 风格保持原核的“异步置位、同步释放”，未改端口/极性。
6. `out_valid && !out_ready && !flush` 时输出字段冻结（稳定性）。
7. `flush=0` 时仍为 II=1。

以上与 `INTERFACE.md` 第 2 节一致，不是事后放宽。

## 3. 数值语义（明确保持，未“修正”）

- 单次 RNE 的 binary32 FMA，129 位累加器；FTZ；qNaN=`0x7fc00000`；
  `inf*0 -> NaN`，`inf+(-inf) -> NaN`；精确非零抵消 -> `+0`；
  `x*0+c -> c` bit-exact。
- **保留旧项目特例**：两个加数都是 FTZ 零时结果符号取 `sign(c)`
  （故 `(+0)+(-0) -> -0`）；`inf*subnormal` 用原始位判零，故返回 `inf`。
  这不是 strict IEEE，已在 INTERFACE 第 3 节文档化，本任务不允许改。
- 独立 gold（`gold/fma_gold_independent.py`，从契约重写，不引用旧 golden）
  对冻结 8734 和 251 的 expected 列**逐条重算，0 mismatch**；strict 模式与
  project 模式在 8734 上有 **58** 条差异（AR-002 记录为 59，实测 58；
  本树的 strict 结果与 `fma_8734_strict.txt` 也 0 mismatch）。这只用于
  说明差异存在，不作为通过标准，也没有改任何 expected 值。

## 4. 测试矩阵（本轮新跑，未使用旧 JSON PASS）

编译串行（逐项 `iverilog -g2012`）；每个仿真都有 TB 内 watchdog + shell
`timeout 300`；每个用例同时校验**真实退出码**和日志标记，二者不一致即 gate
失败。

| 用例 | 内容 | rc | 关键结果 |
|---|---|---:|---|
| `gold_check` | 独立 gold 对 8734/251 | 0 | `project_gold_mismatch=0`；strict diff=58 |
| `mode0_8734` | 原 8734，随机反压，stream | 0 | `n=8734 out=8734 errors=0` |
| `mode1_flush_8734` | flush 新 epoch（旧 epoch 必须消失） | 0 | 8734 新结果全对，无旧输出 |
| `mode2_reset_8734` | reset 后重发 | 0 | `out=8734 errors=0` |
| `mode3_ii_8734` | II=1 | 0 | `max_gap=1 accepted=8734` |
| `mode4_flush_handshake` | **独立 tb mode4，flush 期间连续 valid** | 0 | `FLUSH_HANDSHAKES=0` |
| `mode0_fresh2000` | 独立 gold 新 2000 向量 + 反压 | 0 | `out=2000 errors=0` |
| `mode1/2/3/4_fresh2000` | 新向量 flush/reset/II/handshake | 0 | 全 PASS |
| `latency_7_ii1_bypass` | 7 拍、II=1、mode0 bypass、in-flight flush、输出冻结 | 0 | `latency=7, II=1`；`LATENCY_TEST_ERRORS=0` |
| `flush_contract` | flush 屏障、当前拍 out_valid 取消、停放结果取消、reset 屏障、8 拍 flush 压力、post-epoch 7 拍 | 0 | `CONTRACT_ERRORS=0` |
| `flush_leaves` | i48/FMA/i16/lane 的 flush drain | 0 | `FLUSH_ERRORS=0` |
| `wrap_lane_latency` | wrapper 7 拍、lane mode0 旁路 12 拍 | 0 | wrapper=7 II=1；lane=12 II=1 |
| `asr_wrapper_8734` | AXIS wrapper 8734 | 0 | `in=8734 out=8734` |
| `asr_numeric_compare` | wrapper 输出序列对冻结 expected | 0 | `mismatch=0` |

## 5. 负向控制（证明测试不是宽松通过）

| 用例 | 输入 | 期望 | 实测 |
|---|---|---|---|
| `neg_m0_original_mode4` | 未修复原核 + mode4 | 必须失败 | rc=1，`FLUSH_HANDSHAKES=4`，`FAIL` |
| `neg_m0_original_mode1` | 未修复原核 + flush epoch | 仍应通过（只坏握手） | rc=0，PASS |
| `neg_m1_inready_only` | 只 gate `in_ready`，不 gate `out_valid` | 必须失败 | rc=1，`CONTRACT_ERRORS=2`（flush 拍仍输出） |
| `neg_m2_no_reset_gate` | gate flush 但不 gate reset | 必须失败 | rc=1，`CONTRACT_ERRORS=3`（reset 期间 `in_ready=1`） |

`$finish(n)` 在 Icarus 下不改变进程退出码，因此本树 TB 的失败路径统一改为
`$fatal(1,...)`；这也是 gate 能保证“退出码 = 子项结果”的原因。

## 6. 复跑

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_repair_fmaflush
bash scripts/run_all.sh gate
echo $?        # 0 = GATE_PASS；result.json 的 top_rc 同为 0
```

单独复现 AR-001：

```bash
iverilog -g2012 -s tb_fma -o sim/manual.vvp tb/tb_fma_mode4.sv rtl/fp32_fma_pipe.sv
timeout 300 vvp sim/manual.vvp +vec=vectors/fma_8734_proj.txt +mode=4
# 期望 FLUSH_HANDSHAKES=0 / PASS / rc=0
```

结果文件：`result.json`（32 cases，`top_rc=0`）、`logs/gate/*.log`、
`logs/gate/runs.tsv`、`SHA256SUMS`、`FINAL_SHA256SUMS`。

## 7. 未验证范围 / 残余风险

- 未综合、未 Vivado、未 STA、未上板、未 VNC、未 push；**没有 ns/MHz 时序结论**。
- 仅模块级修复；未在 `ds_unified_graph` 统一顶层重跑，不能把本结果当作系统 PASS。
- 只修 `fp32_fma_pipe`（以及经它导出的 `epilogue_fma_stage.in_ready`）。
  `epilogue_i48_to_f32` / `epilogue_relu` / `epilogue_f32_to_i16` 仍保留原
  flush 行为，属于本次 AR-001 范围外，未做同类 gate。
- 反压来自 TB 的确定性 LFSR/定向序列，不是形式化证明；未做 X 传播、
  亚稳态、跨时钟域分析。
- 保留项目 FTZ signed-zero / `inf*subnormal` 特例，因此**不能宣称 strict IEEE**。
- 未覆盖完整模型依赖/真实 ASR 工作负载；不把 stub 当完整图。
