# INTERFACE — ds_numeric_adversarial 测试台契约

本文件描述**审计测试台**的接口/向量格式/运行方式，不是被测 RTL 的接口契约。被测模块的接口以各自 worker 的 `INTERFACE.md` 为准。

---

## 1. 目录与职责

| 路径 | 职责 |
|---|---|
| `ref/refmodel.py` | 独立精确参考（Fraction/整数，RNE/FTZ/FMA/i16） |
| `ref/c_ref.c` | C libc 独立交叉参考（cast/lrintf/fmaf） |
| `vectors/*.vec` | 对抗输入向量（十六进制） |
| `tb/tb_i48_to_f32.sv` | `epilogue_i48_to_f32` 文件驱动测试台 |
| `tb/tb_fma.sv` | `epilogue_fma_stage` 文件驱动测试台（mode/scale/bias 逐向量） |
| `tb/tb_f32_to_i16.sv` | `epilogue_f32_to_i16` 文件驱动测试台 |
| `tb/tb_approx.sv` | `approx_div_sqrt` 文件驱动测试台（可选 `HAS_FLUSH`） |
| `tb/tb_approx_flush.sv` | 新 approx 的 5 拍延迟/flush 专用测试 |
| `tb/tb_asr_fma_ip.sv` | `asr_fma_ip` 非阻塞 AXIS 包装器测试 |
| `tb/tb_stream.sv` | `epilogue_stream_engine_v023` 集成测试（cfg/param/spill/abort/reconfig/BP） |
| `tb/tb_flush.sv` | i48/FMA/i16/lane 的 leaf flush 测试 |
| `scripts/gen_vectors.py` | 生成全部向量 |
| `scripts/run_suite.py` | 编译/运行/对比/JSON 汇总；每个仿真有墙钟 watchdog |
| `scripts/crosscheck_c.py` | Python 参考 vs C libc 交叉核对 |
| `scripts/audit_model.py` | 实际 ASR 参数审计（只读 manifest/parameters.bin） |
| `scripts/consolidate.py` | 汇总为最终 `result.json` |

---

## 2. 向量格式

所有文件为 ASCII 十六进制，按行读取；`run_suite.py` 负责生成/解析。

### 2.1 `vectors/i48.vec`
```
<data_48bit_hex> <tag_16bit_hex> <last_0|1>
```
- `data` 按 48-bit 二进制补码解释（`0x800000000000` = -2^47）。
- 输出行：`<in_cycle> <out_cycle> <data_32bit_hex> <tag_16bit_hex> <last>`。

### 2.2 `vectors/fma.vec`
```
<mode_hex> <scale_32bit_hex> <bias_32bit_hex> <data_32bit_hex> <tag_16bit_hex> <last_0|1>
```
- `mode=0`：转换旁路，期望 `out=data`；
- `mode=1`：`out=round_once(data*scale + bias)`；
- `mode=2`：`out=round_once(data*scale + 0)`。
- 输出行：`<in_cycle> <out_cycle> <data_32bit_hex> <tag_16bit_hex> <last>`。

### 2.3 `vectors/f32_i16.vec`
```
<data_32bit_hex> <tag_16bit_hex> <last_0|1>
```
- 输出行：`<in_cycle> <out_cycle> <i16_16bit_hex> <tag_16bit_hex> <last>`。

### 2.4 `vectors/approx.vec`
```
<op_hex> <a_32bit_hex> <b_32bit_hex> <tag_16bit_hex>
```
- `op=0` DIV，`op=1` SQRT，`op=2` RSQRT。
- 输出行：`<in_cycle> <out_cycle> <result_32bit_hex> <flags_8bit_hex> <tag_16bit_hex>`。
- `tag` 必须唯一（本套件用 0..N-1），用于 in/out cycle 配对和 latency 计算。

### 2.5 `vectors/stream.vec`
```
<lane0_48bit_hex> <lane1_48bit_hex> <lane2_48bit_hex> <lane3_48bit_hex> <tag_16bit_hex> <last_0|1>
```
- 输出行：
  - `A <cycle> <a16_64bit_hex> <tag_16bit_hex> <last>`
  - `P <cycle> <packed_128bit_hex> <tag_16bit_hex> <last>`
  - `S <cycle> <spill_192bit_hex> <tag_16bit_hex> <last>`
- `stream_reconfig.vec`：2 beat，第二拍 last=1，用于重配置在途测试。

---

## 3. Testbench 参数

### 3.1 通用 plusargs
| 参数 | 含义 |
|---|---|
| `+VEC_FILE=<path>` | 输入向量（相对 `ds_numeric_adversarial` 的路径，避免中文绝对路径在 Icarus `%s` 中损坏） |
| `+OUT_FILE=<path>` | 输出日志 |
| `+MAX_CYCLES=<n>` | SV cycle watchdog；超限 `$finish(2)` |
| `+BP=<0|1|2|3>` | 输出反压模式；0=always ready，1=随机 50%，2=7/8 ready，3=31/32 ready |

