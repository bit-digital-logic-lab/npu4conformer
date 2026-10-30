# 流式模块同负载周期比较：gemini_stream_round2 vs primary_stream_fix

- 日期：2026-10-29T23:12:03+0800
- 工作目录：`/home/yang/Desktop/项目/v023_repair/ds_cycle_stream_compare`
- 方向：**before = `gemini_stream_round2`，after = `primary_stream_fix`**；`delta = after - before`（负值=周期减少），`percent = 100*delta/before`（负值=收益）。
- 范围：**仅模块级逻辑仿真**（Icarus Verilog）；未综合、未 Vivado/STA、未上板、未 VNC、未 push；不是整机/全模型结果。

## 结论

- 在 256/1024/4096 beats × 转换/非平凡FMA × 无背压/两端随机/packed长停顿 的 **18 组同负载用例**中，两版数值、tag、last、计数均正确，**18/18 组成立**。
- 在这些**两版都正确**的用例中，主版 `primary_stream_fix` 的周期全面少于 `gemini_stream_round2`；收益来自 A16 与 packed 的并行/独立输出，而不是少做工作。
- **bias-only 参数预装**是正确性负对照：旧版 `gemini_stream_round2` 失败（256 A16 + 128 packed 数据失配，未初始化 `param_mem[0]` 被当作 scale），主版通过。该用例**不计入加速比**，只记失败。
- 状态：`module_pass_system_pending`。**不能把本模块结果拼成系统 PASS**；整机、全模型、综合/时序均未验收。

## 1. 同负载与公平性

- 受测数据通路：4 lane/beat（每 beat 192-bit C48，输出 64-bit A16 与 128-bit packed）。
- 输入长度：256、1024、4096 beats；每个长度使用**独立生成**的向量文件，不是同一文件截断。
- 配置：
  - `conv`：mode=0，scale=0x3f800000，bias=0x00000000；INT48->FP32->INT16 conversion bypass, relu=0。
  - `fma_nontrivial`：mode=1，scale=0x3f000001，bias=0x3f800000；non-trivial FMA scale/bias (rounding-discriminating), relu=0。
- 背压场景：
  - `bp0_no_backpressure`：BP=0；a16_ready=1, a16_packed_ready=1。
  - `bp1_both_random`：BP=1；a16_ready and a16_packed_ready driven by independent LFSR bits。
  - `bp5_packed_long_stall`：BP=5；a16_ready=1; packed ready only in last 32 of every 256 cycles (224-cycle stall)。
- **依赖集固定**：两版使用完全相同的 `epilogue_i48_to_f32`、`epilogue_fma_stage`、`fp32_fma_pipe`、`epilogue_f32_to_i16`、`epilogue_relu`、`epilogue_lane`（取自 `primary_stream_fix/candidate`，即 gemini_fma_round2 的修正 SHA），只有 stream engine 源文件不同。
- **tag 契约差异按候选真实接线处理**：
  - `gemini_stream_round2`：共享 tag，packed handshake 时从 `a16_tag` 读取 `p128_tag`。
  - `primary_stream_fix`：新增独立 `a16_packed_tag` 端口，packed tag 从该端口读取。
- 编译：`iverilog -g2012`，两版分别编译，**一次一个（无并行编译作业）**；每个仿真有 cycle watchdog （`MAX_CYCLES=2000000`）和 wall-clock watchdog（180 s）。
- 参数传参：`PARAM_EN/PARAM_ADDR/PARAM_DATA` 作为 plusarg 实际传入仿真（不是只写在 Python 里）；bias-only 用例正是用这条路径。
- 独立参考：`ref/refmodel.py` 从 `primary_stream_fix/ref` 只读复制，按 i48→f32、单次舍入 FMA、f32→i16 的语义生成期望值；没有调用 DUT 或候选自带 golden。
- 退出码门槛：仿真 rc、里程碑、A16/packed 数值、tag、last、计数任一不满足即判该用例失败；失败用例不进入加速统计。`primary_stream_fix` 目录全程只读，未修改。

### 输入向量 SHA-256

| 向量 | beats | SHA-256 |
|---|---:|---|
| `vectors/stream_256.vec` | 256 | `33d966c1257365615986ccd30f46bb38cdd0debf1a30bd5f6c7558c0ca92b3dd` |
| `vectors/stream_1024.vec` | 1024 | `bc104c7d08c67e13e22d94a7ac38a1e8b77a5b0e8571149099ac195c71d71cfb` |
| `vectors/stream_4096.vec` | 4096 | `ed67d5363b5a0784e2456bdbd54271a3d6a170506a021fde97c2f5b3f8d7d0f1` |

