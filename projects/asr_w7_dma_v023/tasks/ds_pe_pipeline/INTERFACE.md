# INTERFACE — PE / 16×16 array pipeline contract

本文件是 `candidate/pe_w7_c48_cfg.sv` 与 `candidate/array16_w7_c48_cfg.sv`
的接口说明。它只描述逻辑契约；不是 STA、资源或频率签核。

## 1. PE 端口

```systemverilog
module pe_w7_c48_cfg #(
    parameter integer PIPE_STAGES = 4, // 3..6
    parameter integer ACCUM_MODE  = 0, // 0=native CARRY, 1=dual-rail CSA
    parameter integer CPA_PIPE    = 1  // CSA final CPA register
)(
    input  wire clk, reset, flush, clear_sum,
    input  wire [15:0] a_in,
    input  wire [6:0]  w_in,
    input  wire av_in, wv_in,
    input  wire [15:0] positions,
    input  wire clip,
    output reg  [15:0] a_out,
    output reg  [6:0]  w_out,
    output reg         av_out, wv_out,
    output wire signed [47:0] sum,
    output wire        sum_valid,
    output wire        pipe_empty,
    output wire [7:0]  latency_cycles,
    output wire [7:0]  drain_cycles
);
```

- `a_out/w_out/av_out/wv_out`：1 拍 systolic 前递，`flush` 清 0。
- `sum`：48-bit two's complement，INT48 自然回绕。
- `sum_valid`：累加真正发生后的指示；native 在累加边沿后的下一拍，
  CSA+CPA 再晚一拍。
- `pipe_empty`：本 PE 乘法流水及 CSA CPA pending 为空。
- `latency_cycles` / `drain_cycles`：同一个常量 `DRAIN`，见下式。
  名字保留两个是为了让控制器代码可读，值相同。

## 2. 阶段切分（PIPE_STAGES = 3..6）

| 级 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|
| 0 | ABS/DECODE | ABS/DECODE | ABS/DECODE | ABS/DECODE |
| 1 | MUL | MUL | MUL | MUL |
| 2 | SHIFT+SUB+NEG | SHIFT+SUB | SHIFT | SHIFT |
| 3 | — | NEG | SUB | SUB |
| 4 | — | — | NEG | NEG |
| 5 | — | — | — | SEXT48 |
| 之后 | ACC | ACC | ACC | ACC |

逐级组合操作：

1. **ABS/DECODE**（轻）：  
   `p = positions[w_in[5:4]*4 +: 4]`；  
   `sat = clip && p==12 && w_in[3:0]>=8`；  
   `mag = a_in[15] ? (~a_in + 16'd1) : a_in`（-32768 → 32768）；  
   `m = sat ? 8 : w_in[3:0]`；`neg = a_in[15] ^ w_in[6]`。
2. **MUL**：`raw = mag * m`，16×4 → 20 bit。
3. **SHIFT**：`aligned = {12'd0, raw} << p`，32 bit。
4. **SUB**：`magnitude = aligned - (sat ? {16'd0, mag} : 32'd0)`，32 bit。
5. **NEG**：`product32 = neg ? -$signed(magnitude) : $signed(magnitude)`，32 bit。
6. **SEXT48**（仅 6-stage）：`product48 = {{16{product32[31]}}, product32}`。
7. **ACC**：native `sum <= sum + product48`；CSA 用 3:2 压缩更新 `sum_s/sum_c`，
   最终 CPA 在 `CPA_PIPE=1` 时寄存。

3-stage 仍把 SHIFT+SUB+NEG 放在同一级，是 baseline 等价形状；
4/5/6-stage 没有任何一级同时堆 mul+shift+sub+negate。

## 3. 延迟常量

```text
PE_DRAIN_native = PIPE_STAGES + 1
PE_DRAIN_csa    = PIPE_STAGES + 2   // ACCUM_MODE=1 && CPA_PIPE=1
ARRAY_DRAIN     = 15 + PE_DRAIN     // 16x16, row/column skew = 15
```

`DRAIN` 的精确定义：从“输入被接受的那一拍”到“累加器更新边沿”的拍数；
累加结果在更新边沿后的下一拍可见。控制器不需要知道内部级数，只使用常量。

**II = 1**：PE 每拍可接受一个 `av_in && wv_in` 输入；16×16 array 的每个
wavefront 每拍推进一个 K 元素。135,000 个 back-to-back 乘积的 PE 测试
覆盖了 II=1 连续流。

