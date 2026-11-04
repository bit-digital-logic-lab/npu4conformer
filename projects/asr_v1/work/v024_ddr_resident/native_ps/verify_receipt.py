"""Validate raw A53 mailbox/output captures without board access."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def verify(mode, folder):
    def require(valid, message):
        if not valid:
            raise ValueError(message)

    raw = (folder / "mailbox.bin").read_bytes()
    keys = ("magic abi state capabilities request_seq response_seq command feature_frames "
            "result encoder_frames pl_calls stage ticks_lo ticks_hi timer_hz selftest_mask").split()
    box = dict(zip(keys, struct.unpack("<16I", raw)))
    require(box["magic"] == 0x50533234 and box["abi"] == 1, "invalid mailbox identity")
    require(box["request_seq"] == box["response_seq"], "incomplete request")
    require(box["timer_hz"] == 33333000, "unexpected counter frequency")
    require(box["result"] == 0, f"firmware error {box['result']:#x}")
    rec = dict(mode=mode, mailbox=box, mailbox_sha256=hashlib.sha256(raw).hexdigest())
    cmd = {"boot": 0, "selftest": 1, "pltest": 3, "encode": 2}[mode]
    require(box["command"] == cmd and box["state"] == (1 if mode == "boot" else 3),
            "wrong command or terminal state")
    ticks = box["ticks_lo"] + (box["ticks_hi"] << 32)
    rec["board_elapsed_seconds"] = ticks / box["timer_hz"]
    if mode == "boot":
        require(box["request_seq"] == 0 and box["capabilities"] & 1, "invalid firmware boot")
    elif mode == "selftest":
        require(box["selftest_mask"] == 31 and box["pl_calls"] == 0, "A53 kernel check failed")
    elif mode == "pltest":
        require(box["capabilities"] & 4 and box["pl_calls"] >= 2, "PL test missing")
        raw = (folder / "matrix_output.bin").read_bytes()
        rows, depth, cols = 35, 1057, 129
        xs = [[(17*r+29*k+(r^k)) % 3-1 for k in range(depth)] for r in range(rows)]
        ws = [[(7*k+13*c+((k>>2)^c)) % 5-2 for k in range(depth)] for c in range(cols)]
        actual = struct.unpack(f"<{rows*cols}f", raw)
        error = 0.0
        for i, row in enumerate(xs):
            for j, col in enumerate(ws):
                dot = sum(a*b for a, b in zip(row, col))
                target = dot * (0.5 if j % 2 else 1.0) + j/256
                value = actual[i*cols+j]
                require(math.isfinite(value), "nonfinite PL output")
                error = max(error, abs(value-target))
        require(error <= 2e-4, f"matrix mismatch: max absolute error {error}")
        rec.update(output_sha256=hashlib.sha256(raw).hexdigest(), matrix=[rows, depth, cols],
                   checked_words=len(actual), max_abs_error=error)
    else:
        frames = box["feature_frames"]
        first = (frames-1)//2
        t = (first-1)//2
        calls = (first*39+63)//64 + (t*19+63)//64 + 1 + 12*35
        require(7 <= frames <= 1876 and box["encoder_frames"] == t, "unexpected encoder shape")
        require(box["stage"] == 300 and box["pl_calls"] == calls, "PL/operator coverage mismatch")
        raw = (folder / "encoder_output_f32.bin").read_bytes()
        values = struct.unpack(f"<{t*512}f", raw)
        require(all(math.isfinite(x) for x in values), "nonfinite encoder output")
        require(min(values) < max(values), "degenerate encoder output")
        rec.update(output_sha256=hashlib.sha256(raw).hexdigest(), output_shape=[t,512],
                   expected_pl_calls=calls, minimum=min(values), maximum=max(values))
    rec["passed"] = True
    return rec


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("boot", "selftest", "pltest", "encode"))
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    receipt = json.dumps(verify(args.mode, args.folder), indent=2) + "\n"
    (args.folder / "verified.json").write_text(receipt, encoding="utf-8")
    print(receipt, end="")
