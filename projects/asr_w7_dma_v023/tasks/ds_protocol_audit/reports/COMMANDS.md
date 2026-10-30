# Commands and RC (reproduce)

All commands run from the task directory. Read-only sources are under
`/home/yang/Desktop/项目/work`; the candidate is the snapshot
`snapshots/axi_dma_v020_multi_snapshot_20261029.sv` (SHA 7123c26f...).

```bash
cd /home/yang/Desktop/项目/tasks/ds_protocol_audit
bash scripts/run_all.sh          # full reproduction; RC=0 at 2026-10-29T11:05:33Z
```

The script compiles with Icarus 14.0 (`-g2012`) and runs each test with a
watchdog. Fixture folders are passed through ASCII symlinks
`/tmp/opencode/vf/*` and `/tmp/opencode/lf/*` because Icarus mis-handles the
UTF-8 path in `$value$plusargs("%s")`. The symlinks point at the read-only
`work/tests/*fixtures`.

## Compile commands (see reports/compile/*.log, *.rc)

```bash
# v019 directed
iverilog -g2012 -s tb_dma_edge -o reports/compile/dma_edge.vvp \
  tb/tb_dma_edge.sv work/rtl/axi_dma_v019.sv

# vector fixtures (no FMA: forbidden stub aborts if op17 is used)
iverilog -g2012 -s tb_vector_stress -o reports/compile/vector_stress.vvp \
  tb/tb_vector_stress.sv tb/axi128_stress_bfm.sv \
  work/rtl/ddr_vector_axi.sv work/rtl/ddr_vector_engine.sv \
  work/rtl/asr_fp32_alu.sv work/rtl/axi_dma_v019.sv \
  work/tests/fma_forbidden_stub.sv

# layout fixtures
iverilog -g2012 -s tb_layout_stress -o reports/compile/layout_stress.vvp \
  tb/tb_layout_stress.sv tb/axi128_stress_bfm.sv \
  work/rtl/ddr_layout_axi.sv work/rtl/ddr_layout_engine.sv \
  work/rtl/u16_divmod.sv work/rtl/axi_dma_v019.sv

# CSR readback
iverilog -g2012 -s tb_csr_snapshot -o reports/compile/csr.vvp \
  tb/tb_csr_snapshot.sv work/rtl/plan_submit_csr.sv

# plan watchdog / stall
iverilog -g2012 -s tb_plan_stall -o reports/compile/plan_stall.vvp \
  tb/tb_plan_stall.sv tb/axi128_stress_bfm.sv \
  work/rtl/pl_execution_plan_v022.sv work/rtl/axi_dma_v019.sv

# v020_multi candidate snapshot
iverilog -g2012 -s tb_dma_multi -o reports/compile/multi.vvp \
  tb/tb_dma_multi.sv snapshots/axi_dma_v020_multi_snapshot_20261029.sv
iverilog -g2012 -s tb_strobe -o reports/compile/strobe.vvp \
  tb/tb_strobe.sv snapshots/axi_dma_v020_multi_snapshot_20261029.sv
```

## Directed runs (cmd.txt + rc.txt in each directory)

```bash
vvp reports/compile/dma_edge.vvp         # DMA_EDGE_PASS errors=0 cycles=70101
vvp reports/compile/csr.vvp              # CSR_SNAPSHOT_BUG_CONFIRMED
vvp reports/compile/plan_stall.vvp       # phase1/2 unbounded; phase3 done
vvp reports/compile/multi.vvp            # MULTI_TEST_END errors=0; write_bytes bug print
vvp reports/compile/strobe.vvp           # mem=00 01 02 00; write_bytes=16
```

## Fixture runs

```bash
# vector: 5 fixtures x seeds 5/17/29
vvp reports/compile/vector_stress.vvp +folder=/tmp/opencode/vf/add_scalar +nbytes=4004 +seed=5
... (see reports/vector_stress001/summary.tsv)

# layout: 7 small fixtures x seeds 5/17, case0000 x seeds 17/29
vvp reports/compile/layout_stress.vvp +folder=/tmp/opencode/lf/unpack_c48_compact +nbytes=6930 +seed=17
vvp reports/compile/layout_stress.vvp +folder=/tmp/opencode/lf/case0000_embed_conv0 +nbytes=157696 +seed=17

# ACL (64-bit extent must reject 0xFFFFFFF0, no AXI)
vvp reports/compile/vector_stress.vvp +folder=/tmp/opencode/vf/add_scalar +nbytes=4004 +seed=5 +acl=1
vvp reports/compile/layout_stress.vvp +folder=/tmp/opencode/lf/copy_i16 +nbytes=2002 +seed=5 +acl=1
```

## RC summary

All `reports/*/rc.txt` and `reports/compile/*.rc` are `0`. The vector/layout
per-run rc is in `reports/vector_stress001/summary.tsv` and
`reports/layout_stress001/summary.tsv` (all 0).

Key measured metrics:

| Run | Metric |
|---|---|
| v019 edge | 20 groups, errors=0, cycles=70101 |
| v019 max beats | 65535 beats, 4096 bursts, 1,048,560 B, read_index=0xFFFF |
| vector | 15/15 byte-exact; out16 tail 2002 B; i48 4004 B |
| layout | 16/16 byte-exact; C48 6930 B; case0000 157,696 B, 9856 write bursts, 20,843 cache hits |
| ACL | fault=1 err=01 rb=0 wb=0 for both engines |
| multi | ar_max=4, b_max=2, FIFO high=128; 256-beat drain; 13 functional scenarios errors=0 |
| multi metric | write_bytes=64 for last WSTRB=0x0007 (should 51) |
| strobe | mem=00 01 02 00 (correct); write_bytes=16 (should 3) |
| CSR | interleaved 0x20,0x30,0x24 returns 0xAABBCCDD (wrong) |
| plan | phase1 dma_state=2 RDATA wait=997 fault=0; phase2 state=10 wait=401; phase3 done=1 |
