# 下界与未满归因（自动生成，详见 result.json/bounds.json）

- useful MAC: 3,461,011,968; padded MAC: 3,991,404,544; unique C48: 4,471,808
- matrix PE cycles: 32,157,312 -> padded 124.12 MAC/cycle, useful 107.63
- C48 retire: 0.139/cycle = 6.7 bit/cycle; A/W 片上供数 368 bit/cycle
- matrix DDR bytes: 125,143,040 B = 3.89 B/PE-cycle (16B/cycle 通道的 24.32%)
- vector/layout bytes: 807,885,856 B; total 933,028,896 B
- whole plan 12.4866s; stage sum 12.4844s; overlap 0.0022s
- naive max(stage) 6.8155s（仅独立假设，不采用）

| compute MHz | matrix RUN-only s | matrix 256MAC/s | vector s | layout s | whole schedule s |
|---:|---:|---:|---:|---:|---:|
| 125 | 0.2573 | 0.1247 | 6.8155 | 3.3535 | 12.4866 |
| 300 | 0.1072 | 0.0520 | 2.8398 | 1.3973 | 5.2027 |
| 600 | 0.0536 | 0.0260 | 1.4199 | 0.6986 | 2.6014 |

| DDR MHz | peak GB/s | total bytes LB s | vector/layout LB s | matrix LB s | actual effective MB/s |
|---:|---:|---:|---:|---:|---:|
| 125 | 2.00 | 0.4665 | 0.4039 | 0.0626 | 74.7 |
| 200 | 3.20 | 0.2916 | 0.2525 | 0.0391 | 74.7 |
| 250 | 4.00 | 0.2333 | 0.2020 | 0.0313 | 74.7 |
| 300 | 4.80 | 0.1944 | 0.1683 | 0.0261 | 74.7 |

- compulsory on-chip-intermediate LB: 102,055,936 B (weights 81,007,616 + boundary in 4,539,392 + out 16,508,928)
- all-intermediate-DDR coarse LB: 127,240,192 B; actual total 933,028,896 B = 9.14× on-chip LB
- unique tensor range 12,592,128 B; actual vector/layout 807,885,856 B = 64.2× unique tensor range

| latency | base read | cand read | base write | cand write | base read util | cand read util |
|---:|---:|---:|---:|---:|---:|---:|
| 8 | 6404 | 4111 | 7347 | 4816 | 0.640 | 0.996 |
| 32 | 12548 | 4135 | 7404 | 4815 | 0.326 | 0.991 |
| 64 | 20740 | 4167 | 7376 | 4800 | 0.198 | 0.983 |

Ping-pong: serial 1651 cycles, prefetch 1339 cycles, speedup 1.233×, overlap 303 cycles.
