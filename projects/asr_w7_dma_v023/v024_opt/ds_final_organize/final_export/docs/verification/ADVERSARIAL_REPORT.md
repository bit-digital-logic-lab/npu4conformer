# REPORT — ds_adversarial_review（V0.24 独立只读审查）

**模型**：`opencode-go/deepseek-v4.1-flash`（唯一执行模型）
**范围**：只写本目录；`v023_repair/`、`work/`、ZIP、其他 worker 目录只读。
**边界**：仅本地 RTL 逻辑仿真（Icarus `-g2012`）。无综合 / Vivado / STA /
板卡 / VNC / push；不承诺频率、整模型秒数或 591-tensor DAG。

## 0. 结论（先给可接入/拒绝项）

| 项 | 冻结 SHA（前 16） | 独立结论 |
|---|---|---|
| FMA 7 级 II=1 深流水 | `b062284af692349a` / repair `3c1114bc` | **可接入**；用 repair SHA 满足 flush 握手契约（AR-001 已修） |
| Vector op17 II=1 + 4-lane tail | `dad7cac00ecbe5a7` | **可接入（tail/II/drain）**；旧版 9..16 负例已复现 |
| Per-channel epilogue | `4fff5c3f…` / repair `f4857c19…` | **功能可接入（无背压）**；repair 修 AR-007，AR-006 双通道背压仍开，**暂拒绝整机接双输出** |
| Write coalescer / 4KiB | `0a25f951bb6fe817` | **native 可接入**；generic 4KiB 跨页/背靠背，**拒绝 generic 路径** |
| Matrix 2×1 W reuse | worker cluster | **可接入（实测 W 读 6144→3072）**；容量按第二 A stage 计，非“零 BRAM” |
| Fusion 双缓冲 done-B | worker dual top | **可接入（done 严格在最后 B 之后）** |
| Graph prefetch/账本 | `ds_graph_prefetch` | 账本纠正成立；lookahead 为可选、默认关；epoch 有实跑证据 |
| **整机 ds_unified_graph** | 无冻结交付 | **部分正向（fused 512/512）但整体未交付（fallback/异常/result 未闭环，见 §10）** |

## 1. 方法：独立 gold、负例、冻结

1. `gold/fma_gold.py`、`gold/epilogue_gold.py`、`gold/gen_*` 全部按公开契约用
   Python 整数/Fraction 重写；**不 import、不执行**任何 worker 的 RTL 或 golden
   脚本。DIV/SQRT 近似按相对误差契约，其余为逐位。
2. 每个候选先记录 SHA-256 到 `reports/frozen_shas.json`，再编译/仿真；同一
   filelist、同一向量、同一 BFM、同一完成排空边界。
3. 每个仿真有 shell `timeout` 和 in-TB cycle watchdog；任何 mismatch、watchdog、
   fault、旧 epoch 输出都使脚本 rc≠0。
4. 负例不是“旧 JSON PASS”：`mutants/` 里是本任务自己复制的 RTL 变体，证明测试
   能抓住对应 bug 类（见各节）。
5. 编译串行（一次一个 iverilog），`-j1` 风格。

## 2. REVIEW_DECISIONS 假设逐条审计

1. **融合统一 / layout 整拍 / vector FMA II1 / tail / 写合并 / 权重复用 / 参数表 /
   长锥拆分作为方向**：方向成立。FMA II1、tail、写合并、W 复用均有本任务实测；
   “长锥拆分”只能由结构审查确认，**没有 STA，不能给 ns/频率结论**。
2. **拒绝 59.8% 控制开销归因**：成立。graph_prefetch 的 exclusive union 实测
   `383(fetch)+44(idle)+8(dispatch)+23339(engine)=23774`，非 engine 仅 435 拍
   **1.83%**；59.8% 是“总周期 − 最后 op telemetry”的算术错误。lookahead 实测只
   省 114 拍（0.48%），不是 12k 拍。
3. **互连 CREDIT8/QDEPTH32、peak1 不能断言单事务；多 HP 不相加**：同意，本任务
   没有改板级拓扑，也没有多 HP 带宽结论。
