"""Offline cross-check of LibriSpeech inputs, native A53 receipts and raw board outputs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "native_host"))
from frontend_ctc import ASR, HostFrontendCTC


def sha(data):
    return hashlib.sha256(data).hexdigest()


def audit(folder):
    model = HostFrontendCTC()
    ctc_w, ctc_b = model.ctc_weight.numpy(), model.ctc_bias.numpy()
    runs = json.loads((folder / "summary.json").read_text(encoding="utf-8-sig"))["records"]
    audited = []
    for rec in runs:
        name = rec["clip"]
        speaker, chapter, _ = name.split("-")
        corpus = ASR / "data" / "LibriSpeech" / "test-clean" / speaker / chapter
        original = corpus / f"{name}.flac"
        gold = dict(line.split(" ", 1) for line in (corpus/f"{speaker}-{chapter}.trans.txt").read_text().splitlines())[name]
        raw = Path(rec["encoded_f32"]).parent
        source = model.features(original)
        payload = (raw/"input_f32.bin").read_bytes()
        assert (folder/name/"features_f32.bin").read_bytes() == payload
        sent = np.frombuffer(payload, dtype="<f4").reshape(-1,80)
        delta = float(np.max(np.abs(source-sent)))
        assert delta <= 4e-6, "current source audio differs from captured log-Mel"
        box = struct.unpack("<8Ii3IQ2I", (raw/"mailbox.bin").read_bytes())
        magic, abi, state, cap, seq, resp, cmd, frames, rc, t, calls, stage, ticks, hz, mask = box
        t1=(frames-1)//2
        whole=(t1*39+63)//64+(t*19+63)//64+1+12*(4+5+8*3+2)
        assert (magic,abi,state,cap,cmd,rc,stage,hz,mask)==(0x50533234,1,3,7,2,0,300,33333000,31)
        assert seq == resp == int((raw/"DONE").read_text()) == rec["request_seq"]
        assert frames==source.shape[0] and t==(t1-1)//2 and calls==whole and ticks>0
        output = (raw/"encoder_output_f32.bin").read_bytes()
        encoded = np.frombuffer(output,dtype="<f4").reshape(t,512)
        assert np.isfinite(encoded).all()
        # Independent CPU NumPy projection; uses neither the run's saved tokens
        # nor the reference transcript as inputs. No PC-side encoder invocation.
        logits = encoded @ ctc_w.T + ctc_b
        path = logits.argmax(axis=1)
        distinct = path[np.r_[True,path[1:]!=path[:-1]]]
        tokens = [int(i) for i in distinct if i not in (0,len(model.tokens)-1)]
        text = model.spm.decode_pieces([model.tokens[i] for i in tokens])
        assert text==gold==rec["text"] and tokens==rec["token_ids"]
        audited.append(dict(clip=name, raw_path=str(raw), abi=abi, sequence=seq, source_flac_sha256=sha(original.read_bytes()),
                   saved_frontend_exact_upload_bytes=True, regenerated_logmel_max_abs_error=delta,
                   regenerated_logmel_exact_fraction=float(np.mean(source==sent)), input_sha256=sha(payload), output_sha256=sha(output),
                   word_count=int(encoded.size), shape=[t,512], pl_calls=calls, ticks=ticks,
                   timer_hz=hz, board_seconds=ticks/hz, independently_decoded=text, reference_exact=True))
    assert len(audited)>=2 and len({r["output_sha256"] for r in audited})==len(audited)
    assert len({r["input_sha256"] for r in audited})==len(audited)
    assert all(b["sequence"]==a["sequence"]+1 for a,b in zip(audited,audited[1:]))
    assert len({(r["session_id"],r["xsdb_pid"],r["runtime_boot"]) for r in runs})==1
    first=runs[0]
    return dict(passed=True, method="Fresh raw input reconstructed from each corpus FLAC; unpacked original A53 mailbox, independent NumPy CTC projection and token collapse on every board output word; reference compared only after decoding.",session=first["session_id"],xsdb_pid=first["xsdb_pid"],
                firmware_session=first["runtime_boot"],image=first["image"],records=audited)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder",type=Path)
    args=parser.parse_args()
    verified=audit(args.folder.resolve())
    out=HERE/"runs"/f"native_host_{args.folder.name}_audit.json"
    out.write_text(json.dumps(verified,indent=2),encoding="utf-8")
    print(out)
