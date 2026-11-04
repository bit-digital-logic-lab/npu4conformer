"""Recompute both numerical checks from saved JTAG hex, independently of live inference."""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys
import numpy as np

run = Path(sys.argv[1]).resolve()
result = json.loads((run / "result.json").read_text())
root = Path(__file__).resolve().parent.parent.parent
spec = importlib.util.spec_from_file_location("frozen_int_gold", root / "core/scripts/analysis/gen_matrix_gold.py")
gold_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gold_module)


def words(path):
    return np.array([int(x, 16) for x in path.read_text().split()], dtype="<u4")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(test, message):
    if not test:
        raise ValueError(message)


max_sqrt_error = 0.
sqrt_count = 0
for call in result["calls"]:
    src = run / call["input_file"]
    dst = run / call["output_file"]
    require(sha(src) == call["input_sha256"] and sha(dst) == call["output_sha256"], "changed raw SQRT bytes")
    expected = np.sqrt(words(src).view("<f4").astype(np.float64))
    actual = words(dst).view("<f4")
    require(actual.shape == expected.shape and len(actual) == call["words"], "SQRT shape")
    max_sqrt_error = max(max_sqrt_error, np.max(np.abs(actual - expected) / expected).item())
    sqrt_count += len(actual)
require(max_sqrt_error <= 6e-6 and sqrt_count == result["useful_sqrt_words"], "SQRT tolerance")
audit = dict(raw_sqrt_count=sqrt_count, max_sqrt_relative_error=max_sqrt_error)
if "matrix_query" in result:
    folder = run/"matrix"
    lookup = np.array([gold_module.prod(1, v & 127, 0x3210, 1) for v in range(256)], dtype=np.int32)
    odd = np.array([v.bit_count() % 2 for v in range(256)])
    query = result["matrix_query"]
    frames = query["frames"]
    nrows = (frames+31)//32
    sums = np.zeros((nrows*32,512),dtype=np.int64)
    seen = set()
    for t in sorted(folder.glob("tile_*.req")):
        b,k,c = map(int,t.read_text().split())
        require((b,k,c) not in seen, "duplicated tile")
        seen.add((b,k,c))
        a = words(folder/f"a_{b:02d}_{k:02d}.hex").view("<i2").reshape(32,32).astype(np.int32)
        w = words(folder/f"w_{k:02d}_{c:02d}.hex").view("u1").reshape(32,32)
        require(not np.any(odd[w]), "W7 byte parity mismatch")
        mac = a @ lookup[w]
        pred = np.rint(mac.astype(np.float64)/256).astype(np.int32)
        out = words(folder/f"out_{t.stem.split('_')[1]}.hex").view("<i2").reshape(32,32)
        require(np.array_equal(pred,out), f"integer dot product mismatch {t.name}")
        sums[b*32:(b+1)*32,c*32:(c+1)*32] += out
    require(seen == {(b,k,c) for b in range(nrows) for k in range(16) for c in range(16)}, "missing tile")
    x = np.load(folder/"activation_fp32.npy")
    w = np.load(folder/"weight_fp32.npy")
    a_scale = float(np.abs(x).max()) / 2047
    scale = np.max(np.abs(w),axis=1)/120
    produced = (sums[:frames].astype(np.float64) * (256*a_scale) * scale[None,:]).astype(np.float32)
    if (folder/"bias_fp32.npy").exists():
        produced += np.load(folder/"bias_fp32.npy")
    require(np.array_equal(produced,np.load(folder/"query_from_board.npy")), "full projection reconstruction mismatch")
    audit.update(matrix_tiles=len(seen), physical_partial_i16_matched=len(seen)*1024,
                 reconstructed_query_fp32_matched=produced.size, frozen_gold_sha256=sha(Path(spec.origin)))
require(json.loads((run/"process.json").read_text())["vivado_exit_code"] == 0, "failed hardware process")
audit.update(status="PASS", live_receipt_sha256=sha(run/"result.json"), raw_axi_sha256=sha(run/"stream_axi.tsv"))
(run/"independent_raw_check.json").write_text(json.dumps(audit,indent=2),encoding="utf-8")
print(json.dumps(audit,indent=2))