| 配置 | PE_DRAIN | 16×16 ARRAY_DRAIN | K=32 的 RUN end |
|---|---:|---:|---:|
| 3-stage native | 4 | 19 | 65 |
| 4-stage native | 5 | 20 | 66 |
| 5-stage native | 6 | 21 | 67 |
| 6-stage native | 7 | 22 | 68 |
| 4-stage CSA + CPA | 6 | 21 | 67 |

`K=32 的 RUN end = 46 + ARRAY_DRAIN`，因为最后外部 A/W 输入在
`run_cycle=46`（16×16、K=32 的波前）。对一般 K：
`RUN_END = (K + 14) + ARRAY_DRAIN`。不要写死 65。

## 4. 16×16 array 端口

```systemverilog
module array16_w7_c48_cfg #(
    parameter integer PIPE_STAGES = 4,
    parameter integer ACCUM_MODE  = 0,
    parameter integer CPA_PIPE    = 1
)(
    input  wire clk, reset, flush, clear_sum,
    input  wire [255:0] a_left,
    input  wire [111:0] w_top,
    input  wire [15:0]  av,
    input  wire [15:0]  wv,
    input  wire [15:0]  positions,
    input  wire         clip,
    output wire [12287:0] sums,       // 256 x 48-bit, PE(r,c) at [(r*16+c)*48 +:48]
    output wire pipe_empty,
    output wire drain_done,           // same as pipe_empty
    output wire [7:0] pe_drain_cycles,
    output wire [7:0] array_drain_cycles
);
```

`drain_done` 在最后一个外部 `av|wv` 输入之后 `ARRAY_DRAIN` 拍精确拉高。
它不依赖控制器知道 65；如果控制器继续给输入，quiet counter 会重新计数。
`reset` 或 `flush` 时 `pipe_empty/drain_done` 直接为 1。

### 推荐控制器写法

```systemverilog
localparam integer ARRAY_DRAIN = ...; // 从数组输出读取或由参数计算
localparam integer LAST_INPUT  = K + 14; // 16x16
// state == RUN:
if (run_cycle == LAST_INPUT + ARRAY_DRAIN) begin
    // 此时 sums 已稳定；下一拍可进入 C_READ/COLLECT
    state <= C_READ;
end
```

对应旧 `block_engine_l1bank_v020` 的 16×16/K=32 情况：
baseline/3-stage 仍是 65；4-stage 必须 66；5-stage 67；6-stage 68；
4-stage CSA 67。旧代码的 `run_cycle==65` 不能直接复用于 4/5/6-stage。

## 5. 事件语义

| 事件 | 对 `sum` | 对在途乘法/前递 |
|---|---|---|
| `reset` | 清 0 | 清空 |
| `flush` | 保持不变 | 清空（在途乘积丢弃） |
| `clear_sum` | 清 0 | 不清；在途乘积之后仍可累加进已清零的 sum |
| `clear_sum && flush` | 清 0 | 清空 |

`valid` 气泡：`av_in=0` 或 `wv_in=0` 时该拍不产生乘积。
PE 的 `flush` 与 `clear_sum` 都是同步、高有效。

## 6. 数值与静态约束

- A16 有符号补码，`-32768` 的绝对值为 32768；W7 的 `S/J/M` 语义、
  `positions` 4-bit nibble、`clip` 饱和、INT48 回绕均保持 baseline 行为。
- 中间 `aligned/magnitude/product32` 保留 baseline 的 32-bit 截断/回绕；
  合同要求 `P<=12`，`block_engine_l1bank_v020` 已有 P<=12 检查。
  候选对 P=13..15 也与 baseline 逐位一致（测试覆盖，但不建议使用）。
- **16×16 array 的 `positions` 与 `clip` 必须在整个 wavefront 以及排空期（直到 `drain_done`）保持静态**。
  逐拍动态切换只在单 PE 且所有操作数同时到达时成立；systolic skew 下
  不同 PE 会在不同拍采样 positions，甚至在外部输入停止后的排空期才采样，
  动态切换会产生空间不一致。
- 本任务不修改 QDQ / FP32 FTZ / RNE / FMA；这些路径不在本 PE 内。

## 7. 结构估算（非综合）

仅按 RTL 声明状态位估算，**不是 Vivado 资源报告**：

| 配置 | 估算 FF/PE | 256 PE 约 |
|---|---:|---:|
| baseline `pe_direct_v020` | ~176 | ~45k |
| 3-stage native | ~181 | ~46k |
| 4-stage native | ~214 | ~55k |
| 5-stage native | ~264 | ~68k |
| 6-stage native | ~312 | ~80k |
| 4-stage CSA + CPA | ~310 | ~79k |

这些数字只用于架构比较；真实 LUT/FF/CARRY/DSP 映射必须等后续综合/实现。