### 源码 SHA-256

| 文件 | SHA-256 |
|---|---|
| `candidate/gemini/epilogue_stream_engine_v023.sv` | `5a2a111c35f3e688574cb4ae8df5e03edd1f09793272d182cea60829ace25ffd` |
| `candidate/primary/epilogue_stream_engine_v023.sv` | `336e859f7c061e6c71b25761a299e00656f0fc2d8d18fcf77bdb40c0e98b2e18` |
| `candidate/primary/epilogue_i48_to_f32.sv` | `637a7b327d35760bc5d741128d04f77bcddde87cc40886dcf24aff09cebd29bf` |
| `candidate/primary/epilogue_fma_stage.sv` | `34b55dc340b33ee570c540453662404579a77b2f8e2b166dbb2563ab3740c00b` |
| `candidate/primary/fp32_fma_pipe.sv` | `1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12` |
| `candidate/primary/epilogue_f32_to_i16.sv` | `c51d3327a7fcfbe7e584f1efa275413644147669c9d216ea7f5fbf31b864af6b` |
| `candidate/primary/epilogue_relu.sv` | `0e008b394489fcdd2f453aeebee5288f1b812d715c5e8840d47f19bcb3142c4d` |
| `candidate/primary/epilogue_lane.sv` | `d00b4d57776a605cbed790d19e9a7be7bb4b0f1751d4f6b617a9ca35489435f7` |
| `tb/tb_stream_bench.sv` | `6627a146cdc3d8d991121034fca1a8e10d20405b6ac1e52567ee3f1cf488ffb4` |
| `ref/refmodel.py` | `38eb7ed944f05d6ac45ff68b69fbaa4b0b5b895f0eef46fa33e138395ceb64e2` |
| `scripts/gen_vectors.py` | `77950435b804a5bb8ab632cc84688da3bf96218fd35fd90e844c094465c3594e` |
| `scripts/run_bench.py` | `630becc0bb573e1ab2392e037d42751fefd3ad3a0c9f15063e95db2d89228ed3` |
| `scripts/make_report.py` | `dd6099af9258e9aa6cf95013b865bdf28a52158d6850f1733bf34185ea4eb8f4` |
| `run_all.sh` | `e6dc1589d895a0acc6678e4590987bd68f3304d96fdddaf69fa60049dd3d29bd` |

## 2. 周期定义与排空边界

- 时间轴以 **第一个 `cval_valid && cval_ready` 握手**为 0（每版各自取自己的首个输入握手）。
- `t_last_a16`：首个输入握手 → 最后一次 A16 握手。
- `t_last_packed`：首个输入握手 → 最后一次 packed 握手。
- `t_idle`：首个输入握手 → DUT `engine_idle` 首次为 1；`engine_idle = in_flight_beats==0 && !pack_has_half && !p128_valid && !in_burst && !abort`。
- `drain_tail`：`t_idle - max(t_last_a16, t_last_packed)`，即最后一次输出握手之后到引擎排空边界。
- 所有用例 `drain_tail = 1`：最后一次输出握手后的下一拍 `engine_idle` 成立，说明没有额外残留 beat/packer 半字；这 1 拍是状态寄存器的观测边界，不是额外流水线工作。
- `last_p_minus_last_a`：`t_last_packed - t_last_a16`；旧版串行输出时通常为 1，主版并行输出时为 0。

## 3. 正确性门槛（先过数值/tag，再谈周期）

### 3.1 正式比较场景

