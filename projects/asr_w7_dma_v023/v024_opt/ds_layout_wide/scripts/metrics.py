#!/usr/bin/env python3
"""Shared parsing/metrics helpers for the ds_layout_wide regression."""
import re

FIELDS = ["cycles", "processed", "read_requests", "write_requests",
          "read_beats", "write_beats", "read_bytes", "write_bytes",
          "fast_elements", "fast_beats", "fast_groups"]


def parse_log(text):
    d = {"pass": "V022_LAYOUT_AXI_PASS" in text,
         "fatal": "FATAL" in text}
    for k in FIELDS:
        m = re.search(rf"{k}=\s*(\d+)", text)
        d[k] = int(m.group(1)) if m else None
    return d


REQUIRED = ["cycles", "processed", "read_requests", "write_requests",
            "read_beats", "write_beats", "read_bytes", "write_bytes"]
WIDE_REQUIRED = REQUIRED + ["fast_elements", "fast_beats", "fast_groups"]


def missing_fields(d, keys):
    return [k for k in keys if d.get(k) is None]


def source_bytes(w):
    """Unique source footprint declared by the descriptor (EXTENT1 logic)."""
    mode, nbytes = w[1], w[5]
    if mode == 0:
        elems = w[4]
        return elems * nbytes
    if mode == 1:
        return w[6] * w[8] * nbytes                 # m * full_n
    if mode == 2:
        return w[10] * w[11] * w[12] * 2            # channels * ih * iw * 2
    mt, nt = (w[6] + 31) // 32, (w[7] + 31) // 32   # mode 3/4
    return mt * nt * 1024 * nbytes


def read_overfetch(rec, w):
    return rec["read_bytes"] - source_bytes(w)


def touched_lines(w):
    """Distinct 16-byte source lines the descriptor semantics actually consume.

    Computed independently from the descriptor (same expansion as layout_model)
    and used only for overfetch accounting; it never drives RTL control.
    """
    mode, src, nbytes = w[1], w[2], w[5]
    lines = set()
    def add(idx):
        lines.add((src + idx * nbytes) >> 4)
    if mode == 0:
        for i in range(w[4]): add(i)
    elif mode == 1:
        m, n, full_n, ko = w[6], w[7], w[8], w[23]
        for r in range(m):
            base = r * full_n + ko
            for c in range(n): add(base + c)
    elif mode == 2:
        ch, ih, iw, kh, kw = w[10], w[11], w[12], w[13], w[14]
        oh, ow, sh, sw, dh, dw = w[15], w[16], w[17], w[18], w[19], w[20]
        ph, pw, ko = w[21], w[22], w[23]
        m, n = w[6], w[7]
        for rr in range(m):
            oy, ox = divmod(rr, ow)
            for cc in range(n):
                k = ko + cc
                kc, rem = divmod(k, kh * kw)
                ky, kx = divmod(rem, kw)
                iy = oy * sh + ky * dh - ph
                ix = ox * sw + kx * dw - pw
                if kc >= ch or iy < 0 or ix < 0 or iy >= ih or ix >= iw:
                    continue
                add((kc * ih + iy) * iw + ix)
    else:
        m, n = w[6], w[7]
        nt = (n + 31) // 32
        for r in range(m):
            for c in range(n):
                add(((r >> 5) * nt + (c >> 5)) * 1024 + (r & 31) * 32 + (c & 31))
    return len(lines)