4. **可信 FMA 是 4 级 129 位 acc，不是 3 级 76 位；旧 7.745ns 不能赋给新 RTL**：
   属实。v023 为 4 级；新深流水为 7 级，8734 向量逐位一致；本任务不做 STA，不引用
   旧 ns。
5. **“零额外 BRAM / 固定 1 cycle collect / 8× layout / FMA 减半”均待验证**：本
   任务只接受可测项：W 复用实测省 3072 B 读；collect 由 worker 报 1688→1560；
   layout 8× 未由本任务独立验收；FMA 是 II1 而非“减半”。
6. **54.8KB 是整条小链 AXI 读写，不是 vector 独占**：同意。本报告所有字节数都是
   单个 fixture 的实测握手，不外推整模型。
7. **512 维 ASR、主机一次预装、PL 自主 DMA；缺完整依赖不能用 stub 当完整图**：
   遵守。本任务只做小图/模块，未声称完整模型。
8. **旧候选只读、独立工作、先统一联仿再整理**：遵守；本任务未修改任何 worker
   源码，只在本目录写测试与报告（并在 USER_UPDATES 追加指针）。

## 3. FMA 新 latency / flush（重点 1）

**DUT**：`ds_fma_deep/candidate/fp32_fma_pipe.sv` `b062284af692349a…`（7 级，II1）。

- 独立 8734 向量（全 special/FTZ/RNE/tie/cancel + 随机）：**8734/8734 位精确**
  （项目契约；strict-IEEE 差异见 AR-002）。
- II：`out_ready=1` 连续进数，8734 个 accept 用 8734 拍，`max_accept_gap=1`。
- 随机背压 stream、mid-flight reset、1 拍 flush 后新 epoch：251/251 通过。
- **AR-001（S2，已在 repair 修复）**：`ds_repair_fmaflush` 的
  `fp32_fma_pipe.sv` `3c1114bc…` 上 mode4 `PASS`（flush 期间 0 握手），
  且 8734/flush/reset/II 全过。整机应选这个 SHA，而不是 `b062284a…`。
  原 `b062`/v023 版本仍有“flush 同拍接受”隐患。
- **负例**：`mutants/fma/fma_flush_broken.sv`（只清 S1）mode0 过、mode1 挂；
  `fma_sticky_broken.sv`/`fma_tag_broken.sv` mode0 挂。证明测试抓得住。

## 4. Vector tail（重点 2）

**DUT**：`ds_vector_fma/rtl/ddr_vector_engine_pipe.sv` `dad7cac00ecbe5a7…`。

- op17 FMA：total 1/2/3/4/5/7/8/9/16/17/127/255/256/257/1001 全过；
  1001 时 1840 拍，`last_b < done`，`b_after_done=0`。
- op0 ADD：1..17/127/255/257/1001 全过。
- op15 F32_I16 + out16：1..17/127/255/257/1001 全过（16-bit 尾 strobe 正确）。
- **旧版负例**：v023 `ddr_vector_engine_pipe` 在 op0 total **9..16** 失败
  （20..48 byte mismatch），1..8 走标量回退才过；候选修复后全过。
- **“只删条件”负例**：`mutants/vector/ddr_vector_engine_naive_gate.sv` 仅去掉
  `bank_elems>8`，在 5..8 失败，证明必须保留/实现真正的 mask/pack 修复。
- 限制：单 lane op17（1 element/cycle），不是 4-lane FMA；btiled 多 tile 未扩展。

## 5. Per-channel 列 tag（重点 3）

**DUT**：`ds_epilogue_channels` engine `4fff5c3f…` / lane `c633576d…` /
i2f `4c862453…` / fma `1ed8801a…`。

- 无背压：bank0 32 拍 + bank1 32 拍 + scalar 8 拍，a16/fp32 各 72 个，逐位对
  独立 gold；`stat_table_hits=256`，`col_align_err=0`；配置等待、active-bank
  写拒绝计数、abort 后新 epoch 均通过。
- **AR-004（已修，保留证据）**：较早 SHA 上 per-column scale/bias 未随 C48 过
  i2f 两级，实测 **+2 beat（+8 列）**偏移，61 个 mismatch，且 table_hits 仍为 256
  —— 静默错值。worker 后续把 scale/bias 一起过 i2f 后修复。