| beats | 配置 | 场景 | A16 数 (before/after) | packed 数 | A16 数据错 | packed 数据错 | tag 错 | last 错 | 两版 PASS |
|---:|---|---|---:|---:|---:|---:|---:|---:|---|
| 256 | conv | bp0_no_backpressure | 256/256 | 128/128 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 256 | conv | bp1_both_random | 256/256 | 128/128 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 256 | conv | bp5_packed_long_stall | 256/256 | 128/128 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 256 | fma_nontrivial | bp0_no_backpressure | 256/256 | 128/128 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 256 | fma_nontrivial | bp1_both_random | 256/256 | 128/128 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 256 | fma_nontrivial | bp5_packed_long_stall | 256/256 | 128/128 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 1024 | conv | bp0_no_backpressure | 1024/1024 | 512/512 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 1024 | conv | bp1_both_random | 1024/1024 | 512/512 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 1024 | conv | bp5_packed_long_stall | 1024/1024 | 512/512 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 1024 | fma_nontrivial | bp0_no_backpressure | 1024/1024 | 512/512 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 1024 | fma_nontrivial | bp1_both_random | 1024/1024 | 512/512 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 1024 | fma_nontrivial | bp5_packed_long_stall | 1024/1024 | 512/512 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 4096 | conv | bp0_no_backpressure | 4096/4096 | 2048/2048 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 4096 | conv | bp1_both_random | 4096/4096 | 2048/2048 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 4096 | conv | bp5_packed_long_stall | 4096/4096 | 2048/2048 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 4096 | fma_nontrivial | bp0_no_backpressure | 4096/4096 | 2048/2048 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 4096 | fma_nontrivial | bp1_both_random | 4096/4096 | 2048/2048 | 0/0 | 0/0 | 0/0 | 0/0 | YES |
| 4096 | fma_nontrivial | bp5_packed_long_stall | 4096/4096 | 2048/2048 | 0/0 | 0/0 | 0/0 | 0/0 | YES |

每版还核对了 `stat_c48_beats_in == beats`、`stat_a16_beats_out == beats`，以及 packed 计数 `ceil(beats/2)`；所有正式用例均为 0 失配、计数精确。

### 3.2 bias-only 负对照（不计加速）

预期语义：只预装 bias（addr=1, 2.0）时，scale 回退到 cfg=1.5；bias 使用预装值 2.0。

| 版本 | rc | A16 数 | packed 数 | A16 数据错 | packed 数据错 | tag 错 | PASS | 处理 |
|---|---:|---:|---:|---:|---:|---:|---|---|
| `gemini_stream_round2` | 0 | 256 | 128 | 256 | 128 | 0 | NO | **失败，仅记录，不报加速** |
| `primary_stream_fix` | 0 | 256 | 128 | 0 | 0 | 0 | YES | 通过 |

旧版失败根因：写 bias 也把共享 `param_loaded` 置 1，随后 `eff_scale = param_mem[0]` 读取未初始化值，输出出现 X/失配。主版把 `scale_valid` 与 `bias_valid` 分开，未预装 scale 时正确回退 cfg。

## 4. 周期结果（before/after/delta/percent）

### 首个输入 → 最后 A16 握手 (`t_last_a16`)

| beats | 配置 | 场景 | before | after | delta | percent | speedup |
|---:|---|---|---:|---:|---:|---:|---:|
| 256 | conv | bp0_no_backpressure | 391 | 265 | -126 | -32.23% | 1.475x |
| 256 | conv | bp1_both_random | 636 | 509 | -127 | -19.97% | 1.250x |
| 256 | conv | bp5_packed_long_stall | 3055 | 2044 | -1011 | -33.09% | 1.495x |
| 256 | fma_nontrivial | bp0_no_backpressure | 391 | 265 | -126 | -32.23% | 1.475x |
| 256 | fma_nontrivial | bp1_both_random | 636 | 509 | -127 | -19.97% | 1.250x |
| 256 | fma_nontrivial | bp5_packed_long_stall | 3055 | 2044 | -1011 | -33.09% | 1.495x |
| 1024 | conv | bp0_no_backpressure | 1543 | 1033 | -510 | -33.05% | 1.494x |
| 1024 | conv | bp1_both_random | 2533 | 2018 | -515 | -20.33% | 1.255x |
| 1024 | conv | bp5_packed_long_stall | 12012 | 8188 | -3824 | -31.83% | 1.467x |
| 1024 | fma_nontrivial | bp0_no_backpressure | 1543 | 1033 | -510 | -33.05% | 1.494x |
| 1024 | fma_nontrivial | bp1_both_random | 2533 | 2018 | -515 | -20.33% | 1.255x |
| 1024 | fma_nontrivial | bp5_packed_long_stall | 12012 | 8188 | -3824 | -31.83% | 1.467x |
| 4096 | conv | bp0_no_backpressure | 6151 | 4105 | -2046 | -33.26% | 1.498x |
| 4096 | conv | bp1_both_random | 10223 | 8211 | -2012 | -19.68% | 1.245x |
| 4096 | conv | bp5_packed_long_stall | 47840 | 32764 | -15076 | -31.51% | 1.460x |
| 4096 | fma_nontrivial | bp0_no_backpressure | 6151 | 4105 | -2046 | -33.26% | 1.498x |
| 4096 | fma_nontrivial | bp1_both_random | 10223 | 8211 | -2012 | -19.68% | 1.245x |
| 4096 | fma_nontrivial | bp5_packed_long_stall | 47840 | 32764 | -15076 | -31.51% | 1.460x |

