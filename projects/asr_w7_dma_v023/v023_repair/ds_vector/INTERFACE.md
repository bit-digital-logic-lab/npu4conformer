# INTERFACE — ds_vector v023 candidate contract

Status: **delivered and simulated** (v023 ds_vector). The approx contract was published
before RTL completion and is now backed by the single delivered gemini_approx 4-stage core. Logic simulation only; no synthesis,
no board, no Vivado. Baseline files copied under `baseline/` are read-only references.

## 1. Candidate vs baseline file map

| Role | Baseline (frozen reference) | Candidate (this task) |
|---|---|---|
| Vector engine | `baseline/rtl/ddr_vector_engine.sv` (`ddr_vector_engine`) | `candidate/rtl/ddr_vector_engine_pipe.sv` (`ddr_vector_engine_pipe`) |
| Fixed-latency FP32 lanes | `baseline/rtl/asr_fp32_alu.sv` (`asr_fp32_alu`) | `candidate/rtl/asr_fp32_lane_fixed.sv` (`asr_fp32_lane_fixed`) |
| Descriptor validator | combinational block inside baseline engine | `candidate/rtl/vector_desc_check_pipe.sv` (`vector_desc_check_pipe`) |
| AXI wrapper | `baseline/rtl/ddr_vector_axi.sv` (`ddr_vector_axi`) | `candidate/rtl/ddr_vector_axi_pipe.sv` (`ddr_vector_axi_pipe`) |
| Approx div/sqrt | not present (exact iterative only) | `gemini_approx` core copied under `candidate/rtl/gemini_approx/` (`approx_div_sqrt`, `approx_recip_lut`, `approx_rsqrt_lut`); wrapper `candidate/rtl/ddr_vector_engine_approx.sv` |

The candidate engine keeps the **same top-level port names, directions and widths** as
`ddr_vector_engine`, so `ddr_vector_axi_pipe` is the only wrapper change needed for the
existing DMA cluster. One parameter is added:

```systemverilog
parameter integer USE_APPROX_DIV_SQRT = 0   // 0: exact legacy DIV/SQRT (default)
                                             // 1: instantiate external approx_div_sqrt
```

With `USE_APPROX_DIV_SQRT=0` the candidate must be bit-identical to the baseline for all
fixed-latency ops and may only differ in cycle count; DIV/SQRT/EXP/LOG use the unchanged
exact `asr_fp32_alu` submodule. With `USE_APPROX_DIV_SQRT=1`, DIV and SQRT results are
**approximate by contract** and must be reported with measured error, never as bitexact.

W7p8 / A16 / C48 / QDQ positions, clip and all QDQ boundaries are unchanged. FMA (op 17)
still uses the vendor `asr_fma_ip` interface and is **not covered** by the Icarus tests
because no vendor simulation library is present here. No arithmetic substitute/stub is
used for FMA.

## 2. `ddr_vector_engine_pipe` timing contract

Top ports are identical to `ddr_vector_engine` (descriptor 512 b, two independent DMA
request/data channels, status counters). Semantics:

- `start && ready` accepts one descriptor. The 512-bit descriptor is snapshotted on
  acceptance (`cfg`) and later host changes are ignored. `start && !ready` increments
  `rejected_starts` and must not disturb the running job.
- Descriptor validation is pipelined through **3 registered stages** (`V1`, `V2`, `V3`).
  It adds about 3 cycles before the first DMA request; `error_code=8'h01` and zero DMA
  side effects for an invalid descriptor are preserved.
- `ready = !busy && rd_request_ready && wr_request_ready` (unchanged).
- `done` only after read DMA, compute drain and write DMA are all fully drained.
- Fixed-latency ops are executed by **4 parallel lane pipelines**. Contract:
  - lane pipeline depth **L_FIXED = 3** cycles (s0 latch, s1 prepare/mul, s2 finish);
  - lane initiation interval **II_LANE = 1** element/cycle/lane;
  - engine issue rate **II_ENGINE = 1 beat/cycle = 4 elements/cycle** for FP32/A16
    (2 elements/cycle for C48/A48 input, because only 2 C48 fit one 128-bit beat);
  - reported number is measured, not assumed. See `FINDINGS.md`.
- DIV/SQRT/EXP/LOG (and FMA) are **not** claimed II=1. They use a single shared
  sequential core: exact `asr_fp32_alu` by default, or `approx_div_sqrt` when enabled.
  Contract: engine issue gap and latency are measured per run; the exact iterative
  DIV/SQRT takes ~32 cycles/element in the baseline, and the candidate must not label
  that path II=1.
- 128-bit unpack: one 128-bit raw window per cycle yields 4 FP32 or 8 A16 (or 2 C48)
  operand items; 128-bit result pack yields 4 FP32 or 8 I16 per output beat.
- Backpressure: both DMA channels and the internal lane output use ready/valid. Every
  in-flight beat has a tag/token (element index / bank+sequence) that is echoed with the
  result. A stalled `wr_ready`, `rd_valid` gap or lane `out_ready` must freeze the
  corresponding pipeline without dropping/reordering elements.

## 3. `approx_div_sqrt` — contract supplied to `gemini_approx`

`gemini_approx` owns the approximation algorithm and error measurements. `ds_vector`
owns only this adapter boundary. **Plain ports (no SystemVerilog interface object)** so
Icarus/Vivado and mixed-language wrappers can use it.

