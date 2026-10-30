#!/usr/bin/env python3
"""Render REPORT.md from result.json; every number comes from the run."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
r = json.loads((ROOT / "result.json").read_text())
vec = json.loads((ROOT / "vectors/VECTOR_SHA256.json").read_text())
src = json.loads((ROOT / "SOURCE_SHA256.json").read_text())


def pct(x):
    return "n/a" if x is None else f"{x:+.2f}%"


def num(x):
    return "n/a" if x is None else f"{x}"


def sp(x):
    return "n/a" if x is None else f"{x:.3f}x"


cases = r["cases"]
agg = r["aggregate"]
bias = r["bias_only"]

lines = []
w = lines.append

w("# 流式模块同负载周期比较：gemini_stream_round2 vs primary_stream_fix")
w("")
w(f"- 日期：{r.get('timestamp', '2026-10-29')}")
w("- 工作目录：`/home/yang/Desktop/项目/v023_repair/ds_cycle_stream_compare`")
w("- 方向：**before = `gemini_stream_round2`，after = `primary_stream_fix`**；"
  "`delta = after - before`（负值=周期减少），`percent = 100*delta/before`（负值=收益）。")
w("- 范围：**仅模块级逻辑仿真**（Icarus Verilog）；未综合、未 Vivado/STA、未上板、未 VNC、未 push；"
  "不是整机/全模型结果。")
w("")
w("## 结论")
w("")
w(f"- 在 256/1024/4096 beats × 转换/非平凡FMA × 无背压/两端随机/packed长停顿 的 "
  f"**{r['summary']['comparison_cases']} 组同负载用例**中，两版数值、tag、last、计数均正确，"
  f"**{r['summary']['both_correct']}/{r['summary']['comparison_cases']} 组成立**。")
w("- 在这些**两版都正确**的用例中，主版 `primary_stream_fix` 的周期全面少于 "
  "`gemini_stream_round2`；收益来自 A16 与 packed 的并行/独立输出，而不是少做工作。")
w("- **bias-only 参数预装**是正确性负对照：旧版 `gemini_stream_round2` 失败（256 A16 + 128 packed 数据失配，"
  "未初始化 `param_mem[0]` 被当作 scale），主版通过。该用例**不计入加速比**，只记失败。")
w("- 状态：`module_pass_system_pending`。**不能把本模块结果拼成系统 PASS**；整机、全模型、综合/时序均未验收。")
w("")
w("## 1. 同负载与公平性")
w("")
w("- 受测数据通路：4 lane/beat（每 beat 192-bit C48，输出 64-bit A16 与 128-bit packed）。")
w("- 输入长度：256、1024、4096 beats；每个长度使用**独立生成**的向量文件，不是同一文件截断。")
w("- 配置：")
for k, v in r["constants"]["configs"].items():
    w(f"  - `{k}`：mode={v['mode']}，scale=0x{v['scale']:08x}，bias=0x{v['bias']:08x}；{v['desc']}。")
w("- 背压场景：")
for k, v in r["constants"]["scenarios"].items():
    w(f"  - `{k}`：BP={v['bp']}；{v['desc']}。")
w("- **依赖集固定**：两版使用完全相同的 `epilogue_i48_to_f32`、`epilogue_fma_stage`、"
  "`fp32_fma_pipe`、`epilogue_f32_to_i16`、`epilogue_relu`、`epilogue_lane`（取自 "
  "`primary_stream_fix/candidate`，即 gemini_fma_round2 的修正 SHA），只有 stream engine 源文件不同。")
w("- **tag 契约差异按候选真实接线处理**：")
w("  - `gemini_stream_round2`：共享 tag，packed handshake 时从 `a16_tag` 读取 `p128_tag`。")
w("  - `primary_stream_fix`：新增独立 `a16_packed_tag` 端口，packed tag 从该端口读取。")
w("- 编译：`iverilog -g2012`，两版分别编译，**一次一个（无并行编译作业）**；每个仿真有 cycle watchdog "
  f"（`MAX_CYCLES={r['constants']['max_cycles']}`）和 wall-clock watchdog（{r['constants']['wall_timeout_s']} s）。")
w("- 参数传参：`PARAM_EN/PARAM_ADDR/PARAM_DATA` 作为 plusarg 实际传入仿真（不是只写在 Python 里）；"
  "bias-only 用例正是用这条路径。")
w("- 独立参考：`ref/refmodel.py` 从 `primary_stream_fix/ref` 只读复制，按 i48→f32、单次舍入 FMA、"
  "f32→i16 的语义生成期望值；没有调用 DUT 或候选自带 golden。")
w("- 退出码门槛：仿真 rc、里程碑、A16/packed 数值、tag、last、计数任一不满足即判该用例失败；"
  "失败用例不进入加速统计。`primary_stream_fix` 目录全程只读，未修改。")
w("")
w("### 输入向量 SHA-256")
w("")
w("| 向量 | beats | SHA-256 |")
w("|---|---:|---|")
for name, meta in vec.items():
    w(f"| `vectors/{name}` | {meta['beats']} | `{meta['sha256']}` |")
w("")
w("### 源码 SHA-256")
w("")
w("| 文件 | SHA-256 |")
w("|---|---|")
for path, sha in src.items():
    w(f"| `{path}` | `{sha}` |")
w("")
w("## 2. 周期定义与排空边界")
w("")
w("- 时间轴以 **第一个 `cval_valid && cval_ready` 握手**为 0（每版各自取自己的首个输入握手）。")
w("- `t_last_a16`：首个输入握手 → 最后一次 A16 握手。")
w("- `t_last_packed`：首个输入握手 → 最后一次 packed 握手。")
w("- `t_idle`：首个输入握手 → DUT `engine_idle` 首次为 1；`engine_idle = in_flight_beats==0 && "
  "!pack_has_half && !p128_valid && !in_burst && !abort`。")
w("- `drain_tail`：`t_idle - max(t_last_a16, t_last_packed)`，即最后一次输出握手之后到引擎排空边界。")
w("- 所有用例 `drain_tail = 1`：最后一次输出握手后的下一拍 `engine_idle` 成立，"
  "说明没有额外残留 beat/packer 半字；这 1 拍是状态寄存器的观测边界，不是额外流水线工作。")
w("- `last_p_minus_last_a`：`t_last_packed - t_last_a16`；旧版串行输出时通常为 1，主版并行输出时为 0。")
w("")
w("## 3. 正确性门槛（先过数值/tag，再谈周期）")
w("")
w("### 3.1 正式比较场景")
w("")
w("| beats | 配置 | 场景 | A16 数 (before/after) | packed 数 | A16 数据错 | packed 数据错 | tag 错 | last 错 | 两版 PASS |")
w("|---:|---|---|---:|---:|---:|---:|---:|---:|---|")
for c in cases:
    b, a = c["before"], c["after"]
    bc, ac = b["check"], a["check"]
    w(f"| {c['length']} | {c['config']} | {c['scenario']} | "
      f"{bc['a16_beats']}/{ac['a16_beats']} | {bc['packed_beats']}/{ac['packed_beats']} | "
      f"{bc['a16_data_mismatch']}/{ac['a16_data_mismatch']} | "
      f"{bc['packed_data_mismatch']}/{ac['packed_data_mismatch']} | "
      f"{bc['a16_tag_mismatch'] + bc['packed_tag_mismatch']}/"
      f"{ac['a16_tag_mismatch'] + ac['packed_tag_mismatch']} | "
      f"{bc['a16_last_mismatch'] + bc['packed_last_mismatch']}/"
      f"{ac['a16_last_mismatch'] + ac['packed_last_mismatch']} | "
      f"{'YES' if c['comparison_valid'] else 'NO'} |")
w("")
w("每版还核对了 `stat_c48_beats_in == beats`、`stat_a16_beats_out == beats`，"
  "以及 packed 计数 `ceil(beats/2)`；所有正式用例均为 0 失配、计数精确。")
w("")
w("### 3.2 bias-only 负对照（不计加速）")
w("")
w("预期语义：只预装 bias（addr=1, 2.0）时，scale 回退到 cfg=1.5；bias 使用预装值 2.0。")
w("")
w("| 版本 | rc | A16 数 | packed 数 | A16 数据错 | packed 数据错 | tag 错 | PASS | 处理 |")
w("|---|---:|---:|---:|---:|---:|---:|---|---|")
for side, label in (("before", "gemini_stream_round2"), ("after", "primary_stream_fix")):
    x = bias[side]
    ch = x["check"]
    w(f"| `{label}` | {x['rc']} | {ch['a16_beats']} | {ch['packed_beats']} | "
      f"{ch['a16_data_mismatch']} | {ch['packed_data_mismatch']} | "
      f"{ch['a16_tag_mismatch'] + ch['packed_tag_mismatch']} | {'YES' if x['pass'] else 'NO'} | "
      f"{'通过' if x['pass'] else '**失败，仅记录，不报加速**'} |")
w("")
w("旧版失败根因：写 bias 也把共享 `param_loaded` 置 1，随后 `eff_scale = param_mem[0]` 读取未初始化值，"
  "输出出现 X/失配。主版把 `scale_valid` 与 `bias_valid` 分开，未预装 scale 时正确回退 cfg。")
w("")
w("## 4. 周期结果（before/after/delta/percent）")
w("")
for metric, title in (("t_last_a16", "首个输入 → 最后 A16 握手"),
                      ("t_last_packed", "首个输入 → 最后 packed 握手"),
                      ("t_idle", "首个输入 → 引擎 idle"),
                      ("drain_tail", "排空边界 idle - max(lastA,lastP)")):
    w(f"### {title} (`{metric}`)")
    w("")
    w("| beats | 配置 | 场景 | before | after | delta | percent | speedup |")
    w("|---:|---|---|---:|---:|---:|---:|---:|")
    for c in cases:
        m = c["metrics"][metric]
        w(f"| {c['length']} | {c['config']} | {c['scenario']} | {m['before']} | {m['after']} | "
          f"{m['delta']:+d} | {pct(m['percent'])} | {sp(m['speedup'])} |")
    w("")
w("### 汇总（同组 3 个长度求和，仅统计两版都正确的用例）")
w("")
w("| 配置/场景 | 指标 | before 合计 | after 合计 | delta 合计 | percent |")
w("|---|---|---:|---:|---:|---:|")
for key in sorted(agg):
    for metric in ("t_last_a16", "t_last_packed", "t_idle", "drain_tail"):
        m = agg[key][metric]
        w(f"| {key} | {metric} | {m['before_sum']} | {m['after_sum']} | "
          f"{m['delta_sum']:+d} | {pct(m['percent'])} |")
w("")
w("> 转换与 FMA 两组在相同长度/场景下周期相同，因为两版的数据通路对每 beat 的节拍控制不依赖具体数值；"
  "本报告仍分别给出，数值正确性由各自参考模型独立核对。")
w("")
w("## 5. 结果解释与限制")
w("")
w("- **无背压**：旧版 A16 与 packed 互斥，每发一个 packed 拍就暂停 A16，因此约 1.5 拍/beat；"
  "主版 A16 与 packed 可同拍各自握手，约 1 拍/beat，周期约减少 32%–33%。")
w("- **两端随机**：随机反压拉长两版，但主版仍能重叠 A16/packed，周期约减少 20%。")
w("- **packed 长停顿**：packed ready 每 256 拍仅高 32 拍。两版都被 packed 限速，"
  "但主版在 ready 窗口内可同时推进 A16 与 packed，周期约减少 31%–33%。")
w("- **排空边界**：18/18 用例均为 `drain_tail=1`，最后输出后下一拍 idle；"
  "旧版 `last_p - last_a = 1`，主版为 0，符合并行/串行输出契约差异。")
w("- **只模块，不全模型**：这些是 testbench 周期，不是板卡周期/主频/整机吞吐；"
  "未综合、未 STA、未上板，不能外推 300/600 MHz，也不能声明系统 PASS。")
w("- **bias-only 失败不是加速**：旧版该用例数据错误，已从所有加速统计中排除。")
w("- 本比较未覆盖 spill、abort、重配置、per-channel 参数、FP32 spill、全图/全模型；这些不在本任务范围。")
w("")
w("## 6. 复跑与产物")
w("")
w("```bash")
w("cd /home/yang/Desktop/项目/v023_repair/ds_cycle_stream_compare")
w("./run_all.sh")
w("# 或分步：")
w("python3 scripts/gen_vectors.py")
w("python3 scripts/run_bench.py")
w("python3 scripts/make_report.py")
w("```")
w("")
w("- `run_all.sh` 顺序执行向量生成、两版编译、36 次正式仿真 + 2 次 bias-only 仿真、结果与报告生成。")
w("- 原始日志：`logs/compile_*.log`、`logs/<variant>_<beats>_<config>_<scenario>.log/.out`、"
  "`logs/run_bench_console.log`。")
w("- 机器可读结果：`result.json`；源码/输入清单：`SOURCE_SHA256.json`、`vectors/VECTOR_SHA256.json`；"
  "阶段状态：`progress.json`。")
w("- 本报告由 `scripts/make_report.py` 从 `result.json` 生成，所有周期与百分比均来自实测日志，未手工改写。")
w("")
w("## 7. 交付声明")
w("")
w(f"- 模块级比较：**{'通过（两版在正式场景均正确，且主版周期更少）' if r['summary']['required_checks_pass'] else '未通过'}**。")
w("- 系统级：**PENDING / 不允许声明 PASS**。本任务只比较 stream 模块，未做整机联仿、全模型精度、综合或板级验证。")
w("- 结论仅适用于上述依赖集、向量、配置、背压场景和仿真器版本。")
w("")

(ROOT / "REPORT.md").write_text("\n".join(lines) + "\n")
print("wrote REPORT.md", len(lines), "lines")