### 首个输入 → 最后 packed 握手 (`t_last_packed`)

| beats | 配置 | 场景 | before | after | delta | percent | speedup |
|---:|---|---|---:|---:|---:|---:|---:|
| 256 | conv | bp0_no_backpressure | 392 | 265 | -127 | -32.40% | 1.479x |
| 256 | conv | bp1_both_random | 637 | 509 | -128 | -20.09% | 1.251x |
| 256 | conv | bp5_packed_long_stall | 3056 | 2044 | -1012 | -33.12% | 1.495x |
| 256 | fma_nontrivial | bp0_no_backpressure | 392 | 265 | -127 | -32.40% | 1.479x |
| 256 | fma_nontrivial | bp1_both_random | 637 | 509 | -128 | -20.09% | 1.251x |
| 256 | fma_nontrivial | bp5_packed_long_stall | 3056 | 2044 | -1012 | -33.12% | 1.495x |
| 1024 | conv | bp0_no_backpressure | 1544 | 1033 | -511 | -33.10% | 1.495x |
| 1024 | conv | bp1_both_random | 2534 | 2015 | -519 | -20.48% | 1.258x |
| 1024 | conv | bp5_packed_long_stall | 12013 | 8188 | -3825 | -31.84% | 1.467x |
| 1024 | fma_nontrivial | bp0_no_backpressure | 1544 | 1033 | -511 | -33.10% | 1.495x |
| 1024 | fma_nontrivial | bp1_both_random | 2534 | 2015 | -519 | -20.48% | 1.258x |
| 1024 | fma_nontrivial | bp5_packed_long_stall | 12013 | 8188 | -3825 | -31.84% | 1.467x |
| 4096 | conv | bp0_no_backpressure | 6152 | 4105 | -2047 | -33.27% | 1.499x |
| 4096 | conv | bp1_both_random | 10224 | 8211 | -2013 | -19.69% | 1.245x |
| 4096 | conv | bp5_packed_long_stall | 47841 | 32764 | -15077 | -31.51% | 1.460x |
| 4096 | fma_nontrivial | bp0_no_backpressure | 6152 | 4105 | -2047 | -33.27% | 1.499x |
| 4096 | fma_nontrivial | bp1_both_random | 10224 | 8211 | -2013 | -19.69% | 1.245x |
| 4096 | fma_nontrivial | bp5_packed_long_stall | 47841 | 32764 | -15077 | -31.51% | 1.460x |

### 首个输入 → 引擎 idle (`t_idle`)

| beats | 配置 | 场景 | before | after | delta | percent | speedup |
|---:|---|---|---:|---:|---:|---:|---:|
| 256 | conv | bp0_no_backpressure | 393 | 266 | -127 | -32.32% | 1.477x |
| 256 | conv | bp1_both_random | 638 | 510 | -128 | -20.06% | 1.251x |
| 256 | conv | bp5_packed_long_stall | 3057 | 2045 | -1012 | -33.10% | 1.495x |
| 256 | fma_nontrivial | bp0_no_backpressure | 393 | 266 | -127 | -32.32% | 1.477x |
| 256 | fma_nontrivial | bp1_both_random | 638 | 510 | -128 | -20.06% | 1.251x |
| 256 | fma_nontrivial | bp5_packed_long_stall | 3057 | 2045 | -1012 | -33.10% | 1.495x |
| 1024 | conv | bp0_no_backpressure | 1545 | 1034 | -511 | -33.07% | 1.494x |
| 1024 | conv | bp1_both_random | 2535 | 2019 | -516 | -20.36% | 1.256x |
| 1024 | conv | bp5_packed_long_stall | 12014 | 8189 | -3825 | -31.84% | 1.467x |
| 1024 | fma_nontrivial | bp0_no_backpressure | 1545 | 1034 | -511 | -33.07% | 1.494x |
| 1024 | fma_nontrivial | bp1_both_random | 2535 | 2019 | -516 | -20.36% | 1.256x |
| 1024 | fma_nontrivial | bp5_packed_long_stall | 12014 | 8189 | -3825 | -31.84% | 1.467x |
| 4096 | conv | bp0_no_backpressure | 6153 | 4106 | -2047 | -33.27% | 1.499x |
| 4096 | conv | bp1_both_random | 10225 | 8212 | -2013 | -19.69% | 1.245x |
| 4096 | conv | bp5_packed_long_stall | 47842 | 32765 | -15077 | -31.51% | 1.460x |
| 4096 | fma_nontrivial | bp0_no_backpressure | 6153 | 4106 | -2047 | -33.27% | 1.499x |
| 4096 | fma_nontrivial | bp1_both_random | 10225 | 8212 | -2013 | -19.69% | 1.245x |
| 4096 | fma_nontrivial | bp5_packed_long_stall | 47842 | 32765 | -15077 | -31.51% | 1.460x |