```systemverilog
module approx_div_sqrt #(
    parameter integer LATENCY = 0,   // declared by implementation, for reporting only
    parameter integer II      = 1    // declared by implementation, for reporting only
)(
    input  wire        clk,
    input  wire        rst_n,
    // request
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [1:0]  op,        // 0=DIV(a/b), 1=SQRT(a), 2=RSQRT(a) (reserved)
    input  wire [31:0] a,
    input  wire [31:0] b,         // ignored for SQRT/RSQRT
    input  wire [15:0] tag,       // opaque token, echoed on result
    // completion (in-order required; tag is for tracing/merge)
    output wire        out_valid,
    input  wire        out_ready,
    output wire [31:0] result,
    output wire [7:0]  flags,
    output wire [15:0] tag_out
);
```

Rules:

1. `in_valid && in_ready` accepts one request on the rising edge. `out_valid &&
   out_ready` accepts one result. `out_valid` must not depend combinationally on
   `out_ready` and must hold `result/flags/tag_out` stable while `out_ready=0`.
2. Results may be returned with `LATENCY` cycles and may be issued with initiation
   interval `II` (back-to-back when `II=1`). **In-order completion is required** for the
   current engine adapter. `tag_out` must equal the corresponding `tag`.
3. `flags` bits: `[0]` invalid (NaN/negative sqrt), `[1]` divide-by-zero,
   `[2]` overflow, `[3]` underflow/FTZ, `[4]` approximate-result marker,
   `[7:5]` reserved zero. The engine treats `flags[2:0]` exactly like the exact ALU:
   any of bits 0..2 aborts with `error_code=8'h04`; bit 4 only updates
   `numeric_flags` and never aborts.
4. Required edge behavior, measured by `gemini_approx`:
   - `b==+0` or `b==-0`: DIV returns signed infinity with `flags[1]` (unless `a` is NaN);
   - `a==0,b==0`, NaN input, negative SQRT: NaN + `flags[0]`;
   - `+/-Inf`, finite/inf, inf/inf, sqrt(inf), sqrt(+0): IEEE-like result or documented
     fallback + flag; no X propagation;
   - negative zero sqrt returns `-0` or `+0` with a documented rule;
   - subnormal inputs/results: FTZ or gradual, documented; result below normal range sets
     `flags[3]`;
   - out-of-range fallback (e.g. LUT index) must set an explicit flag, not silently
     return 0.
5. The engine adapter drives `op=0,a=numerator,b=divisor` for DIV and `op=1,a=radicand`
   for SQRT, with `tag = {bank, element_index[14:0]}`. It accepts one outstanding
   request in the first integration; if `II>1` the engine inserts bubbles and reports
   the measured gap. No engine state assumes `II=1`.
6. `LATENCY/II` parameters are **declarations**, not proof. The final report must contain
   measured latency/II from the gemini_approx RTL test and the integrated vector test.

### 3.1 Delivered implementation (gemini_approx)

`gemini_approx` delivered `approx_div_sqrt` with the §3 ports. The integrated copy is in
`candidate/rtl/gemini_approx/` (source SHA preserved below). Parameters:

- the delivered RTL has a **single fixed 4-stage structure** (128-entry LUT + one
  Newton step). `TIER`, `LATENCY` and `II` are declarations/metadata in the delivered
  source and are **not** used to build 2/7-cycle variants; the primary acceptance
  rerun confirmed this. Do not claim a three-tier implementation or 300/600 MHz from
  these parameters. The ds_vector integration pins the measured default structure;
- in-order completion, ready/valid backpressure, tag echo.

Measured integration of the single delivered 4-stage core (same 1001-element fixtures):
DIV max relative error `1.10e-3`, mean `2.69e-4`, median 1456 ULP, 12.30x cycle speedup;
SQRT max relative error `5.24e-6`, mean `1.10e-6`, median 10 ULP, 12.79x cycle speedup.
The engine keeps at most 4 outstanding approximate requests and measures
~2.63 cycles/element (DIV) and ~2.49 cycles/element (SQRT) including DMA overhead;
this is not a whole-model accuracy claim. See `approx_result.json`.

### 3.2 Tag/token status

- Approx path: `tag_out` is checked in-order against `{bank, drain_element}`; a mismatch
  aborts with `error_code=8'h06`.
- Wide fixed-latency path: each lane carries/echoes a 16-bit tag token; because the
  four lanes are in-order by construction, the engine does not gate on the lane tag in
  this revision. The tag is preserved for tracing and is available for a future
  out-of-order merge. This limitation is explicit, not hidden.

## 4. Descriptor ABI (unchanged)

`descriptor[31:0] = 32'h22564543`, `[39:32]=op`, `[40]=a16`, `[41]=out16`,
`[42]=bscalar`, `[43]=ascalar`, `[44]=cscalar`, `[45]=a48`, `[46]=btiled`,
`[63:47]=0`, `[95:64]=A`, `[127:96]=B`, `[159:128]=C`, `[191:160]=D`,
`[223:192]=count`, `[255:224]=B period`, `[511:256]=0`.
All original address-window/alignment/overlap/ACL checks are preserved; only their
evaluation is pipelined.

## 5. Integration checklist for the main agent

1. Replace `ddr_vector_engine` with `ddr_vector_engine_pipe` (or keep both behind a
   parameter) and use `ddr_vector_axi_pipe` in the DMA cluster. Ports unchanged.
2. Keep `USE_APPROX_DIV_SQRT=0` until `gemini_approx` delivers a measured core; then set
   it to 1 only for DIV/SQRT descriptors and keep exact fallback selectable.
3. Do not report FMA as tested unless the vendor `asr_fma_ip` simulation model is linked.
4. Real-load cycle numbers must come from the same fixture/BFM for baseline and
   candidate; see `result.json`/`REPORT.md` for the measured table.