- **AR-006（S1，仍开）**：A16 与 FP32 同时独立反压 → 32 拍只出 22 A16/25 FP32，
  tag 22..31 丢失，watchdog。单边反压（只 A16 或只 FP32）32/32 过。repair
  `ds_repair_epilogue` 的 `f4857c19…` 仍未修复（同样 22/25）。
- **AR-007（S2，已在 repair 修复）**：多相位（bank0→bank1→scalar）仅 A16 反压
  原为 54/57 of 72 后挂死；`f4857c19…` 上 72/72 PASS。
- 复跑：`bash scripts/run_epilogue.sh …`；advisory probe 名为
  `probe_both_bp`、`probe_multiphase_a16bp`。**在修复前不建议整机接 perchannel
  输出通道。**

## 6. Write 合并 4KiB / stride（重点 4）

**DUT**：`ds_storage_write/rtl/block_storage_stream_v3.sv` `0a25f951…`。

- native（含 `C_BASE=0x03000C00` 使 6144 B 块跨两个 4KiB 页）：
  64 cseg → **24 posted requests**，384 beats，max 16 beat，**2 次 4KiB split**，
  6144 B 逐字节重建且每字节只写一次，`cwr_pending=0`。
- generic 单段（`0x…1110`，96 B）：1 req/6 beat/96 B，数据正确。
- **AR-008（S1/S2，开）**：
  * generic 段在 `0x03000FE0` 发出 `0x…0FE0..0x…103F` 的 6-beat 请求，**跨 4KiB**；
    AXI4 不允许。native 会 split，generic 不会。
  * 两个 generic 段背靠背（`0x…1110`、`0x…1190`）第二段不完成，`cseg_ready` 变 X。
  * 复跑 `scripts/run_write.sh` 的 advisory probes。
- 注：worker 自己的 `tb_storage_coalesce.sv` 在当前树无法 elaborate
  （`rd_req_ready` 同时是 TB reg 和 BFM output），其 PASS 不能作为这两个 generic
  用例的证据。

## 7. 权重复用 RAW（重点 5）

**DUT**：`ds_matrix_reuse/candidate/rtl` cluster，PIPE_STAGES=4。

同一 fixture、同一 BFM，只改 `cfg_w_reuse`：
| 运行 | rd_bytes | AXI W bytes | cycles | 结果 |
|---|---:|---:|---:|---|
| M64 N32 K96 reuse=0 | 18,432 | 12,288 | 7,612 | PASS |
| M64 N32 K96 reuse=1 | 15,360 | 12,288 | 7,236 | PASS |

读减少正好 3,072 B = W 总量 6,144 的一半；输出字节不变。说明是真实调度复用，
不是只翻一个控制位。**容量口径**：pair 用现有两个 C slot + 第二 A stage，不是
“零额外 BRAM”；按 INTERFACE 的容量清单计。

## 8. 双缓冲 done-B（重点 6）

**DUT**：`ds_fusion_buffers/rtl/fusion_a16_writer.sv` 与
`matrix_stream_fusion_top_dual.sv`（worker SHA `ff13ca00…`）。

- 独立 writer 单测：B delay 0/5/30 + 8 B odd tail，`done` 严格晚于 `dma_done`，
  `last_w < last_b`，尾 strobe `0x00ff`。
- 负例 `mutants/fusion/fusion_a16_writer_early_done.sv`（最后一个 W 就 done）
  在 bdelay=30 失败。
- 双 top 实跑：
  * main 1 tile `bextra=120`：`last_w=2106, last_b=2238, done=2240`，8 B，PASS。
  * n64 2 tile `bextra=3000`：`last_w=4825, last_b=7855, done=7857`，16 B，
    `task_cycles=2934` vs `cycles=7857`，PASS。
- 结论：done 边界和 compute/write overlap 成立；这是 cluster 级，不是整机。

## 9. 图 prefetch 旧 epoch（重点 7）

**DUT**：`ds_graph_prefetch`（`LOOKAHEAD_EN` 默认 0）。

- 账本：exclusive union 八桶之和 = cycles（23774）；非 engine 435 拍 1.83%；
  纠正 59.8% 假归因。