### 排空边界 idle - max(lastA,lastP) (`drain_tail`)

| beats | 配置 | 场景 | before | after | delta | percent | speedup |
|---:|---|---|---:|---:|---:|---:|---:|
| 256 | conv | bp0_no_backpressure | 1 | 1 | +0 | +0.00% | 1.000x |
| 256 | conv | bp1_both_random | 1 | 1 | +0 | +0.00% | 1.000x |
| 256 | conv | bp5_packed_long_stall | 1 | 1 | +0 | +0.00% | 1.000x |
| 256 | fma_nontrivial | bp0_no_backpressure | 1 | 1 | +0 | +0.00% | 1.000x |
| 256 | fma_nontrivial | bp1_both_random | 1 | 1 | +0 | +0.00% | 1.000x |
| 256 | fma_nontrivial | bp5_packed_long_stall | 1 | 1 | +0 | +0.00% | 1.000x |
| 1024 | conv | bp0_no_backpressure | 1 | 1 | +0 | +0.00% | 1.000x |
| 1024 | conv | bp1_both_random | 1 | 1 | +0 | +0.00% | 1.000x |
| 1024 | conv | bp5_packed_long_stall | 1 | 1 | +0 | +0.00% | 1.000x |
| 1024 | fma_nontrivial | bp0_no_backpressure | 1 | 1 | +0 | +0.00% | 1.000x |
| 1024 | fma_nontrivial | bp1_both_random | 1 | 1 | +0 | +0.00% | 1.000x |
| 1024 | fma_nontrivial | bp5_packed_long_stall | 1 | 1 | +0 | +0.00% | 1.000x |
| 4096 | conv | bp0_no_backpressure | 1 | 1 | +0 | +0.00% | 1.000x |
| 4096 | conv | bp1_both_random | 1 | 1 | +0 | +0.00% | 1.000x |
| 4096 | conv | bp5_packed_long_stall | 1 | 1 | +0 | +0.00% | 1.000x |
| 4096 | fma_nontrivial | bp0_no_backpressure | 1 | 1 | +0 | +0.00% | 1.000x |
| 4096 | fma_nontrivial | bp1_both_random | 1 | 1 | +0 | +0.00% | 1.000x |
| 4096 | fma_nontrivial | bp5_packed_long_stall | 1 | 1 | +0 | +0.00% | 1.000x |

### 汇总（同组 3 个长度求和，仅统计两版都正确的用例）