### 3.2 `tb_approx.sv`
- 编译宏 `HAS_FLUSH`：连接 `.flush(flush)`；旧 approx 无此端口，不定义。
- `-Ptb_approx.TIER=<n>`：选择 TIER；新 approx 只接受 1，0/2 会在 elaboration 失败（测试脚本把失败视为“正确拒绝”）。
- 输出 `STABILITY_ERRORS=<n>`：`out_valid && !out_ready` 时 result/flags/tag 必须保持。

### 3.3 `tb_stream.sv`
| 参数 | 含义 |
|---|---|
| `+MODE=<0|1|2>` | cfg_fma_mode |
| `+RELU=<0|1>` | cfg_relu_en |
| `+SPILL=<0|1>` | cfg_spill_c48 |
| `+SCALE=<hex32>` | cfg_scale |
| `+BIAS=<hex32>` | cfg_bias |
| `+ABORT_AT=<n>` | 第 n 个输入握手后拉 abort 一拍；-1 不 abort |
| `+PARAM_EN=<0|1>` | 在 cfg 前写 `param_wr_*` 一次 |
| `+PARAM_ADDR=<n>` / `+PARAM_DATA=<hex32>` | 参数口地址/数据 |
| `+RECFG_AT=<n>` | 第 n 个输入握手后立即加载新 cfg（用于在途重配置测试） |
| `+RECFG_SCALE=<hex32>` / `+RECFG_BIAS=<hex32>` | 新 cfg scale/bias |

`tb_stream` 在 `out_valid && out_ready` 时记录 A16，在 `a16_packed_valid && a16_packed_ready` 时记录 packed，在 `spill_valid && spill_ready` 时记录 spill。**注意**：A16 的 `a16_valid && a16_ready` 是外部消费者看到的握手；packer_full 时 DUT 内部不推进但 `a16_valid` 仍高，本 TB 会如实记录重复握手（这是 F12 的证据，不是 TB 误判）。

---

## 4. 参考语义（本审计采用）

1. **FP32**：binary32，RNE；subnormal 输入/输出 FTZ；NaN canonical `0x7fc00000`。
2. **i48→f32**：精确整数 → RNE，无溢出（2^47 在 f32 范围内）。
3. **FMA**：`round_once(x*s + b)`，不是先乘后加；这是用户保留的“FMA 顺序”契约。
4. **f32→i16**：RNE + `[-32768,32767]` 饱和；NaN→0；±Inf→饱和；±0→0。
5. **DIV/SQRT/RSQRT**：用户允许近似，不要求逐位；本审计测相对误差、特殊值/flag、延迟/II、反压/tag/order、flush，不把近似差异直接判 bug（除因子 2/符号/特殊值这类结构性错误）。
6. **特殊值**：DIV 的 0/0、inf/inf、x/0；SQRT/RSQRT 的 NaN、负值、±0、inf；RSQRT(-0) 期望 `-inf`（IEEE-754），DUT 返回 `+inf` 记为 F9。
7. **Flags**：`[0]` invalid，`[1]` div0，`[2]` overflow，`[3]` underflow/FTZ，`[4]` approx，`[7:5]` reserved=0。

---

## 5. 通过/失败判定

- 功能向量：逐位比较；任何 mismatch → 该测试 `pass=false`。
- 近似向量：特殊值/flag/tag/order/stability 必须精确；普通值比较最大/均值相对误差，不要求逐位。
- 协议：`out_valid && !out_ready` 时输出必须保持；tag 必须等于对应输入 tag；in-order；无丢失/重复（stream A16 计数必须等于输入 beat 数）。
- 每个测试的 `rc` 写入 `result_*.json`；任何 `rc != 0` 或 `pass=false` 都会使最终 `result.json` 的 `overall_pass=false`。
- **不使用无条件 PASS 打印**；所有断言失败影响退出码。

---

## 6. 运行

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial
python3 scripts/gen_vectors.py
python3 scripts/audit_model.py
python3 scripts/crosscheck_c.py
python3 scripts/run_suite.py --label old_final
```

被测源通过 `--i48/--fma/--fma-pipe/--f32i16/--relu/--lane/--stream/--approx/--recip/--rsqrt` 覆盖；新 approx 加 `--approx-has-flush`。完整命令见 `REPORT.md` 与 `result.json.commands`。

---

## 7. 产物

- `result.json`：最终机器可读汇总（overall_pass=false）。
- `result_*.json`：每次运行的原始结果。
- `logs/*.log`：编译/仿真 stdout + watchdog 记录。
- `logs/*.out`：逐拍输出。
- `model_audit.json`、`ref_c_crosscheck.json`、`approx_worst_cases.json`。
- `REPORT.md`、`FINDINGS.md`、本文件、`progress.json`。