- lookahead on：23660 拍 vs off 23774，实际省 **114 拍（0.48%）**；hits=6，
  misses=1，aborts=0。header prefetch 省 0 拍。
- 旧 epoch：正常 run `epoch=2, valid=0`；fault/isolation/abort run `epoch=3/4,
  valid=0, aborts>0`；SEQ 计划 `has_seq=1, fetches=0`。实跑日志见
  `ds_graph_prefetch/logs/lu_*.log`。
- 结论：可选 lookahead 与 epoch 失效契约成立；默认关，未证明大幅收益，不能引用
  59.8%。

## 10. 整机集成（ds_unified_graph 阶段交付）—— 未通过/未交付

截至审查截止（2026-10-30 15:54）：

- **fused 小图**：worker 最新一次干净运行 `rc=0`（145 s）。本任务独立解析
  `logs/v024_fused_out.hex`，在文档地址 `0x04007800` 与冻结
  `fixtures/v024_ref.json` 的 `fused_a16_words` **512/512 words 完全一致**。
  这是 fused MAT→per-channel→A16 的正向证据（仍属 worker 生成的 fixture/ref；
  本任务对 per-channel 模块自身用的是自己的 gold，见 §5）。
- **fallback 小图**：早先一次 `v024_fallback rc=143 Terminated`，随后
  worker 反复重启运行；到截止时**没有一次 fallback PASS**，也没有
  `V024_CHECK PASS`。
- `safety_normal` 实跑 `rc=124`（90 s timeout），最后状态
  `WAIT cyc=20000 busy=1 fault=0 rd=0 wr=0 b=0`，图在矩阵后未再发 AXI。
- **没有 `ds_unified_graph/result.json` / 冻结阶段交付**。

因此：**不把 FMA/vector/epilogue/storage/reuse/fusion 的模块 PASS 拼成整机
PASS**。整机项按“部分正向、整体未交付/未通过”结束：fused 路径可继续推进，
但 fallback/异常/drain 与统一 result 未闭环。需要 worker 冻结统一 SHA +
result.json，审查员再用同一脚本复跑。这个结论是流程/技术阻塞，不是断言每个
模块都错。

另外，`unified/rtl/epilogue_stream_engine_v024.sv` 是 worker 自己的 per-channel
接口（`param_wr_addr 0..31/32..63`、`(beat_in_row%8)*4+lane`），与本任务已验收的
`ds_epilogue_channels` 接口（`cval_col/cval_bc/cfg_table_en`）**不同**；模块
验收不能直接迁移到整机，必须按 §10 的整机实跑重新证明。

## 11. 未完成 / 限制

- 无综合/STA，无频率/资源/时序结论；`repair` 类 worker 的最终 SHA 若再变，需
  按本目录脚本重新冻结复跑。
- FMA strict-IEEE 的 signed-zero / inf×subnormal 与项目契约不同（AR-002），
  未作为优化回归，但必须声明。
- perchannel 输出背压死锁（AR-006/007）未修前，整机不应接双输出通道。
- generic 写路径 4KiB/背靠背问题（AR-008）未修前，整机不应把非 native stride
  的 C48 段交给它。
- 图 prefetch 只在 worker 的 integrated_copy 上测，未在本任务重跑其 18 项；
  账本与 epoch 结论来自其真实仿真日志的独立复算。
- 未测：完整 591 DAG、ONNX/WER、CDC、板卡、DDR PHY、多 HP 带宽。

## 12. 复跑 / 文件 / rc

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_adversarial_review
bash scripts/run_all.sh
```

单测入口：`scripts/run_fma.sh`、`run_epilogue.sh`、`run_vector_tail.sh`、
`run_write.sh`。每个脚本先写 `reports/frozen_shas.json`，再 `iverilog -g2012`，
每个 `vvp` 有 `timeout`；失败 rc≠0。日志在 `logs/<test>/<tag>/`。

**唯一交付文件清单**：`filelist.txt`（本目录生成物 + 脚本 + gold + tb + mutants）。
**机器可读结果**：`result.json`（含 rc、SHA、测了什么、未完）。