| 配置/场景 | 指标 | before 合计 | after 合计 | delta 合计 | percent |
|---|---|---:|---:|---:|---:|
| conv/bp0_no_backpressure | t_last_a16 | 8085 | 5403 | -2682 | -33.17% |
| conv/bp0_no_backpressure | t_last_packed | 8088 | 5403 | -2685 | -33.20% |
| conv/bp0_no_backpressure | t_idle | 8091 | 5406 | -2685 | -33.19% |
| conv/bp0_no_backpressure | drain_tail | 3 | 3 | +0 | +0.00% |
| conv/bp1_both_random | t_last_a16 | 13392 | 10738 | -2654 | -19.82% |
| conv/bp1_both_random | t_last_packed | 13395 | 10735 | -2660 | -19.86% |
| conv/bp1_both_random | t_idle | 13398 | 10741 | -2657 | -19.83% |
| conv/bp1_both_random | drain_tail | 3 | 3 | +0 | +0.00% |
| conv/bp5_packed_long_stall | t_last_a16 | 62907 | 42996 | -19911 | -31.65% |
| conv/bp5_packed_long_stall | t_last_packed | 62910 | 42996 | -19914 | -31.65% |
| conv/bp5_packed_long_stall | t_idle | 62913 | 42999 | -19914 | -31.65% |
| conv/bp5_packed_long_stall | drain_tail | 3 | 3 | +0 | +0.00% |
| fma_nontrivial/bp0_no_backpressure | t_last_a16 | 8085 | 5403 | -2682 | -33.17% |
| fma_nontrivial/bp0_no_backpressure | t_last_packed | 8088 | 5403 | -2685 | -33.20% |
| fma_nontrivial/bp0_no_backpressure | t_idle | 8091 | 5406 | -2685 | -33.19% |
| fma_nontrivial/bp0_no_backpressure | drain_tail | 3 | 3 | +0 | +0.00% |
| fma_nontrivial/bp1_both_random | t_last_a16 | 13392 | 10738 | -2654 | -19.82% |
| fma_nontrivial/bp1_both_random | t_last_packed | 13395 | 10735 | -2660 | -19.86% |
| fma_nontrivial/bp1_both_random | t_idle | 13398 | 10741 | -2657 | -19.83% |
| fma_nontrivial/bp1_both_random | drain_tail | 3 | 3 | +0 | +0.00% |
| fma_nontrivial/bp5_packed_long_stall | t_last_a16 | 62907 | 42996 | -19911 | -31.65% |
| fma_nontrivial/bp5_packed_long_stall | t_last_packed | 62910 | 42996 | -19914 | -31.65% |
| fma_nontrivial/bp5_packed_long_stall | t_idle | 62913 | 42999 | -19914 | -31.65% |
| fma_nontrivial/bp5_packed_long_stall | drain_tail | 3 | 3 | +0 | +0.00% |

> 转换与 FMA 两组在相同长度/场景下周期相同，因为两版的数据通路对每 beat 的节拍控制不依赖具体数值；本报告仍分别给出，数值正确性由各自参考模型独立核对。

## 5. 结果解释与限制

- **无背压**：旧版 A16 与 packed 互斥，每发一个 packed 拍就暂停 A16，因此约 1.5 拍/beat；主版 A16 与 packed 可同拍各自握手，约 1 拍/beat，周期约减少 32%–33%。
- **两端随机**：随机反压拉长两版，但主版仍能重叠 A16/packed，周期约减少 20%。
- **packed 长停顿**：packed ready 每 256 拍仅高 32 拍。两版都被 packed 限速，但主版在 ready 窗口内可同时推进 A16 与 packed，周期约减少 31%–33%。
- **排空边界**：18/18 用例均为 `drain_tail=1`，最后输出后下一拍 idle；旧版 `last_p - last_a = 1`，主版为 0，符合并行/串行输出契约差异。
- **只模块，不全模型**：这些是 testbench 周期，不是板卡周期/主频/整机吞吐；未综合、未 STA、未上板，不能外推 300/600 MHz，也不能声明系统 PASS。
- **bias-only 失败不是加速**：旧版该用例数据错误，已从所有加速统计中排除。
- 本比较未覆盖 spill、abort、重配置、per-channel 参数、FP32 spill、全图/全模型；这些不在本任务范围。

## 6. 复跑与产物

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_cycle_stream_compare
./run_all.sh
# 或分步：
python3 scripts/gen_vectors.py
python3 scripts/run_bench.py
python3 scripts/make_report.py
```

- `run_all.sh` 顺序执行向量生成、两版编译、36 次正式仿真 + 2 次 bias-only 仿真、结果与报告生成。
- 原始日志：`logs/compile_*.log`、`logs/<variant>_<beats>_<config>_<scenario>.log/.out`、`logs/run_bench_console.log`。
- 机器可读结果：`result.json`；源码/输入清单：`SOURCE_SHA256.json`、`vectors/VECTOR_SHA256.json`；阶段状态：`progress.json`。
- 本报告由 `scripts/make_report.py` 从 `result.json` 生成，所有周期与百分比均来自实测日志，未手工改写。

## 7. 交付声明

- 模块级比较：**通过（两版在正式场景均正确，且主版周期更少）**。
- 系统级：**PENDING / 不允许声明 PASS**。本任务只比较 stream 模块，未做整机联仿、全模型精度、综合或板级验证。
- 结论仅适用于上述依赖集、向量、配置、背压场景和仿真器版本。

